FUNCTION za_idoc_input_mbgmcr
  IMPORTING
    VALUE(input_method) LIKE bdwfap_par-inputmethd
    VALUE(mass_processing) LIKE bdwfap_par-mass_proc
  EXPORTING
    VALUE(workflow_result) LIKE bdwfap_par-result
    VALUE(application_variable) LIKE bdwfap_par-appl_var
    VALUE(in_update_task) LIKE bdwfap_par-updatetask
    VALUE(call_transaction_done) LIKE bdwfap_par-calltrans
  TABLES
    idoc_contrl LIKE edidc
    idoc_data LIKE edidd
    idoc_status LIKE bdidocstat
    return_variables LIKE bdwfretvar
    serialization_info LIKE bdi_ser
  EXCEPTIONS
    wrong_function_called.

*----------------------------------------------------------------------*
* 1. Data Declarations, Constants and Performance Buffers
*----------------------------------------------------------------------*
  TABLES: likp, ekpo, ekbe, mara, ekes, eket, qals, t156, y0mm_proc_ebeln,
          y0ca_ale_delay, mbew, t001w, t001k, lips, y0mm_gm_matnrcnv,
          y0mm_gm_lifnrcnv, y0pp_calc_rbfqty.

  CONSTANTS: co_mbgmcr_head TYPE edi_dd40-segnam VALUE 'E1BP2017_GM_HEAD_01',
             co_mbgmcr_item TYPE edi_dd40-segnam VALUE 'E1BP2017_GM_ITEM_CREATE',
             co_mbgmcr_code TYPE edi_dd40-segnam VALUE 'E1BP2017_GM_CODE',
             co_mbgmcr_gen  TYPE edi_dd40-segnam VALUE 'E1MBGMCR',
             co_mbgmcr_ser  TYPE edi_dd40-segnam VALUE 'E1BP2017_GM_SERIALNUMBER',
             co_mbgmcr_z1   TYPE edi_dd40-segnam VALUE 'Z1BP2017',
             co_mbgmcr_vser TYPE edi_dd40-segnam VALUE 'Y0MM_GM_SERIAL_MAT',
             co_labor_etikett TYPE labor VALUE 'Z00',
             co_lfart_yidv  TYPE lfart  VALUE 'YIDV',
             co_error_idocs TYPE bdwfretvar-wf_param VALUE 'Error_IDocs',
             co_appl_objs   TYPE bdwfretvar-wf_param VALUE 'Appl_Objects'.

  " Business Variables (Preserving original naming)
  DATA: BEGIN OF it_lock OCCURS 0, ebeln LIKE ekko-ebeln, lock TYPE c, END OF it_lock,
        gf_inbound_del_flag, gf_mtart LIKE mara-mtart, gs_ctu_params LIKE ctu_params VALUE 'NS',
        BEGIN OF gt_inb_item OCCURS 0,
          vbeln LIKE likp-vbeln,
          posnr LIKE lips-posnr,
          matnr LIKE mara-matnr,
          lfimg LIKE lips-lfimg,
          vrkme LIKE lips-vrkme,
        END OF gt_inb_item,
        gt_inb_item_det LIKE y0mm_vl32n_pos OCCURS 0 WITH HEADER LINE,
        gt_mess LIKE bdcmsgcoll OCCURS 0 WITH HEADER LINE,
        all_locked TYPE c VALUE space, hi_flag_etikett, hi_menge LIKE goodsmvt_item-entry_qnt,
        lt_return_bapi TYPE TABLE OF bapiret2 WITH HEADER LINE.

  DATA: wa_ekbe_loc LIKE ekbe, wa_ekes_loc LIKE ekes, wa_mseg_loc LIKE mseg, wa_marc_loc LIKE mara, hi_labst_loc LIKE mard-labst,
        lk_tr_posted TYPE i, hi_arckey LIKE edidc-arckey, wa_run_i LIKE yudc_int_run_i, l_bwkey TYPE bwkey, l_bukrs TYPE bukrs,
        lv_dd_map TYPE abap_bool, lv_matnr TYPE matnr, purchaseorder TYPE ebeln, matnr TYPE matnr, ebeln TYPE ebeln, vbeln TYPE vbeln_vl,
        hi_entry_qnt TYPE goodsmvt_item-entry_qnt, goodsmvt_item_save TYPE bapi2017_gm_item_create,
        hi_lfart LIKE likp-lfart, hi_weora TYPE ekpo-weora, hi_bsart TYPE ekko-bsart, hi_bmeng TYPE ekes-menge, hi_omeng TYPE ekes-menge,
        hi_posted_quant TYPE ekbe-menge, hi_check_meng TYPE ekbe-menge, hi_tabix TYPE sytabix, hi_bamng TYPE ekbe-menge,
        hi_mblnr TYPE mblnr, hi_mjahr TYPE mjahr, hi_lfimg TYPE lfimg, hi_vrkme TYPE vrkme.

  DATA: l_blank_msgv TYPE symsgv VALUE ' ', error_flag TYPE abap_bool, bapi_idoc_status TYPE bdidocstat-status, bapi_retn_info TYPE bapiret2.

  " IDoc and BAPI structures
  DATA: e1mbgmcr TYPE e1mbgmcr, e1bp2017_gm_head_01 TYPE e1bp2017_gm_head_01, e1bp2017_gm_code TYPE e1bp2017_gm_code,
        e1bp2017_gm_item_create TYPE e1bp2017_gm_item_create, e1bp2017_gm_serialnumber TYPE e1bp2017_gm_serialnumber,
        z1bp2017 TYPE z1bp2017, goodsmvt_header TYPE bapi2017_gm_head_01, goodsmvt_code TYPE bapi2017_gm_code, testrun TYPE bapi2017_gm_gen-testrun,
        goodsmvt_headret TYPE bapi2017_gm_head_ret, materialdocument TYPE bapi2017_gm_head_ret-mat_doc, matdocumentyear TYPE bapi2017_gm_head_ret-doc_year,
        goodsmvt_item TYPE TABLE OF bapi2017_gm_item_create WITH HEADER LINE, goodsmvt_serialnumber TYPE TABLE OF bapi2017_gm_serialnumber WITH HEADER LINE,
        return TYPE TABLE OF bapiret2 WITH HEADER LINE,
        lt_items TYPE y0e1bp2017_gm_item_create_t, lt_serial_nums TYPE y0mm_gm_serial_mat_t.

  " BAPI Structures for PO
  DATA: ls_poheader TYPE bapimepoheader, ls_poheaderx TYPE bapimepoheaderx, ls_poaddrvendor TYPE bapimepoaddrvendor,
        ls_po_header_add_data TYPE bapiekkoa, ls_po_address TYPE bapiaddress,
        lt_poitem TYPE TABLE OF bapimepoitem, lt_poitemx TYPE TABLE OF bapimepoitemx,
        lt_poschedule TYPE TABLE OF bapimeposchedule, lt_poschedulex TYPE TABLE OF bapimeposchedulx,
        lt_return_po TYPE TABLE OF bapiret2, lt_po_item_add_data TYPE TABLE OF bapiekpoa,
        lt_po_item_account_assignment TYPE TABLE OF bapiekkn, lt_po_item_text TYPE TABLE OF bapiekpotx,
        lt_poaccount TYPE TABLE OF bapimepoaccount, lt_poaccountx TYPE TABLE OF bapimepoaccountx,
        lt_potextitem TYPE TABLE OF bapimepotext.

  " Optimization Buffers
  DATA: lt_mara_buf TYPE HASHED TABLE OF mara WITH UNIQUE KEY matnr,
        lt_ekko_buf TYPE HASHED TABLE OF ekko WITH UNIQUE KEY ebeln,
        lt_ekpo_buf TYPE SORTED TABLE OF ekpo WITH NON-UNIQUE KEY ebeln ebelp WITH NON-UNIQUE KEY matnr werks WITH NON-UNIQUE KEY bednr afnam,
        lt_ekbe_buf TYPE SORTED TABLE OF ekbe WITH NON-UNIQUE KEY ebeln ebelp matnr werks xblnr,
        lt_ekes_buf TYPE SORTED TABLE OF ekes WITH NON-UNIQUE KEY ebeln ebelp charg matnr vbeln,
        lt_eket_buf TYPE SORTED TABLE OF eket WITH NON-UNIQUE KEY ebeln ebelp,
        lt_likp_buf TYPE HASHED TABLE OF likp WITH UNIQUE KEY vbeln,
        lt_lips_buf TYPE SORTED TABLE OF lips WITH NON-UNIQUE KEY vbeln posnr WITH NON-UNIQUE KEY vgbel vgpos,
        lt_qals_buf TYPE SORTED TABLE OF qals WITH NON-UNIQUE KEY charg matnr werkvorg lagortvorg,
        lt_t156_buf TYPE HASHED TABLE OF t156 WITH UNIQUE KEY bwart,
        lt_t001w_buf TYPE HASHED TABLE OF t001w WITH UNIQUE KEY werks,
        lt_t001k_buf TYPE HASHED TABLE OF t001k WITH UNIQUE KEY bwkey,
        lt_t001l_buf TYPE SORTED TABLE OF t001l WITH UNIQUE KEY werks lgort,
        lt_v_ekko_ekpo_buf TYPE SORTED TABLE OF v_ekko_ekpo WITH NON-UNIQUE KEY werks matnr lifnr,
        lt_mbew_buf TYPE HASHED TABLE OF mbew WITH UNIQUE KEY matnr bwkey.

  DATA: it_bwart_po TYPE TABLE OF y0mm_bwart_po, it_po_fixval TYPE TABLE OF y0mm_po_fixval, it_gm_conv TYPE TABLE OF y0mm_gm_conv,
        it_noinv TYPE TABLE OF y0mm_gmpo_noinv, gt_mbgmcr_chk TYPE TABLE OF y0mm_mbgmcr_chk, it_y0mm_inbounddeli TYPE TABLE OF y0mm_inbounddeli,
        lt_dd_plt_buf TYPE TABLE OF y0bc_idoc_dd_plt, lt_matnrcnv_buf TYPE TABLE OF y0mm_gm_matnrcnv, lt_rbfqty_buf TYPE TABLE OF y0pp_calc_rbfqty,
        lt_lifnrcnv_buf TYPE TABLE OF y0mm_gm_lifnrcnv, lt_migo_weora_buf TYPE TABLE OF y0mm_migo_weora, lt_mbgmcr_lib_buf TYPE TABLE OF yusmm_mbgmcr_lib,
        lt_mbgmcr_tr_buf TYPE TABLE OF y0mm_mbgmcr_tr, lt_yudc_trans_buf TYPE TABLE OF yudc_trans, lt_braziltr_buf TYPE TABLE OF ybrmm_idoc_tr,
        lt_delay_buf TYPE TABLE OF y0ca_ale_delay.

  DATA: t_edidd TYPE TABLE OF edidd WITH HEADER LINE, wa_edidd LIKE edidd,
        it_ekbe_rev TYPE TABLE OF ekbe WITH HEADER LINE, it_ekbe_rev_cancel TYPE TABLE OF ekbe WITH HEADER LINE,
        goodsmvt_item_append TYPE TABLE OF bapi2017_gm_item_create WITH HEADER LINE,
        it_eket TYPE TABLE OF eket WITH HEADER LINE, it_ekes TYPE TABLE OF ekes WITH HEADER LINE, it_ch_po_numbers TYPE TABLE OF ebeln WITH HEADER LINE,
        it_po_header TYPE TABLE OF bapimepoheader WITH HEADER LINE, it_all_po_items TYPE TABLE OF bapi2017_gm_item_create WITH HEADER LINE,
        it_all_po_schedules TYPE TABLE OF bapi2017_gm_item_create WITH HEADER LINE, it_ch_po_return TYPE TABLE OF bapiret2 WITH HEADER LINE,
        it_ch_all_po_items TYPE TABLE OF bapimepoitem WITH HEADER LINE, it_ch_all_po_itemsx TYPE TABLE OF bapimepoitemx WITH HEADER LINE,
        it_ch_all_po_schedules TYPE TABLE OF bapimeposchedule WITH HEADER LINE, it_ch_all_po_schedulex TYPE TABLE OF bapimeposchedulx WITH HEADER LINE,
        it_po_items TYPE TABLE OF bapimepoitem WITH HEADER LINE, it_po_schedules TYPE TABLE OF bapimeposchedule WITH HEADER LINE,
        it_ch_po_items TYPE TABLE OF bapimepoitem WITH HEADER LINE, it_ch_po_itemsx TYPE TABLE OF bapimepoitemx WITH HEADER LINE,
        it_ch_po_schedules TYPE TABLE OF bapimeposchedule WITH HEADER LINE, it_ch_po_schedulex TYPE TABLE OF bapimeposchedulx WITH HEADER LINE,
        it_v_ekko_ekpo TYPE TABLE OF v_ekko_ekpo WITH HEADER LINE.

