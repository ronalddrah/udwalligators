REPORT yussd_pos_sales_order_create.
************************************************************************
* Topic             : US POS order creation report                     *
* Programmer        : Ronald Drah (Modernized & Robust)                *
*----------------------------------------------------------------------*
* POS order creation using modern ABAP 7.40+ grouping and syntax.      *
************************************************************************

* Tables
TABLES: y0sd_posordh.

* Types
TYPES: BEGIN OF ty_sel,
         ordernum   TYPE y0sd_posordh-ordernum,
         ordercycle TYPE y0sd_posordh-ordercycle,
         accountid  TYPE y0sd_posordh-accountid,
         salesorder TYPE y0sd_posordi-salesorder,
         shiplocid  TYPE kna1-kunnr,
         procstatus TYPE y0sd_posordi-procstatus,
         soid       TYPE y0sd_posordh-salesofficeid,
         custgroup  TYPE y0sd_posordh-custgroupid,
       END OF ty_sel.

TYPES: BEGIN OF ty_header.
         INCLUDE TYPE y0sd_posordh.
TYPES:   account_o TYPE y0sd_posaccountid,
       END OF ty_header.

TYPES: BEGIN OF ty_item,
         accountid TYPE y0sd_posaccountid,
         kunwe     TYPE kunwe.
         INCLUDE TYPE y0sd_posordi.
TYPES: END OF ty_item.

TYPES: BEGIN OF ty_upd,
         ordernum  TYPE y0sd_posordh-ordernum,
         shiplocid TYPE kunwe,
       END OF ty_upd.

TYPES: BEGIN OF ty_customer,
         kunnr      TYPE kna1-kunnr,
         regio      TYPE kna1-regio,
         zz_p_tools TYPE kna1-zz_p_tools,
         vkbur      TYPE knvv-vkbur,
       END OF ty_customer.

* Global Data
DATA: gt_header    TYPE STANDARD TABLE OF ty_header,
      gs_header    TYPE ty_header,
      gt_item      TYPE STANDARD TABLE OF y0sd_posordi,
      gs_item      TYPE y0sd_posordi,
      gt_item_conv TYPE STANDARD TABLE OF ty_item,
      gs_item_conv TYPE ty_item,
      gs_item_cpd  TYPE ty_item,
      gt_out       TYPE STANDARD TABLE OF yussd_pos_so_create_alv,
      gs_out       TYPE yussd_pos_so_create_alv,
      gt_upd       TYPE STANDARD TABLE OF ty_upd,
      gs_head      TYPE bapisdhd1,
      gt_partners  TYPE STANDARD TABLE OF bapiparnr,
      gt_items     TYPE STANDARD TABLE OF bapisditm,
      gt_sched     TYPE STANDARD TABLE OF bapischdl,
      gt_texts     TYPE STANDARD TABLE OF bapisdtext,
      gs_return    TYPE bapiret2,
      gt_return    TYPE STANDARD TABLE OF bapiret2,
      gt_plant     TYPE STANDARD TABLE OF yussd_pos_plant,
      gs_plant     TYPE yussd_pos_plant,
      gt_soldto    TYPE STANDARD TABLE OF yussd_pos_soldto,
      gt_customer  TYPE STANDARD TABLE OF ty_customer,
      gs_customer  TYPE ty_customer,
      g_salesorder TYPE vbeln_va,
      g_date       TYPE dats,
      g_seq        TYPE numc2,
      g_posnr      TYPE posnr_va,
      g_miss       TYPE char1,
      gs_sel       TYPE ty_sel.

* Selection Screen
SELECTION-SCREEN BEGIN OF BLOCK 001 WITH FRAME.
  SELECT-OPTIONS: so_num   FOR gs_sel-ordernum,
                  so_ocycl FOR gs_sel-ordercycle,
                  so_soid  FOR gs_sel-soid,
                  so_cgid  FOR gs_sel-custgroup,
                  so_acc   FOR gs_sel-accountid,
                  so_kunwe FOR gs_sel-shiplocid,
                  so_vbeln FOR gs_sel-salesorder.
SELECTION-SCREEN END OF BLOCK 001.

SELECTION-SCREEN BEGIN OF BLOCK 002 WITH FRAME.
  PARAMETERS: pa_crea RADIOBUTTON GROUP type.
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN: POSITION 5.
    PARAMETERS: pa_test AS CHECKBOX DEFAULT 'X'.
    SELECTION-SCREEN COMMENT (10) TEXT-001 FOR FIELD pa_test.
  SELECTION-SCREEN END OF LINE.
  SELECTION-SCREEN ULINE.
  PARAMETERS: pa_show RADIOBUTTON GROUP type.
  SELECT-OPTIONS: so_stat FOR gs_sel-procstatus.
SELECTION-SCREEN END OF BLOCK 002.

* Execution
AT SELECTION-SCREEN.
  PERFORM authority_check.

