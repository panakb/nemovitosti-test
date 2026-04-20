# Nemovitosti – Datové řešení

## Stav projektu

| Část | Stav |
|------|------|
| SQL schéma (`01_schema.sql`) | ✅ hotovo |
| SQL import (`02_import_raw.sql`) | ✅ hotovo |
| SQL transformace + view (`03_transform.sql`) | ✅ hotovo |
| Jupyter Notebook ETL (`notebooks/import.ipynb`) | ✅ hotovo |
| Power BI report | ⬜ zbývá |
| Reverse geocoding (Nominatim) | ✅ implementováno v notebooku |

---

## Zadání (shrnutí)

Datové řešení pro dva datasety nemovitostí:
- propojit s číselníky ČÚZK (katastrální území → pracoviště → kontakt)
- Power BI report: adresa + katastrální úřad, mapa, filtry, datová kvalita

---

## Datové zdroje

### Zdrojové soubory (složka `data/`)

| Soubor | Obsah | Řádků |
|--------|-------|-------|
| `Občanská vybavenost- nemovitosti.xlsx` | stavby OV, převážně Praha 2 | ~4 760 |
| `Činžovní domy - nemovitosti.xlsx` | bytové domy, celá ČR | ~2 051 |

Sheet v obou souborech: `NEMOVITOSTI`

### Struktura sloupců

| Sloupec | OV | CD |
|---------|----|----|
| ID | ✓ | ✓ |
| ID Subjektu | ✗ | ✓ |
| Využití budovy | ✓ | ✓ |
| Kraj / Okres / MČ | ✓ | ✓ |
| Katastrální území | ✓ | ✓ |
| Ulice č.p./č.e. | ✓ | ✓ |
| Město / PSČ | ✓ | ✓ |
| GPS | ✓ `N xx.xxxx E xx.xxxx` | ✓ zkrácená přesnost |
| Vymezené byty / Vlastnictví / Typ budovy / Ochrana | ✓ | ✓ |
| Datum dokončení RUIAN | ✓ | ✗ |

### ČÚZK číselníky (složka `data/cuzk/`)

