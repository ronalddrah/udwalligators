FUNCTION za_idoc_input_zrepbf
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




  CALL FUNCTION 'Y0BC_WHEN_USED'.

  DATA: l_matnr TYPE matnr,
        l_mtart TYPE mtart,
        l_lines TYPE sytabix.

  DATA: lv_cls_upd TYPE abap_bool.

  DATA: zarmmts_segm TYPE zarmmts.

  repbf_code = 0.
* check basis idoc type
  READ TABLE idoc_contrl INDEX 1.
  IF idoc_contrl-idoctp NE 'ZAREPBF'.
    MESSAGE e029(e0) WITH idoc_contrl-idoctp TEXT-001
            'ZA_IDOC_INPUT_ZREPBF' RAISING wrong_function_called.
  ENDIF.
* check for duplicates
  IF line_exists( idoc_data[ segnam = co_zarmmts ] ).
    zarmmts_segm = idoc_data[ segnam = co_zarmmts ]-sdata.
    DATA(check_result) = y0mm_cl_inbound_idoc_checks=>duplicate_check(
                           idoc_header         = idoc_contrl
                           segment_zrepbf      = zarmmts_segm
                         ).
    IF line_exists( check_result[ type = 'E' ] ).
      DATA(result_line) = check_result[ type = 'E' ].
      PERFORM insert_status USING co_idoc_status_error
                                  result_line-type
                                  result_line-id
                                  result_line-number
                                  result_line-message_v1
                                  result_line-message_v2
                                  result_line-message_v3
                                  result_line-message_v4.
      EXIT.
    ENDIF.
  ENDIF.
* Init global data
  PERFORM zarepbf_init_data.
* Parse IDOC and split to internal tables
  PERFORM zarepbf_idoc_parse.
*  CHECK idoc_status-status NE co_idoc_status_error.

  "Only classification update or complete processing?
  IF idoc_contrl-mescod = co_mescod_cls. "Only classification update
    PERFORM zarepbf_cls_post.

  ELSE. "Complete processing (backflush + classification update)

    " Perform check if actual posting plant matches header material plant
    " otherwise this would cause cross-company postings
*    PERFORM check_posting_plant TABLES it_we it_re it_wa.
*    CHECK repbf_code = 0.

** delay if necessary
* get delay values
    CLEAR y0ca_ale_delay.
    SELECT SINGLE * FROM y0ca_ale_delay WHERE mesty = idoc_contrl-mestyp.
    IF sy-subrc = 0.
      ADD 1 TO y0ca_ale_delay-retry.
*    material versions to be locked (all must be locked)
      REFRESH it_mkal.
      PERFORM add_mkal TABLES it_we USING co_postype_we.
      PERFORM add_mkal TABLES it_re USING co_postype_we.
      PERFORM add_mkal TABLES it_wa USING co_postype_wa.
*    check if Backfluschs are currenty processed by other IDOCs -> wait
      locked = 0.

      WHILE locked = 0 AND y0ca_ale_delay-retry > 0.
*      try to lock each material version
        LOOP AT it_mkal.
          CALL FUNCTION 'ENQUEUE_EY0PP_PROC_MKAL'
            EXPORTING
              matnr          = it_mkal-matnr
              werks          = it_mkal-werks
              verid          = it_mkal-verid
            EXCEPTIONS
              foreign_lock   = 1
              system_failure = 2
              OTHERS         = 3.
          IF sy-subrc = 0.
            locked = 1.
          ELSE.
            locked = 0.
            EXIT.         "If one fails, all fail
          ENDIF.
        ENDLOOP.
        IF locked = 0.
          WAIT UP TO y0ca_ale_delay-delay SECONDS.
        ENDIF.

        y0ca_ale_delay-retry = y0ca_ale_delay-retry - 1.
      ENDWHILE.
    ENDIF.

* Add service materials to components
    PERFORM zarepbf_add_service_materials TABLES it_we it_wa USING space.
    PERFORM zarepbf_add_service_materials TABLES it_re it_ra USING 'X'.
* For HFG add service material for consumed FERT (only for new settlement)
    SELECT * FROM y0pp_rem_no_hfg INTO TABLE it_no_hfg. "Get plant execptions for HFG process
    REFRESH it_hfg.
    LOOP AT it_wa.
* No HFG processing for specific plants (CDP plants -> consumned FERTs already settled)
      READ TABLE it_no_hfg TRANSPORTING NO FIELDS WITH KEY werks = it_wa-prodplant.
      IF sy-subrc EQ 0.
        CONTINUE.
      ENDIF.
      CLEAR: l_matnr.
*   convert materialnumber to internal format
      CALL FUNCTION 'CONVERSION_EXIT_MATN1_INPUT'
        EXPORTING
          input        = it_wa-materialnr
        IMPORTING
          output       = l_matnr
        EXCEPTIONS
          length_error = 1
          OTHERS       = 2.
      SELECT SINGLE mtart INTO l_mtart FROM mara WHERE matnr = l_matnr.
      IF sy-subrc = 0 AND l_mtart = 'FERT'.
        APPEND it_wa TO it_hfg.
      ENDIF.
    ENDLOOP.
    DESCRIBE TABLE it_hfg LINES l_lines.
    IF l_lines > 0.
      READ TABLE it_hfg INDEX 1.
      SELECT SINGLE * FROM y0pp_rem_active.
      IF y0pp_rem_active-datum LE it_hfg-postdate AND sy-subrc IS INITIAL.
        PERFORM zarepbf_add_service_materials TABLES it_hfg it_wa USING 'R'.
      ENDIF.
    ENDIF.
* Post backflush
    IF repbf_code = 0.
      PERFORM zarepbf_post.     "backflushs first
      PERFORM zarepbf_cls_post. "then batch classification updates
    ENDIF.
* set return values
    PERFORM zarepbf_result_set.
* de-lock again
    LOOP AT it_mkal.
      CALL FUNCTION 'DEQUEUE_EY0PP_PROC_MKAL'
        EXPORTING
          matnr = it_mkal-matnr
          werks = it_mkal-werks
          verid = it_mkal-verid.
    ENDLOOP.

  ENDIF.

ENDFUNCTION.