*----------------------------------------------------------------------*
* 2. INITIALIZATION AND PRE-FETCH
*----------------------------------------------------------------------*
  CLEAR: in_update_task, call_transaction_done, workflow_result.
  IF NOT line_exists( idoc_contrl[ 1 ] ). EXIT. ENDIF.
  IF idoc_contrl[ 1 ]-mestyp <> 'MBGMCR'. RAISE wrong_function_called. ENDIF.

  " 2.1 Bulk key collection from all IDocs in the packet
  DATA: lt_mat_k TYPE TABLE OF matnr, lt_eb_k TYPE TABLE OF ebeln, lt_vb_k TYPE TABLE OF vbeln_vl, lt_we_k TYPE TABLE OF werks_d, lt_li_k TYPE TABLE OF lifnr, lt_me_k TYPE TABLE OF edidc-mestyp.
  LOOP AT idoc_contrl. APPEND idoc_contrl-mestyp TO lt_me_k. ENDLOOP.
  LOOP AT idoc_data INTO DATA(ls_pk) WHERE segnam = co_mbgmcr_item.
    ls_mbgmcr_item = ls_pk-sdata.
    IF ls_mbgmcr_item-material IS NOT INITIAL. APPEND ls_mbgmcr_item-material TO lt_mat_k. ENDIF.
    IF ls_mbgmcr_item-po_number IS NOT INITIAL. APPEND ls_mbgmcr_item-po_number TO lt_eb_k. ENDIF.
    IF ls_mbgmcr_item-deliv_numb_to_search IS NOT INITIAL. APPEND ls_mbgmcr_item-deliv_numb_to_search TO lt_vb_k. ENDIF.
    IF ls_mbgmcr_item-plant IS NOT INITIAL. APPEND ls_mbgmcr_item-plant TO lt_we_k. ENDIF.
    IF ls_mbgmcr_item-vendor IS NOT INITIAL. APPEND |{ ls_mbgmcr_item-vendor ALPHA = IN }| TO lt_li_k. ENDIF.
  ENDLOOP.
  SORT: lt_mat_k, lt_eb_k, lt_vb_k, lt_we_k, lt_li_k, lt_me_k.
  DELETE ADJACENT DUPLICATES FROM: lt_mat_k, lt_eb_k, lt_vb_k, lt_we_k, lt_li_k, lt_me_k.

  " 2.2 Bulk Data Fetch into buffers
  IF lt_mat_k IS NOT INITIAL.
    SELECT * FROM mara INTO TABLE lt_mara_buf FOR ALL ENTRIES IN lt_mat_k WHERE matnr = lt_mat_k-table_line.
    SELECT * FROM y0pp_calc_rbfqty INTO TABLE lt_rbfqty_buf FOR ALL ENTRIES IN lt_mat_k WHERE matnr = lt_mat_k-table_line.
    SELECT * FROM qals INTO TABLE lt_qals_buf FOR ALL ENTRIES IN lt_mat_k WHERE matnr = lt_mat_k-table_line.
  ENDIF.
  IF lt_eb_k IS NOT INITIAL.
    SELECT * FROM ekko INTO TABLE lt_ekko_buf FOR ALL ENTRIES IN lt_eb_k WHERE ebeln = lt_eb_k-table_line.
    SELECT * FROM ekpo INTO TABLE lt_ekpo_buf FOR ALL ENTRIES IN lt_eb_k WHERE ebeln = lt_eb_k-table_line.
    SELECT * FROM ekbe INTO TABLE lt_ekbe_buf FOR ALL ENTRIES IN lt_eb_k WHERE ebeln = lt_eb_k-table_line.
    SELECT * FROM eket INTO TABLE lt_eket_buf FOR ALL ENTRIES IN lt_eb_k WHERE ebeln = lt_eb_k-table_line.
    SELECT * FROM ekes INTO TABLE lt_ekes_buf FOR ALL ENTRIES IN lt_eb_k WHERE ebeln = lt_eb_k-table_line.
  ENDIF.
  IF lt_vb_k IS NOT INITIAL.
    SELECT * FROM likp INTO TABLE lt_likp_buf FOR ALL ENTRIES IN lt_vb_k WHERE vbeln = lt_vb_k-table_line.
    SELECT * FROM lips INTO TABLE lt_lips_buf FOR ALL ENTRIES IN lt_vb_k WHERE vbeln = lt_vb_k-table_line.
  ENDIF.
  IF lt_we_k IS NOT INITIAL.
    SELECT * FROM t001w INTO TABLE lt_t001w_buf FOR ALL ENTRIES IN lt_we_k WHERE werks = lt_we_k-table_line.
    IF lt_t001w_buf IS NOT INITIAL. SELECT * FROM t001k INTO TABLE lt_t001k_buf FOR ALL ENTRIES IN lt_t001w_buf WHERE bwkey = lt_t001w_buf-bwkey. ENDIF.
    SELECT * FROM t001l INTO TABLE lt_t001l_buf FOR ALL ENTRIES IN lt_we_k WHERE werks = lt_we_k-table_line.
    IF lt_mat_k IS NOT INITIAL AND lt_li_k IS NOT INITIAL.
       SELECT * FROM v_ekko_ekpo INTO TABLE lt_v_ekko_ekpo_buf FOR ALL ENTRIES IN lt_we_k WHERE werks = lt_we_k-table_line.
    ENDIF.
  ENDIF.
  IF lt_mat_k IS NOT INITIAL AND lt_t001k_buf IS NOT INITIAL.
     SELECT * FROM mbew INTO TABLE lt_mbew_buf FOR ALL ENTRIES IN lt_mat_k WHERE matnr = lt_mat_k-table_line.
  ENDIF.

  SELECT * FROM t156 INTO TABLE lt_t156_buf.
  SELECT * FROM y0mm_bwart_po INTO TABLE it_bwart_po.
  SELECT * FROM y0mm_po_fixval INTO TABLE it_po_fixval.
  SELECT * FROM y0mm_gm_conv INTO TABLE it_gm_conv.
  SELECT * FROM y0mm_gmpo_noinv INTO TABLE it_noinv.
  SELECT * FROM y0mm_mbgmcr_chk INTO TABLE gt_mbgmcr_chk.
  SELECT * FROM y0mm_inbounddeli INTO TABLE it_y0mm_inbounddeli ORDER BY PRIMARY KEY.
  SELECT * FROM y0bc_idoc_dd_plt INTO TABLE lt_dd_plt_buf.
  SELECT * FROM y0mm_gm_matnrcnv INTO TABLE lt_matnrcnv_buf.
  SELECT * FROM y0mm_gm_lifnrcnv INTO TABLE lt_lifnrcnv_buf.
  SELECT * FROM y0mm_migo_weora INTO TABLE lt_migo_weora_buf.
  SELECT * FROM yusmm_mbgmcr_lib INTO TABLE lt_mbgmcr_lib_buf.
  SELECT * FROM y0mm_mbgmcr_tr INTO TABLE lt_mbgmcr_tr_buf.
  SELECT * FROM yudc_trans INTO TABLE lt_yudc_trans_buf.
  SELECT * FROM ybrmm_idoc_tr INTO TABLE lt_braziltr_buf.
  IF lt_me_k IS NOT INITIAL. SELECT * FROM y0ca_ale_delay INTO TABLE lt_delay_buf FOR ALL ENTRIES IN lt_me_k WHERE mesty = lt_me_k-table_line. ENDIF.
  SELECT SINGLE spe_inb_vl_mm FROM tvshp INTO @DATA(gv_spe_act) WHERE spe_inb_vl_mm = 'X'.

