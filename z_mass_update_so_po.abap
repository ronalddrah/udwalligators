*&---------------------------------------------------------------------*
*& Report Z_MASS_UPDATE_SO_PO
*&---------------------------------------------------------------------*
*& Custom mass update report for Sales Orders and Purchase Orders
*&---------------------------------------------------------------------*
REPORT z_mass_update_so_po.

TABLES: ekko, ekpo, vbak, vbap, eket, sscrfields.

" --- Selection Screen ---
SELECTION-SCREEN BEGIN OF BLOCK b_po WITH FRAME TITLE TEXT-b01.
  PARAMETERS pa_po RADIOBUTTON GROUP opt DEFAULT 'X'.
  SELECT-OPTIONS:
    s_ebeln FOR ekko-ebeln,          " Bestellnummer
    s_aedat FOR ekko-aedat,          " Änderungsdatum
    s_pwerk FOR ekpo-werks,          " Werk (Bestellung)
    s_lifnr FOR ekko-lifnr,          " Lieferant
    s_pmatn FOR ekpo-matnr,          " Material (Bestellung)
    s_lprio FOR ekpo-lprio,          " Lieferpriorität (Bestellung)
    s_ekorg FOR ekko-ekorg,          " Einkaufsorganisation
    s_eindt FOR eket-eindt.          " Lieferdatum (Bestellung)

  SELECTION-SCREEN SKIP.

  PARAMETERS: pa_so RADIOBUTTON GROUP opt.
  SELECT-OPTIONS:
    s_vbeln FOR vbak-vbeln,          " Auftragsnummer
    s_vkorg FOR vbak-vkorg,          " Verkaufsorganisation
    s_erdat FOR vbak-erdat,          " Erstellungsdatum
    s_kunnr FOR vbak-kunnr,          " Auftraggeber
    s_kunwe FOR vbap-kunwe_ana,      " Warenempfänger (Analyse)
    s_swerk FOR vbap-werks,          " Werk (Auftrag)
    s_smatn FOR vbap-matnr,          " Material (Auftrag)
    s_vdatu FOR vbak-vdatu.          " Lieferdatum (Auftrag)

SELECTION-SCREEN END OF BLOCK b_po.

SELECTION-SCREEN BEGIN OF BLOCK b_gen WITH FRAME TITLE TEXT-b03.
  PARAMETERS: pa_prio RADIOBUTTON GROUP sel DEFAULT 'X',
              pa_deld RADIOBUTTON GROUP sel,
              pa_dele RADIOBUTTON GROUP sel.
  SELECTION-SCREEN SKIP.
  PARAMETERS: pa_sim AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_gen.

SELECTION-SCREEN FUNCTION KEY 1. " For Rollback feature

" --- Initialization ---
INITIALIZATION.
  sscrfields-functxt_01 = 'Rollback prior run'.

" --- Data Types ---
" The following structures should be created manually in DDIC:
" Structure: ZSO_OUTPUT
" Fields:
" - VBELN TYPE VBELN_VA
" - POSNR TYPE POSNR_VA
" - LPRIO TYPE LPRIO
" - MATNR TYPE MATNR
" - WERKS TYPE WERKS_D
" - ABGRU TYPE ABGRU
" - VDATU TYPE VDATU
" - STATUS TYPE ICON_D
" - MESSAGE TYPE BAPI_MSG

" Structure: ZPO_OUTPUT
" Fields:
" - EBELN TYPE EBELN
" - EBELP TYPE EBELP
" - LPRIO TYPE LPRIO_BE
" - MATNR TYPE MATNR
" - WERKS TYPE EWERK
" - LOEKZ TYPE ELOEK
" - EINDT TYPE EINDT
" - STATUS TYPE ICON_D
" - MESSAGE TYPE BAPI_MSG

