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
--          what a (*) "acCOUNTtive drivers" report would say after a week

-- Q1: Find duplicated drivers after running the class ETL twice.

SELECT
    driver_id,
    COUNT(*) AS copies,
    ARRAY_AGG(driver_key ORDER BY driver_key) AS driver_keys
FROM dim_driver
GROUP BY driver_id
HAVING COUNT(*) > 1
ORDER BY driver_id;


-- Q1: Show how many fact rows point to each duplicate driver_key.

SELECT
    d.driver_id,
    d.driver_key,
    COUNT(f.trip_key) AS fact_rows
FROM dim_driver d
LEFT JOIN fact_trips f
    ON f.driver_key = d.driver_key
WHERE d.driver_id IN (
    SELECT driver_id
    FROM dim_driver
    GROUP BY driver_id
    HAVING COUNT(*) > 1
)
GROUP BY d.driver_id, d.driver_key
ORDER BY d.driver_id, d.driver_key;


/*
Q1 Answers:

ON CONFLICT DO NOTHING did not prevent duplicate drivers because dim_driver.driver_id
does not have a UNIQUE constraint. PostgreSQL only detects a conflict when a PRIMARY KEY,
UNIQUE constraint, or other applicable unique index is violated.

The fact rows use the driver_key that existed when the facts were originally inserted.
On the second ETL run, new duplicate dimension rows are inserted, but fact_trips already
contains the same source_trip_id values, so the fact rows are not inserted again.

dim_location does not duplicate because location_id is defined UNIQUE.

fact_trips does not duplicate because source_trip_id is defined UNIQUE.

If the ETL runs nightly for one week and inserts the same drivers every night,
COUNT(*) on dim_driver would report roughly 7 times the real driver count,
assuming one load per night and starting from an empty warehouse.
*/

-- Q2 — What the fact table can't answer (Design)
-- Comment: grain of fact_trips; why cancellation rate by month is impossible
--          (show the duration_minutes IS NULL attempt + its flaw); why rush hour is impossible;
--          what happens to cancelled_by in etl.py

-- Q2: Show why the current fact table cannot properly answer cancellation-rate questions.

SELECT
    date_key,
    COUNT(*) AS total_trips,
    COUNT(*) FILTER (WHERE duration_minutes IS NULL) AS assumed_cancelled,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE duration_minutes IS NULL)
        / NULLIF(COUNT(*), 0),
        2
    ) AS assumed_cancellation_rate_pct
FROM fact_trips
GROUP BY date_key
ORDER BY date_key;


/*
Q2 Answers:

Grain:
fact_trips has one row per trip from the source system.

Cancellation rate:
The warehouse cannot correctly calculate cancellation rate because fact_trips
does not currently store the trip status.

Using duration_minutes IS NULL as a substitute is incorrect because NULL duration
can represent both cancelled trips and no-show trips. Product would want those
statuses distinguished rather than grouped together.

Rush-hour fares:
The warehouse also cannot properly answer whether fares are higher during rush hour.
dim_time contains is_rush_hour, but fact_trips currently has no time_key linking
each trip to dim_time.

cancelled_by:
extract_trips() already selects cancelled_by from the source, but the current
transform/load process does not store it in fact_trips, so the value is lost
before it reaches the warehouse.
*/

-- Q3 — Averages of averages (Intermediate · semi-additive measures)
-- Per year: true_avg_rating, avg_of_monthly_avgs, rated_trips, total_trips — one query
-- Comment: biggest gap + why; AVG and NULL ratings; one SUM-able column, one never-SUM column

-- Q3: Compare the true yearly average rating with the average of monthly averages.

WITH monthly AS (
    SELECT
        d.year,
        d.month,
        AVG(f.driver_rating) AS monthly_avg_rating
    FROM fact_trips f
    JOIN dim_date d
        ON d.date_key = f.date_key
    GROUP BY d.year, d.month
),
yearly AS (
    SELECT
        d.year,
        AVG(f.driver_rating) AS true_avg_rating,
        COUNT(f.driver_rating) AS rated_trips,
        COUNT(*) AS total_trips
    FROM fact_trips f
    JOIN dim_date d
        ON d.date_key = f.date_key
    GROUP BY d.year
)
SELECT
    y.year,
    ROUND(y.true_avg_rating, 4) AS true_avg_rating,
    ROUND(AVG(m.monthly_avg_rating), 4) AS avg_of_monthly_avgs,
    y.rated_trips,
    y.total_trips
FROM yearly y
JOIN monthly m
    ON m.year = y.year
