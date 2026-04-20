-- =============================================================================
-- Nemovitosti – datové řešení
-- 03_transform.sql  –  transformace + view pro reporting
--
-- Spustit po 02_import_raw.sql.
-- Skript je idempotentní – lze spustit opakovaně bez vedlejších efektů.
--
-- Vazba:
--   nemovitosti.katastralni_uzemi = katastralni_uzemi.ku_nazev
--     → katastralni_uzemi.prares_kod = katastralni_urady.kod
-- =============================================================================

USE nemovitosti; 
SET SQL_SAFE_UPDATES = 0;


-- =============================================================================
-- 1. Naplnění katastralni_uzemi_klic
--    Logika: pokud katastralni_uzemi obsahuje alespoň jednu pomlčku,
--            vezmi vše před posledním výskytem '-' a ořež mezery.
--            Jinak zkopíruj katastralni_uzemi beze změny.
--    Příklady:
--      'Nové Město'                    → 'Nové Město'
--      'Říčany u Prahy - Říčany'       → 'Říčany u Prahy'
--      'Říčany-Radošovice - Radošovice'→ 'Říčany-Radošovice'
--      'Benešov u Prahy - Benešov'     → 'Benešov u Prahy'
-- =============================================================================

UPDATE nemovitosti
SET katastralni_uzemi_klic =
    CASE
        WHEN katastralni_uzemi LIKE '%-%'
        THEN TRIM(LEFT(
                 katastralni_uzemi,
                 CHAR_LENGTH(katastralni_uzemi)
                 - CHAR_LENGTH(SUBSTRING_INDEX(katastralni_uzemi, '-', -1))
                 - 1))
        ELSE katastralni_uzemi
    END
WHERE katastralni_uzemi IS NOT NULL;

SELECT CONCAT('katastralni_uzemi_klic naplněno: ', ROW_COUNT(), ' řádků') AS info;


-- =============================================================================
-- 1b. Druhá iterace pro nenapárované řádky
--     Případ: 'Příbram - Příbram V-Zdaboř' → 'Příbram - Příbram V' (krok 1, nenalezeno)
--             → strip znovu → 'Příbram' (nalezeno)
--     Operuje na katastralni_uzemi_klic (ne na originálu).
--     Podmínka: klic stále obsahuje pomlčku A nenašel se v číselníku.
-- =============================================================================

UPDATE nemovitosti n
LEFT  JOIN katastralni_uzemi ku ON ku.ku_nazev = n.katastralni_uzemi_klic
SET    n.katastralni_uzemi_klic =
    TRIM(LEFT(
        n.katastralni_uzemi_klic,
        CHAR_LENGTH(n.katastralni_uzemi_klic)
        - CHAR_LENGTH(SUBSTRING_INDEX(n.katastralni_uzemi_klic, '-', -1))
        - 1))
WHERE  ku.ku_kod IS NULL
  AND  n.katastralni_uzemi_klic LIKE '%-%';

SELECT CONCAT('katastralni_uzemi_klic opraveno (2. iterace): ', ROW_COUNT(), ' řádků') AS info;


-- =============================================================================
-- 2. Parsování GPS  –  formát: "N 50.0815533703108 E 14.4243770057724"
-- =============================================================================

UPDATE nemovitosti
SET
    gps_lat = CAST(
                  SUBSTRING(gps_text, 3, LOCATE(' E ', gps_text) - 3)
                  AS DECIMAL(10, 7)),
    gps_lon = CAST(
                  SUBSTRING(gps_text, LOCATE(' E ', gps_text) + 3)
                  AS DECIMAL(10, 7))
WHERE  gps_text LIKE 'N % E %'
  AND  gps_lat  IS NULL;

SELECT CONCAT('GPS naparsováno: ', ROW_COUNT(), ' řádků') AS info;


-- =============================================================================
-- 3. Počet budov OV do 7 km pro každý činžovní dům
--    Pravoúhlá aproximace (Pythagoras):
--      d = SQRT( (Δlat × 111.32)² + (Δlon × 111.32 × COS(RADIANS(lat)))² )  [km]
--    Bounding box |Δlat| < 0.065°, |Δlon| < 0.11° před výpočtem odmocniny.
--    Krok a) inicializace → 0 (okamžité).
--    Krok b) přepis pro CD s alespoň 1 OV v dosahu (INNER JOIN).
--    Idempotentní – krok a) má WHERE pocet_ov_7km IS NULL.
-- =============================================================================

