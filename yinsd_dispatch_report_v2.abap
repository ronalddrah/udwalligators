REPORT yinsd_dispatch_report_v2.

TABLES: vbrk, likp, vbrp.

SELECTION-SCREEN BEGIN OF BLOCK 001 WITH FRAME.
  SELECTION-SCREEN BEGIN OF BLOCK 004 WITH FRAME.
    PARAMETERS: pa_so RADIOBUTTON GROUP rad1 DEFAULT 'X',
                pa_po RADIOBUTTON GROUP rad1.
  SELECTION-SCREEN END OF BLOCK 004.
  SELECTION-SCREEN BEGIN OF BLOCK 002 WITH FRAME TITLE TEXT-h01.
    SELECT-OPTIONS: so_vkorg FOR vbrk-vkorg OBLIGATORY,
                    so_vbeln FOR vbrk-vbeln,
                    so_fkart FOR vbrk-fkart,
                    so_erdat FOR vbrk-erdat,
                    so_fkdat FOR vbrk-fkdat,
                    so_kunag FOR vbrk-kunag,
                    so_regio FOR vbrk-regio,
                    so_matnr FOR vbrp-matnr,
                    so_werks FOR vbrp-werks,
                    so_vstel FOR vbrp-vstel.
  SELECTION-SCREEN END OF BLOCK 002.

  SELECTION-SCREEN BEGIN OF BLOCK 003 WITH FRAME TITLE TEXT-h02.
    SELECT-OPTIONS: so_lvbln FOR likp-vbeln,
                    so_lfdat FOR likp-lfdat,
                    so_lfedt FOR likp-erdat,
                    so_wadat FOR likp-wadat_ist.
  SELECTION-SCREEN END OF BLOCK 003.
SELECTION-SCREEN END OF BLOCK 001.

AT SELECTION-SCREEN.
  SELECT vkorg FROM tvko INTO TABLE @DATA(lt_vkorg) WHERE vkorg IN @so_vkorg.
  LOOP AT lt_vkorg INTO DATA(lv_vkorg).
    AUTHORITY-CHECK OBJECT 'V_VBRK_VKO'
                    ID 'VKORG' FIELD lv_vkorg
                    ID 'ACTVT' FIELD '03'.
    IF sy-subrc <> 0.
      MESSAGE e514(vf) WITH lv_vkorg.
    ENDIF.
  ENDLOOP.