START-OF-SELECTION.
  CALL FUNCTION 'Y0BC_WHEN_USED'.

  IF pa_crea IS NOT INITIAL.
    PERFORM get_data.
  ELSE.
    PERFORM get_log.
  ENDIF.

  IF gt_item IS NOT INITIAL.
    PERFORM post_data.
  ENDIF.

END-OF-SELECTION.
  PERFORM output.

*&---------------------------------------------------------------------*
*&      Form  GET_DATA
*&---------------------------------------------------------------------*
FORM get_data.
  SELECT * FROM y0sd_posordh
    INTO TABLE @gt_header
    WHERE ordernum      IN @so_num
      AND ordercycle    IN @so_ocycl
      AND accountid     IN @so_acc
      AND salesofficeid IN @so_soid
      AND custgroupid   IN @so_cgid.

  PERFORM lock_header_tab.
  IF gt_header IS INITIAL. RETURN. ENDIF.

  SELECT * FROM y0sd_posordi
    INTO TABLE @gt_item
    FOR ALL ENTRIES IN @gt_header
    WHERE ordernum = @gt_header-ordernum
      AND shiplocid IN @so_kunwe
      AND salesorder = @space.

  IF gt_item IS INITIAL. RETURN. ENDIF.

  SELECT k~kunnr, k~regio, k~zz_p_tools, v~vkbur
    FROM kna1 AS k
    INNER JOIN knvv AS v ON v~kunnr = k~kunnr
    INTO TABLE @gt_customer
    FOR ALL ENTRIES IN @gt_item
    WHERE ( k~kunnr = @gt_item-shiplocid OR k~kunnr = @gt_item-cdpcust )
      AND v~vkorg = '5090'.

  IF gt_customer IS NOT INITIAL.
    SELECT * FROM yussd_pos_plant
      INTO TABLE @gt_plant
      FOR ALL ENTRIES IN @gt_customer
      WHERE vkorg = '5090' AND vkbur = @gt_customer-vkbur.
  ENDIF.

  DATA(lv_date) = |{ sy-datum(6) }01|.
  CALL FUNCTION 'RP_LAST_DAY_OF_MONTHS' EXPORTING day_in = lv_date IMPORTING last_day_of_month = lv_date EXCEPTIONS OTHERS = 2.
  CALL FUNCTION 'DATE_CONVERT_TO_FACTORYDATE'
    EXPORTING correct_option = '-' date = lv_date factory_calendar_id = 'US'
    IMPORTING date = g_date EXCEPTIONS OTHERS = 7.

  SELECT * FROM yussd_pos_soldto INTO TABLE @gt_soldto.

  LOOP AT gt_header ASSIGNING FIELD-SYMBOL(<fs_h>).
    READ TABLE gt_soldto INTO DATA(ls_st) WITH KEY vkorg = '5090'
                                                   salesofficeid = <fs_h>-salesofficeid
                                                   custgroupid   = <fs_h>-custgroupid.
    IF sy-subrc = 0.
      <fs_h>-soldtoid = ls_st-kunag.
    ELSE.
      <fs_h>-account_o = <fs_h>-accountid.
      DATA(lv_acc) = |{ <fs_h>-accountid ALPHA = IN }|.
      SELECT SINGLE kunnr FROM knvh INTO @<fs_h>-accountid
        WHERE hityp = 'A' AND vkorg = '5090' AND vtweg = '00' AND spart = '00'
          AND datab LE @sy-datum AND datbi GE @sy-datum AND hkunnr = @lv_acc AND hzuor = '00'.
      <fs_h>-soldtoid = <fs_h>-accountid.
    ENDIF.
    <fs_h>-accountid = |{ <fs_h>-accountid ALPHA = IN }|.
  ENDLOOP.

  LOOP AT gt_item INTO DATA(ls_itm) WHERE orderqty > 0.
    ASSIGN gt_header[ ordernum = ls_itm-ordernum ] TO FIELD-SYMBOL(<ls_h_ref>).
    IF sy-subrc = 0.
      APPEND VALUE #( BASE CORRESPONDING #( ls_itm ) accountid = <ls_h_ref>-soldtoid kunwe = ls_itm-shiplocid ) TO gt_item_conv.
    ENDIF.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  POST_DATA