-- LEFT JOIN → COUNT(ov.id) vrátí 0 pro CD bez OV v dosahu (COUNT nikdy NULL).
-- Jeden krok postačí, inicializace na 0 není potřeba.
UPDATE nemovitosti n
JOIN (
    SELECT
        cd.id,
        cd.typ_datasetu,
        COUNT(ov.id) AS pocet
    FROM      nemovitosti cd
    LEFT JOIN nemovitosti ov
           ON ov.typ_datasetu = 'obcanska_vybavenost'
          AND ov.gps_lat IS NOT NULL AND ov.gps_lon IS NOT NULL
          AND ABS(cd.gps_lat - ov.gps_lat) < 0.065
          AND ABS(cd.gps_lon - ov.gps_lon) < 0.11
          AND SQRT(
                  POW((cd.gps_lat - ov.gps_lat) * 111.32, 2) +
                  POW((cd.gps_lon - ov.gps_lon) * 111.32 * COS(RADIANS(cd.gps_lat)), 2)
              ) <= 7.0
    WHERE  cd.typ_datasetu = 'cinzovni_domy'
      AND  cd.gps_lat IS NOT NULL AND cd.gps_lon IS NOT NULL
    GROUP BY cd.id, cd.typ_datasetu
) sub ON sub.id = n.id AND sub.typ_datasetu = n.typ_datasetu
SET   n.pocet_ov_7km = sub.pocet
WHERE n.pocet_ov_7km IS NULL;

SELECT CONCAT('pocet_ov_7km vypočteno: ', ROW_COUNT(), ' řádků') AS info;


SET SQL_SAFE_UPDATES = 1;


-- =============================================================================
-- 2. View pro reporting
--
-- Join: nemovitosti.katastralni_uzemi = katastralni_uzemi.ku_nazev
--       katastralni_uzemi.prares_kod  = katastralni_urady.kod
--
-- Flagy nesrovnalostí (1 = problém):
--   flag_bez_gps    – GPS se nepodařilo naparsovat
--   flag_bez_ulice  – chybí ulice / č.p.
--   flag_bez_ku     – katastrální území nenalezeno v číselníku ČÚZK
-- =============================================================================

CREATE OR REPLACE VIEW v_report AS
SELECT
    -- identifikace záznamu
    n.id,
    n.typ_datasetu,
    n.id_subjektu,

    -- adresa
    n.ulice_cp,
    n.mesto,
    n.psc,
    n.mc,
    n.katastralni_uzemi_klic,
    n.katastralni_uzemi,
    n.okres,
    n.kraj,

    -- vlastnosti budovy
    n.vyuziti_budovy,
    n.typ_budovy,
    n.vlastnictvi,
    n.vymezene_byty,
    n.ochrana,
    n.datum_dokonceni_ruian,

    -- GPS
    n.gps_lat,
    n.gps_lon,
    n.gps_text,

    -- katastrální území (z číselníku)
    ku.ku_kod,
    ku.ku_nazev,

    -- katastrální pracoviště
    prac.kod        AS pracoviste_kod,
    prac.nazev      AS pracoviste_nazev,
    prac.telefon    AS pracoviste_telefon,
    prac.email      AS pracoviste_email,
    CONCAT_WS(', ',
        NULLIF(TRIM(CONCAT_WS(' ', prac.nazev_ulice, prac.cislo_domovni)), ''),
        NULLIF(TRIM(CONCAT_WS(' ', prac.psc, prac.obec)), '')
    )               AS pracoviste_adresa,

    -- index obslužnosti
    n.pocet_ov_7km,

    -- bonus: výsledek geocodingu
    n.geocoding_shoda,
    n.geocoding_adresa,

    -- audit
    n.created_at,
    n.updated_at,

    -- flagy nesrovnalostí
    CASE WHEN n.gps_lat  IS NULL THEN 1 ELSE 0 END  AS flag_bez_gps,
    CASE WHEN n.ulice_cp IS NULL THEN 1 ELSE 0 END  AS flag_bez_ulice,
    CASE WHEN ku.ku_kod  IS NULL THEN 1 ELSE 0 END  AS flag_bez_ku

FROM       nemovitosti        n
LEFT JOIN  katastralni_uzemi  ku   ON  ku.ku_nazev = n.katastralni_uzemi_klic 
        AND ku.okres_nazev = n.okres 
        AND ku.platnost_do IS NULL 
LEFT JOIN  katastralni_urady  prac ON  prac.kod    = ku.prares_kod;


-- =============================================================================
-- 3. Validační report
-- =============================================================================

SELECT
    typ_datasetu,
    COUNT(*)          AS celkem,
    SUM(flag_bez_gps)    AS bez_gps,
    SUM(flag_bez_ulice)  AS bez_ulice,
    SUM(flag_bez_ku)     AS bez_ku
FROM  v_report
GROUP BY typ_datasetu;
