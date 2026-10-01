# Week 4 — Data Warehouse & ETL

This week we took the normalized ride-share database (the **OLTP** side) and built a **data
warehouse** from it: a star schema (`ride_warehouse`) and a Python ETL that loads it.

```
 ride_prod  (OLTP, normalized)            ride_warehouse  (star schema)
 ─────────────────────────────            ─────────────────────────────
 drivers, passengers, locations,   etl.py  dim_driver, dim_passenger, dim_location,
 payment_methods, promo_codes,    ───────► dim_payment_method, dim_promo_code,
 trips, trip_cancellations, ...            dim_date, dim_time
                                           fact_trips
```

## Files

| File | What it does |
|---|---|
| [`ride_prod_sample.sql`](ride_prod_sample.sql) | Creates the source OLTP database `ride_prod`: normalized tables, constraints, indexes, and the `v_trips` / `v_promo_usage` views |
| [`sample_data_loader.py`](sample_data_loader.py) | Fills `ride_prod` with fake data (fixed seed 42): 25 drivers, 45 passengers, 25 locations, 10,000 trips (~80% completed, 15% cancelled, 5% no-show) |
| [`warehouse.sql`](warehouse.sql) | Creates the star schema in `ride_warehouse` and pre-fills `dim_date` (every day from 2023 to 2026) and `dim_time` (96 fifteen-minute buckets) |
| [`etl.py`](etl.py) | Extracts from `ride_prod`, transforms, and loads into `ride_warehouse` |
| [`assignment/`](assignment/) | This week's assignment |

### Running it

```bash
pip install -r requirements.txt

psql -c "CREATE DATABASE ride_prod;"
psql -d ride_prod -f ride_prod_sample.sql     # skip its first CREATE DATABASE line if it errors
python sample_data_loader.py                   # DB_* from .env, else localhost/ride_prod/postgres

psql -c "CREATE DATABASE ride_warehouse;"
psql -d ride_warehouse -f warehouse.sql
python etl.py                                  # uses SRC_DB_* and DEST_DB_* from .env
```

`.env` needs two sets of connection details, because the ETL talks to two databases at once:

```
SRC_DB_HOST=localhost    SRC_DB_PORT=5432    SRC_DB_NAME=ride_prod       SRC_DB_USER=...   SRC_DB_PASSWORD=...
DEST_DB_HOST=localhost   DEST_DB_PORT=5432   DEST_DB_NAME=ride_warehouse DEST_DB_USER=...  DEST_DB_PASSWORD=...
```

(Write one `KEY=value` per line. They're shown side by side here only to save space.)

---

## Why a warehouse at all?

We already have all the data in `ride_prod`, so why copy it somewhere else?

**The two databases do different jobs.**

| | OLTP (`ride_prod`) | Warehouse (`ride_warehouse`) |
|---|---|---|
| Used by | the app: booking a ride, completing it, charging the card | analysts, dashboards, reports |
| Typical query | "insert this trip", "update trip 4512" | "revenue by region per month for 3 years" |
| Rows touched | one or a few | thousands to millions |
| Design goal | no duplicated data, fast safe writes (normalized, 3NF) | easy, fast reads (denormalized star schema) |

Why that matters:

1. **Protect production.** A heavy report that scans every trip competes with the app for the
   same database. If it runs on the warehouse instead, the app stays fast.
2. **Simpler questions.** In `ride_prod`, "revenue by region" means joining `trips` →
   `locations`, working out the region from `state_province`, and recomputing `fare_amount`
   from four columns. In the warehouse, `region` is already a column on `dim_location` and
   `fare_amount` is already on `fact_trips`.
3. **Calculate business rules once.** Fare formula, region mapping, tenure buckets, cohort
   month: the ETL calculates each of them once. Every report then uses the same answer, instead
   of every analyst writing their own `CASE` statement.
4. **Time is built in.** `dim_date` already knows the quarter, weekday name and whether a day is
   a weekend. `dim_time` knows the time of day and whether it's rush hour. The OLTP database
   only has a raw timestamp.
5. **History and many sources.** A warehouse can keep history the source throws away, and can
   combine data from several systems (later in the course).

---

## What goes in a fact table and what goes in a dimension?

**A simple test:** if you'd **measure** it (sum it, average it, count it), it goes in the
**fact** table. If you'd **filter or group by** it ("by month", "by city", "by payment
type"), it goes in a **dimension**.

### Fact table: `fact_trips`

The **grain** is one row per trip in `ride_prod.trips`. A fact table holds two kinds of
column.

**Foreign keys to every dimension**: `date_key`, `driver_key`, `passenger_key`,
`pickup_location_key`, `dropoff_location_key`, `payment_method_key`, `promo_code_key`.

**Measures**, the numbers. `warehouse.sql` groups them by how you're allowed to aggregate
them:

| Type | Columns | Rule |
|---|---|---|
| Additive | `base_fare`, `tip_amount`, `discount_amount`, `fare_amount`, `distance_km`, `duration_minutes`, `trip_count` | Can be `SUM`med across any dimension |
| Semi-additive | `driver_rating`, `passenger_rating` | `AVG` only. A total of ratings means nothing |
| Non-additive | `surge_multiplier` | A ratio. Never `SUM` it |

It also has `source_trip_id`, which is the OLTP `trip_id`. It's for lineage (tracing a fact
row back to its source row) and is `UNIQUE`, so the same trip can't be loaded twice. And it
keeps `requested_at`, the raw timestamp.