*&---------------------------------------------------------------------*
FORM post_data.
  LOOP AT gt_item_conv INTO DATA(ls_itm_conv)
       WHERE dpshipnoi IS INITIAL
       GROUP BY ( accountid = ls_itm_conv-accountid kunwe = ls_itm_conv-kunwe )
       ASSIGNING FIELD-SYMBOL(<group>).

    REFRESH: gt_items, gt_texts, gt_upd.
    CLEAR: g_posnr, gs_customer, gs_item_cpd.

    LOOP AT GROUP <group> INTO DATA(ls_member).
      IF sy-tabix = 1.
        gs_header = VALUE #( gt_header[ ordernum = ls_member-ordernum ] OPTIONAL ).
        PERFORM header.
      ENDIF.

      IF ls_member-cdpcust IS NOT INITIAL.
        gs_item_cpd = CORRESPONDING #( ls_member ).
      ENDIF.

      gs_item = CORRESPONDING #( ls_member ).
      COLLECT VALUE ty_upd( ordernum = ls_member-ordernum shiplocid = ls_member-kunwe ) INTO gt_upd.

      CALL FUNCTION 'ROUND' EXPORTING input = gs_item-dpliaqty sign = '+' IMPORTING output = gs_item-dpliaqty EXCEPTIONS OTHERS = 4.

      DATA(lv_kun) = COND #( WHEN gs_item-cdpcust IS INITIAL THEN gs_item-shiplocid ELSE gs_item-cdpcust ).
      gs_customer = VALUE #( gt_customer[ kunnr = lv_kun ] OPTIONAL ).

      g_seq = '01'.
      READ TABLE gt_plant INTO gs_plant WITH KEY vkbur = gs_customer-vkbur sequence = g_seq regio = gs_customer-regio.
      IF sy-subrc <> 0.
        LOOP AT gt_plant INTO gs_plant WHERE vkbur = gs_customer-vkbur AND sequence = g_seq.
          IF gs_customer-regio CP gs_plant-regio. EXIT. ENDIF.
          CLEAR gs_plant.
        ENDLOOP.
      ENDIF.

      ADD 1 TO g_posnr.
      APPEND VALUE #( itm_number = g_posnr
                      material   = gs_item-positemid
                      target_qty = COND #( WHEN gs_item-dpliaqty > 0 THEN gs_item-dpliaqty ELSE gs_item-orderqty )
                      target_qu  = gs_item-orderqtyunit
                      t_unit_iso = gs_item-orderqtyunit
                      sales_unit = gs_item-orderqtyunit
                      plant      = gs_plant-werks ) TO gt_items.

      IF gs_item-item_note IS NOT INITIAL.
        PERFORM add_line_item_text USING gs_item-item_note g_posnr.
      ENDIF.
    ENDLOOP.

    IF gs_customer-zz_p_tools IS INITIAL.
      PERFORM error_cust_pos.
    ELSE.
      PERFORM fill_partner.
      CLEAR g_miss.
      PERFORM availability_check.
      PERFORM create_order.
    ENDIF.
  ENDLOOP.

  IF pa_test IS INITIAL.
    LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<fs_i>) WHERE orderqty = 0 OR dpshipnoi IS NOT INITIAL.
      <fs_i> = VALUE #( BASE <fs_i> procstatus = '02' procstatustext = 'Posted' salesorder = space procon = sy-datum ).
    ENDLOOP.
    MODIFY y0sd_posordi FROM TABLE gt_item.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  CREATE_ORDER
