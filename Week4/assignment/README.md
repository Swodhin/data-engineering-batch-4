# Week 4 Assignment

This assignment uses the star schema from class (`ride_warehouse`: `dim_date`, `dim_time`,
`dim_driver`, `dim_passenger`, `dim_location`, `dim_payment_method`, `dim_promo_code`,
`fact_trips`) and the ETL that loads it from `ride_prod` ([`../etl.py`](../etl.py)).

The class ETL works on its first run. This assignment asks what happens on the second run, and
whether the warehouse numbers actually match the source:

**[Assignment](sql_assignment.md)**: 8 SQL questions, a schema migration, a two-part Python ETL
exercise, and a stretch exercise.

- **Audit** the class warehouse. Run `etl.py` twice and `dim_driver` has twice the drivers.
  Find out why `ON CONFLICT DO NOTHING` didn't stop it, what the fact table *can't* answer (no
  trip status; `dim_time` isn't joined to anything), and why an average of monthly averages
  isn't the yearly average.
- **Migrate** the warehouse ([`warehouse_migration_template.sql`](warehouse_migration_template.sql)):
  deduplicate the dimensions without orphaning facts, add the missing `UNIQUE` constraints, and
  add `time_key`, `trip_status` and `cancelled_by` to `fact_trips`.
- **Extend the ETL** ([`etl_pipeline.py`](etl_pipeline.py)): populate the new fact columns, and
  write a `reconcile()` check that proves the warehouse matches the source.

  Your reconcile *will* find a real bug in the class pipeline. Tracking it down is part of the
  exercise.
- **Query** the fixed star schema: share of monthly revenue by region, `dim_location` joined
  twice as a role-playing dimension, rush-hour and weekend patterns, and a dimension attribute
  that silently went stale.
- **Stretch:** what happens to `dim_driver` when a driver's status changes, and how SCD Type 1
  and Type 2 handle it.

Use the class files as worked examples for syntax, but don't copy-paste them. No question can be
answered by pasting a class query unchanged.

## Setup

You should already have `ride_prod` (loaded with [`../sample_data_loader.py`](../sample_data_loader.py))
and `ride_warehouse` (created with [`../warehouse.sql`](../warehouse.sql) and loaded by
`../etl.py`) from class. Check:

```sql
-- in ride_prod
SELECT count(*) FROM trips;          -- 10000
-- in ride_warehouse
SELECT count(*) FROM fact_trips;     -- 10000
```

If either is missing, rebuild it from the class files before starting.

**Then run the class ETL a second time** (`python ../etl.py` from this folder). Part 1 needs
the duplicates that a second run creates.

```bash
pip install -r ../requirements.txt
```

`etl_pipeline.py` reads the same `SRC_DB_*` / `DEST_DB_*` variables as the class ETL.
`load_dotenv()` searches upward from the script's folder, so your existing `Week4/.env` is found
automatically.

## What to submit

| File | Start from |
|---|---|
| `week4_queries.sql` | [`week4_queries_template.sql`](week4_queries_template.sql) |
| `warehouse_migration.sql` | [`warehouse_migration_template.sql`](warehouse_migration_template.sql) |
| `etl_pipeline.py` | [`etl_pipeline.py`](etl_pipeline.py) (fill in the `TODO`s) |
| `etl_run_log.txt` | log output from test steps (a)–(c) in the assignment |

Every query needs a one-line comment stating what it answers. Every written answer goes as a
comment directly under its query, not in a separate file.

## How to submit

Same workflow as previous weeks:

```bash
git checkout main
git pull upstream main
git checkout -b week4-assignment

# ... complete the four files ...

git add Week4/assignment/week4_queries.sql Week4/assignment/warehouse_migration.sql \
        Week4/assignment/etl_pipeline.py Week4/assignment/etl_run_log.txt
git commit -m "Complete week 4 assignment"
git push -u origin week4-assignment
```

Then open a pull request **on your own fork** (base: `main`, compare: `week4-assignment`) and
share the link with your instructor. Submit before the Week 5 session begins.