GROUP BY
    y.year,
    y.true_avg_rating,
    y.rated_trips,
    y.total_trips
ORDER BY y.year;


/*
Q3 Answers:

The year with the biggest gap is 2025.

Averaging monthly averages can give the wrong yearly average because each month
may contain a different number of rated trips. A simple average of the 12 monthly
averages gives every month equal weight, even when some months contain far more
ratings than others.

This is especially important for 2026 if the dataset contains only part of that
year, because the number of months and the number of rated trips per month are uneven.

AVG(driver_rating) ignores NULL values, so unrated trips are excluded from the
average. That is appropriate here because only trips with an actual rating should
contribute to the rating average.

An additive measure that can safely be SUMmed is fare_amount.

A numeric measure that must not be SUMmed is surge_multiplier because it is a ratio;
it should normally be averaged instead.
*/

-- ════════════════════════════════════════════════════════════════════════════
-- Part 2 — Q4 post-backfill checks
-- (the migration itself goes in warehouse_migration.sql;
--  run these AFTER `python etl_pipeline.py` has backfilled the new columns)
-- ════════════════════════════════════════════════════════════════════════════

-- Q4 — Verify zero NULL trip_status / time_key, then SET NOT NULL on both
-- Comment: why couldn't SET NOT NULL go in the migration itself?

-- Q4 — Verify zero NULL trip_status / time_key, then SET NOT NULL on both

SELECT
    COUNT(*) FILTER (WHERE trip_status IS NULL) AS null_trip_status,
    COUNT(*) FILTER (WHERE time_key IS NULL) AS null_time_key
FROM fact_trips;

/*
Q4 Answer:

SET NOT NULL could not be added in the migration itself because trip_status
had not yet been populated from the source database. The ETL pipeline had to
backfill trip_status first.

After the ETL completed and this verification showed zero NULL values,
the NOT NULL constraints could be safely added.
*/

ALTER TABLE fact_trips
ALTER COLUMN trip_status SET NOT NULL;

ALTER TABLE fact_trips
ALTER COLUMN time_key SET NOT NULL;


-- ════════════════════════════════════════════════════════════════════════════
-- Part 4 — Query the star schema
-- ════════════════════════════════════════════════════════════════════════════

-- Q5 — Monthly revenue by region, with share of month (Intermediate · star join + window)
-- 2025, completed: month, month_name, region, trips, revenue, pct_of_month
-- pct_of_month via SUM(SUM(fare_amount)) OVER (PARTITION BY ...)
-- Comment: why filter on dim_date.year instead of EXTRACT(YEAR FROM requested_at)?

-- Q5: Monthly completed-trip revenue by pickup region for 2025,
-- including each region's percentage share of that month's revenue.

SELECT
    d.month,
    d.month_name,
    l.region,
    COUNT(*) AS trips,
    ROUND(SUM(f.fare_amount), 2) AS revenue,
    ROUND(
        100.0 * SUM(f.fare_amount)
        / SUM(SUM(f.fare_amount)) OVER (PARTITION BY d.month),
        1
    ) AS pct_of_month
FROM fact_trips f
JOIN dim_date d
    ON d.date_key = f.date_key
JOIN dim_location l
    ON l.location_key = f.pickup_location_key
WHERE d.year = 2025
  AND f.trip_status = 'completed'
GROUP BY
    d.month,
    d.month_name,
    l.region
ORDER BY
    d.month,
    revenue DESC;


/*
Q5 Answer:

Filtering on dim_date.year = 2025 is preferred because dim_date is the warehouse's
calendar dimension. It centralizes reusable date attributes such as year, month,
month name, quarter, weekday and weekend flags instead of recalculating them from
fact_trips.requested_at in every query.

Both approaches can return the same rows, but using dim_date keeps analytical
queries consistent with the star-schema design and makes calendar-based grouping
and filtering easier.
*/

-- Q6 — Role-playing dimension: routes (Intermediate · same dim joined twice)
-- (1) Top 10 'pickup → dropoff' routes by completed trips, with revenue + avg distance_km
-- (2) Cross-country trips / total trips / percentage
-- Comment: what is a role-playing dimension, why alias one table twice instead of two tables?

-- Q6: Top 10 completed routes by trip count, with revenue and average distance.

SELECT
    pl.city_name || ' → ' || dl.city_name AS route,
    COUNT(*) AS trips,
    ROUND(SUM(f.fare_amount), 2) AS revenue,
    ROUND(AVG(f.distance_km), 2) AS avg_distance_km