Stáhnout z [ČÚZK – číselníky](https://cuzk.gov.cz/Katastr-nemovitosti/Poskytovani-udaju-z-KN/Ciselniky-ISKN/Ciselniky-katastralnich-uzemi-a-pracovist-resortu.aspx) ve formátu CSV (ZIP):

| Soubor | Obsah | Kódování |
|--------|-------|----------|
| `SC_PRACRES_DOTAZ.csv` | pracoviště resortu ČÚZK (~117 řádků) | cp1250, LF |
| `SC_SEZNAMKUKRA_DOTAZ.csv` | katastrální území (~13 074 řádků) | cp1250, LF |

---

## Architektura databáze

### Schéma (star schema)

```
katastralni_urady          katastralni_uzemi
─────────────────          ──────────────────────────────
kod PK              ←FK─   prares_kod
nazev                      ku_kod PK
typ_prac                   ku_nazev         ←── join key
telefon / email            platnost_do NULL = aktivní
nazev_ulice / obec / psc

                           nemovitosti (fact)
                           ─────────────────────────────
                           (id, typ_datasetu) PK
                           katastralni_uzemi       ← zdrojový text
                           katastralni_uzemi_klic  ← odvozený join key
                           gps_lat / gps_lon / gps_text
                           pocet_ov_7km            ← index obslužnosti
                           geocoding_shoda/adresa
```

Join pro reporting: `nemovitosti.katastralni_uzemi_klic = katastralni_uzemi.ku_nazev`

### Klíčová rozhodnutí

- **Žádné FK na `nemovitosti`** – join logika žije ve view `v_report`, ne v constraintech
- **`katastralni_uzemi_klic`** – odvozený sloupec: text ze zdroje bez části za poslední `-`
  - `'Říčany u Prahy - Říčany'` → `'Říčany u Prahy'`
  - `'Říčany-Radošovice - Radošovice'` → `'Říčany-Radošovice'`
  - Dvě iterace: druhá pro případ `'Příbram - Příbram V-Zdaboř'` → `'Příbram - Příbram V'` → `'Příbram'`
- **`platnost_do IS NULL`** ve view – jen aktivní katastrální území (historické duplicity)
- **Composite PK** `(id, typ_datasetu)` – ID pochází ze dvou nezávislých systémů
- **`pocet_ov_7km`** – počet budov OV do 7 km (Pythagorova aproximace), jen pro `cinzovni_domy`

---

## Spuštění

### SQL pipeline (přímý import z CSV)

**Příprava:** zkopírovat do `C:/ProgramData/MySQL/MySQL Server 9.6/Uploads/`:
- `SC_PRACRES_DOTAZ.csv`
- `SC_SEZNAMKUKRA_DOTAZ.csv`
- `Obcanska_vybavenost.csv` (export z xlsx, UTF-8, středník, CRLF)
- `Cinzovni_domy.csv` (totéž)

**Pořadí spuštění:**

| Situace | Skripty |
|---------|---------|
| Nová databáze / změna schématu | `01_schema.sql` → `02_import_raw.sql` → `03_transform.sql` |
| Pouze aktualizace dat | `02_import_raw.sql` → `03_transform.sql` |

> ⚠️ Workbench timeout: `Edit → Preferences → SQL Editor → DBMS connection read timeout → 600 s`

### Jupyter Notebook (alternativa – čte xlsx přímo)

```bash
pip install pandas openpyxl sqlalchemy pymysql cryptography requests
jupyter notebook notebooks/import.ipynb
```

1. Upravit `DB_URL` v buňce Config (heslo)
2. Spustit všechny buňky po pořadí
3. `pocet_ov_7km` se spočítá v Pythonu (numpy), uloží přes upsert
4. Geocoding (poslední buňka) – LIMIT 100, rate limit 1 req/s

---

## Tabulky a view

### `nemovitosti` – vybrané sloupce

| Sloupec | Typ | Popis |
|---------|-----|-------|
| `id` | BIGINT | PK část 1 |
| `typ_datasetu` | ENUM | `obcanska_vybavenost` / `cinzovni_domy` |
| `katastralni_uzemi` | VARCHAR(100) | zdrojový text (audit) |
| `katastralni_uzemi_klic` | VARCHAR(100) | join key na číselník |
| `gps_text` | VARCHAR(60) | původní GPS řetězec (audit) |
| `gps_lat` / `gps_lon` | DECIMAL(10,7) | parsované souřadnice |
| `pocet_ov_7km` | SMALLINT UNSIGNED | index obslužnosti (jen CD) |
| `geocoding_shoda` | TINYINT(1) | výsledek reverse geocodingu |
| `geocoding_adresa` | VARCHAR(300) | adresa z Nominatim |

### `v_report` – view pro Power BI (SQL pipeline)

Flagy nesrovnalostí (1 = problém):

| Flag | Podmínka |
|------|----------|
| `flag_bez_gps` | `gps_lat IS NULL` |
| `flag_bez_ulice` | `ulice_cp IS NULL` |
| `flag_bez_ku` | katastrální území nenalezeno v číselníku |

---

## Power BI (zbývá)

Doporučený přístup: načíst jednotlivé tabulky z MySQL a propojit vztahy v Power BI (star schema).

**Tabulky k načtení:**
- `nemovitosti`
- `katastralni_uzemi`
- `katastralni_urady`

**Vztahy:**
- `nemovitosti.katastralni_uzemi_klic` → `katastralni_uzemi.ku_nazev`
- `katastralni_uzemi.prares_kod` → `katastralni_urady.kod`

**Požadované funkce:**
- Tabulka: adresa + katastrální pracoviště (název, telefon, email, adresa)
- Filtrování: kraj / okres / MČ
- Mapa (Azure Maps): body nemovitostí z `gps_lat`, `gps_lon`; velikost bubliny = `pocet_ov_7km`
- Podmíněné formátování: `flag_bez_gps`, `flag_bez_ulice`, `flag_bez_ku`
- DAX measures:
  ```dax
  Index obslužnosti = DIVIDE(
      CALCULATE(COUNTROWS('nemovitosti'), 'nemovitosti'[typ_datasetu] = "obcanska_vybavenost"),
      CALCULATE(COUNTROWS('nemovitosti'), 'nemovitosti'[typ_datasetu] = "cinzovni_domy")
  )

  Diverzita OV = CALCULATE(
      DISTINCTCOUNT('nemovitosti'[vyuziti_budovy]),
      'nemovitosti'[typ_datasetu] = "obcanska_vybavenost"
  )
  ```

---

## Známé gotchas

| Problém | Řešení |
|---------|--------|
| MySQL 9.6 nepodporuje `ON DUPLICATE KEY UPDATE` v `LOAD DATA` | použit `REPLACE` keyword |
| ČÚZK CSV má trailing spaces v názvech sloupců | `df.columns.str.strip()` v notebooku |
| Workbench timeout 30 s | nastavit na 600 s v Preferences |
| MySQL caching_sha2_password auth | `pip install cryptography` |
| VS Code hlásí chybu na `CREATE DATABASE IF NOT EXISTS` | false positive, v Workbench funguje |
| GPS formát: `N lat E lon` | parsovat SUBSTRING + LOCATE (SQL) nebo `split(' E ')` (Python) |
| Datum v CSV: formát `DD.MM.YYYY` | `STR_TO_DATE(..., '%d.%m.%Y')` / `pd.to_datetime(..., format='%d.%m.%Y')` |
