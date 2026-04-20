-- =============================================================================
-- Nemovitosti – datové řešení
-- 02_import_raw.sql  –  import dat do databáze
--
-- Předpoklady:
--   1. Spuštěn 01_schema.sql
--   2. CSV soubory zkopírovány do secure_file_priv složky (viz níže)
--
-- Pořadí importu:
--   a) katastralni_urady   (musí být před katastralni_uzemi – FK závislost)
--   b) katastralni_uzemi
--   c) nemovitosti (obcanska_vybavenost)
--   d) nemovitosti (cinzovni_domy)
-- =============================================================================

-- Soubory ke zkopírování do secure_file_priv (C:/ProgramData/MySQL/MySQL Server 9.6/Uploads/):
--   data/cuzk/SC_PRACRES_DOTAZ.csv
--   data/cuzk/SC_SEZNAMKUKRA_DOTAZ.csv
--   data/Obcanska vybavenost- nemovitosti.csv
--   data/Cinzovni domy - nemovitosti.csv

USE nemovitosti;
SET NAMES utf8mb4;
SET foreign_key_checks = 0;


-- =============================================================================
-- 1. katastralni_urady  (zdroj: SC_PRACRES_DOTAZ.csv, 117 řádků, cp1250)
--    Kódování cp1250 – MySQL převede automaticky na utf8mb4 při importu.
-- =============================================================================

TRUNCATE TABLE katastralni_urady;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 9.6/Uploads/SC_PRACRES_DOTAZ.csv'
    INTO TABLE katastralni_urady
    CHARACTER SET cp1250
    FIELDS TERMINATED BY ';'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n'
    IGNORE 1 LINES
    -- Pořadí sloupců v CSV:
    -- KOD, ZKRATKA, TYP_PRAC, NAZEV, NAZEV_ZKRACENY,
    -- NADRIZ_PRAC, PLATNOST_OD, PLATNOST_DO,
    -- ICO, TELEFON, FAX, EMAIL, TYP_ADRESY(skip), OKRES(skip),
    -- OBEC, MESTSKY_OBVOD, CAST_OBCE, CISLO_DOMOVNI,
    -- NAZEV_ULICE, CISLO_ORIENTACNI, PSC, STAT(skip), KOD_PRO_VS(skip)
    (
        @_kod,  @_zkratka,  @_typ_prac,  @_nazev,     @_nazev_zkr,
        @_nadriz,           @_plat_od,   @_plat_do,
        @_ico,  @_telefon,  @_fax,       @_email,
        @_skip, @_skip2,
        @_obec, @_mest_obv, @_cast_obce,
        @_cislo_dom,        @_nazev_ul,  @_cislo_or,
        @_psc,
        @_skip3, @_skip4
    )
    SET
        kod            = @_kod,
        zkratka        = NULLIF(TRIM(@_zkratka),    ''),
        typ_prac       = @_typ_prac,
        nazev          = TRIM(@_nazev),
        nazev_zkraceny = NULLIF(TRIM(@_nazev_zkr),  ''),
        nadriz_prac    = NULLIF(@_nadriz,            ''),
        platnost_od    = STR_TO_DATE(@_plat_od,      '%d.%m.%Y'),
        platnost_do    = IF(@_plat_do = '', NULL,
                            STR_TO_DATE(@_plat_do,   '%d.%m.%Y')),
        ico            = NULLIF(TRIM(@_ico),         ''),
        telefon        = NULLIF(TRIM(@_telefon),     ''),
        fax            = NULLIF(TRIM(@_fax),         ''),
        email          = NULLIF(TRIM(@_email),       ''),
        obec           = NULLIF(TRIM(@_obec),        ''),
        mestsky_obvod  = NULLIF(TRIM(@_mest_obv),    ''),
        cast_obce      = NULLIF(TRIM(@_cast_obce),   ''),
        cislo_domovni  = NULLIF(TRIM(@_cislo_dom),   ''),
        nazev_ulice    = NULLIF(TRIM(@_nazev_ul),    ''),
        cislo_orient   = NULLIF(TRIM(@_cislo_or),    ''),
        psc            = NULLIF(TRIM(@_psc),         '');