FROM fact_trips f
JOIN dim_location pl
    ON pl.location_key = f.pickup_location_key
JOIN dim_location dl
    ON dl.location_key = f.dropoff_location_key
WHERE f.trip_status = 'completed'
GROUP BY
    pl.city_name,
    dl.city_name
ORDER BY
    trips DESC,
    revenue DESC
LIMIT 10;


-- Q6: Share of trips that cross a country border.

SELECT
    COUNT(*) FILTER (
        WHERE pl.country IS DISTINCT FROM dl.country
    ) AS cross_border_trips,

    COUNT(*) AS total_trips,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE pl.country IS DISTINCT FROM dl.country
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS cross_border_pct
FROM fact_trips f
JOIN dim_location pl
    ON pl.location_key = f.pickup_location_key
JOIN dim_location dl
    ON dl.location_key = f.dropoff_location_key;


/*
Q6 Answer:

dim_location is a role-playing dimension because the same dimension table
is used in more than one role in the fact table.

Here it is joined once as the pickup location and again as the dropoff location.

Using aliases for the same dim_location table is better than creating separate
dim_pickup_location and dim_dropoff_location tables because both roles describe
the same kind of entity and share the same attributes. Keeping one dimension
avoids duplicated data and duplicated maintenance.
*/

-- Q7 — When do people ride, and when do they cancel? (Intermediate–Advanced · two dims + FILTER)
-- is_weekend x time_of_day: trips, avg_fare (completed), avg_surge, cancellation_rate_pct
-- Cancelled only: cancelled_by share, rush hour vs not
-- Comment: are rush-hour fares higher? why does Night have the most trips?

-- Q7: Compare ride patterns by weekend status and time of day.

SELECT
    d.is_weekend,
    t.time_of_day,
    COUNT(*) AS trips,

    ROUND(
        AVG(f.fare_amount) FILTER (
            WHERE f.trip_status = 'completed'
        ),
        2
    ) AS avg_fare,

    ROUND(
        AVG(f.surge_multiplier),
        2
    ) AS avg_surge,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE f.trip_status = 'cancelled'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS cancellation_rate_pct

FROM fact_trips f
JOIN dim_date d
    ON d.date_key = f.date_key
JOIN dim_time t
    ON t.time_key = f.time_key

GROUP BY
    d.is_weekend,
    t.time_of_day

ORDER BY
    d.is_weekend,
    t.time_of_day;


-- Q7: Who cancels during rush hour vs outside rush hour?

SELECT
    t.is_rush_hour,
    f.cancelled_by,
    COUNT(*) AS cancellations,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (
            PARTITION BY t.is_rush_hour
        ),
        2
    ) AS pct_of_period_cancellations

FROM fact_trips f
JOIN dim_time t
    ON t.time_key = f.time_key

WHERE f.trip_status = 'cancelled'

GROUP BY
    t.is_rush_hour,
    f.cancelled_by

ORDER BY
    t.is_rush_hour,
    cancellations DESC;


/*
Q7 Answer:

The first query shows whether completed-trip fares are higher during different
time-of-day buckets and whether weekend behaviour differs from weekdays.

To answer Product's original question about rush hour, compare the fare results
associated with rush-hour periods against the other periods. Report what the
query shows rather than assuming rush hour must be more expensive.

The Night bucket contains more hours than the other time_of_day categories.
In warehouse.sql:

Morning   = 06:00–11:59  -> 6 hours
Afternoon = 12:00–16:59  -> 5 hours
Evening   = 17:00–20:59  -> 4 hours
Night     = 21:00–05:59  -> 9 hours

Therefore Night can contain more trips partly because it covers a much larger
portion of the day, not necessarily because riders prefer travelling at night.
*/

-- Q8 — The tenure bucket that never changes (Advanced · dimension design)
-- Revenue by dim_driver.tenure_bucket (expect one bucket) — explain why
-- Revenue / trips / distinct drivers by tenure AT TRIP TIME (requested_at - joined_at)
-- Comment: why NOW()-relative attributes are bad, DO UPDATE vs DO NOTHING effect,
--          where tenure-at-trip should live in the model

-- Q8: Show revenue grouped by the stored driver tenure bucket.

SELECT
    d.tenure_bucket,
    COUNT(*) AS trips,
    ROUND(SUM(f.fare_amount), 2) AS revenue,
    COUNT(DISTINCT d.driver_id) AS distinct_drivers
FROM fact_trips f
JOIN dim_driver d
    ON d.driver_key = f.driver_key
WHERE f.trip_status = 'completed'
GROUP BY d.tenure_bucket
ORDER BY d.tenure_bucket;


