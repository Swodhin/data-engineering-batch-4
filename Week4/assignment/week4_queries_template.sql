-- Week 4 Queries — Answers
-- Fill in each query below. See sql_assignment.md for the full scenario text.
-- Rename this file to week4_queries.sql before committing.
-- Run against ride_warehouse unless a question says otherwise.


-- ════════════════════════════════════════════════════════════════════════════
-- Part 1 — Audit the class warehouse (run the class etl.py TWICE first)
-- ════════════════════════════════════════════════════════════════════════════

-- Q1 — Run it twice, get twice the drivers (Intermediate · GROUP BY / HAVING + constraints)
-- Row counts: dim_driver, dim_passenger, dim_location, fact_trips vs ride_prod source tables
-- Duplicated driver_ids with copy count + every driver_key (STRING_AGG / ARRAY_AGG)
-- One duplicated driver: fact_trips rows per driver_key
-- Comment: why ON CONFLICT DO NOTHING didn't help; why dim_location / fact_trips didn't duplicate;
--          what a COUNT(*) "active drivers" report would say after a week



-- Q2 — What the fact table can't answer (Design)
-- Comment: grain of fact_trips; why cancellation rate by month is impossible
--          (show the duration_minutes IS NULL attempt + its flaw); why rush hour is impossible;
--          what happens to cancelled_by in etl.py



-- Q3 — Averages of averages (Intermediate · semi-additive measures)
-- Per year: true_avg_rating, avg_of_monthly_avgs, rated_trips, total_trips — one query
-- Comment: biggest gap + why; AVG and NULL ratings; one SUM-able column, one never-SUM column



-- ════════════════════════════════════════════════════════════════════════════
-- Part 2 — Q4 post-backfill checks
-- (the migration itself goes in warehouse_migration.sql;
--  run these AFTER `python etl_pipeline.py` has backfilled the new columns)
-- ════════════════════════════════════════════════════════════════════════════

-- Q4 — Verify zero NULL trip_status / time_key, then SET NOT NULL on both
-- Comment: why couldn't SET NOT NULL go in the migration itself?



-- ════════════════════════════════════════════════════════════════════════════
-- Part 4 — Query the star schema
-- ════════════════════════════════════════════════════════════════════════════

-- Q5 — Monthly revenue by region, with share of month (Intermediate · star join + window)
-- 2025, completed: month, month_name, region, trips, revenue, pct_of_month
-- pct_of_month via SUM(SUM(fare_amount)) OVER (PARTITION BY ...)
-- Comment: why filter on dim_date.year instead of EXTRACT(YEAR FROM requested_at)?



-- Q6 — Role-playing dimension: routes (Intermediate · same dim joined twice)
-- (1) Top 10 'pickup → dropoff' routes by completed trips, with revenue + avg distance_km
-- (2) Cross-country trips / total trips / percentage
-- Comment: what is a role-playing dimension, why alias one table twice instead of two tables?



-- Q7 — When do people ride, and when do they cancel? (Intermediate–Advanced · two dims + FILTER)
-- is_weekend x time_of_day: trips, avg_fare (completed), avg_surge, cancellation_rate_pct
-- Cancelled only: cancelled_by share, rush hour vs not
-- Comment: are rush-hour fares higher? why does Night have the most trips?



-- Q8 — The tenure bucket that never changes (Advanced · dimension design)
-- Revenue by dim_driver.tenure_bucket (expect one bucket) — explain why
-- Revenue / trips / distinct drivers by tenure AT TRIP TIME (requested_at - joined_at)
-- Comment: why NOW()-relative attributes are bad, DO UPDATE vs DO NOTHING effect,
--          where tenure-at-trip should live in the model



-- ════════════════════════════════════════════════════════════════════════════
-- Stretch — Slowly changing dimensions (Design · optional SQL)
-- ════════════════════════════════════════════════════════════════════════════
-- 1. After suspending driver 3, dim_driver still says active — bug? who is misled?
-- 2. SCD Type 1 (DO UPDATE): what does "2023 revenue by driver status" say about driver 3?
-- 3. SCD Type 2: columns to add, driver 3's rows + surrogate keys after the change
-- 4. Is UNIQUE (driver_id) still valid? What must a trip's driver lookup match on instead?