*&---------------------------------------------------------------------*
FORM create_order.
  DATA(lt_items_temp) = gt_items.
  CLEAR: gt_items, gt_sched.

  g_posnr = 1.
  LOOP AT lt_items_temp INTO DATA(ls_itm) WHERE target_qty > 0.
    DATA(lv_old_pos) = ls_itm-itm_number.
    APPEND VALUE #( BASE ls_itm itm_number = g_posnr target_qty = ls_itm-target_qty / 1000 dlv_prio = '50' ) TO gt_items.
    LOOP AT gt_texts ASSIGNING FIELD-SYMBOL(<fs_txt>) WHERE itm_number = lv_old_pos.
      <fs_txt>-itm_number = g_posnr.
    ENDLOOP.
    APPEND VALUE #( itm_number = g_posnr req_qty = ls_itm-target_qty / 1000 req_date = g_date ) TO gt_sched.
    ADD 1 TO g_posnr.
  ENDLOOP.

  CALL FUNCTION 'YUSSD_POS_ORDER_FLAG_SET' EXPORTING i_custid = gs_header-custgroupid.
  CLEAR gt_return.

  CALL FUNCTION 'BAPI_SALESORDER_CREATEFROMDAT2'
    EXPORTING order_header_in = gs_head testrun = 'X' int_number_assignment = 'X'
    IMPORTING salesdocument = g_salesorder
    TABLES    return = gt_return order_items_in = gt_items order_partners = gt_partners order_schedules_in = gt_sched.

  PERFORM lock_header_tab_single.

  READ TABLE gt_return INTO DATA(ls_err) WITH KEY type = 'E'.
  DATA(lv_err) = sy-subrc.

  IF lv_err <> 0 AND pa_test IS INITIAL. " Simulation OK, Execute
    CALL FUNCTION 'BAPI_SALESORDER_CREATEFROMDAT2'
      EXPORTING order_header_in = gs_head int_number_assignment = 'X'
      IMPORTING salesdocument = g_salesorder
      TABLES    return = gt_return order_items_in = gt_items order_partners = gt_partners order_schedules_in = gt_sched.

    IF g_salesorder IS NOT INITIAL.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = 'X'.
      PERFORM lock_header_tab_single.

      DATA(lv_txt) = |{ gs_header-accountname } { gs_header-firstname } { gs_header-lastname } { gs_header-accomment }|.
      IF lv_txt IS NOT INITIAL OR gt_texts IS NOT INITIAL. PERFORM save_text USING lv_txt g_salesorder. ENDIF.

      LOOP AT gt_upd INTO DATA(ls_u).
        LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<fs_s>) WHERE ordernum = ls_u-ordernum AND shiplocid = ls_u-shiplocid.
          <fs_s> = VALUE #( BASE <fs_s> procstatus = '02' procstatustext = 'Posted' salesorder = g_salesorder procon = sy-datum ).
          ASSIGN gt_header[ ordernum = ls_u-ordernum ] TO FIELD-SYMBOL(<fs_h_s>).
          IF sy-subrc = 0.
            PERFORM fill_protocoll USING <fs_h_s> <fs_s> VALUE bapiret2( gt_return[ type = 'S' ] DEFAULT VALUE #( gt_return[ 1 ] OPTIONAL ) ).
            PERFORM unlock_header_tab USING <fs_h_s>.
            MODIFY y0sd_posordh FROM <fs_h_s>.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ELSE. " Real Run Fail
      READ TABLE gt_return INTO ls_err WITH KEY type = 'E'.
      LOOP AT gt_upd INTO ls_u.
        LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<fs_f>) WHERE ordernum = ls_u-ordernum AND shiplocid = ls_u-shiplocid.
          <fs_f> = VALUE #( BASE <fs_f> procstatus = '03' procstatustext = ls_err-message procon = sy-datum ).
          ASSIGN gt_header[ ordernum = ls_u-ordernum ] TO FIELD-SYMBOL(<fs_h_f>).
          IF sy-subrc = 0.
            PERFORM fill_protocoll USING <fs_h_f> <fs_f> ls_err.
            PERFORM unlock_header_tab USING <fs_h_f>.
            MODIFY y0sd_posordh FROM <fs_h_f>.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDIF.
  ELSEIF pa_test IS INITIAL. " Simulation Fail
    LOOP AT gt_upd INTO ls_u.
      LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<fs_sf>) WHERE ordernum = ls_u-ordernum AND shiplocid = ls_u-shiplocid.
        <fs_sf> = VALUE #( BASE <fs_sf> procstatus = '03' procstatustext = ls_err-message procon = sy-datum ).
        ASSIGN gt_header[ ordernum = ls_u-ordernum ] TO FIELD-SYMBOL(<fs_h_sf>).
        IF sy-subrc = 0.
          PERFORM fill_protocoll USING <fs_h_sf> <fs_sf> ls_err.
          PERFORM unlock_header_tab USING <fs_h_sf>.
          MODIFY y0sd_posordh FROM <fs_h_sf>.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ELSE. " Test Run Logging
    LOOP AT gt_upd INTO ls_u.
      LOOP AT gt_item INTO DATA(ls_t) WHERE ordernum = ls_u-ordernum AND shiplocid = ls_u-shiplocid.
        ASSIGN gt_header[ ordernum = ls_u-ordernum ] TO FIELD-SYMBOL(<fs_h_t>).
        IF sy-subrc = 0.
          PERFORM fill_protocoll USING <fs_h_t> ls_t VALUE bapiret2( gt_return[ type = 'E' ] DEFAULT VALUE #( gt_return[ 1 ] OPTIONAL ) ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDIF.
  CLEAR: gt_items, gt_sched, gt_texts, gt_upd, g_posnr.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  HEADER
*&---------------------------------------------------------------------*
FORM header.
  gs_head = VALUE #( doc_type = 'YVO1' sales_org = '5090' distr_chan = '00' division = '00' req_date_h = g_date
                     sales_off = gs_header-salesofficeid pmnttrms = '0001' incoterms1 = 'PPD' ordcomb_in = 'X'
                     purch_no_c = gs_header-ordercycle created_by = gs_header-userid ).
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  FILL_PARTNER
*&---------------------------------------------------------------------*
FORM fill_partner.
  CLEAR gt_partners.
  APPEND VALUE #( partn_role = 'AG' itm_number = '000000' partn_numb = |{ gs_header-soldtoid ALPHA = IN }| ) TO gt_partners.
  IF gs_item_cpd-cdpcust IS NOT INITIAL.
    SELECT SINGLE lzone FROM kna1 INTO @DATA(lv_lz) WHERE kunnr = @gs_item_cpd-cdpcust.
    APPEND VALUE #( partn_role = 'WE' itm_number = '000000' partn_numb = |{ gs_item_cpd-cdpcust ALPHA = IN }|
                    name = gs_item_cpd-cstname1 name_2 = gs_item_cpd-cstname2 region = gs_item_cpd-cststate
                    street = |{ gs_item_cpd-cststreet }{ gs_item_cpd-csthouse_num1 }| city = gs_item_cpd-cstcity
                    postl_code = gs_item_cpd-cstzip country = gs_item_cpd-cstcountry telephone = gs_item_cpd-csttelephone
                    langu = 'E' langu_iso = 'EN' transpzone = lv_lz ) TO gt_partners.
  ELSE.
    APPEND VALUE #( partn_role = 'WE' itm_number = '000000' partn_numb = |{ gs_item-shiplocid ALPHA = IN }| ) TO gt_partners.
  ENDIF.
  APPEND VALUE #( partn_role = 'RG' itm_number = '000000' partn_numb = '0000405000' ) TO gt_partners.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  AVAILABILITY_CHECK