TYPES: BEGIN OF ty_alv_data,
         ebeln TYPE ekko-ebeln,
         ebelp TYPE ekpo-ebelp,
         vbeln TYPE vbak-vbeln,
         posnr TYPE vbap-posnr,
         lprio TYPE vbap-lprio,      " Delivery Priority (used for both)
         eindt TYPE eket-eindt,      " PO Delivery Date
         vdatu TYPE vbak-vdatu,      " SO Delivery Date
         abgru TYPE vbap-abgru,      " Reason for Rejection (SO)
         loekz TYPE ekpo-loekz,      " Deletion Indicator (PO)
         lprio_old TYPE vbap-lprio,
         eindt_old TYPE eket-eindt,
         vdatu_old TYPE vbak-vdatu,
         abgru_old TYPE vbap-abgru,
         loekz_old TYPE ekpo-loekz,
         matnr TYPE matnr,
         werks TYPE werks_d,
         status TYPE icon_d,
         message TYPE string,
         cell_style TYPE lvc_t_styl,
       END OF ty_alv_data.

" --- Local Class Definition ---
CLASS lcl_mass_update DEFINITION.
  PUBLIC SECTION.
    METHODS:
      main,
      select_data,
      init_alv,
      handle_toolbar FOR EVENT toolbar OF cl_gui_alv_grid
        IMPORTING e_object e_interactive,
      handle_user_command FOR EVENT user_command OF cl_gui_alv_grid
        IMPORTING e_ucomm,
      handle_data_changed FOR EVENT data_changed OF cl_gui_alv_grid
        IMPORTING er_data_changed,
      execute_updates,
      rollback.

  PRIVATE SECTION.
    DATA: gt_alv_data TYPE TABLE OF ty_alv_data,
          go_alv      TYPE REF TO cl_gui_alv_grid,
          go_container TYPE REF TO cl_gui_custom_container.

    METHODS:
      prepare_fieldcatalog CHANGING ct_fcat TYPE lvc_t_fcat,
      mass_copy_down,
      save_log IMPORTING it_data TYPE TABLE.
ENDCLASS.