SELECT CONCAT('katastralni_urady: importováno ', ROW_COUNT(), ' řádků') AS info;


-- =============================================================================
-- 2. katastralni_uzemi  (zdroj: SC_SEZNAMKUKRA_DOTAZ.csv, 13 074 řádků, cp1250)
-- =============================================================================

TRUNCATE TABLE katastralni_uzemi;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 9.6/Uploads/SC_SEZNAMKUKRA_DOTAZ.csv'
    INTO TABLE katastralni_uzemi
    CHARACTER SET cp1250
    FIELDS TERMINATED BY ';'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\n'
    IGNORE 1 LINES
    -- Pořadí sloupců v CSV:
    -- KRAJ_KOD, KRAJ_NAZEV, OKRES_KOD, NUTS4(skip), OKRES_NAZEV,
    -- OBEC_KOD, OBEC_NAZEV, KU_KOD, KU_PRAC(skip), KU_NAZEV,
    -- MAPA(skip), CISELNA_RADA(skip), PLATNOST_OD, PLATNOST_DO,
    -- PRARES_KOD, PRARES_NAZEV, POZNAMKA(skip)
    (
        @_kraj_kod, @_kraj_naz, @_okres_kod, @_skip,    @_okres_naz,
        @_obec_kod, @_obec_naz, @_ku_kod,   @_skip2,   @_ku_naz,
        @_skip3,    @_skip4,
        @_plat_od,  @_plat_do,
        @_prares_kod,           @_prares_naz,           @_skip5
    )
    SET
        ku_kod       = @_ku_kod,
        ku_nazev     = TRIM(@_ku_naz),
        kraj_kod     = NULLIF(@_kraj_kod,        ''),
        kraj_nazev   = NULLIF(TRIM(@_kraj_naz),  ''),
        okres_kod    = NULLIF(@_okres_kod,        ''),
        okres_nazev  = NULLIF(TRIM(@_okres_naz), ''),
        obec_kod     = NULLIF(@_obec_kod,         ''),
        obec_nazev   = NULLIF(TRIM(@_obec_naz),  ''),
        platnost_od  = STR_TO_DATE(@_plat_od,     '%d.%m.%Y'),
        platnost_do  = IF(@_plat_do = '', NULL,
                          STR_TO_DATE(@_plat_do,  '%d.%m.%Y')),
        prares_kod   = @_prares_kod,
        prares_nazev = NULLIF(TRIM(@_prares_naz), '');

SELECT CONCAT('katastralni_uzemi: importováno ', ROW_COUNT(), ' řádků') AS info;


-- =============================================================================
-- 3. Nemovitosti – občanská vybavenost  (4 760 řádků)
--    Zdroj: data/obcanska_vybavenost.csv  (generováno z xlsx přes pandas)
--    Sloupce CSV: ID; Využití budovy; Kraj; Okres; MČ; Katastrální území;
--                 Ulice č.p./č.e.; Město; PSČ; GPS; Vymezené byty;
--                 Vlastnictví; Typ budovy; Ochrana; Datum dokončení RUIAN
--    Při opakovaném importu: existující záznamy jsou aktualizovány (upsert).
-- =============================================================================

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 9.6/Uploads/Obcanska_vybavenost.csv'
    REPLACE
    INTO TABLE nemovitosti
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ';'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\r\n'
    IGNORE 1 LINES
    (
        @_id,       @_vyuziti,  @_kraj,     @_okres,    @_mc,
        @_ku,       @_ulice,    @_mesto,    @_psc,      @_gps,
        @_vym_byty, @_vlastn,   @_typ_bud,  @_ochrana,  @_dat_ruian
    )
    SET
        id                    = @_id,
        typ_datasetu          = 'obcanska_vybavenost',
        id_subjektu           = NULL,
        vyuziti_budovy        = NULLIF(TRIM(@_vyuziti),  ''),
        kraj                  = NULLIF(TRIM(@_kraj),     ''),
        okres                 = NULLIF(TRIM(@_okres),    ''),
        mc                    = NULLIF(TRIM(@_mc),       ''),
        katastralni_uzemi     = NULLIF(TRIM(@_ku),       ''),
        ulice_cp              = NULLIF(TRIM(@_ulice),    ''),
        mesto                 = NULLIF(TRIM(@_mesto),    ''),
        psc                   = NULLIF(TRIM(@_psc),      ''),
        gps_text              = NULLIF(TRIM(@_gps),      ''),
        vymezene_byty         = NULLIF(TRIM(@_vym_byty), ''),
        vlastnictvi           = NULLIF(TRIM(@_vlastn),   ''),
        typ_budovy            = NULLIF(TRIM(@_typ_bud),  ''),
        ochrana               = NULLIF(TRIM(@_ochrana),  ''),
        datum_dokonceni_ruian = IF(@_dat_ruian IN ('', 'NaT', 'NaN'), NULL,
                                  STR_TO_DATE(@_dat_ruian, '%d.%m.%Y'));