*&---------------------------------------------------------------------*
FORM availability_check.
  DATA: lt_item_in TYPE STANDARD TABLE OF bapiitemin, l_error TYPE char1.
  LOOP AT gt_items INTO DATA(ls_itm).
    APPEND VALUE #( material = ls_itm-material target_qty = ls_itm-target_qty * 1000 req_qty = ls_itm-target_qty * 1000
                    target_qu = ls_itm-target_qu t_unit_iso = ls_itm-t_unit_iso sales_unit = ls_itm-target_qu plant = ls_itm-plant ) TO lt_item_in.
  ENDLOOP.
  DATA(lt_part_in) = CORRESPONDING bapipartnr_tab( gt_partners ).
  PERFORM simulate TABLES lt_item_in lt_part_in USING CORRESPONDING bapisdhead( gs_head ) CHANGING l_error.
  IF l_error IS INITIAL.
    gt_items = VALUE #( FOR i IN lt_item_in ( material = i-material target_qty = i-target_qty target_qu = i-target_qu
                                              t_unit_iso = i-t_unit_iso sales_unit = i-target_qu plant = i-plant ) ).
  ELSE.
    LOOP AT gt_items ASSIGNING FIELD-SYMBOL(<fsi>). <fsi>-target_qty *= 1000. ENDLOOP.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  SIMULATE