-- Q8: Calculate driver tenure at the time of each trip instead of using NOW().

WITH tenure_data AS (
    SELECT
        CASE
            WHEN f.requested_at < d.joined_at + INTERVAL '1 year'
                THEN '0-1 yr'
            WHEN f.requested_at < d.joined_at + INTERVAL '2 years'
                THEN '1-2 yrs'
            WHEN f.requested_at < d.joined_at + INTERVAL '3 years'
                THEN '2-3 yrs'
            ELSE '3+ yrs'
        END AS tenure_at_trip,
        f.fare_amount,
        d.driver_id
    FROM fact_trips f
    JOIN dim_driver d
        ON d.driver_key = f.driver_key
    WHERE f.trip_status = 'completed'
)

SELECT
    tenure_at_trip,
    COUNT(*) AS trips,
    ROUND(SUM(fare_amount), 2) AS revenue,
    COUNT(DISTINCT driver_id) AS distinct_drivers
FROM tenure_data
GROUP BY tenure_at_trip
ORDER BY
    CASE tenure_at_trip
        WHEN '0-1 yr' THEN 1
        WHEN '1-2 yrs' THEN 2
        WHEN '2-3 yrs' THEN 3
        ELSE 4
    END;


/*
Q8 Answer:

The stored tenure_bucket is calculated relative to NOW() when the driver
dimension is loaded. That means it describes the driver's tenure at load time,
not their tenure when each historical trip happened.

This is a problem because historical trips can be grouped using a value that
changes over time.

Because the dimension load uses ON CONFLICT DO NOTHING, an existing driver's
tenure_bucket is not recalculated on later ETL runs.

Tenure at trip time is really a property of the trip event.

One option is to calculate it during analysis from requested_at and joined_at,
as shown above. This avoids storing redundant data, but every query has to
repeat the calculation.

Another option would be to store a tenure-at-trip bucket directly on the fact
table. That makes reporting easier, but adds another derived attribute to the
fact table.
*/

-- ════════════════════════════════════════════════════════════════════════════
-- Stretch — Slowly changing dimensions (Design · optional SQL)
-- ════════════════════════════════════════════════════════════════════════════
-- 1. After suspending driver 3, dim_driver still says active — bug? who is misled?
-- 2. SCD Type 1 (DO UPDATE): what does "2023 revenue by driver status" say about driver 3?
-- 3. SCD Type 2: columns to add, driver 3's rows + surrogate keys after the change
-- 4. Is UNIQUE (driver_id) still valid? What must a trip's driver lookup match on instead?

/*
STRETCH — Slowly Changing Dimensions

1. Is the stale driver status a bug?

Yes. If a driver's status changes in ride_prod, the warehouse can become stale
because the dimension load uses ON CONFLICT DO NOTHING.

An analyst could be misled because dim_driver might still show a driver as
'active' even after the source system changed them to 'suspended' or another
status.


2. SCD Type 1

SCD Type 1 overwrites the existing dimension row with the newest values.

For example:

ON CONFLICT (driver_id)
DO UPDATE SET
    status = EXCLUDED.status,
    name = EXCLUDED.name,
    joined_at = EXCLUDED.joined_at,
    tenure_bucket = EXCLUDED.tenure_bucket;

The drawback is that historical values are lost.

If driver 3 becomes suspended today, then a report such as
"2023 revenue by driver status" would classify that driver's old 2023 trips
under the driver's current status, 'suspended', even though the driver was active
when those trips occurred.


3. SCD Type 2

SCD Type 2 keeps historical versions of the dimension row.

Useful columns would include:

valid_from
valid_to
is_current

For driver 3, there could be two rows:

driver_key = 3
driver_id = 3
status = 'active'
valid_from = original start date
valid_to = date/time of suspension
is_current = FALSE

driver_key = new surrogate key
driver_id = 3
status = 'suspended'
valid_from = date/time of suspension
valid_to = NULL
is_current = TRUE

Each version has its own surrogate driver_key.


4. UNIQUE constraint and lookup changes

Under SCD Type 2, UNIQUE(driver_id) is no longer valid because the same natural
driver_id must be allowed to appear in multiple historical rows.

Instead, uniqueness could be enforced using something such as a combination of
driver_id and version/effective-date information.

The lookup can no longer simply map:

driver_id -> driver_key

It must select the dimension row whose validity range contains the trip date,
for example:

trip requested_at >= valid_from
AND
trip requested_at < valid_to

or use the row with valid_to IS NULL for the current version when appropriate.
*/