`trip_count` is always `1`. It looks pointless, but `SUM(trip_count)` works in any BI tool
without anyone needing to write `COUNT(*)`.

Fact tables are **long and narrow**: lots of rows (one per event), and mostly numbers and keys.

### Dimension tables: `dim_*`

Each dimension describes one business entity, the "who / what / where / when" of a trip:

| Dimension | Describes | Columns the warehouse adds that the OLTP table doesn't have |
|---|---|---|
| `dim_driver` | who drove | `tenure_bucket` ('0-6 months' … '2+ years') |
| `dim_passenger` | who rode | `cohort_month` ('YYYY-MM' they signed up) |
| `dim_location` | where (used twice: pickup and dropoff) | `region` (Northeast / West / South / Midwest / International) |
| `dim_payment_method` | how they paid | — |
| `dim_promo_code` | which discount | — |
| `dim_date` | which day | year, quarter, month name, ISO week, day name, `is_weekend` |
| `dim_time` | what time | 15-min bucket, `time_of_day`, `is_rush_hour` |

Every dimension has two kinds of key:
- a **surrogate key** (`driver_key`, `SERIAL`): the warehouse's own ID, and the one the fact
  table points to
- the **natural key** (`driver_id`): the ID from the source system, kept so the ETL can match
  rows back to the source

Dimensions are **short and wide**: few rows, many descriptive text columns.

`dim_date` and `dim_time` don't come from `ride_prod` at all. They are **generated** once in
`warehouse.sql` with `generate_series`, and their keys are readable numbers (`20250315`,
`1430`) instead of `SERIAL` values. This means the ETL can work out the key directly from the
timestamp.

Why does the fact table point at our own surrogate key instead of just storing `driver_id`?
- It keeps the warehouse independent of the source's IDs (they can be reused, change, or clash
  when you combine two systems).
- It lets a dimension keep **history** later: one driver can have several `dim_driver` rows,
  one per version (slowly changing dimensions).
- It allows placeholder rows such as "Unknown" or "No Promo" (the comments in
  `dim_payment_method` / `dim_promo_code` mention these) so a fact row always has something to
  join to.

---

## Why load the dimensions first?

Because **the fact table can't be built until the dimension rows exist.**

1. **Foreign keys.** `fact_trips.driver_key REFERENCES dim_driver(driver_key)`. If a fact row
   arrives before its driver, Postgres rejects the insert.
2. **Surrogate keys don't exist until you insert.** `driver_key` is a `SERIAL`, so the warehouse
   assigns it when the `dim_driver` row is inserted. The source trip only knows
   `driver_id = 7`. Until `dim_driver` is loaded, nobody knows which `driver_key` driver 7 has.
3. **The lookup is built from the dimensions.** Step 2 of the transform reads the dimension
   tables. Load them late and the lookup is empty or out of date, and trips get skipped.

So `etl.py`'s `main()` follows a fixed order:

```
drivers → passengers → locations → payment methods → promo codes   (dimensions)
   ↓
extract trips → build lookups from the loaded dims → transform → load fact_trips
```

`dim_date` and `dim_time` are already filled by `warehouse.sql`, which is why they don't appear
in the ETL.

---

## Why use a lookup?

Every trip arrives with **natural keys** (`driver_id`, `passenger_id`, `pickup_location_id`, …),
but `fact_trips` needs **surrogate keys** (`driver_key`, …). Something has to translate one to
the other for every trip: up to 7 translations per trip (date included).

**Approach 1: ask the database each time** (`SELECT driver_key FROM dim_driver WHERE driver_id
= %s`). For 10,000 trips that's up to **70,000 small queries**, each one a round trip over the
network. It's slow, and it gets worse as data grows.

**Approach 2: load each dimension into memory once.** `load_lookup_dim()` runs **6 queries in
total** and builds Python dictionaries:

```python
lookup["driver"]   = {driver_id: driver_key, ...}       # {1: 1, 2: 2, ...}
lookup["location"] = {location_id: location_key, ...}
lookup["date"]     = {date_key: True, ...}              # just "does this date exist?"
```

After that, each translation is a dictionary lookup (`lookup["driver"].get(row["driver_id"])`),
which is effectively instant.

This works because dimensions are **small** (25 drivers, 25 locations, about 1,500 dates) and
fit easily in memory. The fact data is the big part, and it gets streamed through the
dictionaries.

The lookup also acts as a **validation step**: if a key isn't in the dictionary, the trip refers
to a driver, location or date the warehouse doesn't know about. That's the signal for the
transform to skip the row instead of loading bad data.

