*&---------------------------------------------------------------------*
*& Report Z_SEASON_UPDATE
*&---------------------------------------------------------------------*
*& Modern ABAP Report for Season Update in MARA
*&---------------------------------------------------------------------*
REPORT z_season_update.

* Selection Screen
TABLES: mara.
SELECT-OPTIONS: s_matnr FOR mara-matnr,
                s_satnr FOR mara-satnr,
                s_brand FOR mara-brand_id,
                s_mstae FOR mara-mstae,
                s_lvorm FOR mara-lvorm.
PARAMETERS: p_test AS CHECKBOX DEFAULT 'X'.

CLASS lcl_report DEFINITION.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_mara_update,
             matnr        TYPE mara-matnr,
             brand_id     TYPE mara-brand_id,
             satnr        TYPE mara-satnr,
             zzseason_o   TYPE mara-zzseason,
             zzsyear_o    TYPE mara-zzsyear,
             zzsyear_to_o TYPE mara-zzsyear_to,
             zzseason_n   TYPE mara-zzseason,
             zzsyear_n    TYPE mara-zzsyear,
             zzsyear_to_n TYPE mara-zzsyear_to,
           END OF ty_mara_update.

    TYPES: ty_seasons_mat TYPE STANDARD TABLE OF fsh_seasons_mat WITH EMPTY KEY,
           ty_sd_periods  TYPE STANDARD TABLE OF fsh_sd_periods WITH EMPTY KEY
                          WITH UNIQUE SORTED KEY k1 COMPONENTS fsh_season_year fsh_season fsh_collection fsh_theme.

    METHODS:
      run.

  PRIVATE SECTION.
    DATA: mt_mara_update TYPE STANDARD TABLE OF ty_mara_update,
          mt_seasons_mat TYPE ty_seasons_mat,
          mt_sd_periods  TYPE ty_sd_periods.

    METHODS:
      fetch_data,
      process_logic,
      display_results,
      update_database.
ENDCLASS.

