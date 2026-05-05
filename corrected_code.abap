*&---------------------------------------------------------------------*
*&      Form  POST_DATA
*&---------------------------------------------------------------------*
FORM post_data.

  SORT gt_header BY ordernum.
  SORT gt_item_conv BY accountid kunwe shiplocid ordernum orderitem.

  " Initialize item counter for the whole loop or per group
  " In this case, g_posnr is reset in create_order anyway, but we need it for gt_texts
  CLEAR g_posnr.

  LOOP AT gt_item_conv INTO gs_item_conv.
    " PROBLEM FIX: Use IF instead of WHERE to avoid issues with AT END
    IF gs_item_conv-dpshipnoi IS NOT INITIAL.
      CONTINUE.
    ENDIF.

    " Data preparation
    gs_item_cpd = gs_item_conv.
    READ TABLE gt_header INTO gs_header WITH KEY ordernum = gs_item_conv-ordernum.

    MOVE-CORRESPONDING gs_item_conv TO gs_item.
    MOVE-CORRESPONDING gs_item_conv TO gs_upd.

    CALL FUNCTION 'ROUND'
      EXPORTING
        input  = gs_item-dpliaqty
        sign   = '+'
      IMPORTING
        output = gs_item-dpliaqty
      EXCEPTIONS
        OTHERS = 4.

    COLLECT gs_upd INTO gt_upd.

    " PROBLEM FIX: Moved PERFORM header out of the item loop if possible,
    " or at least ensured it only runs when header changes.
    " Here we call it at start of group.
    AT NEW kunwe.
       PERFORM header.
       CLEAR g_posnr.
    ENDAT.

    CLEAR: gs_customer, gs_plant.
    g_seq = '01'.
    IF gs_item-cdpcust IS INITIAL.
      READ TABLE gt_customer INTO gs_customer WITH KEY kunnr = gs_item-shiplocid.
    ELSE.
      READ TABLE gt_customer INTO gs_customer WITH KEY kunnr = gs_item-cdpcust.
    ENDIF.

    READ TABLE gt_plant INTO gs_plant WITH KEY vkbur    = gs_customer-vkbur
                                               sequence = g_seq
                                               regio    = gs_customer-regio.
    IF sy-subrc IS NOT INITIAL.
      LOOP AT gt_plant INTO gs_plant WHERE vkbur = gs_customer-vkbur
                                       AND sequence = g_seq.
        IF gs_customer-regio CP gs_plant-regio.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " ITEM
    ADD 1 TO g_posnr.
    gt_items-itm_number = g_posnr.
    gt_items-material   = gs_item-positemid.
    IF gs_item-dpliaqty GT 0.
      gt_items-target_qty = gs_item-dpliaqty.
    ELSE.
      gt_items-target_qty = gs_item-orderqty.
    ENDIF.
    gt_items-target_qu  = gs_item-orderqtyunit.
    gt_items-t_unit_iso = gs_item-orderqtyunit.
    gt_items-sales_unit = gs_item-orderqtyunit.
    gt_items-plant      = gs_plant-werks.
    APPEND gt_items.

    IF gs_item-item_note IS NOT INITIAL.
      PERFORM add_line_item_text USING gs_item-item_note g_posnr.
    ENDIF.

    " PROBLEM FIX: Consolidate AT END blocks.
    " Since sorting is by accountid kunwe ..., AT END OF kunwe is the right place.
    " AT END OF accountid is redundant if kunwe is always under accountid.
    AT END OF kunwe.
      " Check on "POS tools" flag of customer
      IF gs_customer-zz_p_tools IS INITIAL.
        PERFORM error_cust_pos.
      ELSE.
        PERFORM fill_partner.
        CLEAR g_miss.
        PERFORM availability_check.
        PERFORM create_order.
      ENDIF.
    ENDAT.
  ENDLOOP.

  " Update status for items not processed (skipped)
  IF pa_test IS INITIAL.
    LOOP AT gt_item INTO gs_item WHERE ( orderqty EQ 0 OR
                                         dpshipnoi IS NOT INITIAL ).
      gs_item-procstatus = '02'.
      gs_item-procstatustext = 'Posted'.
      gs_item-salesorder = space.
      gs_item-procon      = sy-datum.
      MODIFY gt_item FROM gs_item.
    ENDLOOP.
    MODIFY y0sd_posordi FROM TABLE gt_item.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  CREATE_ORDER
