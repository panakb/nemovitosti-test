-- =============================================================================
-- Nemovitosti – datové řešení
-- 01_schema.sql  –  vytvoření databáze a tabulek
--
-- Pořadí spuštění:
--   1. tento soubor
--   2. 02_import_raw.sql  (import ČÚZK číselníků + surová data nemovitostí)
--   3. 03_transform.sql   (parsování GPS, naplnění klíče, view)
-- =============================================================================

CREATE DATABASE IF NOT EXISTS nemovitosti
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_czech_ci;

USE nemovitosti;

SET foreign_key_checks = 0;

DROP TABLE IF EXISTS nemovitosti;
DROP TABLE IF EXISTS katastralni_uzemi;
DROP TABLE IF EXISTS katastralni_urady;

SET foreign_key_checks = 1;


-- -----------------------------------------------------------------------------
-- katastralni_urady
-- Zdroj: SC_PRACRES_DOTAZ.csv (ČÚZK)
-- Obsahuje všechna pracoviště: katastrální úřady (typ_prac=1),
-- katastrální pracoviště (typ_prac=2) i ostatní typy.
-- -----------------------------------------------------------------------------
CREATE TABLE katastralni_urady (
    kod             INT             NOT NULL    COMMENT 'PK z SC_PRACRES_DOTAZ.KOD',
    zkratka         VARCHAR(20)     NULL,
    typ_prac        TINYINT         NOT NULL    COMMENT '1=KÚ, 2=pracoviště, 3=SCD, 5=ZÚ, 7=ČÚZK',
    nazev           VARCHAR(200)    NOT NULL,
    nazev_zkraceny  VARCHAR(100)    NULL,
    nadriz_prac     INT             NULL        COMMENT 'Kód nadřízeného pracoviště',
    platnost_od     DATE            NOT NULL,
    platnost_do     DATE            NULL,
    ico             VARCHAR(20)     NULL,
    telefon         VARCHAR(50)     NULL,
    fax             VARCHAR(50)     NULL,
    email           VARCHAR(100)    NULL,
    obec            VARCHAR(100)    NULL,
    mestsky_obvod   VARCHAR(100)    NULL,
    cast_obce       VARCHAR(100)    NULL,
    cislo_domovni   VARCHAR(20)     NULL,
    nazev_ulice     VARCHAR(100)    NULL,
    cislo_orient    VARCHAR(20)     NULL,
    psc             VARCHAR(10)     NULL,

    PRIMARY KEY (kod)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_czech_ci;


-- -----------------------------------------------------------------------------
-- katastralni_uzemi
-- Zdroj: SC_SEZNAMKUKRA_DOTAZ.csv (ČÚZK)
-- Číselník katastrálních území s vazbou na příslušné pracoviště (prares_kod).
-- -----------------------------------------------------------------------------
CREATE TABLE katastralni_uzemi (
    ku_kod          INT             NOT NULL    COMMENT 'PK z SC_SEZNAMKUKRA_DOTAZ.KU_KOD',
    ku_nazev        VARCHAR(100)    NOT NULL,
    kraj_kod        INT             NULL,
    kraj_nazev      VARCHAR(100)    NULL,
    okres_kod       INT             NULL,
    okres_nazev     VARCHAR(100)    NULL,
    obec_kod        INT             NULL,
    obec_nazev      VARCHAR(100)    NULL,
    platnost_od     DATE            NOT NULL,
    platnost_do     DATE            NULL,
    prares_kod      INT             NOT NULL    COMMENT 'FK na katastralni_urady.kod (pracoviště)',
    prares_nazev    VARCHAR(200)    NULL,

    PRIMARY KEY (ku_kod),
    CONSTRAINT fk_uzemi_pracoviste
        FOREIGN KEY (prares_kod) REFERENCES katastralni_urady (kod)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_czech_ci;


-- -----------------------------------------------------------------------------
-- nemovitosti
-- Sjednocená tabulka pro oba zdrojové soubory.
-- Rozlišení zdroje přes typ_datasetu.
-- PK je složený (id, typ_datasetu) – ID pochází ze dvou nezávislých systémů.
-- -----------------------------------------------------------------------------
CREATE TABLE nemovitosti (
    id                      BIGINT          NOT NULL,
    typ_datasetu            ENUM(
                                'obcanska_vybavenost',
                                'cinzovni_domy'
                            )               NOT NULL,
    id_subjektu             BIGINT          NULL        COMMENT 'Pouze cinzovni_domy',
    vyuziti_budovy          VARCHAR(100)    NULL,
    kraj                    VARCHAR(100)    NULL,
    okres                   VARCHAR(100)    NULL,
    mc                      VARCHAR(100)    NULL,
    katastralni_uzemi       VARCHAR(100)    NULL        COMMENT 'Textový název ze zdroje',
    katastralni_uzemi_klic  VARCHAR(100)    NULL        COMMENT 'Join klíč: katastralni_uzemi bez textu za poslední pomlčkou',
    ku_kod                  INT             NULL,
    ulice_cp                VARCHAR(150)    NULL,
    mesto                   VARCHAR(150)    NULL,
    psc                     VARCHAR(10)     NULL,
    gps_text                VARCHAR(60)     NULL        COMMENT 'Původní GPS řetězec – audit trail',
    gps_lat                 DECIMAL(10, 7)  NULL,
    gps_lon                 DECIMAL(10, 7)  NULL,
    vymezene_byty           VARCHAR(10)     NULL,
    vlastnictvi             VARCHAR(50)     NULL,
    typ_budovy              VARCHAR(100)    NULL,
    ochrana                 VARCHAR(200)    NULL,
    datum_dokonceni_ruian   DATE            NULL        COMMENT 'Pouze obcanska_vybavenost',
    geocoding_shoda         VARCHAR(50)     NULL        COMMENT 'Typ výsledku z Mapy.cz (regional.address, poi.school, …)',
    geocoding_adresa        VARCHAR(300)    NULL,
    geocoding_metoda        VARCHAR(10)     NULL        COMMENT 'forward = adresa→GPS, reverse = GPS→adresa',
    pocet_ov_7km            SMALLINT UNSIGNED NULL       COMMENT 'Počet budov OV do 7 km (pouze cinzovni_domy)',
    created_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME        NOT NULL    DEFAULT CURRENT_TIMESTAMP
                                                        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id, typ_datasetu),
    INDEX idx_kraj      (kraj),
    INDEX idx_okres     (okres),
    INDEX idx_mc        (mc),
    INDEX idx_typ       (typ_datasetu),
    INDEX idx_gps       (gps_lat, gps_lon),
    INDEX idx_ku_klic (katastralni_uzemi_klic)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_czech_ci;