CLASS lcl_report IMPLEMENTATION.
  METHOD run.
    fetch_data( ).
    IF mt_mara_update IS INITIAL.
      MESSAGE 'No materials found for given criteria' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    process_logic( ).
    IF p_test = abap_true.
      display_results( ).
    ELSE.
      update_database( ).
    ENDIF.
  ENDMETHOD.

  METHOD fetch_data.
    SELECT matnr, brand_id, satnr, zzseason, zzsyear, zzsyear_to
      FROM mara
      WHERE matnr    IN @s_matnr
        AND satnr    IN @s_satnr
        AND brand_id IN @s_brand
        AND mstae    IN @s_mstae
        AND lvorm    IN @s_lvorm
      INTO TABLE @DATA(lt_mara).

    IF lt_mara IS INITIAL.
      RETURN.
    ENDIF.

    mt_mara_update = VALUE #( FOR ls_mara IN lt_mara (
      matnr        = ls_mara-matnr
      brand_id     = ls_mara-brand_id
      satnr        = ls_mara-satnr
      zzseason_o   = ls_mara-zzseason
      zzsyear_o    = ls_mara-zzsyear
      zzsyear_to_o = ls_mara-zzsyear_to
    ) ).

    " Fetch all relevant seasons for variants
    SELECT * FROM fsh_seasons_mat
      FOR ALL ENTRIES IN @lt_mara
      WHERE matnr = @lt_mara-matnr
      INTO TABLE @mt_seasons_mat.

    " Fetch all relevant seasons for styles (generic level)
    DATA(lt_styles) = lt_mara.
    SORT lt_styles BY satnr.
    DELETE ADJACENT DUPLICATES FROM lt_styles COMPARING satnr.
    DELETE lt_styles WHERE satnr IS INITIAL.

    IF lt_styles IS NOT INITIAL.
      SELECT * FROM fsh_seasons_mat
        APPENDING TABLE @mt_seasons_mat
        FOR ALL ENTRIES IN @lt_styles
        WHERE matnr = @lt_styles-satnr.
    ENDIF.

    " Remove duplicates
    SORT mt_seasons_mat BY matnr fsh_season_year fsh_season fsh_collection fsh_theme.
    DELETE ADJACENT DUPLICATES FROM mt_seasons_mat COMPARING ALL FIELDS.

    IF mt_seasons_mat IS NOT INITIAL.
      " Fetch SD periods
      SELECT * FROM fsh_sd_periods
        FOR ALL ENTRIES IN @mt_seasons_mat
        WHERE fsh_season_year = @mt_seasons_mat-fsh_season_year
          AND fsh_season      = @mt_seasons_mat-fsh_season
          AND fsh_collection  = @mt_seasons_mat-fsh_collection
          AND fsh_theme       = @mt_seasons_mat-fsh_theme
        INTO TABLE @mt_sd_periods.
    ENDIF.
  ENDMETHOD.

  METHOD process_logic.
    DATA: lt_relevant_seasons TYPE ty_seasons_mat,
          lt_relevant_periods TYPE ty_sd_periods,
          lv_today            TYPE d.

    lv_today = sy-datum.

    LOOP AT mt_mara_update ASSIGNING FIELD-SYMBOL(<fs_update>).
      " 1. Find relevant entries in FSH_SEASONS_MAT
      CLEAR lt_relevant_seasons.
      " a) Try variant level
      lt_relevant_seasons = VALUE #( FOR ls_sea IN mt_seasons_mat WHERE ( matnr = <fs_update>-matnr ) ( ls_sea ) ).

      " b) If no variant entries, try style level
      IF lt_relevant_seasons IS INITIAL AND <fs_update>-satnr IS NOT INITIAL.
        lt_relevant_seasons = VALUE #( FOR ls_sea IN mt_seasons_mat WHERE ( matnr = <fs_update>-satnr ) ( ls_sea ) ).
      ENDIF.

      IF lt_relevant_seasons IS INITIAL.
        CONTINUE.
      ENDIF.

      " If there are entries, find periods
      CLEAR lt_relevant_periods.
      LOOP AT lt_relevant_seasons INTO DATA(ls_rel_sea).
        READ TABLE mt_sd_periods INTO DATA(ls_period)
          WITH KEY k1 COMPONENTS fsh_season_year = ls_rel_sea-fsh_season_year
                                 fsh_season      = ls_rel_sea-fsh_season
                                 fsh_collection  = ls_rel_sea-fsh_collection
                                 fsh_theme       = ls_rel_sea-fsh_theme.
        IF sy-subrc = 0.
          APPEND ls_period TO lt_relevant_periods.
        ENDIF.
      ENDLOOP.

      IF lt_relevant_periods IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA: ls_final_season TYPE fsh_seasons_mat,
            lv_final_year_to TYPE fsh_season_year,
            lv_final_year_from TYPE fsh_season_year.

      IF lines( lt_relevant_seasons ) = 1.
        ls_final_season = lt_relevant_seasons[ 1 ].
      ELSE.
        " Multiple entries
        DATA(lt_matching_periods) = VALUE ty_sd_periods( FOR ls_p IN lt_relevant_periods
                                                         WHERE ( sd_dldt_from <= lv_today AND sd_dldt_to >= lv_today )
                                                         ( ls_p ) ).

        DATA: ls_best_period TYPE fsh_sd_periods.

        IF lt_matching_periods IS INITIAL.
          " No entry matches, take the one where "delivery date to" is highest
          SORT lt_relevant_periods BY sd_dldt_to DESCENDING.
          ls_best_period = lt_relevant_periods[ 1 ].
        ELSE.
          " More than one matches, take the one with highest "delivery date to"
          SORT lt_matching_periods BY sd_dldt_to DESCENDING.
          ls_best_period = lt_matching_periods[ 1 ].
        ENDIF.

        " Find the matching season entry
        READ TABLE lt_relevant_seasons INTO ls_final_season
          WITH KEY fsh_season_year = ls_best_period-fsh_season_year
                   fsh_season      = ls_best_period-fsh_season
                   fsh_collection  = ls_best_period-fsh_collection
                   fsh_theme       = ls_best_period-fsh_theme.
      ENDIF.

      " ZZSYEAR (Season from) - lowest delivery date from
      SORT lt_relevant_periods BY sd_dldt_from ASCENDING.
      lv_final_year_from = lt_relevant_periods[ 1 ]-fsh_season_year.

      " ZZSYEAR_TO adjustment
      lv_final_year_to = ls_final_season-fsh_season_year.
      IF <fs_update>-brand_id <> 'ATA'.
        lv_final_year_to = lv_final_year_to + 1.
      ENDIF.

      " Assign results
      <fs_update>-zzseason_n   = ls_final_season-fsh_season.
      <fs_update>-zzsyear_n    = lv_final_year_from.
      <fs_update>-zzsyear_to_n = lv_final_year_to.

    ENDLOOP.
  ENDMETHOD.

  METHOD display_results.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = DATA(lo_alv)
          CHANGING
            t_table      = mt_mara_update
        ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).

        " Set column headers
        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->get_column( 'ZZSEASON_O' )->set_short_text( 'Old Sea' ).
        lo_cols->get_column( 'ZZSYEAR_O' )->set_short_text( 'Old Year' ).
        lo_cols->get_column( 'ZZSYEAR_TO_O' )->set_short_text( 'Old YrTo' ).
        lo_cols->get_column( 'ZZSEASON_N' )->set_short_text( 'New Sea' ).
        lo_cols->get_column( 'ZZSYEAR_N' )->set_short_text( 'New Year' ).
        lo_cols->get_column( 'ZZSYEAR_TO_N' )->set_short_text( 'New YrTo' ).

        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'ALV Error' TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD update_database.
    DATA: ls_headdata    TYPE bapimathead,
          lt_extensionin TYPE TABLE OF bapipare,
          ls_extensionin TYPE bapipare,
          ls_te_mara     TYPE bapi_te_mara,
          ls_te_marax    TYPE bapi_te_marax,
          lt_return      TYPE TABLE OF bapiret2.

    DATA(lv_updated) = 0.

    LOOP AT mt_mara_update INTO DATA(ls_update) WHERE zzseason_n IS NOT INITIAL.
      CLEAR: ls_headdata, lt_extensionin, lt_return, ls_te_mara, ls_te_marax.

      ls_headdata-material = ls_update-matnr.

      " Extension Data
      ls_te_mara-material   = ls_update-matnr.
      ls_te_mara-zzseason   = ls_update-zzseason_n.
      ls_te_mara-zzsyear    = ls_update-zzsyear_n.
      ls_te_mara-zzsyear_to = ls_update-zzsyear_to_n.

      ls_extensionin-structure = 'BAPI_TE_MARA'.
      ls_extensionin-valuepart1 = ls_te_mara.
      APPEND ls_extensionin TO lt_extensionin.

      " Extension Flags
      ls_te_marax-material   = ls_update-matnr.
      ls_te_marax-zzseason   = abap_true.
      ls_te_marax-zzsyear    = abap_true.
      ls_te_marax-zzsyear_to = abap_true.

      ls_extensionin-structure = 'BAPI_TE_MARAX'.
      ls_extensionin-valuepart1 = ls_te_marax.
      APPEND ls_extensionin TO lt_extensionin.

      CALL FUNCTION 'BAPI_MATERIAL_SAVEDATA'
        EXPORTING
          headdata    = ls_headdata
        TABLES
          return      = lt_return
          extensionin = lt_extensionin.

      IF NOT line_exists( lt_return[ type = 'E' ] ) AND NOT line_exists( lt_return[ type = 'A' ] ).
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            wait = abap_true.
        lv_updated = lv_updated + 1.
      ELSE.
        " In batch mode, consider logging these errors
      ENDIF.
    ENDLOOP.

    IF lv_updated > 0.
      MESSAGE |{ lv_updated } records updated via BAPI.| TYPE 'S'.
    ELSE.
      MESSAGE 'No records to update or all BAPI calls failed.' TYPE 'S'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  NEW lcl_report( )->run( ).