---

## What happens in the transformation layer?

The transformation happens in **two places**.

### 1. In the extract SQL (for dimensions)

The derived columns for the dimensions are calculated by Postgres inside the `SELECT`, before
the data reaches Python:

| Dimension | Transformation |
|---|---|
| `dim_driver` | `tenure_bucket`: `CASE` on how long ago `joined_at` was, compared with `NOW()` |
| `dim_passenger` | `cohort_month`: `TO_CHAR(created_at, 'YYYY-MM')` |
| `dim_location` | `region`: `CASE` that maps US `state_province` values to Northeast / Midwest / South / West, with anything else as International |

### 2. In Python: `transform_trip()` (for the fact table)

For each extracted trip (joined to `trip_cancellations`), the transform does five things.

1. **Works out `date_key`** from `requested_at` (`2025-03-15 14:37` → `20250315`), and checks
   that it exists in `dim_date`.
2. **Swaps every natural key for a surrogate key** using the lookups: driver, passenger, pickup
   location and dropoff location. `dim_location` is used for **both** pickup and dropoff (a
   *role-playing* dimension).
3. **Handles keys that can be NULL**. `payment_method_id` is `NULL` on no-show trips, and
   `promo_code_id` is `NULL` when no promo was used. The transform only looks these up when they
   have a value. Otherwise the fact column stays `NULL`, which `fact_trips` allows.
4. **Skips bad rows instead of crashing.** If a lookup fails (unknown driver, date outside
   `dim_date`, and so on), it logs a warning with the trip ID and the reason, adds to a
   `skipped` counter, and moves on. At the end it logs `Transformed N rows, skipped M`.
5. **Calculates derived measures** that the OLTP database doesn't store:
   - `fare_amount = base_fare × surge_multiplier + tip_amount − discount_amount` (rounded to 2
     decimals). This is the same formula as the `v_trips` view in `ride_prod`.
   - `duration_minutes = completed_at − requested_at`, only for completed trips. It's `NULL`
     for cancelled and no-show trips.

The output is a list of dictionaries, one per fact row, with the same column names as
`fact_trips`.

---

## What happens in the load layer?

Every `load_*` function follows the same pattern:

```python
try:
    with conn.cursor() as curr:
        curr.executemany(INSERT_SQL, rows)   # one parameterized INSERT, run once per row
        logger.info(f"{curr.rowcount} inserted to <table>")
    conn.commit()                            # the whole table's batch lands together…
except Exception as e:
    conn.rollback()                          # …or none of it does
    logger.error(str(e))
    raise                                    # don't hide the failure from the caller
```

- **Parameterized SQL** (`%(driver_id)s`): `psycopg2` passes the values separately from the
  SQL text, so there are no quoting bugs and no SQL injection. This is the same rule as Week 1.
- **One transaction per table.** Each dimension or fact batch commits as a unit. If one row
  fails, that table's whole batch rolls back (the Week 3 ACID guarantee). Tables that already
  committed stay committed.
- **Rollback, log, re-raise.** The error is logged with its message and then raised again, so
  `main()` stops and nothing is loaded on top of a broken step.
- **`ON CONFLICT … DO NOTHING`**: if a row conflicts with a unique key that's already there,
  it's skipped instead of erroring.
  - `fact_trips` uses `ON CONFLICT (source_trip_id)`, so the same trip can't be loaded twice.
  - `dim_location`, `dim_payment_method` and `dim_promo_code` conflict on their unique natural
    key.
  - `ON CONFLICT` only works if a matching unique constraint exists on the table. Check which
    dimensions have one in `warehouse.sql`. The assignment's Q1 picks up from here.
- **Empty-batch guard.** `load_fact_trips()` returns early when the transform produced no
  rows.
- **Separate connections.** `src_conn` (to `ride_prod`) is only read from. `dst_conn` (to
  `ride_warehouse`) is only written to. The ETL never writes back to production.

---

## Summary: one ETL run

```
                 ride_prod                                   ride_warehouse
                 ─────────                                   ──────────────
 EXTRACT   SELECT drivers (+tenure_bucket) ──┐
           SELECT passengers (+cohort_month) ┤ LOAD ──► dim_driver, dim_passenger,
           SELECT locations (+region)        ┤          dim_location, dim_payment_method,
           SELECT payment_methods, promos ───┘          dim_promo_code        (commit each)
                                                               │
           SELECT trips ⟕ trip_cancellations                   │ load_lookup_dim()
                       │                                       ▼
 TRANSFORM             └──► transform_trip(): natural → surrogate keys,
                            date_key, fare_amount, duration_minutes, skip bad rows
                                       │
 LOAD                                  └──► fact_trips (ON CONFLICT source_trip_id DO NOTHING)
```

The class version gets the warehouse loaded. The [assignment](assignment/) tests it: what
happens when you run it a second time, whether its numbers match the source, and what questions
it still can't answer.