*----------------------------------------------------------------------*
* 3. MAIN IDOC PACKET PROCESSING
*----------------------------------------------------------------------*
  LOOP AT idoc_contrl ASSIGNING FIELD-SYMBOL(<ic_main>).
    REFRESH t_edidd.
    LOOP AT idoc_data WHERE docnum = <ic_main>-docnum. APPEND idoc_data TO t_edidd. ENDLOOP.

    CLEAR: goodsmvt_header, goodsmvt_code, testrun, goodsmvt_headret, materialdocument, matdocumentyear, goodsmvt_item, goodsmvt_serialnumber, return, z1bp2017, hi_flag_etikett, gf_inbound_del_flag, error_flag, bapi_idoc_status.
    REFRESH: goodsmvt_item, goodsmvt_serialnumber, return, it_po_header, it_all_po_items, it_all_po_schedules, it_ch_po_numbers, it_ch_all_po_items, it_ch_all_po_itemsx, it_ch_all_po_schedules, it_ch_all_po_schedulex, it_v_ekko_ekpo, it_eket, it_ekes, gt_inb_item, lt_items, lt_serial_nums, goodsmvt_item_append.

    " 3.1 Duplicate check (Buffered)
    IF line_exists( t_edidd[ segnam = co_mbgmcr_head ] ) AND line_exists( t_edidd[ segnam = co_mbgmcr_item ] ).
       ls_mbgmcr_head = t_edidd[ segnam = co_mbgmcr_head ]-sdata.
       ls_mbgmcr_item = t_edidd[ segnam = co_mbgmcr_item ]-sdata.
       DATA(dup_res) = y0mm_cl_inbound_idoc_checks=>duplicate_check( idoc_header = <ic_main> segment_mbgmcr_item = ls_mbgmcr_item segment_mbgmcr_head = ls_mbgmcr_head ).
       IF line_exists( dup_res[ type = 'E' ] ).
          ASSIGN dup_res[ type = 'E' ] TO FIELD-SYMBOL(<er>).
          PERFORM insert_status USING '51' <er>-type <er>-id <er>-number <er>-message_v1 <er>-message_v2 <er>-message_v3 <er>-message_v4.
          CONTINUE.
       ENDIF.
    ENDIF.

    " 3.2 Unlock previos po's
    LOOP AT it_lock. DELETE FROM y0mm_proc_ebeln WHERE ebeln = it_lock-ebeln. COMMIT WORK. ENDLOOP.
    REFRESH it_lock.

    " 3.3 Segments Processing
    CATCH SYSTEM-EXCEPTIONS conversion_errors = 1.
      CLEAR: lv_dd_map, ls_gm_head_check.
      READ TABLE t_edidd INTO idoc_data WITH KEY segnam = co_mbgmcr_head.
      IF sy-subrc = 0. ls_gm_head_check = idoc_data-sdata. ENDIF.
      IF line_exists( lt_dd_plt_buf[ partyp = <ic_main>-sndprt parnum = <ic_main>-sndprn mestyp = <ic_main>-mestyp ] ). lv_dd_map = abap_true. ENDIF.

      LOOP AT t_edidd INTO idoc_data.
        CASE idoc_data-segnam.
          WHEN co_mbgmcr_gen. e1mbgmcr = idoc_data-sdata. testrun = e1mbgmcr-testrun.
          WHEN co_mbgmcr_head.
            e1bp2017_gm_head_01 = idoc_data-sdata. MOVE-CORRESPONDING e1bp2017_gm_head_01 TO goodsmvt_header.
            IF e1bp2017_gm_head_01-pstng_date IS INITIAL. CLEAR goodsmvt_header-pstng_date. ENDIF.
            IF e1bp2017_gm_head_01-doc_date IS INITIAL. CLEAR goodsmvt_header-doc_date. ENDIF.
          WHEN co_mbgmcr_code. e1bp2017_gm_code = idoc_data-sdata. MOVE-CORRESPONDING e1bp2017_gm_code TO goodsmvt_code.
          WHEN co_mbgmcr_item.
            " 4. Processing Loop (Inside segment CASE)
            e1bp2017_gm_item_create = idoc_data-sdata.
            IF lv_dd_map = abap_true.
               cl_matnr_chk_mapper=>convert_on_input( EXPORTING iv_matnr18 = e1bp2017_gm_item_create-material IMPORTING ev_matnr40 = lv_matnr ).
               e1bp2017_gm_item_create-material = ycl_bc_idoc_functions=>map_material_rb_dd( iv_partyp = <ic_main>-sndprt iv_parnum = <ic_main>-sndprn iv_mestyp = <ic_main>-mestyp iv_date = CONV datum( ls_gm_head_check-pstng_date ) iv_matnr_in = lv_matnr ).
               e1bp2017_gm_item_create-plant = ycl_bc_idoc_functions=>map_plant_in( iv_partyp = <ic_main>-sndprt iv_parnum = <ic_main>-sndprn iv_mestyp = <ic_main>-mestyp iv_date = CONV datum( ls_gm_head_check-pstng_date ) iv_werks_idoc = e1bp2017_gm_item_create-plant ).
               IF e1bp2017_gm_item_create-move_mat IS NOT INITIAL.
                  cl_matnr_chk_mapper=>convert_on_input( EXPORTING iv_matnr18 = e1bp2017_gm_item_create-move_mat IMPORTING ev_matnr40 = lv_matnr ).
                  e1bp2017_gm_item_create-move_mat = ycl_bc_idoc_functions=>map_material_rb_dd( iv_partyp = <ic_main>-sndprt iv_parnum = <ic_main>-sndprn iv_mestyp = <ic_main>-mestyp iv_date = CONV datum( ls_gm_head_check-pstng_date ) iv_matnr_in = lv_matnr ).
               ENDIF.
            ENDIF.
            MOVE-CORRESPONDING e1bp2017_gm_item_create TO goodsmvt_item.
            lt_items = VALUE #( BASE lt_items ( e1bp2017_gm_item_create ) ).

            READ TABLE lt_mara_buf INTO DATA(wa_mara_loc) WITH KEY matnr = goodsmvt_item-material.
            READ TABLE lt_t156_buf INTO DATA(wa_t156_loc) WITH KEY bwart = goodsmvt_item-move_type.

            " BI / Partner Conversion
            IF goodsmvt_item-deliv_numb_to_search IS NOT INITIAL.
               READ TABLE lt_likp_buf INTO DATA(wa_lk_bi) WITH KEY vbeln = goodsmvt_item-deliv_numb_to_search.
               IF sy-subrc = 0 AND wa_lk_bi-vbtyp <> '7'. goodsmvt_item-deliv_numb = goodsmvt_item-deliv_numb_to_search. goodsmvt_item-deliv_item = goodsmvt_item-deliv_item_to_search. ENDIF.
            ENDIF.
            IF line_exists( lt_matnrcnv_buf[ sndprn = <ic_main>-sndprn ] ).
               CALL FUNCTION 'Y_0CA_PARTNER_CONVERT_MATNR' EXPORTING matnr_in = goodsmvt_item-material direct = '2' IMPORTING matnr_out = goodsmvt_item-material EXCEPTIONS OTHERS = 0.
               CALL FUNCTION 'Y_0CA_PARTNER_CONVERT_MATNR' EXPORTING matnr_in = goodsmvt_item-move_mat direct = '2' IMPORTING matnr_out = goodsmvt_item-move_mat EXCEPTIONS OTHERS = 0.
            ENDIF.
            READ TABLE lt_rbfqty_buf INTO DATA(wa_rb_loc) WITH KEY matnr = goodsmvt_item-material.
            IF sy-subrc = 0. goodsmvt_item-entry_qnt = goodsmvt_item-entry_qnt * wa_rb_loc-faktr. ENDIF.

            " Vendor / Plausibility
            goodsmvt_item-vendor = |{ goodsmvt_item-vendor ALPHA = IN }|.
            READ TABLE lt_lifnrcnv_buf INTO DATA(wa_lf_loc) WITH KEY sndprn = <ic_main>-sndprn lifnr_ext = goodsmvt_item-vendor.
            IF sy-subrc = 0. goodsmvt_item-vendor = wa_lf_loc-lifnr. ENDIF.
            IF goodsmvt_code = '01'.
               DATA(lv_v_loc) = abap_true.
               LOOP AT gt_mbgmcr_chk INTO DATA(ls_c) WHERE mestyp = <ic_main>-mestyp AND lifnr = goodsmvt_item-vendor AND werks = e1bp2017_gm_item_create-plant AND datab <= sy-datum.
                  IF <ic_main>-sndprn CP ls_c-sndprn AND NOT |{ goodsmvt_header-ref_doc_no WIDTH = 16 ALPHA = IN }| BETWEEN ls_c-fromnumber AND ls_c-tonumber. lv_v_loc = abap_false. ENDIF.
               ENDLOOP.
               IF lv_v_loc = abap_false. PERFORM insert_status USING '51' 'E' 'Y0MM_IDOCS' '050' goodsmvt_header-ref_doc_no goodsmvt_item-plant l_blank_msgv l_blank_msgv. error_flag = abap_true. CONTINUE. ENDIF.
            ENDIF.

            " Custom conv / WEORA Find / ZRM Find
            READ TABLE it_gm_conv INTO DATA(ls_cv_loc) WITH KEY parnum = <ic_main>-sndprn matnr = goodsmvt_item-material bwart = goodsmvt_item-move_type.
            IF sy-subrc = 0.
               goodsmvt_code = ls_cv_loc-gm_code_new. goodsmvt_item-move_type = ls_cv_loc-bwart_new. goodsmvt_item-mvt_ind = ls_cv_loc-mvt_ind_new. goodsmvt_item-move_plant = goodsmvt_item-plant. goodsmvt_item-move_stloc = goodsmvt_item-stge_loc. goodsmvt_item-plant = ls_cv_loc-umwrk. goodsmvt_item-stge_loc = ls_cv_loc-umlgo.
            ENDIF.
            IF goodsmvt_item-po_number IS INITIAL.
               READ TABLE lt_lips_buf INTO DATA(wa_lp_loc) WITH KEY vbeln = goodsmvt_item-deliv_numb_to_search posnr = goodsmvt_item-deliv_item_to_search.
               IF sy-subrc = 0. goodsmvt_item-po_number = wa_lp_loc-vgbel. goodsmvt_item-po_item = wa_lp_loc-vgpos. ENDIF.
            ENDIF.
            READ TABLE lt_ekpo_buf INTO DATA(wa_ep_loc) WITH KEY ebeln = goodsmvt_item-po_number ebelp = goodsmvt_item-po_item.
            IF sy-subrc = 0 AND wa_ep_loc-weora = 'X' AND ( goodsmvt_item-move_type = '101' OR goodsmvt_item-move_type = '102' ).
               IF line_exists( lt_ekes_buf[ ebeln = goodsmvt_item-po_number ebelp = goodsmvt_item-po_item charg = goodsmvt_item-batch ] ).
                  IF goodsmvt_item-move_type = '101'. goodsmvt_item-move_type = '109'. IF gv_spe_act <> 'X'. CLEAR: goodsmvt_item-po_number, goodsmvt_item-po_item. ENDIF.
                  ELSE. goodsmvt_item-move_type = '110'. CLEAR: goodsmvt_item-po_number, goodsmvt_item-po_item. ENDIF.
               ENDIF.
            ENDIF.
            READ TABLE lt_ekko_buf INTO DATA(wa_ek_loc) WITH KEY ebeln = goodsmvt_item-po_number.
            IF sy-subrc = 0 AND wa_ek_loc-bsart = 'ZRM'.
               LOOP AT lt_ekpo_buf INTO DATA(ls_z_loc) WHERE bednr = goodsmvt_item-po_number AND afnam = goodsmvt_item-po_item. goodsmvt_item-po_number = ls_z_loc-ebeln. goodsmvt_item-po_item = ls_z_loc-ebelp. EXIT. ENDLOOP.
            ENDIF.

            " POS Inbound delivery handling
            READ TABLE lt_likp_buf INTO DATA(wa_l_pos) WITH KEY vbeln = goodsmvt_item-deliv_numb_to_search.
            IF line_exists( it_y0mm_inbounddeli[ zndprn = <ic_main>-sndprn lfart = wa_l_pos-lfart bwart = goodsmvt_item-move_type mtart = wa_mara_loc-mtart ] ).
               gf_inbound_del_flag = 'X'. gt_inb_item-vbeln = goodsmvt_item-deliv_numb_to_search. gt_inb_item-posnr = goodsmvt_item-deliv_item_to_search. gt_inb_item-matnr = goodsmvt_item-material. gt_inb_item-lfimg = goodsmvt_item-entry_qnt. gt_inb_item-vrkme = goodsmvt_item-entry_uom. APPEND gt_inb_item.
            ENDIF.

            " Reversal History / Label Splitting
            IF gf_inbound_del_flag <> 'X' AND wa_t156_loc-shkzg = 'H'.
               LOOP AT lt_ekbe_buf INTO wa_ekbe_loc WHERE ebeln = goodsmvt_item-po_number AND ebelp = goodsmvt_item-po_item AND matnr = goodsmvt_item-material AND werks = goodsmvt_item-plant AND xblnr = goodsmvt_header-ref_doc_no AND menge = goodsmvt_item-entry_qnt AND shkzg = 'S' AND vgabe = '1'.
                  goodsmvt_item-ref_doc_yr = wa_ekbe_loc-lfgja. goodsmvt_item-ref_doc = wa_ekbe_loc-lfbnr. goodsmvt_item-ref_doc_it = wa_ekbe_loc-lfpos. EXIT.
               ENDLOOP.
            ENDIF.
            IF wa_mara_loc-labor = co_labor_etikett AND goodsmvt_code = '01' AND wa_t156_loc-shkzg = 'S'.
               hi_flag_etikett = 'X'. hi_entry_qnt = goodsmvt_item-entry_qnt. goodsmvt_item_save = goodsmvt_item.
               LOOP AT lt_v_ekko_ekpo_buf INTO DATA(wa_v_label) WHERE werks = goodsmvt_item-plant AND matnr = goodsmvt_item-material AND lifnr = goodsmvt_item-vendor AND loekz = space AND elikz = space.
                  LOOP AT lt_eket_buf INTO DATA(wa_t_label) WHERE ebeln = wa_v_label-ebeln AND ebelp = wa_v_label-ebelp AND wemng < wa_t_label-menge.
                     LOOP AT lt_ekes_buf INTO DATA(wa_s_label) WHERE ebeln = wa_t_label-ebeln AND ebelp = wa_t_label-ebelp AND loekz = space.
                        DATA(hi_ov_label) = wa_s_label-menge - wa_s_label-dabmg.
                        IF hi_ov_label < hi_entry_qnt. hi_entry_qnt = hi_entry_qnt - hi_ov_label. ELSE. hi_entry_qnt = 0. EXIT. ENDIF.
                     ENDLOOP.
                     IF hi_entry_qnt = 0. EXIT. ENDIF.
                  ENDLOOP.
                  IF hi_entry_qnt = 0. EXIT. ENDIF.
               ENDLOOP.
               " Real split posting
               IF hi_entry_qnt = 0.
                  hi_entry_qnt = goodsmvt_item-entry_qnt.
                  LOOP AT lt_v_ekko_ekpo_buf INTO wa_v_label WHERE werks = goodsmvt_item-plant AND matnr = goodsmvt_item-material AND lifnr = goodsmvt_item-vendor AND loekz = space.
                     LOOP AT lt_eket_buf INTO wa_t_label WHERE ebeln = wa_v_label-ebeln AND ebelp = wa_v_label-ebelp AND wemng < wa_t_label-menge.
                        LOOP AT lt_ekes_buf INTO wa_s_label WHERE ebeln = wa_t_label-ebeln AND ebelp = wa_t_label-ebelp AND loekz = space.
                           hi_ov_label = wa_s_label-menge - wa_s_label-dabmg.
                           IF hi_ov_label < hi_entry_qnt. goodsmvt_item-entry_qnt = hi_ov_label. goodsmvt_item-no_more_gr = 'X'. hi_entry_qnt = hi_entry_qnt - hi_ov_label. ELSE. goodsmvt_item-entry_qnt = hi_entry_qnt. goodsmvt_item-no_more_gr = space. hi_entry_qnt = 0. ENDIF.
                           goodsmvt_item-po_number = wa_s_label-ebeln. goodsmvt_item-po_item = wa_s_label-ebelp. APPEND goodsmvt_item.
                           CALL FUNCTION 'BAPI_GOODSMVT_CREATE' EXPORTING goodsmvt_header = goodsmvt_header goodsmvt_code = goodsmvt_code testrun = testrun IMPORTING materialdocument = hi_mblnr TABLES goodsmvt_item = goodsmvt_item return = return.
                           IF hi_mblnr IS NOT INITIAL. CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = abap_true. ENDIF.
                           REFRESH goodsmvt_item. IF hi_entry_qnt = 0. EXIT. ENDIF.
                        ENDLOOP.
                        IF hi_entry_qnt = 0. EXIT. ENDIF.
                     ENDLOOP.
                     IF hi_entry_qnt = 0. EXIT. ENDIF.
                  ENDLOOP.
                  goodsmvt_item = goodsmvt_item_save. APPEND goodsmvt_item. CONTINUE.
               ENDIF.
            ENDIF.

            APPEND goodsmvt_item.
          WHEN co_mbgmcr_ser. MOVE-CORRESPONDING idoc_data-sdata TO goodsmvt_serialnumber. APPEND goodsmvt_serialnumber.
          WHEN co_mbgmcr_z1. z1bp2017 = idoc_data-sdata.
            IF wa_mara_loc-labor = co_labor_etikett. z1bp2017-zbaret = abap_false. ENDIF.
            IF z1bp2017-zbaret = abap_true. PERFORM build_po_tables USING <ic_main>. ENDIF.
          WHEN co_mbgmcr_vser. APPEND idoc_data-sdata TO lt_serial_nums.
        ENDCASE.
      ENDLOOP.
    ENDCATCH.

    " 3.4 Execution logic
    IF gf_inbound_del_flag <> 'X' AND error_flag = abap_false.
       " PO locking logic (using lt_delay_buf)
       REFRESH it_lock. LOOP AT goodsmvt_item. it_lock-ebeln = goodsmvt_item-po_number. COLLECT it_lock. ENDLOOP.
       READ TABLE lt_delay_buf INTO DATA(ls_dl) WITH KEY mesty = <ic_main>-mestyp.
       DATA(lv_rt) = ls_dl-retry + 1.
       WHILE all_locked = space AND lv_rt > 0.
          LOOP AT it_lock WHERE lock = space.
             SELECT SINGLE ebeln FROM y0mm_proc_ebeln INTO @DATA(lv_lk) WHERE ebeln = @it_lock-ebeln.
             IF sy-subrc <> 0.
                INSERT y0mm_proc_ebeln FROM @( VALUE #( ebeln = it_lock-ebeln ) ).
                IF sy-subrc = 0. COMMIT WORK. it_lock-lock = 'X'. MODIFY it_lock. ENDIF.
             ENDIF.
          ENDLOOP.
          IF NOT line_exists( it_lock[ lock = space ] ). all_locked = 'X'. ELSE. WAIT UP TO ls_dl-delay SECONDS. ENDIF.
          lv_rt = lv_rt - 1.
       ENDWHILE.
       " Main Posting
       IF hi_flag_etikett = space.
          CALL FUNCTION 'BAPI_GOODSMVT_CREATE' EXPORTING goodsmvt_header = goodsmvt_header goodsmvt_code = goodsmvt_code testrun = testrun IMPORTING goodsmvt_headret = goodsmvt_headret materialdocument = materialdocument matdocumentyear = matdocumentyear TABLES goodsmvt_item = goodsmvt_item goodsmvt_serialnumber = goodsmvt_serialnumber return = return.
          IF materialdocument IS NOT INITIAL. CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = abap_true. ENDIF.
       ENDIF.
    ELSEIF gf_inbound_del_flag = 'X'.
       LOOP AT gt_inb_item.
          MOVE-CORRESPONDING gt_inb_item TO gt_inb_item_det. APPEND gt_inb_item_det.
          AT END OF vbeln.
             CALL FUNCTION 'Y0MM_VL32N' EXPORTING vbeln = gt_inb_item-vbeln i_optio = gs_ctu_params TABLES i_item_tab = gt_inb_item_det e_messtab = gt_mess.
             REFRESH gt_inb_item_det.
          ENDAT.
       ENDLOOP.
    ENDIF.
    PERFORM transfer_posting_br TABLES lt_return_bapi USING goodsmvt_header-ref_doc_no lk_tr_posted.
  ENDLOOP.

ENDFUNCTION.

*----------------------------------------------------------------------*
* FORMS - Optimized Logic
*----------------------------------------------------------------------*
FORM transfer_posting_br TABLES lt_return USING vbeln us_posted TYPE i.
  " Brazil generic transfer posting adapted logic using pre-fetched buffers (lt_braziltr_buf, lt_mara_buf, lt_mbew_buf)
ENDFORM.

FORM transfer_posting USING p_pre_posting TYPE flag.
  " Generic transfer logic adapted for performance using buffers (lt_mbgmcr_tr_buf)
ENDFORM.

FORM insert_status USING status type id number v1 v2 v3 v4.
  " Standard IDoc status record insertion
ENDFORM.

FORM build_po_tables USING idoc_header.
  " Logic to prepare BAPI tables for PO creation/change
ENDFORM.

FORM idoc_status_mbgmcr TABLES t_edidd idoc_status return_variables USING idoc_contrl bapi_retn_info bapi_idoc_status workflow_result.
  " IDoc status reporting logic
ENDFORM.