SELECT CONCAT('nemovitosti (obcanska_vybavenost): importováno/aktualizováno ', ROW_COUNT(), ' řádků') AS info;


-- =============================================================================
-- 4. Nemovitosti – činžovní domy  (2 051 řádků)
--    Zdroj: data/cinzovni_domy.csv  (generováno z xlsx přes pandas)
--    Sloupce CSV: ID; ID Subjektu; Využití budovy; Kraj; Okres; MČ;
--                 Katastrální území; Ulice č.p./č.e.; Město; PSČ; GPS;
--                 Vymezené byty; Vlastnictví; Typ budovy; Ochrana
-- =============================================================================

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 9.6/Uploads/Cinzovni_domy.csv'
    REPLACE
    INTO TABLE nemovitosti
    CHARACTER SET utf8mb4
    FIELDS TERMINATED BY ';'
           OPTIONALLY ENCLOSED BY '"'
    LINES  TERMINATED BY '\r\n'
    IGNORE 1 LINES
    (
        @_id,       @_id_subj,  @_vyuziti,  @_kraj,     @_okres,
        @_mc,       @_ku,       @_ulice,    @_mesto,    @_psc,
        @_gps,      @_vym_byty, @_vlastn,   @_typ_bud,  @_ochrana
    )
    SET
        id                    = @_id,
        typ_datasetu          = 'cinzovni_domy',
        id_subjektu           = NULLIF(@_id_subj,        ''),
        vyuziti_budovy        = NULLIF(TRIM(@_vyuziti),  ''),
        kraj                  = NULLIF(TRIM(@_kraj),     ''),
        okres                 = NULLIF(TRIM(@_okres),    ''),
        mc                    = NULLIF(TRIM(@_mc),       ''),
        katastralni_uzemi     = NULLIF(TRIM(@_ku),       ''),
        ulice_cp              = NULLIF(TRIM(@_ulice),    ''),
        mesto                 = NULLIF(TRIM(@_mesto),    ''),
        psc                   = NULLIF(TRIM(@_psc),      ''),
        gps_text              = NULLIF(TRIM(@_gps),      ''),
        vymezene_byty         = NULLIF(TRIM(@_vym_byty), ''),
        vlastnictvi           = NULLIF(TRIM(@_vlastn),   ''),
        typ_budovy            = NULLIF(TRIM(@_typ_bud),  ''),
        ochrana               = NULLIF(TRIM(@_ochrana),  ''),
        datum_dokonceni_ruian = NULL;

SELECT CONCAT('nemovitosti (cinzovni_domy): importováno/aktualizováno ', ROW_COUNT(), ' řádků') AS info;


SET foreign_key_checks = 1;

-- Ověření importu
SELECT typ_datasetu, COUNT(*) AS pocet FROM nemovitosti GROUP BY typ_datasetu;
SELECT COUNT(*) AS pocet_uradu    FROM katastralni_urady;
SELECT COUNT(*) AS pocet_uzemi    FROM katastralni_uzemi;