*&---------------------------------------------------------------------*
FORM simulate TABLES pt_item STRUCTURE bapiitemin pt_partner STRUCTURE bapipartnr USING p_head CHANGING p_error.
  DATA: lt_o_it TYPE STANDARD TABLE OF bapiitemex, lt_s_it TYPE STANDARD TABLE OF bapiitemex, lt_msg TYPE STANDARD TABLE OF bapiret2, ls_ret TYPE bapireturn.
  CLEAR g_miss.
  CALL FUNCTION 'BAPI_SALESORDER_SIMULATE'
    EXPORTING order_header_in = p_head IMPORTING return = ls_ret
    TABLES    order_items_in = pt_item order_partners = pt_partner order_items_out = lt_o_it messagetable = lt_msg.
  PERFORM lock_header_tab_single.
  IF line_exists( lt_msg[ type = 'E' ] ). p_error = 'X'. RETURN. ENDIF.
  LOOP AT lt_o_it ASSIGNING FIELD-SYMBOL(<fo>).
    SELECT SINGLE meins FROM mara INTO @DATA(lv_me) WHERE matnr = @<fo>-material.
    IF sy-subrc = 0 AND lv_me <> <fo>-sales_unit.
      DATA(lv_q) = <fo>-qty_req_dt / 1000.
      CALL FUNCTION 'ROUND' EXPORTING input = lv_q sign = '-' IMPORTING output = lv_q EXCEPTIONS OTHERS = 4.
      <fo>-qty_req_dt = lv_q * 1000.
    ENDIF.
  ENDLOOP.

  ADD 1 TO g_seq.
  gs_plant = VALUE #( gt_plant[ vkbur = gs_customer-vkbur sequence = g_seq regio = gs_customer-regio ] OPTIONAL ).
  IF gs_plant IS INITIAL.
    LOOP AT gt_plant INTO gs_plant WHERE vkbur = gs_customer-vkbur AND sequence = g_seq.
      IF gs_customer-regio CP gs_plant-regio. EXIT. ENDIF.
      CLEAR gs_plant.
    ENDLOOP.
  ENDIF.

  IF gs_plant-werks IS NOT INITIAL.
    LOOP AT lt_o_it INTO DATA(ls_o) WHERE hg_lv_item IS INITIAL.
      DATA(lv_p) = ls_o-req_qty. DATA(lv_k) = ls_o-qty_req_dt / 1000.
      IF lv_p = lv_k. APPEND ls_o TO lt_s_it.
      ELSE.
        LOOP AT lt_o_it INTO DATA(ls_p) WHERE hg_lv_item = ls_o-itm_number.
          lv_k = ls_p-qty_req_dt / 1000.
          IF lv_k = ls_p-req_qty. APPEND VALUE #( BASE ls_o material = ls_o-mat_entrd qty_req_dt = lv_k * 1000 req_qty = lv_k ) TO lt_s_it. lv_p -= lv_k.
          ELSE.
            APPEND VALUE #( BASE ls_o material = ls_o-mat_entrd qty_req_dt = ls_p-qty_req_dt req_qty = ls_p-qty_req_dt / 1000 ) TO lt_s_it.
            lv_p -= ( ls_p-qty_req_dt / 1000 ). APPEND VALUE #( BASE ls_o qty_req_dt = lv_p * 1000 req_qty = lv_p plant = gs_plant-werks ) TO lt_s_it. g_miss = 'X'.
          ENDIF.
        ENDLOOP.
        IF sy-subrc <> 0.
          APPEND VALUE #( BASE ls_o qty_req_dt = lv_k * 1000 req_qty = lv_k ) TO lt_s_it.
          lv_p -= lv_k. APPEND VALUE #( BASE ls_o qty_req_dt = lv_p * 1000 req_qty = lv_p plant = gs_plant-werks ) TO lt_s_it. g_miss = 'X'.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ELSE.
    CLEAR g_miss. REFRESH pt_item.
    gs_plant = VALUE #( gt_plant[ vkbur = gs_customer-vkbur sequence = '01' regio = gs_customer-regio ] OPTIONAL ).
    IF gs_plant IS INITIAL.
      LOOP AT gt_plant INTO gs_plant WHERE vkbur = gs_customer-vkbur AND sequence = '01'.
        IF gs_customer-regio CP gs_plant-regio. EXIT. ENDIF.
        CLEAR gs_plant.
      ENDLOOP.
    ENDIF.
    LOOP AT lt_o_it INTO ls_o WHERE hg_lv_item IS INITIAL.
      lv_p = ls_o-req_qty. lv_k = ls_o-qty_req_dt / 1000.
      IF lv_p = lv_k. APPEND VALUE #( CORRESPONDING #( ls_o ) target_qty = ls_o-qty_req_dt req_qty = ls_o-qty_req_dt ) TO pt_item.
      ELSE.
        LOOP AT lt_o_it INTO ls_p WHERE hg_lv_item = ls_o-itm_number.
          lv_k = ls_p-qty_req_dt / 1000.
          IF lv_k = ls_p-req_qty. APPEND VALUE #( CORRESPONDING #( ls_o ) material = ls_o-mat_entrd target_qty = lv_k * 1000 req_qty = lv_k * 1000 ) TO pt_item. lv_p -= lv_k.
          ELSE.
            APPEND VALUE #( CORRESPONDING #( ls_o ) material = ls_o-mat_entrd target_qty = ls_p-qty_req_dt req_qty = ls_p-qty_req_dt ) TO pt_item.
            lv_p -= ( ls_p-qty_req_dt / 1000 ). APPEND VALUE #( CORRESPONDING #( ls_o ) target_qty = lv_p * 1000 req_qty = lv_p * 1000 plant = gs_plant-werks ) TO pt_item. g_miss = 'X'.
          ENDIF.
        ENDLOOP.
        IF sy-subrc <> 0.
          APPEND VALUE #( CORRESPONDING #( ls_o ) target_qty = lv_k * 1000 req_qty = lv_k * 1000 ) TO pt_item.
          lv_p -= lv_k. APPEND VALUE #( CORRESPONDING #( ls_o ) target_qty = lv_p * 1000 req_qty = lv_p * 1000 plant = gs_plant-werks ) TO pt_item. g_miss = 'X'.
        ENDIF.
      ENDIF.
    ENDLOOP.
    RETURN.
  ENDIF.

  IF g_miss IS NOT INITIAL.
    DATA(lt_it_sim) = VALUE bapiitemin_tab( FOR s IN lt_s_it ( VALUE #( CORRESPONDING #( s ) target_qty = s-qty_req_dt req_qty = s-qty_req_dt ) ) ).
    PERFORM simulate TABLES lt_it_sim pt_partner USING p_head CHANGING p_error.
    pt_item = CORRESPONDING #( lt_it_sim ).
  ELSE.
    pt_item = VALUE #( FOR s IN lt_s_it ( VALUE #( CORRESPONDING #( s ) target_qty = s-qty_req_dt req_qty = s-qty_req_dt ) ) ).
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  SAVE_TEXT
*&---------------------------------------------------------------------*
FORM save_text USING p_comment p_vbeln.
  SELECT vbeln, posnr, matnr, matwa FROM vbap INTO TABLE @DATA(lt_v) WHERE vbeln = @p_vbeln.
  IF sy-subrc <> 0. RETURN. ENDIF.
  DATA: lt_w TYPE STANDARD TABLE OF char132.
  CALL FUNCTION 'RKD_WORD_WRAP' EXPORTING textline = p_comment outputlen = 132 TABLES out_lines = lt_w.
  LOOP AT lt_v INTO DATA(ls_v).
    DATA(lt_tl) = VALUE tline_tab( FOR line IN lt_w ( tdformat = '*' tdline = line ) ).
    DATA(ls_i) = VALUE #( gt_items[ material = ls_v-matnr ] DEFAULT VALUE #( gt_items[ material = ls_v-matwa ] OPTIONAL ) ).
    LOOP AT gt_texts INTO DATA(ls_txt) WHERE itm_number = ls_i-itm_number. APPEND VALUE #( tdformat = '*' tdline = ls_txt-text_line ) TO lt_tl. ENDLOOP.
    DATA(ls_th) = VALUE thead( tdobject = 'VBBP' tdname = |{ ls_v-vbeln }{ ls_v-posnr }| tdid = '0002' tdspras = sy-langu ).
    CALL FUNCTION 'SAVE_TEXT' EXPORTING header = ls_th insert = 'X' savemode_direct = 'X' TABLES lines = lt_tl EXCEPTIONS OTHERS = 5.
  ENDLOOP.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  FILL_PROTOCOLL
*&---------------------------------------------------------------------*
FORM fill_protocoll USING p_h TYPE ty_header p_i TYPE y0sd_posordi p_ret TYPE bapiret2.
  DATA(ls_out_p) = CORRESPONDING yussd_pos_so_create_alv( p_h ).
  ls_out_p = CORRESPONDING #( BASE ( ls_out_p ) p_i ).
  ls_out_p-status = COND #( WHEN p_ret-type = 'E' THEN '@0A@' ELSE '@08@' ).
  ls_out_p-procstatustext = COND #( WHEN p_ret-type = 'E' THEN p_ret-message ELSE p_i-procstatustext ).

  SELECT SINGLE a~name_text FROM usr21 AS u INNER JOIN adrp AS a ON a~persnumber = u~persnumber INTO @ls_out_p-name_text WHERE u~bname = @p_h-changedby.
  APPEND ls_out_p TO gt_out.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GET_LOG
*&---------------------------------------------------------------------*
FORM get_log.
  SELECT h~ordernum, i~orderitem, h~changedby, a~name_text, i~procstatus, i~salesorder
    FROM y0sd_posordh AS h
    INNER JOIN y0sd_posordi AS i ON i~ordernum = h~ordernum
    LEFT JOIN usr21 AS u ON u~bname = h~changedby
    LEFT JOIN adrp AS a ON a~persnumber = u~persnumber
    INTO TABLE @DATA(lt_idx)
    WHERE h~ordernum IN @so_num AND h~ordercycle IN @so_ocycl AND h~accountid IN @so_acc AND h~salesofficeid IN @so_soid
      AND h~custgroupid IN @so_cgid AND i~salesorder IN @so_vbeln AND i~shiplocid IN @so_kunwe AND i~procstatus IN @so_stat AND i~uomorderqty > 0.
  IF sy-subrc <> 0. RETURN. ENDIF.
  SELECT * FROM y0sd_posordh INTO CORRESPONDING FIELDS OF TABLE @gt_out FOR ALL ENTRIES IN @lt_idx WHERE ordernum = @lt_idx-ordernum.
  IF sy-subrc = 0.
    SELECT * FROM y0sd_posordi INTO TABLE @gt_item FOR ALL ENTRIES IN @lt_idx WHERE ordernum = @lt_idx-ordernum AND orderitem = @lt_idx-orderitem.
    DATA(lt_t) = VALUE STANDARD TABLE OF yussd_pos_so_create_alv( ).
    LOOP AT gt_out INTO DATA(ls_o).
      LOOP AT gt_item INTO DATA(ls_i) WHERE ordernum = ls_o-ordernum.
        ASSIGN lt_idx[ ordernum = ls_o-ordernum orderitem = ls_i-orderitem ] TO FIELD-SYMBOL(<ls_r>).
        APPEND VALUE yussd_pos_so_create_alv( BASE CORRESPONDING #( ls_i ) ordernum = ls_o-ordernum changedby = ls_o-changedby
               name_text = COND #( WHEN sy-subrc = 0 THEN <ls_r>-name_text )
               status = SWITCH #( ls_i-procstatus WHEN '1' THEN '@09@' WHEN '2' THEN '@08@' WHEN '3' THEN '@0A@' ) ) TO lt_t.
      ENDLOOP.
    ENDLOOP.
    gt_out = lt_t.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  AUTHORITY_CHECK
*&---------------------------------------------------------------------*
FORM authority_check.
  AUTHORITY-CHECK OBJECT 'V_VBAK_AAT' ID 'AUART' FIELD 'YVO1' ID 'ACTVT' FIELD '01'.
  IF sy-subrc <> 0. MESSAGE e517(v1) WITH 'YV01'. ENDIF.
  AUTHORITY-CHECK OBJECT 'V_VBAK_VKO' ID 'VKORG' FIELD '5090' ID 'VTWEG' FIELD '00' ID 'SPART' FIELD '00' ID 'ACTVT' FIELD '01'.
  IF sy-subrc <> 0. MESSAGE e515(v1) WITH '5090' '00' '00'. ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  LOCKING/ALV/HELPERS
*&---------------------------------------------------------------------*
FORM lock_header_tab.
  LOOP AT gt_header ASSIGNING FIELD-SYMBOL(<fh>).
    DATA(ltx) = sy-tabix.
    CALL FUNCTION 'ENQUEUE_EY0SD_POSORDH_LC' EXPORTING ordernum = <fh>-ordernum ordercycle = <fh>-ordercycle accountid = <fh>-accountid _scope = '1' EXCEPTIONS OTHERS = 3.
    IF sy-subrc <> 0. APPEND VALUE #( CORRESPONDING #( <fh> ) procstatustext = TEXT-e01 status = '@0A@' ) TO gt_out. DELETE gt_header INDEX ltx. ENDIF.
  ENDLOOP.
ENDFORM.

FORM lock_header_tab_single.
  CALL FUNCTION 'ENQUEUE_EY0SD_POSORDH_LC' EXPORTING ordernum = gs_header-ordernum ordercycle = gs_header-ordercycle accountid = gs_header-account_o _scope = '1' EXCEPTIONS OTHERS = 3.
ENDFORM.

FORM unlock_header_tab USING p_h TYPE ty_header.
  CALL FUNCTION 'DEQUEUE_EY0SD_POSORDH_LC' EXPORTING ordernum = p_h-ordernum ordercycle = p_h-ordercycle accountid = p_h-accountid.
ENDFORM.

FORM add_line_item_text USING p_n p_p.
  DATA: lt_l TYPE STANDARD TABLE OF char132. CALL FUNCTION 'RKD_WORD_WRAP' EXPORTING textline = p_n outputlen = 132 TABLES out_lines = lt_l.
  LOOP AT lt_l INTO DATA(lv_l). APPEND VALUE #( itm_number = p_p text_id = '0002' langu = sy-langu langu_iso = sy-langu format_col = '*' text_line = lv_l ) TO gt_texts. ENDLOOP.
ENDFORM.

FORM output.
  DATA: lt_fc TYPE slis_t_fieldcat_alv. CALL FUNCTION 'REUSE_ALV_FIELDCATALOG_MERGE' EXPORTING i_program_name = sy-repid i_structure_name = 'YUSSD_POS_SO_CREATE_ALV' CHANGING ct_fieldcat = lt_fc.
  LOOP AT lt_fc ASSIGNING FIELD-SYMBOL(<ff>).
    <ff>-ddictxt = 'M'. <ff>-key = space.
    CASE <ff>-fieldname.
      WHEN 'SALESORDER'. <ff>-hotspot = 'X'.
      WHEN 'STATUS'. <ff>-icon = 'X'. <ff>-seltext_s = <ff>-seltext_m = <ff>-seltext_l = 'Status'.
      WHEN 'SOLDTOID'. <ff>-seltext_s = <ff>-seltext_m = <ff>-seltext_l = 'deviant Sold-to'.
    ENDCASE.
  ENDLOOP.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY' EXPORTING i_callback_program = sy-repid i_callback_pf_status_set = 'STATUS' i_callback_user_command = 'USER_COMMAND' is_layout = VALUE #( zebra = 'X' colwidth_optimize = 'X' ) it_fieldcat = lt_fc i_save = 'A' TABLES t_outtab = gt_out.
ENDFORM.

FORM user_command USING r_u LIKE sy-ucomm rs_s TYPE slis_selfield.
  IF r_u = '&IC1' AND rs_s-fieldname = 'SALESORDER'.
    DATA(lv_v) = VALUE #( gt_out[ rs_s-tabindex ]-salesorder OPTIONAL ).
    IF lv_v IS NOT INITIAL. SET PARAMETER ID 'AUN' FIELD lv_v. CALL TRANSACTION 'VA03' AND SKIP FIRST SCREEN. ENDIF.
  ENDIF.
ENDFORM.

FORM status USING p_extab TYPE slis_t_extab. SET PF-STATUS 'STANDARD' EXCLUDING p_extab. ENDFORM.

FORM error_cust_pos.
  LOOP AT gt_upd INTO DATA(ls_u).
    LOOP AT gt_item ASSIGNING FIELD-SYMBOL(<fi>) WHERE ordernum = ls_u-ordernum AND shiplocid = ls_u-shiplocid.
      PERFORM fill_protocoll USING gs_header <fi> VALUE #( message = TEXT-pos type = 'E' ).
    ENDLOOP.
  ENDLOOP.
ENDFORM.
