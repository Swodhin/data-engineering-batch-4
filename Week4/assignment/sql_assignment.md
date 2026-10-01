# Assignment — Week 4

In class we built a star schema (`ride_warehouse`) and an ETL (`etl.py`) that loads it from the
OLTP database (`ride_prod`). It works once. This assignment checks whether it still holds up when
you run it a second time, whether its numbers actually match the source, and what happens when
someone asks a question it wasn't designed for.

You'll work in four parts:

1. **Audit** the class warehouse: find what's broken and what it can't answer
2. **Migrate** it: fix the schema and add the missing columns (`warehouse_migration.sql`)
3. **Extend the ETL** to fill the new columns and check itself against the source (`etl_pipeline.py`)
4. **Query** the fixed star schema (`week4_queries.sql`)

Do the parts **in order**. Part 4 depends on the columns Parts 2 and 3 add.

---

## Part 1 — Audit the class warehouse

Write your answers in `week4_queries.sql`.

> **Before you start:** run the class ETL **twice** (`python ../etl.py`, then again). If you've
> only ever run it once, Q1 has nothing to find.

### Q1 — Run it twice, get twice the drivers (Intermediate · GROUP BY / HAVING + constraints)

Count the rows in `dim_driver`, `dim_passenger`, `dim_location` and `fact_trips`, and compare
each with the source table's row count in `ride_prod`.

1. Write a query that lists every `driver_id` appearing more than once in `dim_driver`, with how
   many copies it has and every `driver_key` it was given (`STRING_AGG` or `ARRAY_AGG`).
2. Pick one duplicated driver. Count how many `fact_trips` rows point at **each** of their
   `driver_key`s. Which copy do the facts actually use, and why that one? Read `load_lookup_dim()`
   and think about which run inserted the fact rows.

In a comment:
- `load_dim_driver()` says `ON CONFLICT DO NOTHING`. Why did that not prevent the duplicates?
  What has to exist on a table for there to be a conflict at all?
- Why did `dim_location` and `fact_trips` **not** duplicate, even though their loads ran twice
  as well? Point to the exact line in `warehouse.sql` that protects each one.
- If an analyst ran `SELECT COUNT(*) FROM dim_driver` to report "active drivers", what number
  would they report after a week of nightly runs?

### Q2 — What the fact table can't answer (Design · no new SQL required beyond trying)

Product asks two questions:

- *"What's our cancellation rate by month?"*
- *"Are fares higher during rush hour?"*

Try to answer each one from `ride_warehouse` alone (no querying `ride_prod`). In a comment:

1. State the **grain** of `fact_trips` in one sentence ("one row per …").
2. Why can't you answer the first question? You might try `duration_minutes IS NULL` as a
   stand-in for "not completed". Show that query, and explain what it lumps together that
   Product would want kept apart.
3. Why can't you answer the second? `dim_time` exists and has `is_rush_hour`, so what's
   missing?
4. `extract_trips()` in `etl.py` already selects `tc.cancelled_by`. What happens to that value?

Part 2 fixes all of this.

### Q3 — Averages of averages (Intermediate · semi-additive measures)

`driver_rating` is a **semi-additive** measure. You can `AVG` it, but you can't `SUM` it, and you
can't average it twice.

For each year, compute in one query:
- `true_avg_rating`: `AVG(driver_rating)` over every trip in that year
- `avg_of_monthly_avgs`: first `AVG` per month, then `AVG` those 12 numbers
- `rated_trips`: how many trips actually have a rating (`COUNT(driver_rating)`)
- `total_trips`: `COUNT(*)`

In a comment:
- Which year shows the biggest gap between the two averages? Why does averaging monthly averages
  give the wrong answer? (Hint: not every month has the same number of rated trips. Look at
  how many months of 2026 are in the data.)
- `rated_trips` is lower than `total_trips`. What does `AVG` do with the `NULL` ratings, and is
  that the behaviour you want here?
- Give one example of a column in `fact_trips` you **can** safely `SUM`, and one you must never
  `SUM` even though it's numeric.

---

## Part 2 — Migrate the warehouse

Write `warehouse_migration.sql`, starting from
[`warehouse_migration_template.sql`](warehouse_migration_template.sql). It must run **once,
top-to-bottom, inside a single transaction**, against a warehouse where the class ETL has been
run at least twice.

### Q4 — The migration (Intermediate–Advanced · DDL + UPDATE … FROM + DELETE … USING)

Your migration must:

1. **Deduplicate `dim_driver` and `dim_passenger`.** Keep exactly one row per natural key. Before
   deleting the extra copies, re-point any `fact_trips` row that references a copy you're about
   to delete (`UPDATE … FROM`). The FK from `fact_trips` will reject a delete that leaves facts
   orphaned, so if your `DELETE` errors, it's telling you something.
2. **Add `UNIQUE` constraints** on `dim_driver(driver_id)` and `dim_passenger(passenger_id)`, so
   this can't happen again.