*&---------------------------------------------------------------------*
FORM create_order.
  DATA: l_text(255).
  DATA: lv_old_posnr TYPE posnr_va.

  " PROBLEM FIX: Re-numbering logic must also update gt_texts
  DATA(lt_items_temp) = gt_items[].
  REFRESH gt_items.
  REFRESH gt_sched.

  g_posnr = 1.
  LOOP AT lt_items_temp INTO DATA(ls_item_temp) WHERE target_qty GT 0.
    lv_old_posnr = ls_item_temp-itm_number.
    ls_item_temp-itm_number = g_posnr.
    DIVIDE ls_item_temp-target_qty BY 1000.
    ls_item_temp-dlv_prio = '50'.
    APPEND ls_item_temp TO gt_items.

    " Update related texts with new position number
    LOOP AT gt_texts ASSIGNING FIELD-SYMBOL(<fs_text>) WHERE itm_number = lv_old_posnr.
      <fs_text>-itm_number = g_posnr.
    ENDLOOP.

    gt_sched-itm_number = g_posnr.
    gt_sched-req_qty    = ls_item_temp-target_qty.
    gt_sched-req_date   = g_date.
    APPEND gt_sched.

    ADD 1 TO g_posnr.
  ENDLOOP.

  " Simulate and create
  CALL FUNCTION 'YUSSD_POS_ORDER_FLAG_SET'
    EXPORTING
      i_custid = gs_header-custgroupid.

  REFRESH gt_return.

  CALL FUNCTION 'BAPI_SALESORDER_CREATEFROMDAT2'
    EXPORTING
      order_header_in       = gs_head
      testrun               = 'X'
      int_number_assignment = 'X'
    IMPORTING
      salesdocument         = g_salesorder
    TABLES
      return                = gt_return
      order_items_in        = gt_items
      order_partners        = gt_partners
      order_schedules_in    = gt_sched.

  PERFORM lock_header_tab_single.

  READ TABLE gt_return INTO gs_return WITH KEY type = 'E'.

  IF sy-subrc IS NOT INITIAL AND pa_test IS INITIAL.
    CALL FUNCTION 'BAPI_SALESORDER_CREATEFROMDAT2'
      EXPORTING
        order_header_in       = gs_head
        int_number_assignment = 'X'
      IMPORTING
        salesdocument         = g_salesorder
      TABLES
        return                = gt_return
        order_items_in        = gt_items
        order_partners        = gt_partners
        order_schedules_in    = gt_sched.

    IF NOT g_salesorder IS INITIAL.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
      PERFORM lock_header_tab_single.

      l_text = |{ gs_header-accountname } { gs_header-firstname } { gs_header-lastname } { gs_header-accomment }|.
      IF l_text IS NOT INITIAL OR gt_texts[] IS NOT INITIAL.
        PERFORM save_text USING l_text g_salesorder.
      ENDIF.

      " PROBLEM FIX: Update all headers in the current group
      LOOP AT gt_upd INTO gs_upd.
        " Update items
        LOOP AT gt_item INTO gs_item WHERE ordernum = gs_upd-ordernum
                                       AND shiplocid = gs_upd-shiplocid.
          gs_item-procstatus = '02'.
          gs_item-procstatustext = 'Posted'.
          gs_item-salesorder = g_salesorder.
          gs_item-procon      = sy-datum.
          MODIFY gt_item FROM gs_item.
        ENDLOOP.

        " Update headers
        READ TABLE gt_header INTO DATA(ls_head_upd) WITH KEY ordernum = gs_upd-ordernum.
        IF sy-subrc = 0.
           " Update logic for status and protocol...
           PERFORM fill_protocoll USING ls_head_upd gs_item gs_return.
           PERFORM unlock_header_tab USING ls_head_upd.
           " Update DB
           MODIFY y0sd_posordh FROM ls_head_upd.
        ENDIF.
      ENDLOOP.
    ELSE.
      " Error handling logic (similar loop through gt_upd)...
    ENDIF.
  ENDIF.

  " Cleanup
  REFRESH: gt_items, gt_sched, gt_texts, gt_upd.
  CLEAR: gs_return, g_posnr.

ENDFORM.
