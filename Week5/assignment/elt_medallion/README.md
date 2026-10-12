# ride_lakehouse — ELT with a medallion architecture

<!-- Week 5 Assignment, Part 3. Answer the three questions at the bottom.
     A few sentences each is enough. -->

```
ride_prod ──COPY──▶ bronze ──SQL──▶ silver ──SQL──▶ gold
           (Python)        (in Postgres)    (in Postgres)
```

| Layer | Holds | Written by |
|---|---|---|
| `bronze` | Every row the source sent, as TEXT, never changed | `run_elt.py` (COPY) |
| `silver` | One clean, typed row per entity; bad rows in `silver.trips_quarantine` | `sql/10_silver.sql` |
| `gold` | Star schema + mart for analysts | `sql/20_gold.sql` |
| `ops` | Log of each run and step | `run_elt.py` |

## Setup

```bash
createdb ride_lakehouse
psql -d ride_lakehouse -f sql/00_bronze.sql      # provided: bronze + ops
psql -d ride_lakehouse -f sql/01_schema.sql      # yours: silver + gold tables
cp .env.example .env                             # fill in passwords
```

## Run

```bash
python run_elt.py                    # copy the source into bronze, then build silver + gold
python run_elt.py --skip-extract     # rebuild silver + gold from bronze only
```

## Questions

### 1. ETL vs ELT
In Part 1 the transformation is Python. Here it is SQL inside the database. Give one advantage
of each approach.

ETL lets Python perform complex transformations before the data reaches the
warehouse, which is useful when the transformation logic is easier to express
in application code. ELT loads the raw data first and uses SQL inside the
database, which makes transformations easy to rebuild using the database's
processing power.

### 2. Why keep bronze?
In step (c) you changed a rule and rebuilt gold. How would you have done that in the Part 1
pipeline, which keeps no raw copy?

Bronze keeps the original raw source data unchanged. When the region rule
changed so Texas and Arizona became Southwest, Silver and Gold could simply
be rebuilt from Bronze without reading the source again. In the Part 1 ETL
pipeline, because no raw copy is retained, we would normally need to extract
the source data again and rerun the transformation.

### 3. Quarantine vs reject
Part 1 logs rejected rows and drops them. Here they go to a table. What can you do with the
table that you can't do with a log line?

A quarantine table preserves the complete bad row together with its rejection
reason. Analysts or engineers can query, investigate, fix, and potentially
reprocess those rows later. A log message only records information about the
failure and does not provide a structured dataset that can easily be queried
or reprocessed.