CLASS zcl_sd_dispatch_report DEFINITION
"  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_selection_params,
        pa_so    TYPE abap_bool, pa_po TYPE abap_bool,
        so_vkorg TYPE RANGE OF vkorg, so_vbeln TYPE RANGE OF vbeln_vf,
        so_fkart TYPE RANGE OF fkart, so_erdat TYPE RANGE OF erdat,
        so_fkdat TYPE RANGE OF fkdat, so_kunag TYPE RANGE OF kunag,
        so_regio TYPE RANGE OF regio, so_matnr TYPE RANGE OF matnr,
        so_werks TYPE RANGE OF werks_d, so_vstel TYPE RANGE OF vstel,
        so_lvbln TYPE RANGE OF vbeln_vl, so_lfdat TYPE RANGE OF lfdat,
        so_lfedt TYPE RANGE OF erdat, so_wadat TYPE RANGE OF wadat_ist,
      END OF ty_selection_params,

      BEGIN OF ty_output,
        vbeln     TYPE vbeln_vf, posnr TYPE posnr_vf, fkart TYPE fkart, fkdat TYPE fkdat,
        ernam     TYPE ernam, matnr TYPE matnr, arktx TYPE arktx, charg TYPE charg_d,
        werks     TYPE werks_d, lgort TYPE lgort_d, lgobe TYPE lgobe, hsdat TYPE hsdat,
        vfdat     TYPE vfdat, ort01 TYPE ort01, regio TYPE bezei40, desti TYPE vtext,
        bstkd     TYPE bstkd, bstdk TYPE bstdk, vbeln_so TYPE vbeln_va, zterm TYPE text50,
        kzsto     TYPE c LENGTH 1, kunwe TYPE kunwe, name_we TYPE name1_gp, ort01_we TYPE ort01_gp,
        zzchannel TYPE y0sd_channel_d, cha_bezei TYPE bezei40, zzsegment TYPE y0sd_segment_d, seg_bezei TYPE bezei40,
        kunag     TYPE kunag, name_ag TYPE name1_gp, kunrg TYPE kunrg, name_rg TYPE name1_gp,
        kunre     TYPE kunre, name_re TYPE name1_gp, kunsp TYPE kunre, name_sp TYPE name1_gp,
        vkaus     TYPE vkaus, zfbdt TYPE dzfbdt, overdue TYPE i, fkimg TYPE fkimg,
        vrkme     TYPE vrkme, netwr TYPE netwr_fp, price TYPE stprs, jlst TYPE kawrt,
        jcst      TYPE kawrt, jocg TYPE kawrt, josg TYPE kawrt, joig TYPE kawrt,
        jicg      TYPE kawrt, jisg TYPE kawrt, jiig TYPE kawrt, zina TYPE kawrt,
        zinb      TYPE kawrt, sum_j TYPE kawrt, brgew TYPE brgew, ntgew TYPE ntgew,
        gross     TYPE netwr_fp, octroi TYPE netwr_fp, traid TYPE traid, bolnr TYPE bolnr,
        licence   TYPE j_1ifrmnum, excise_nr TYPE txline, sfakn TYPE sfakn, stcd3 TYPE stcd3,
        month     TYPE LFMON, year TYPE LFGJA, jcis TYPE kawrt, zind TYPE kawrt,
        zing      TYPE kawrt, zing_p TYPE kbetr, zz01 TYPE kawrt, zz02 TYPE kawrt,
        zz03      TYPE kawrt, zz04 TYPE kawrt, zz05 TYPE kawrt, zz06 TYPE kawrt,
        zz07      TYPE kawrt, zz08 TYPE kawrt,
        knumv     TYPE knumv, vbtyp TYPE vbtyp, cityc TYPE cityc, mtart TYPE mtart,
        steuc     TYPE steuc, umvkz TYPE umvkz, umvkn TYPE umvkn, uecha TYPE posnr_vl,
        pstyv     TYPE pstyv, mwsbp TYPE mwsbp, aubel TYPE aubel,
        wadat_ist TYPE wadat_ist, lfimg TYPE lfimg, meins TYPE meins,
      END OF ty_output,

      tt_output TYPE STANDARD TABLE OF ty_output WITH EMPTY KEY.

    METHODS constructor IMPORTING is_params TYPE ty_selection_params.
    METHODS run.

  PRIVATE SECTION.
    DATA ms_params TYPE ty_selection_params.
    DATA mt_output TYPE tt_output.

    METHODS get_billing_data.
    METHODS get_delivery_data.
    METHODS calculate_prices.
    METHODS get_material_prices.
    METHODS calculate_octroi.
    METHODS get_texts.
    METHODS display_report.

ENDCLASS.