3. **Add three columns to `fact_trips`:**
   - `time_key INTEGER`, a foreign key to `dim_time(time_key)`
   - `trip_status VARCHAR(20)`, with a `CHECK` for the three OLTP statuses (a **degenerate
     dimension**: a dimension attribute that lives on the fact because it has no other
     attributes worth its own table)
   - `cancelled_by VARCHAR(10)`, with a `CHECK` for `driver` / `passenger` / `system`
4. **Backfill `time_key` in pure SQL** from `requested_at`: `HHMM`, with minutes rounded *down*
   to the 15-minute bucket (`14:37` → `1430`, `09:05` → `900`).

`trip_status` and `cancelled_by` **can't** be backfilled from the warehouse alone (Q2 showed
why). You'll backfill them with the new ETL in Part 3.

After the Part 3 backfill, come back and add to `week4_queries.sql`:
- a verification query showing zero `fact_trips` rows with `trip_status IS NULL` or
  `time_key IS NULL`
- `ALTER TABLE fact_trips ALTER COLUMN trip_status SET NOT NULL` (and `time_key`)
- a comment: why couldn't the `SET NOT NULL` go in the migration itself?

---

## Part 3 — Python: extend the ETL

Complete [`etl_pipeline.py`](etl_pipeline.py). It's the class ETL with the dimension loads
folded into one generic `load_dim()`, and with a fact load that **updates** existing rows
(`ON CONFLICT (source_trip_id) DO UPDATE`), so running it fills the new columns on the 10,000
trips the class ETL already loaded. Everything except two functions is provided. Each one is
marked `TODO`:

### P1 — `transform_trip()`: the new columns

Populate `time_key` (same rule as Q4, in Python), `trip_status` and `cancelled_by`.

### P2 — `reconcile()`: prove it, don't assume it

Run three checks against both databases and log one `PASS`/`FAIL` line per check, showing both
numbers:

1. `drivers` vs `dim_driver`, and `passengers` vs `dim_passenger`, row counts
2. trip count **per status**: `trips.status` vs `fact_trips.trip_status`
3. completed revenue: `SUM(fare_amount)` from the source view `v_trips` vs `fact_trips`,
   **to the cent**

Return `True`/`False`. `main()` exits with status `1` on failure so a scheduler would flag the
run.

> **Expect check 3 to FAIL the first time,** by a few dollars on roughly 650k of revenue. Your
> reconcile isn't wrong. The transform is. Find the cause:
> 1. Join source and warehouse fares **per trip** (copy one side across with `\copy`, or compare
>    in Python) and list the trips that differ. By how much does each one differ?
> 2. Take one mismatched trip and compute `base_fare * surge_multiplier + tip_amount -
>    discount_amount` by hand. What is the unrounded value?
> 3. Compare how `v_trips` rounds it (Postgres `ROUND`) with how `transform_trip()` rounds it
>    (Python `round()` on a `Decimal`). Look up "banker's rounding".
>
> Fix it in `transform_trip()` (`Decimal.quantize` with `ROUND_HALF_UP`), re-run, and get all
> checks to `PASS`.

### Test sequence

Run this from `Week4/assignment/`, in order, and paste the log output of each step into
`etl_run_log.txt`:

```bash
psql -d ride_warehouse -f warehouse_migration.sql   # Part 2
python etl_pipeline.py                              # (a) backfill: revenue check FAILS
# ... fix the rounding in transform_trip() ...
python etl_pipeline.py                              # (b) every check PASSES
python etl_pipeline.py                              # (c) run again: dimension counts unchanged, still PASS
```

In a comment at the top of `etl_run_log.txt`: step (c) didn't duplicate anything, but Q1 showed
the class ETL did. What changed? You didn't touch the dimension `INSERT`.

---

## Part 4 — Query the star schema

Every query in this part joins `fact_trips` to at least one dimension. Write them in
`week4_queries.sql`.

### Q5 — Monthly revenue by region, with share of month (Intermediate · star join + window)

For **2025**, completed trips only, show one row per month × pickup region: `month`,
`month_name`, `region`, `trips`, `revenue`, and `pct_of_month`, the region's share of that
month's total revenue (1 decimal). Get `pct_of_month` with a window function over the aggregate
(`SUM(SUM(fare_amount)) OVER (PARTITION BY …)`), not a second query. Order by month, then revenue
descending.

In a comment: why filter on `dim_date.year = 2025` rather than
`EXTRACT(YEAR FROM fact_trips.requested_at) = 2025`? Both give the same rows. What's the point of
having `dim_date`?

### Q6 — Role-playing dimension: routes (Intermediate · same dim joined twice)

`dim_location` plays two roles: pickup and dropoff.
1. Top 10 routes (`'<pickup city> → <dropoff city>'`) by completed trips, with revenue and
   average `distance_km`.
2. One row: how many trips (any status) cross a **country** border, out of how many in total,
   and as a percentage.