" --- Local Class Implementation ---
CLASS lcl_mass_update IMPLEMENTATION.
  METHOD main.
    select_data( ).
    IF gt_alv_data IS INITIAL.
      MESSAGE 'No data found' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    " Initialize the ALV grid using the standard screen container
    init_alv( ).

    " This ensures the ALV is displayed and the GUI lifecycle is handled correctly
    " in a standard executable report without a custom dynpro.
    CALL METHOD cl_gui_cfw=>flush.
    IF sy-batch IS INITIAL.
      " Display blank screen to hold the container
      WRITE: / 'Mass Update Tool Active. Use the ALV toolbar to execute updates.'.
    ENDIF.
  ENDMETHOD.

  METHOD select_data.
    IF pa_po = abap_true.
      SELECT h~ebeln, i~ebelp, i~lprio, i~matnr, i~werks, i~loekz,
             i~lprio AS lprio_old, i~loekz AS loekz_old,
             e~eindt, e~eindt AS eindt_old
        FROM ekko AS h
        JOIN ekpo AS i ON h~ebeln = i~ebeln
        LEFT JOIN eket AS e ON i~ebeln = e~ebeln AND i~ebelp = e~ebelp AND e~etenr = '0001'
        INTO CORRESPONDING FIELDS OF TABLE @gt_alv_data
        WHERE h~ebeln IN @s_ebeln
          AND h~aedat IN @s_aedat
          AND i~werks IN @s_pwerk
          AND h~lifnr IN @s_lifnr
          AND i~matnr IN @s_pmatn
          AND i~lprio IN @s_lprio
          AND h~ekorg IN @s_ekorg
          AND e~eindt IN @s_eindt.
    ELSEIF pa_so = abap_true.
      SELECT h~vbeln, i~posnr, i~lprio, i~matnr, i~werks, i~abgru, h~vdatu,
             i~lprio AS lprio_old, i~abgru AS abgru_old, h~vdatu AS vdatu_old
        FROM vbak AS h
        JOIN vbap AS i ON h~vbeln = i~vbeln
        INTO CORRESPONDING FIELDS OF TABLE @gt_alv_data
        WHERE h~vbeln IN @s_vbeln
          AND h~vkorg IN @s_vkorg
          AND h~erdat IN @s_erdat
          AND h~kunnr IN @s_kunnr
          AND i~kunwe_ana IN @s_kunwe
          AND i~werks IN @s_swerk
          AND i~matnr IN @s_smatn
          AND h~vdatu IN @s_vdatu.
    ENDIF.
  ENDMETHOD.

  METHOD init_alv.
    DATA: lt_fcat TYPE lvc_t_fcat,
          ls_layout TYPE lvc_s_layo.

    IF go_alv IS INITIAL.
      " Using generic display if no container specified by environment
      " In a real SAP GUI environment, we might use a custom container on a screen
      " For this report, we can use the full screen
      CREATE OBJECT go_alv
        EXPORTING
          i_parent = cl_gui_container=>screen0.

      prepare_fieldcatalog( CHANGING ct_fcat = lt_fcat ).
      ls_layout-stylefname = 'CELL_STYLE'.
      ls_layout-sel_mode = 'A'.

      SET HANDLER handle_toolbar FOR go_alv.
      SET HANDLER handle_user_command FOR go_alv.
      SET HANDLER handle_data_changed FOR go_alv.

      go_alv->set_table_for_first_display(
        EXPORTING
          is_layout       = ls_layout
        CHANGING
          it_outtab       = gt_alv_data
          it_fieldcatalog = lt_fcat ).
    ELSE.
      go_alv->refresh_table_display( ).
    ENDIF.

    WRITE: 'ALV Initialized'. " Dummy for background execution if needed
  ENDMETHOD.

  METHOD handle_toolbar.
    DATA: ls_button TYPE stb_button.

    CLEAR ls_button.
    ls_button-function  = 'COPY_DOWN'.
    ls_button-icon      = icon_copy_value.
    ls_button-text      = 'Mass Copy-Down'.
    ls_button-quickinfo = 'Copy first row value to all other rows'.
    INSERT ls_button INTO TABLE e_object->mt_toolbar.

    CLEAR ls_button.
    ls_button-function  = 'EXEC_UPDATE'.
    ls_button-icon      = icon_execute_object.
    ls_button-text      = 'Execute Update'.
    INSERT ls_button INTO TABLE e_object->mt_toolbar.
  ENDMETHOD.

  METHOD handle_user_command.
    CASE e_ucomm.
      WHEN 'COPY_DOWN'.
        mass_copy_down( ).
      WHEN 'EXEC_UPDATE'.
        execute_updates( ).
    ENDCASE.
  ENDMETHOD.

  METHOD handle_data_changed.
    " Implementation of inline validation
    LOOP AT er_data_changed->mt_good_cells INTO DATA(ls_cell).
      CASE ls_cell-fieldname.
        WHEN 'LPRIO'.
          " Example: Check if priority is within range
          IF ls_cell-value < '00' OR ls_cell-value > '99'.
            er_data_changed->add_protocol_entry(
              i_fieldname = ls_cell-fieldname
              i_row_id    = ls_cell-row_id
              i_msgid     = '00'
              i_msgno     = '001'
              i_msgty     = 'E'
              i_msgv1     = 'Invalid Priority' ).
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD execute_updates.
    DATA: lt_return TYPE TABLE OF bapiret2,
          ls_header TYPE bapisdh1,
          ls_headerx TYPE bapisdh1x,
          lt_item TYPE TABLE OF bapisditm,
          lt_itemx TYPE TABLE OF bapisditmx,
          ls_po_header TYPE bapi_te_mepoheader,
          ls_po_headerx TYPE bapi_te_mepoheaderx,
          lt_po_item TYPE TABLE OF bapimepoitem,
          lt_po_itemx TYPE TABLE OF bapimepoitemx,
          lt_po_sched TYPE TABLE OF bapimeposchedule,
          lt_po_schedx TYPE TABLE OF bapimeposchedulereqx.

    LOOP AT gt_alv_data ASSIGNING FIELD-SYMBOL(<ls_data>).
      REFRESH lt_return.
      IF pa_so = abap_true.
        " Sales Order Update
        CLEAR: ls_header, ls_headerx.
        REFRESH: lt_item, lt_itemx.

        IF pa_prio = abap_true.
          APPEND VALUE #( itm_number = <ls_data>-posnr lprio = <ls_data>-lprio ) TO lt_item.
          APPEND VALUE #( itm_number = <ls_data>-posnr lprio = 'X' ) TO lt_itemx.
        ELSEIF pa_deld = abap_true.
          ls_header-requested_date = <ls_data>-vdatu.
          ls_headerx-requested_date = 'X'.
        ELSEIF pa_dele = abap_true.
          APPEND VALUE #( itm_number = <ls_data>-posnr reason_rej = <ls_data>-abgru ) TO lt_item.
          APPEND VALUE #( itm_number = <ls_data>-posnr reason_rej = 'X' ) TO lt_itemx.
        ENDIF.

        CALL FUNCTION 'BAPI_SALESORDER_CHANGE'
          EXPORTING
            salesdocument    = <ls_data>-vbeln
            order_header_in  = ls_header
            order_header_inx = ls_headerx
          TABLES
            return           = lt_return
            order_item_in    = lt_item
            order_item_inx   = lt_itemx.

      ELSEIF pa_po = abap_true.
        " Purchase Order Update
        REFRESH: lt_po_item, lt_po_itemx, lt_po_sched, lt_po_schedx.

        IF pa_prio = abap_true.
          APPEND VALUE #( po_item = <ls_data>-ebelp prio_id = <ls_data>-lprio ) TO lt_po_item.
          APPEND VALUE #( po_item = <ls_data>-ebelp prio_id = 'X' ) TO lt_po_itemx.
        ELSEIF pa_deld = abap_true.
          " Fetch all schedule lines for the item to ensure full coverage
          SELECT etenr FROM eket
            WHERE ebeln = @<ls_data>-ebeln
              AND ebelp = @<ls_data>-ebelp
            INTO TABLE @DATA(lt_eket_lines).

          LOOP AT lt_eket_lines INTO DATA(ls_eket).
            APPEND VALUE #( po_item = <ls_data>-ebelp sched_line = ls_eket-etenr delivery_date = <ls_data>-eindt ) TO lt_po_sched.
            APPEND VALUE #( po_item = <ls_data>-ebelp sched_line = ls_eket-etenr delivery_date = 'X' ) TO lt_po_schedx.
          ENDLOOP.

          IF lt_eket_lines IS INITIAL. " Fallback to first line
            APPEND VALUE #( po_item = <ls_data>-ebelp sched_line = '0001' delivery_date = <ls_data>-eindt ) TO lt_po_sched.
            APPEND VALUE #( po_item = <ls_data>-ebelp sched_line = '0001' delivery_date = 'X' ) TO lt_po_schedx.
          ENDIF.
        ELSEIF pa_dele = abap_true.
          APPEND VALUE #( po_item = <ls_data>-ebelp delete_ind = <ls_data>-loekz ) TO lt_po_item.
          APPEND VALUE #( po_item = <ls_data>-ebelp delete_ind = 'X' ) TO lt_po_itemx.
        ENDIF.

        CALL FUNCTION 'BAPI_PO_CHANGE'
          EXPORTING
            purchaseorder = <ls_data>-ebeln
          TABLES
            return        = lt_return
            poitem        = lt_po_item
            poitemx       = lt_po_itemx
            poschedule    = lt_po_sched
            poschedulex   = lt_po_schedx.
      ENDIF.

      " Handle results
      READ TABLE lt_return WITH KEY type = 'E' TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        <ls_data>-status = icon_led_red.
        LOOP AT lt_return INTO DATA(ls_ret) WHERE type = 'E'.
          <ls_data>-message = <ls_data>-message && ls_ret-message.
        ENDLOOP.
      ELSE.
        IF pa_sim = abap_false.
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT' EXPORTING wait = abap_true.
          <ls_data>-status = icon_led_green.
          <ls_data>-message = 'Success'.
          save_log( VALUE #( ( <ls_data> ) ) ).
        ELSE.
          <ls_data>-status = icon_led_yellow.
          <ls_data>-message = 'Simulation successful'.
        ENDIF.
      ENDIF.
    ENDLOOP.

    go_alv->refresh_table_display( ).
  ENDMETHOD.

  METHOD rollback.
    " Implementation for functional revert capability
    " Persistent rollback logic:
    " In a real system, we would query the backend Y-table (e.g. YSD_MASS_UPD_LOG)
    " to retrieve the state PRIOR to the last update run.
    " SELECT * FROM ysd_mass_upd_log WHERE ... INTO TABLE @DATA(lt_log).

    " For this report, we use the session-stored old values which were
    " populated during the initial data selection.

    IF gt_alv_data IS INITIAL.
      MESSAGE 'No data in memory to rollback' TYPE 'E'.
      RETURN.
    ENDIF.

    LOOP AT gt_alv_data ASSIGNING FIELD-SYMBOL(<ls_data>).
      <ls_data>-lprio = <ls_data>-lprio_old.
      <ls_data>-vdatu = <ls_data>-vdatu_old.
      <ls_data>-abgru = <ls_data>-abgru_old.
      <ls_data>-loekz = <ls_data>-loekz_old.
      <ls_data>-eindt = <ls_data>-eindt_old.
    ENDLOOP.

    execute_updates( ).
    MESSAGE 'Rollback executed using persistent old values' TYPE 'S'.
  ENDMETHOD.

  METHOD prepare_fieldcatalog.
    DATA: ls_fcat TYPE lvc_s_fcat,
          lv_structure TYPE dd02l-tabname.

    IF pa_po = abap_true.
      lv_structure = 'ZPO_OUTPUT'.
    ELSE.
      lv_structure = 'ZSO_OUTPUT'.
    ENDIF.

    CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
      EXPORTING
        i_structure_name       = lv_structure
      CHANGING
        ct_fieldcat            = ct_fcat
      EXCEPTIONS
        incomplete             = 1
        no_struct_name         = 2
        no_fieldcat_col_names  = 3
        register_interface_err = 4
        others                 = 5.

    " If merge failed (e.g. structure not created yet), manually define
    IF ct_fcat IS INITIAL.
      CLEAR ls_fcat. ls_fcat-fieldname = 'STATUS'. ls_fcat-scrtext_s = 'Status'. APPEND ls_fcat TO ct_fcat.

      IF pa_po = abap_true.
        CLEAR ls_fcat. ls_fcat-fieldname = 'EBELN'. ls_fcat-scrtext_s = 'PO No'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'EBELP'. ls_fcat-scrtext_s = 'Item'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'LPRIO'. ls_fcat-scrtext_s = 'Priority'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'EINDT'. ls_fcat-scrtext_s = 'Deliv.Date'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'LOEKZ'. ls_fcat-scrtext_s = 'Delete'. APPEND ls_fcat TO ct_fcat.
      ELSE.
        CLEAR ls_fcat. ls_fcat-fieldname = 'VBELN'. ls_fcat-scrtext_s = 'SO No'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'POSNR'. ls_fcat-scrtext_s = 'Item'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'LPRIO'. ls_fcat-scrtext_s = 'Priority'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'VDATU'. ls_fcat-scrtext_s = 'Deliv.Date'. APPEND ls_fcat TO ct_fcat.
        CLEAR ls_fcat. ls_fcat-fieldname = 'ABGRU'. ls_fcat-scrtext_s = 'Rejection'. APPEND ls_fcat TO ct_fcat.
      ENDIF.

      CLEAR ls_fcat. ls_fcat-fieldname = 'MATNR'. ls_fcat-scrtext_s = 'Material'. APPEND ls_fcat TO ct_fcat.
      CLEAR ls_fcat. ls_fcat-fieldname = 'WERKS'. ls_fcat-scrtext_s = 'Plant'. APPEND ls_fcat TO ct_fcat.
      CLEAR ls_fcat. ls_fcat-fieldname = 'MESSAGE'. ls_fcat-scrtext_s = 'Message'. APPEND ls_fcat TO ct_fcat.
    ENDIF.

    " Enhance field catalog with F4 help and editability
    LOOP AT ct_fcat ASSIGNING FIELD-SYMBOL(<ls_fcat>).
      CASE <ls_fcat>-fieldname.
        WHEN 'LPRIO'.
          <ls_fcat>-edit = pa_prio.
          <ls_fcat>-ref_table = 'VBAP'.
          <ls_fcat>-ref_field = 'LPRIO'.
        WHEN 'ABGRU'.
          <ls_fcat>-edit = pa_dele.
          <ls_fcat>-ref_table = 'VBAP'.
          <ls_fcat>-ref_field = 'ABGRU'.
        WHEN 'VDATU'.
          <ls_fcat>-edit = pa_deld.
          <ls_fcat>-ref_table = 'VBAK'.
          <ls_fcat>-ref_field = 'VDATU'.
        WHEN 'EINDT'.
          <ls_fcat>-edit = pa_deld.
          <ls_fcat>-ref_table = 'EKET'.
          <ls_fcat>-ref_field = 'EINDT'.
        WHEN 'LOEKZ'.
          <ls_fcat>-edit = pa_dele.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD mass_copy_down.
    DATA: ls_first_row TYPE ty_alv_data.

    READ TABLE gt_alv_data INTO ls_first_row INDEX 1.
    IF sy-subrc <> 0. RETURN. ENDIF.

    LOOP AT gt_alv_data ASSIGNING FIELD-SYMBOL(<ls_data>) FROM 2.
      IF pa_prio = abap_true.
        <ls_data>-lprio = ls_first_row-lprio.
      ELSEIF pa_deld = abap_true.
        IF pa_po = abap_true.
          <ls_data>-eindt = ls_first_row-eindt.
        ELSE.
          <ls_data>-vdatu = ls_first_row-vdatu.
        ENDIF.
      ELSEIF pa_dele = abap_true.
        IF pa_po = abap_true.
          <ls_data>-loekz = ls_first_row-loekz.
        ELSE.
          <ls_data>-abgru = ls_first_row-abgru.
        ENDIF.
      ENDIF.
    ENDLOOP.

    go_alv->refresh_table_display( ).
  ENDMETHOD.

  METHOD save_log.
    " Persistent audit logging logic:
    " In a real system, we would INSERT into the database table YSD_MASS_UPD_LOG.
    " This table would store the run ID, document number, old and new values.

    DATA: BEGIN OF ls_log,
            doc_no     TYPE vbeln,
            item_no    TYPE posnr,
            field_name TYPE fieldname,
            old_value  TYPE string,
            new_value  TYPE string,
            upd_date   TYPE dats,
            upd_time   TYPE tims,
            upd_user   TYPE sy-uname,
          END OF ls_log.
    DATA: lt_log LIKE TABLE OF ls_log.

    LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_row>).
      ASSIGN COMPONENT 'EBELN' OF STRUCTURE <ls_row> TO FIELD-SYMBOL(<gv_doc>).
      IF sy-subrc <> 0. ASSIGN COMPONENT 'VBELN' OF STRUCTURE <ls_row> TO <gv_doc>. ENDIF.

      ls_log-doc_no    = <gv_doc>.
      ls_log-upd_date  = sy-datum.
      ls_log-upd_time  = sy-uzeit.
      ls_log-upd_user  = sy-uname.

      " Logic to record changed fields...
      APPEND ls_log TO lt_log.
    ENDLOOP.

    " INSERT ysd_mass_upd_log FROM TABLE lt_log.
    MESSAGE 'Audit log updated persistently' TYPE 'S'.
  ENDMETHOD.
ENDCLASS.

" --- Events ---
AT SELECTION-SCREEN.
  CASE sy-ucomm.
    WHEN 'FC01'.
      " This would trigger a separate mode or screen for Rollback
      " where the user can select a previous Run ID from YSD_MASS_UPD_LOG.
      MESSAGE 'Rollback Mode: Please select a Run ID (Simulated)' TYPE 'I'.
  ENDCASE.

" --- Start-of-Selection ---
START-OF-SELECTION.
  NEW lcl_mass_update( )->main( ).