CLASS zcl_sd_dispatch_report IMPLEMENTATION.

  METHOD constructor. ms_params = is_params. ENDMETHOD.

  METHOD run.
    IF ms_params-pa_so = abap_true. get_billing_data( ). ELSE. get_delivery_data( ). ENDIF.
    calculate_prices( ). get_material_prices( ). calculate_octroi( ). get_texts( ). display_report( ).
  ENDMETHOD.

  METHOD get_billing_data.
    SELECT vbeln, posnr, fkart, fkdat, erdat, ernam, matnr, arktx, charg, werks, lgort, bukrs,
           plantcity, storagelocationname, regionname, channelname, segmentname,
           taxnumber3, payercitycode, aubel, vbtyp, pstyv, mwsbp, netwr, knumv,
           cityc, mtart, vkaus, meins, zterm, fkimg, vrkme, brgew, ntgew,
           traid, bolnr, licence, steuc, umvkz, umvkn, uecha,
           zzchannel, zzsegment, bstkd, wadat_ist
      FROM YINSD_I_DispatchBilling
      WHERE vkorg IN @ms_params-so_vkorg AND vbeln IN @ms_params-so_vbeln
        AND fkart IN @ms_params-so_fkart AND fkdat IN @ms_params-so_fkdat
        AND erdat IN @ms_params-so_erdat AND kunag IN @ms_params-so_kunag
        AND regio IN @ms_params-so_regio AND matnr IN @ms_params-so_matnr
        AND werks IN @ms_params-so_werks AND vstel IN @ms_params-so_vstel
      INTO TABLE @DATA(lt_billing).

    IF lt_billing IS INITIAL. RETURN. ENDIF.

    TYPES: BEGIN OF ty_partner,
             vbeln TYPE vbeln_vf, parvw TYPE parvw, kunnr TYPE kunnr,
             lifnr TYPE lifnr, adrnr TYPE adrnr, lzone TYPE lzone,
             name1 TYPE name1_gp, city1 TYPE ort01_gp,
           END OF ty_partner,
           tt_partners TYPE SORTED TABLE OF ty_partner WITH NON-UNIQUE KEY vbeln,
           BEGIN OF ty_bseg,
             vbeln TYPE vbeln_vf, belnr TYPE belnr_d, zfbdt TYPE dzfbdt, bukrs TYPE bukrs,
           END OF ty_bseg,
           tt_bseg TYPE HASHED TABLE OF ty_bseg WITH UNIQUE KEY vbeln,
           BEGIN OF ty_mch1,
             matnr TYPE matnr, charg TYPE charg_d, hsdat TYPE hsdat, vfdat TYPE vfdat,
           END OF ty_mch1,
           tt_mch1 TYPE SORTED TABLE OF ty_mch1 WITH NON-UNIQUE KEY matnr charg,
           BEGIN OF ty_tzont,
             zone1 TYPE zone1, spras TYPE spras, land1 TYPE land1, vtext TYPE vtext,
           END OF ty_tzont,
           tt_tzont TYPE HASHED TABLE OF ty_tzont WITH UNIQUE KEY zone1.

    DATA lt_partners TYPE tt_partners.
    DATA lt_bseg     TYPE tt_bseg.
    DATA lt_mch1     TYPE tt_mch1.
    DATA lt_tzont    TYPE tt_tzont.

    SELECT vbpa~vbeln, vbpa~parvw, vbpa~kunnr, vbpa~lifnr, vbpa~adrnr, vbpa~lzone, adrc~name1, adrc~city1
      FROM vbpa LEFT OUTER JOIN adrc ON vbpa~adrnr = adrc~addrnumber
      FOR ALL ENTRIES IN @lt_billing WHERE vbpa~vbeln = @lt_billing-vbeln
        AND vbpa~parvw IN ('WE', 'AG', 'RE', 'RG', 'SP')
      INTO TABLE @lt_partners.

    SELECT belnr, vbeln, zfbdt, bukrs FROM bseg FOR ALL ENTRIES IN @lt_billing
      WHERE belnr = @lt_billing-vbeln AND bukrs = @lt_billing-bukrs AND koart = 'D'
      INTO TABLE @lt_bseg.

    SELECT matnr, charg, hsdat, vfdat FROM mch1 FOR ALL ENTRIES IN @lt_billing
      WHERE matnr = @lt_billing-matnr AND charg = @lt_billing-charg
      INTO TABLE @lt_mch1.

    SELECT spras, land1, zone1, vtext FROM tzont FOR ALL ENTRIES IN @lt_partners
      WHERE spras = @sy-langu AND land1 = 'IN' AND zone1 = @lt_partners-lzone
      INTO TABLE @lt_tzont.

    LOOP AT lt_billing ASSIGNING FIELD-SYMBOL(<ls_bill>).
      APPEND INITIAL LINE TO mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      MOVE-CORRESPONDING <ls_bill> TO <ls_out>.
      <ls_out>-ort01 = <ls_bill>-plantcity. <ls_out>-lgobe = <ls_bill>-storagelocationname.
      <ls_out>-regio = <ls_bill>-regionname. <ls_out>-cha_bezei = <ls_bill>-channelname.
      <ls_out>-seg_bezei = <ls_bill>-segmentname. <ls_out>-stcd3 = <ls_bill>-taxnumber3.
      <ls_out>-cityc = <ls_bill>-payercitycode. <ls_out>-vbeln_so = <ls_bill>-aubel.
      <ls_out>-month = <ls_bill>-fkdat+4(2). <ls_out>-year = <ls_bill>-fkdat(4).

      LOOP AT lt_partners INTO DATA(ls_pt) WHERE vbeln = <ls_bill>-vbeln.
        CASE ls_pt-parvw.
          WHEN 'WE'. <ls_out>-kunwe = ls_pt-kunnr. <ls_out>-name_we = ls_pt-name1. <ls_out>-ort01_we = ls_pt-city1.
          WHEN 'AG'. <ls_out>-kunag = ls_pt-kunnr. <ls_out>-name_ag = ls_pt-name1.
          WHEN 'RE'. <ls_out>-kunre = ls_pt-kunnr. <ls_out>-name_re = ls_pt-name1.
          WHEN 'RG'. <ls_out>-kunrg = ls_pt-kunnr. <ls_out>-name_rg = ls_pt-name1.
          WHEN 'SP'. <ls_out>-kunsp = ls_pt-lifnr. <ls_out>-name_sp = ls_pt-name1.
        ENDCASE.
        READ TABLE lt_tzont INTO DATA(ls_tz) WITH TABLE KEY zone1 = ls_pt-lzone.
        IF sy-subrc = 0. <ls_out>-desti = ls_tz-vtext. ENDIF.
      ENDLOOP.

      READ TABLE lt_mch1 INTO DATA(ls_mch) WITH KEY matnr = <ls_bill>-matnr
                                                   charg = <ls_bill>-charg.
      IF sy-subrc = 0. <ls_out>-hsdat = ls_mch-hsdat. <ls_out>-vfdat = ls_mch-vfdat. ENDIF.

      READ TABLE lt_bseg INTO DATA(ls_bs) WITH TABLE KEY vbeln = <ls_bill>-vbeln.
      IF sy-subrc = 0.
        <ls_out>-zfbdt = ls_bs-zfbdt.
        IF <ls_out>-zfbdt IS NOT INITIAL. <ls_out>-overdue = sy-datum - <ls_out>-zfbdt. ENDIF.
      ENDIF.
      IF <ls_bill>-vbtyp = 'N'. <ls_out>-kzsto = 'X'. ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_delivery_data.
    SELECT vbeln, posnr, lfdat, fkdat, erdat, ernam, matnr, arktx, charg, werks, lgort,
           storagelocationname, plantcity, purchaseorder, purchdate, invoiceknumv,
           cancellationdoc, lfimg, umvkn, umvkz, uecha, vstel, knumv, pstyv,
           netwr, mwsbp, fkart, vbtyp, cityc, mtart, vkaus, meins, zterm,
           brgew, ntgew, traid, bolnr, licence, steuc, zzchannel, zzsegment, bstkd, wadat_ist, aubel, fkimg, vrkme
      FROM YINSD_I_DispatchDelivery
      WHERE vbeln IN @ms_params-so_lvbln AND lfdat IN @ms_params-so_lfdat
        AND lfart = 'NL' AND erdat IN @ms_params-so_lfedt
        AND vkorg IN @ms_params-so_vkorg AND wadat_ist IN @ms_params-so_wadat
        AND matnr IN @ms_params-so_matnr
      INTO TABLE @DATA(lt_delivery).

    IF lt_delivery IS INITIAL. RETURN. ENDIF.

    " Aggregate split deliveries (uecha logic)
    DATA lt_delivery_with_key TYPE STANDARD TABLE OF LINE OF lt_delivery
      WITH EMPTY KEY WITH NON-UNIQUE SORTED KEY split_key COMPONENTS vbeln uecha.
    lt_delivery_with_key = lt_delivery.

    LOOP AT lt_delivery ASSIGNING FIELD-SYMBOL(<ls_del>) WHERE uecha IS INITIAL.
      APPEND INITIAL LINE TO mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      MOVE-CORRESPONDING <ls_del> TO <ls_out>.
      <ls_out>-lgobe = <ls_del>-storagelocationname. <ls_out>-ort01 = <ls_del>-plantcity.
      <ls_out>-vbeln_so = <ls_del>-purchaseorder. <ls_out>-bstdk = <ls_del>-purchdate.
      <ls_out>-month = <ls_del>-fkdat+4(2). <ls_out>-year = <ls_del>-fkdat(4).
      <ls_out>-knumv = <ls_del>-invoiceknumv. <ls_out>-sfakn = <ls_del>-cancellationdoc.

      " Sum quantities from splits
      LOOP AT lt_delivery_with_key INTO DATA(ls_split)
           USING KEY split_key WHERE vbeln = <ls_del>-vbeln AND uecha = <ls_del>-posnr.
        IF ls_split-umvkn IS NOT INITIAL.
          <ls_out>-lfimg += ls_split-lfimg * ls_split-umvkz / ls_split-umvkn.
        ENDIF.
      ENDLOOP.
      IF <ls_out>-lfimg IS INITIAL. <ls_out>-lfimg = <ls_del>-lfimg. ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD calculate_prices.
    DATA lt_sel TYPE if_prc_result_database=>ty_prc_result_sel_attrib_t.
    TYPES tt_konv TYPE SORTED TABLE OF konv WITH NON-UNIQUE KEY knumv kposn.
    DATA lt_konv TYPE tt_konv.
    IF mt_output IS INITIAL. RETURN. ENDIF.

    lt_sel = VALUE #( fieldname = 'KSCHL' ( value = 'JLST' ) ( value = 'JCST' ) ( value = 'JCIS' )
                      ( value = 'JOCG' ) ( value = 'JOSG' ) ( value = 'JOIG' ) ( value = 'JICG' )
                      ( value = 'JISG' ) ( value = 'JIIG' ) ( value = 'ZINA' ) ( value = 'ZINB' )
                      ( value = 'ZIND' ) ( value = 'ZING' ) ( value = 'ZINS' ) ( value = 'ZINT' )
                      ( value = 'ZZ01' ) ( value = 'ZZ02' ) ( value = 'ZZ03' ) ( value = 'ZZ04' )
                      ( value = 'ZZ05' ) ( value = 'ZZ06' ) ( value = 'ZZ07' ) ( value = 'ZZ08' )
                      ( value = 'ZINC' ) ( value = 'VPRS' ) ( value = 'ZINM' ) ( value = 'ZIN3' ) ).

    DATA lt_knumv TYPE TABLE OF knumv.
    LOOP AT mt_output INTO DATA(ls_out) WHERE knumv IS NOT INITIAL. APPEND ls_out-knumv TO lt_knumv. ENDLOOP.
    SORT lt_knumv. DELETE ADJACENT DUPLICATES FROM lt_knumv.
    LOOP AT lt_knumv INTO DATA(lv_k).
      APPEND VALUE #( fieldname = 'KNUMV' value = lv_k ) TO lt_sel.
    ENDLOOP.

    TRY.
        cl_prc_result_factory=>get_instance( )->get_prc_result( )->get_price_element_db(
          EXPORTING it_selection_attribute = lt_sel
          IMPORTING et_prc_element_classic_format = lt_konv ).
      CATCH cx_prc_result. RETURN.
    ENDTRY.

    LOOP AT mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      DATA(lv_sign) = COND i( WHEN <ls_out>-fkart = 'S1' OR <ls_out>-vbtyp = 'H'
                               OR <ls_out>-vbtyp = 'O' OR <ls_out>-vbtyp = 'T'
                               OR <ls_out>-vbtyp = 'N' THEN -1 ELSE 1 ).

      " Free Goods quantity handling for net value
      DATA(lv_is_free) = COND abap_bool( WHEN <ls_out>-pstyv = 'KLN' OR <ls_out>-pstyv = 'RENN'
                                         OR <ls_out>-pstyv = 'TANN' THEN abap_true ELSE abap_false ).

      IF lv_is_free = abap_true. <ls_out>-netwr = 0. ENDIF.

      LOOP AT lt_konv INTO DATA(ls_k_v) WHERE knumv = <ls_out>-knumv AND kposn = <ls_out>-posnr.
        DATA(lv_val) = ls_k_v-kwert * lv_sign.
        CASE ls_k_v-kschl.
          WHEN 'JLST'. <ls_out>-jlst = lv_val. WHEN 'JCIS'. <ls_out>-jcis = lv_val.
          WHEN 'JCST'. <ls_out>-jcst = lv_val. WHEN 'JOCG'. <ls_out>-jocg = lv_val.
          WHEN 'JOSG'. <ls_out>-josg = lv_val. WHEN 'JOIG'. <ls_out>-joig = lv_val.
          WHEN 'JICG'. <ls_out>-jicg = lv_val. WHEN 'JISG'. <ls_out>-jisg = lv_val.
          WHEN 'JIIG'. <ls_out>-jiig = lv_val. WHEN 'ZINA'. <ls_out>-zina = lv_val.
          WHEN 'ZINB'. <ls_out>-zinb = lv_val. WHEN 'ZIND'. <ls_out>-zind = lv_val.
          WHEN 'ZING'. <ls_out>-zing = lv_val. <ls_out>-zing_p = ls_k_v-kbetr.
          WHEN 'ZINS' OR 'ZINT'. IF lv_is_free = abap_true. <ls_out>-netwr += lv_val. ENDIF.
          WHEN 'ZZ01'. <ls_out>-zz01 = lv_val. WHEN 'ZZ02'. <ls_out>-zz02 = lv_val.
          WHEN 'ZZ03'. <ls_out>-zz03 = lv_val. WHEN 'ZZ04'. <ls_out>-zz04 = lv_val.
          WHEN 'ZZ05'. <ls_out>-zz05 = lv_val. WHEN 'ZZ06'. <ls_out>-zz06 = lv_val.
          WHEN 'ZZ07'. <ls_out>-zz07 = lv_val. WHEN 'ZZ08'. <ls_out>-zz08 = lv_val.
        ENDCASE.
      ENDLOOP.
      <ls_out>-sum_j = <ls_out>-jcst + <ls_out>-jlst.
      <ls_out>-gross = ( <ls_out>-netwr * lv_sign ) + ( <ls_out>-mwsbp * lv_sign ).
    ENDLOOP.
  ENDMETHOD.

  METHOD get_material_prices.
    IF mt_output IS INITIAL. RETURN. ENDIF.

    TYPES: BEGIN OF ty_mbew,
             matnr TYPE matnr, stprs TYPE stprs, peinh TYPE peinh, bwkey TYPE bwkey,
           END OF ty_mbew,
           tt_mbew TYPE HASHED TABLE OF ty_mbew WITH UNIQUE KEY matnr,
           BEGIN OF ty_mbewh,
             matnr TYPE matnr, lfgja TYPE lfgja, lfmon TYPE lfmon,
             stprs TYPE stprs, peinh TYPE peinh, bwkey TYPE bwkey,
           END OF ty_mbewh,
           tt_mbewh TYPE HASHED TABLE OF ty_mbewh WITH UNIQUE KEY matnr lfgja lfmon.

    DATA lt_mbew  TYPE tt_mbew.
    DATA lt_mbewh TYPE tt_mbewh.

    " Prioritize current period from MBEW
    SELECT matnr, stprs, peinh, bwkey FROM mbew FOR ALL ENTRIES IN @mt_output
      WHERE matnr = @mt_output-matnr AND bwkey = '4200'
      INTO TABLE @lt_mbew.

    SELECT matnr, lfgja, lfmon, stprs, peinh, bwkey FROM mbewh FOR ALL ENTRIES IN @mt_output
      WHERE matnr = @mt_output-matnr AND bwkey = '4200' AND lfgja = @mt_output-year AND lfmon = @mt_output-month
      INTO TABLE @lt_mbewh.

    LOOP AT mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      READ TABLE lt_mbew INTO DATA(ls_m) WITH TABLE KEY matnr = <ls_out>-matnr.
      IF sy-subrc = 0 AND ls_m-stprs IS NOT INITIAL.
        <ls_out>-price = ls_m-stprs / ls_m-peinh.
      ELSE.
        READ TABLE lt_mbewh INTO DATA(ls_mh) WITH TABLE KEY matnr = <ls_out>-matnr
                                                          lfgja = <ls_out>-year
                                                          lfmon = <ls_out>-month.
        IF sy-subrc = 0. <ls_out>-price = ls_mh-stprs / ls_mh-peinh. ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD calculate_octroi.
    LOOP AT mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      IF <ls_out>-cityc = '022'.
        IF <ls_out>-mtart = 'FERT'.
          " Refactored ZINM/ZINC logic for Octroi
          <ls_out>-octroi = <ls_out>-netwr.
        ELSEIF <ls_out>-mtart = 'Y0PO' OR <ls_out>-mtart = 'Y0AM'.
          " Usage Indicator logic (YRB/YFU)
          IF <ls_out>-vkaus = 'YRB'. <ls_out>-octroi = <ls_out>-netwr. ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_texts.
    TYPES: BEGIN OF ty_zterm_cache,
             zterm TYPE dzterm, text1 TYPE text50,
           END OF ty_zterm_cache.
    DATA lt_zterm_cache TYPE HASHED TABLE OF ty_zterm_cache WITH UNIQUE KEY zterm.

    LOOP AT mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      DATA(lv_name) = CONV TDOBNAME( <ls_out>-vbeln && <ls_out>-posnr ).
      DATA lt_lines TYPE TABLE OF tline.
      CALL FUNCTION 'READ_TEXT' EXPORTING id = '0001' language = sy-langu name = lv_name object = 'VBBP'
        TABLES lines = lt_lines EXCEPTIONS OTHERS = 0.
      READ TABLE lt_lines INDEX 1 INTO DATA(ls_l). <ls_out>-excise_nr = ls_l-tdline.

      READ TABLE lt_zterm_cache INTO DATA(ls_cache) WITH KEY zterm = <ls_out>-zterm.
      IF sy-subrc = 0.
        <ls_out>-zterm = ls_cache-text1.
      ELSE.
        DATA(lv_orig_zterm) = <ls_out>-zterm.
        DATA ls_t052 TYPE t052. ls_t052-zterm = <ls_out>-zterm.
        DATA lt_ztext TYPE TABLE OF ttext.
        CALL FUNCTION 'Y0FI_TEXT_ZTERM' EXPORTING i_t052 = ls_t052 TABLES t_ztext = lt_ztext.
        READ TABLE lt_ztext INDEX 1 INTO DATA(ls_zt).
        <ls_out>-zterm = ls_zt-text1.
        INSERT VALUE #( zterm = lv_orig_zterm text1 = ls_zt-text1 ) INTO TABLE lt_zterm_cache.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD display_report.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_salv) CHANGING t_table = mt_output ).
        DATA(lo_cols) = lo_salv->get_columns( ). lo_cols->set_optimize( abap_true ).
        DATA(lt_labels) = VALUE string_table( ( `OVERDUE` ) ( `JLST` ) ( `JCST` ) ( `JCIS` ) ( `JOCG` ) ( `JOSG` ) ( `JOIG` ) ).
        LOOP AT lt_labels INTO DATA(lv_lab).
          TRY.
              DATA lv_COLUMNNAME TYPE CHAR30.
              lv_columnname = lv_lab.
              DATA(lo_col) = lo_cols->get_column( lv_columnname ).
              CASE lv_lab.
                WHEN 'OVERDUE'. lo_col->set_long_text( 'Overdue' ). WHEN 'JLST'. lo_col->set_long_text( 'VAT' ).
                WHEN 'JCST'. lo_col->set_long_text( 'Cst' ). WHEN 'JCIS'. lo_col->set_long_text( 'Cess' ).
                WHEN 'JOCG'. lo_col->set_long_text( 'Central GST' ). WHEN 'JOSG'. lo_col->set_long_text( 'State GST' ).
                WHEN 'JOIG'. lo_col->set_long_text( 'Integrated GST' ).
              ENDCASE.
            CATCH cx_salv_not_found.
          ENDTRY.
        ENDLOOP.
        lo_salv->get_functions( )->set_all( abap_true ). lo_salv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.


START-OF-SELECTION.

  DATA(ls_params) = VALUE zcl_sd_dispatch_report=>ty_selection_params(
    pa_so    = pa_so
    pa_po    = pa_po
    so_vkorg = so_vkorg[]
    so_vbeln = so_vbeln[]
    so_fkart = so_fkart[]
    so_erdat = so_erdat[]
    so_fkdat = so_fkdat[]
    so_kunag = so_kunag[]
    so_regio = so_regio[]
    so_matnr = so_matnr[]
    so_werks = so_werks[]
    so_vstel = so_vstel[]
    so_lvbln = so_lvbln[]
    so_lfdat = so_lfdat[]
    so_lfedt = so_lfedt[]
    so_wadat = so_wadat[]
  ).

  NEW zcl_sd_dispatch_report( ls_params )->run( ).