In a comment: what is a role-playing dimension, and why is joining `dim_location` twice under
two aliases better than building `dim_pickup_location` and `dim_dropoff_location` tables?

### Q7 — When do people ride, and when do they cancel? (Intermediate–Advanced · two dims + FILTER)

Using your new `time_key` and `trip_status`, show one row per `is_weekend` × `time_of_day`
with: `trips` (any status), `avg_fare` (completed only), `avg_surge`, and `cancellation_rate_pct`.
Use `COUNT(*) FILTER (WHERE …)` / `AVG(…) FILTER (WHERE …)` rather than `CASE` inside the
aggregate.

Then, for cancelled trips only: who cancels (`cancelled_by`) during rush hour vs. outside it,
each as a percentage of that period's cancellations.

In a comment: answer Product's question from Q2. Are fares higher during rush hour in this
data? (It's synthetic. Report what the numbers say, even if it's "no meaningful difference".)
`Night` has far more trips than any other bucket. Is that because people ride more at night?
Check how many hours each `time_of_day` covers in `warehouse.sql`.

### Q8 — The tenure bucket that never changes (Advanced · dimension design)

Group completed trips' revenue by `dim_driver.tenure_bucket`. You'll get **one** bucket. Read
how `extract_driver()` computes it and explain why.

Now compute **tenure at the time of the trip** instead (`fact_trips.requested_at -
dim_driver.joined_at`), bucketed as `0-1 yr` / `1-2 yrs` / `2-3 yrs` / `3+ yrs`, and show trips,
revenue and distinct drivers per bucket.

In a comment:
- Why is a dimension attribute computed relative to `NOW()` a bad idea? The loads use `ON
  CONFLICT DO NOTHING`. When does a driver's `tenure_bucket` ever get recalculated?
- Tenure at trip time is a property of the *trip*, not the driver. Where should it live in the
  model? Give one option and its trade-off.

---

## Stretch — Slowly changing dimensions (Design · optional SQL)

Suppose driver 3 is suspended in `ride_prod` (`UPDATE drivers SET status = 'suspended' WHERE
driver_id = 3;`). Run `etl_pipeline.py`, and `dim_driver` still says `active`. `ON CONFLICT DO
NOTHING` never touches an existing row.

In a comment block:
1. Is that a bug? Who would be misled, and how?
2. **SCD Type 1** fixes it by overwriting: `ON CONFLICT (driver_id) DO UPDATE SET status =
   EXCLUDED.status, …`. After that, what would a report of "2023 revenue by driver status" say
   about driver 3's trips from when they were active?
3. **SCD Type 2** keeps history instead. Which columns would you add to `dim_driver`
   (`valid_from`, `valid_to`, `is_current`)? Sketch driver 3's rows after the change: how many
   rows, and which surrogate keys?
4. Under Type 2, is `UNIQUE (driver_id)` still valid? And `load_lookup_dim()` maps
   `driver_id → driver_key`. What does a trip's driver lookup need to match on instead?

---

## What to submit

| File | Contents |
|---|---|
| `week4_queries.sql` | Q1–Q8, the Q4 post-backfill checks, and the stretch exercise |
| `warehouse_migration.sql` | Q4 migration, one transaction |
| `etl_pipeline.py` | P1–P2 implemented, rounding fixed |
| `etl_run_log.txt` | Log output from test steps (a)–(c), plus the step (c) comment |

`week4_queries.sql` must run top-to-bottom against your migrated, backfilled warehouse. Every
question needs a one-line comment stating what it answers, and every written answer goes as a
comment directly under its query.

## Grading checklist

- [ ] Q1: duplicates found with keys listed, fact-key usage explained, `ON CONFLICT` without a unique constraint explained
- [ ] Q2: grain stated, the `duration_minutes IS NULL` proxy shown and its flaw explained, orphan `dim_time` identified
- [ ] Q3: true average vs average of averages in one query, gap explained, `NULL` handling and additive vs non-additive answered
- [ ] Q4: one transaction; facts re-pointed before delete; `UNIQUE` added; three columns with FK/`CHECK`; `time_key` backfilled in SQL; post-backfill NULL check and `SET NOT NULL`
- [ ] P1: `time_key`, `trip_status`, `cancelled_by` populated correctly
- [ ] P2: three checks with both numbers logged, revenue mismatch traced to rounding and fixed, all checks `PASS`
- [ ] `etl_run_log.txt`: steps (a)–(c) show the failing then passing reconcile, re-run causes no duplicates, and the comment explains why
- [ ] Q5: window over aggregate for share of month, `dim_date` filter justified
- [ ] Q6: `dim_location` joined twice, cross-country share computed, role-playing explained
- [ ] Q7: `FILTER` aggregates, rush-hour cancellation split, Night-bucket width noticed
- [ ] Q8: single-bucket problem explained, tenure-at-trip computed, model placement discussed
- [ ] Stretch: `DO NOTHING` staleness explained, Type 1 history loss explained, Type 2 table and lookup changes designed
