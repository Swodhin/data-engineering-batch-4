-- Week 3 Queries — Answers
-- Fill in each query below. See sql_assignment.md for the full scenario text.
-- Rename this file to week3_queries.sql before committing.


-- Q1 — A bulk update that must not partially apply (Basic–Intermediate · transactions + CHECK)
-- Transaction: valid 10% fare correction + one deliberately bad UPDATE -> whole batch rejected
-- Then: correction run alone, COMMIT, verified
-- Comment: why does all-or-nothing matter for a finance-facing bulk update?

-- Q1: Prove a multi-statement fare correction is all-or-nothing

-- Check the driver's current completed-trip total before the test
SELECT
    driver_id,
    COUNT(*) AS completed_trips,
    SUM(fare_amount) AS total_fare
FROM trips
WHERE driver_id = 1
  AND status = 'completed'
GROUP BY driver_id;

BEGIN;

-- Valid update: increase completed-trip fares by 10%
UPDATE trips
SET fare_amount = fare_amount * 1.10
WHERE driver_id = 1
  AND status = 'completed';

-- Deliberately invalid update: violates fare_amount > 0
UPDATE trips
SET fare_amount = -100
WHERE trip_id = (
    SELECT trip_id
    FROM trips
    WHERE driver_id = 1
    LIMIT 1
);

ROLLBACK;

-- Verify the first update did not persist
SELECT
    driver_id,
    COUNT(*) AS completed_trips,
    SUM(fare_amount) AS total_fare
FROM trips
WHERE driver_id = 1
  AND status = 'completed'
GROUP BY driver_id;

BEGIN;

UPDATE trips
SET fare_amount = fare_amount * 1.10
WHERE driver_id = 1
  AND status = 'completed';

COMMIT;

-- Verify the correction now persisted
SELECT
    driver_id,
    COUNT(*) AS completed_trips,
    SUM(fare_amount) AS total_fare
FROM trips
WHERE driver_id = 1
  AND status = 'completed'
GROUP BY driver_id;

-- All-or-nothing matters for finance because a partial update would leave
-- inconsistent fares: some trips would be corrected and others would not.
-- This would make revenue totals and financial reports inaccurate.
-- A transaction ensures the whole batch succeeds together or none of it does.

-- Q2 — FK delete-rule audit
-- Audit the current FK delete rules and demonstrate CASCADE / SET NULL behavior.

-- Initial FK rules found with \d trips:
-- driver_id            -> ON DELETE CASCADE
-- passenger_id         -> NO ACTION
-- pickup_location_id   -> NO ACTION
-- dropoff_location_id  -> NO ACTION
-- payment_method_id    -> NO ACTION


-- Part A: Prove ON DELETE CASCADE for driver_id

INSERT INTO drivers (name)
VALUES ('Q2 Test Driver');

INSERT INTO trips (
    driver_id,
    passenger_id,
    pickup_location_id,
    dropoff_location_id,
    fare_amount,
    distance_km,
    status,
    requested_at
)
SELECT
    driver_id,
    1,
    1,
    2,
    250.00,
    8.5,
    'completed',
    NOW()
FROM drivers
WHERE name = 'Q2 Test Driver'
ORDER BY driver_id DESC
LIMIT 1;

DELETE FROM drivers
WHERE name = 'Q2 Test Driver';

-- Result: 0 rows, proving the trip was deleted by ON DELETE CASCADE.
SELECT t.*
FROM trips t
JOIN drivers d
    ON t.driver_id = d.driver_id
WHERE d.name = 'Q2 Test Driver';


-- Part B: Test payment_method_id delete behavior

INSERT INTO payment_methods (name)
VALUES ('Q2 Test Pay');

INSERT INTO trips (
    driver_id,
    passenger_id,
    pickup_location_id,
    dropoff_location_id,
    fare_amount,
    distance_km,
    status,
    requested_at,
    payment_method_id
)
SELECT
    1,
    1,
    1,
    2,
    300.00,
    10.0,
    'completed',
    NOW(),
    payment_method_id
FROM payment_methods
WHERE name = 'Q2 Test Pay';

-- With the original NO ACTION rule, deleting the payment method failed
-- because a trip still referenced it.

-- Change the FK to ON DELETE SET NULL.
ALTER TABLE trips
DROP CONSTRAINT trips_payment_method_id_fkey;

ALTER TABLE trips
ADD CONSTRAINT trips_payment_method_id_fkey
FOREIGN KEY (payment_method_id)
REFERENCES payment_methods(payment_method_id)
ON DELETE SET NULL;

DELETE FROM payment_methods
WHERE name = 'Q2 Test Pay';

-- The trip remains, but payment_method_id becomes NULL.
SELECT
    trip_id,
    payment_method_id
FROM trips
WHERE payment_method_id IS NULL
ORDER BY trip_id DESC
LIMIT 5;


-- Design explanation:
-- driver_id currently uses ON DELETE CASCADE. This is risky in a real
-- ride-share system because deleting a driver would also delete their trip
-- history, including revenue and reporting records.
--
-- A safer design would usually use ON DELETE RESTRICT or, more commonly,
-- a soft-delete field such as deleted_at so the driver is deactivated without
-- physically removing historical trips.
--
-- payment_method_id is better suited to ON DELETE SET NULL because the trip
-- itself should remain for historical and financial reporting even if the
-- payment method record is removed.

-- Q3 — Anti-join shootout: drivers with no trips (Intermediate–Advanced · EXPLAIN ANALYZE)
-- (a) NOT IN, (b) LEFT JOIN ... IS NULL, (c) NOT EXISTS -- EXPLAIN ANALYZE all three, paste plans
-- Comment: plan shape of each, which was fastest
-- NULL trap: NOT IN on payment_method_id (nullable) -> reproduce, fix with LEFT JOIN/NOT EXISTS
-- Comment: why does NOT IN break when its subquery can return NULL?

-- Q3 — Anti-join shootout: drivers with no trips
-- Compare NOT IN, LEFT JOIN ... IS NULL, and NOT EXISTS using EXPLAIN ANALYZE.

-- First confirm the NULL trap exists for payment_method_id.
SELECT COUNT(*) AS null_payment_methods
FROM trips
WHERE payment_method_id IS NULL;


-- Q3a: NOT IN
EXPLAIN ANALYZE
SELECT *
FROM drivers
WHERE driver_id NOT IN (
    SELECT driver_id
    FROM trips
);

--  QUERY PLAN                                                         
-- ---------------------------------------------------------------------------------------------------------------------------
--  Seq Scan on drivers  (cost=0.00..5697774.00 rows=160 width=222) (actual time=0.096..0.097 rows=0.00 loops=1)
--    Filter: (NOT (ANY (driver_id = (SubPlan 1).col1)))
--    Rows Removed by Filter: 11
--    Buffers: shared hit=3
--    SubPlan 1
--      ->  Materialize  (cost=0.00..33111.00 rows=1000000 width=4) (actual time=0.002..0.004 rows=11.91 loops=11)
--            Storage: Memory  Maximum Storage: 18kB
--            Buffers: shared hit=2
--            ->  Seq Scan on trips  (cost=0.00..24204.00 rows=1000000 width=4) (actual time=0.014..0.019 rows=39.00 loops=1)                                                 
--                  Buffers: shared hit=2                                               
--  Planning Time: 0.457 ms                                                             
--  Execution Time: 0.714 ms                                                            
-- (12 rows)            


-- Q3b: LEFT JOIN ... IS NULL
EXPLAIN ANALYZE
SELECT d.*
FROM drivers d
LEFT JOIN trips t
    ON d.driver_id = t.driver_id
WHERE t.trip_id IS NULL;

--    QUERY PLAN                                                         
-- ---------------------------------------------------------------------------------------------------------------------------
--  Hash Right Join  (cost=17.20..26880.97 rows=1 width=222) (actual time=426.524..426.529 rows=0.00 loops=1)
--    Hash Cond: (t.driver_id = d.driver_id)
--    Filter: (t.trip_id IS NULL)
--    Rows Removed by Filter: 916534
--    Buffers: shared hit=14205
--    ->  Seq Scan on trips t  (cost=0.00..24204.00 rows=1000000 width=8) (actual time=0.005..132.933 rows=916534.00 loops=1)
--          Buffers: shared hit=14204
--    ->  Hash  (cost=13.20..13.20 rows=320 width=222) (actual time=0.011..0.013 rows=11.00 loops=1)
--          Buckets: 1024  Batches: 1  Memory Usage: 9kB                                
--          Buffers: shared hit=1                                                       
--          ->  Seq Scan on drivers d  (cost=0.00..13.20 rows=320 width=222) (actual time=0.007..0.009 rows=11.00 loops=1)                                                    
--                Buffers: shared hit=1                                                 
--  Planning:                                                                           
--    Buffers: shared hit=12                                                            
--  Planning Time: 0.137 ms                                                             
--  Execution Time: 426.561 ms                                                          
-- (16 rows)                                                                            
                               

-- Q3c: NOT EXISTS
EXPLAIN ANALYZE
SELECT *
FROM drivers d
WHERE NOT EXISTS (
    SELECT 1
    FROM trips t
    WHERE t.driver_id = d.driver_id
);

--  QUERY PLAN                                                         
-- ---------------------------------------------------------------------------------------------------------------------------
--  Hash Right Anti Join  (cost=17.20..27263.39 rows=308 width=222) (actual time=353.458..353.462 rows=0.00 loops=1)
--    Hash Cond: (t.driver_id = d.driver_id)
--    Buffers: shared hit=14205
--    ->  Seq Scan on trips t  (cost=0.00..24204.00 rows=1000000 width=4) (actual time=0.004..125.983 rows=916534.00 loops=1)
--          Buffers: shared hit=14204
--    ->  Hash  (cost=13.20..13.20 rows=320 width=222) (actual time=0.009..0.012 rows=11.00 loops=1)
--          Buckets: 1024  Batches: 1  Memory Usage: 9kB
--          Buffers: shared hit=1
--          ->  Seq Scan on drivers d  (cost=0.00..13.20 rows=320 width=222) (actual time=0.006..0.007 rows=11.00 loops=1)                                                    
--                Buffers: shared hit=1                                                 
--  Planning:                                                                           
--    Buffers: shared hit=3                                                             
--  Planning Time: 0.397 ms                                                             
--  Execution Time: 353.485 ms                                                          
-- (14 rows)                             


-- Compare the plans:
-- NOT IN may use a subquery/materialization strategy.
-- LEFT JOIN ... IS NULL may produce an anti-join style plan.
-- NOT EXISTS may also produce an anti-join plan.
-- Replace the notes above with the actual plan shapes and execution times
-- you observe in your own EXPLAIN ANALYZE output.


-- NULL trap: NOT IN with nullable payment_method_id

SELECT *
FROM payment_methods
WHERE payment_method_id NOT IN (
    SELECT payment_method_id
    FROM trips
);

-- Because trips.payment_method_id can contain NULL, the NOT IN query may
-- return zero rows even when an unused payment method exists.


-- Correct version using LEFT JOIN ... IS NULL
SELECT pm.*
FROM payment_methods pm
LEFT JOIN trips t
    ON pm.payment_method_id = t.payment_method_id
WHERE t.trip_id IS NULL;


-- Alternative correct version using NOT EXISTS
SELECT *
FROM payment_methods pm
WHERE NOT EXISTS (
    SELECT 1
    FROM trips t
    WHERE t.payment_method_id = pm.payment_method_id
);


-- Explanation:
-- NOT IN behaves badly when the subquery contains NULL because a comparison
-- such as x NOT IN (1, 2, NULL) becomes UNKNOWN rather than TRUE.
-- Rows are only kept by WHERE when the condition is TRUE, so UNKNOWN rows
-- are filtered out. That is why NOT IN can return no rows when NULL is present.

-- Q4 — Index the fix (Intermediate · CREATE INDEX)
-- EXPLAIN ANALYZE baseline on corrected Q3 query, CREATE INDEX on payment_method_id, re-run
-- Paste both plans

-- Q4 — Index the fix
-- Compare the corrected payment-method anti-join before and after indexing.

-- Baseline before index
EXPLAIN ANALYZE
SELECT pm.*
FROM payment_methods pm
WHERE NOT EXISTS (
    SELECT 1
    FROM trips t
    WHERE t.payment_method_id = pm.payment_method_id
);

-- QUERY PLAN                                                           
-- -------------------------------------------------------------------------------------------------------------------------------
--  Hash Right Anti Join  (cost=26.65..26945.85 rows=734 width=82) (actual time=444.932..444.937 rows=0.00 loops=1)
--    Hash Cond: (t.payment_method_id = pm.payment_method_id)
--    Buffers: shared hit=14205
--    ->  Seq Scan on trips t  (cost=0.00..24204.00 rows=1000000 width=4) (actual time=0.006..128.715 rows=916534.00 loops=1)
--          Buffers: shared hit=14204
--    ->  Hash  (cost=17.40..17.40 rows=740 width=82) (actual time=0.017..0.020 rows=6.00 loops=1)
--          Buckets: 1024  Batches: 1  Memory Usage: 9kB
--          Buffers: shared hit=1
--          ->  Seq Scan on payment_methods pm  (cost=0.00..17.40 rows=740 width=82) (actual time=0.013..0.014 rows=6.00 loops=1)                                             
--                Buffers: shared hit=1                                                 
--  Planning:                                                                           
--    Buffers: shared hit=3                                                             
--  Planning Time: 0.178 ms                                                             
--  Execution Time: 444.974 ms                                                          
-- (14 rows)                                          


-- Create index on payment_method_id
CREATE INDEX idx_trips_payment_method_id
ON trips(payment_method_id);


-- Run the same query again after indexing
EXPLAIN ANALYZE
SELECT pm.*
FROM payment_methods pm
WHERE NOT EXISTS (
    SELECT 1
    FROM trips t
    WHERE t.payment_method_id = pm.payment_method_id
);

--   QUERY PLAN                                                                         
-- -----------------------------------------------------------------------------------------------------------------------------------------------------------
--  Nested Loop Anti Join  (cost=0.42..345.47 rows=734 width=82) (actual time=0.246..0.246 rows=0.00 loops=1)
--    Buffers: shared hit=15 read=11
--    ->  Seq Scan on payment_methods pm  (cost=0.00..17.40 rows=740 width=82) (actual time=0.015..0.017 rows=6.00 loops=1)
--          Buffers: shared hit=1
--    ->  Index Only Scan using idx_trips_payment_method_id on trips t  (cost=0.42..2754.64 rows=152756 width=4) (actual time=0.038..0.038 rows=1.00 loops=6)
--          Index Cond: (payment_method_id = pm.payment_method_id)
--          Heap Fetches: 6
--          Index Searches: 6
--          Buffers: shared hit=14 read=11                                              
--  Planning:                                                                           
--    Buffers: shared hit=24 read=1                                                     
--  Planning Time: 4.459 ms                                                             
--  Execution Time: 0.461 ms                                                            
-- (13 rows)                                           


-- Explanation:
-- Compare the scan type and execution time before and after the index.
-- Record whether PostgreSQL changed from a sequential scan to an index-based
-- plan, and calculate roughly how much faster or slower the indexed version was.

-- Q5 — When not to index (Design · no new SQL required)
-- Comment only: cost of an index beyond disk space; would you index rating / drivers.name?

-- Q5 — When not to index

-- Indexes improve read performance, but they also add overhead to writes.
-- Every INSERT, UPDATE, or DELETE may require PostgreSQL to update the related
-- indexes as well, which increases write time and storage usage.

-- I would generally NOT add an index on trips.rating because rating has very
-- few distinct values (roughly 1.0 to 5.0), so it is not very selective and
-- PostgreSQL may still prefer a sequential scan for many rating filters.

-- I would consider an index on drivers.name only if the application frequently
-- searches or filters drivers by name. Names are more selective than rating,
-- but if the table is small or name lookups are rare, the extra index may not
-- provide much benefit.

-- Q6 — Driver performance summary (Intermediate–Advanced · aggregation view)
-- CREATE VIEW driver_performance_summary AS ...
-- driver_id, driver_name, total_rides, total_completed_trips, total_cancelled_trips,
-- completion_rate, cancellation_rate, total_revenue, avg_rating
-- SELECT from it ordered by completion_rate ascending

-- Q6 — Driver performance summary
-- One row per driver with ride counts, rates, revenue, and average rating.

CREATE OR REPLACE VIEW driver_performance_summary AS
SELECT
    d.driver_id,
    d.name AS driver_name,

    COUNT(t.trip_id) AS total_rides,

    COUNT(t.trip_id) FILTER (
        WHERE t.status = 'completed'
    ) AS total_completed_trips,

    COUNT(t.trip_id) FILTER (
        WHERE t.status = 'cancelled'
    ) AS total_cancelled_trips,

    ROUND(
        100.0 * COUNT(t.trip_id) FILTER (
            WHERE t.status = 'completed'
        ) / NULLIF(COUNT(t.trip_id), 0),
        1
    ) AS completion_rate,

    ROUND(
        100.0 * COUNT(t.trip_id) FILTER (
            WHERE t.status = 'cancelled'
        ) / NULLIF(COUNT(t.trip_id), 0),
        1
    ) AS cancellation_rate,

    COALESCE(
        SUM(t.fare_amount) FILTER (
            WHERE t.status = 'completed'
        ),
        0
    ) AS total_revenue,

    ROUND(
        AVG(t.rating) FILTER (
            WHERE t.status = 'completed'
        ),
        2
    ) AS avg_rating

FROM drivers d
LEFT JOIN trips t
    ON d.driver_id = t.driver_id

GROUP BY
    d.driver_id,
    d.name;

-- Show worst completion rates first
SELECT *
FROM driver_performance_summary
ORDER BY completion_rate ASC NULLS FIRST;
-- Q7 — 7-day moving average fare (Advanced · window frame clause)
-- Daily series: one row per day, avg fare_amount for completed trips that day
-- AVG(...) OVER (ORDER BY trip_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
-- Comment: what happens for the first 6 days of the series, and is that average meaningful?

-- Q7 — 7-day moving average fare
-- Build a daily average fare series, then calculate a trailing 7-row moving average.

WITH daily_fares AS (
    SELECT
        requested_at::date AS trip_date,
        AVG(fare_amount) AS daily_avg_fare
    FROM trips
    WHERE status = 'completed'
    GROUP BY requested_at::date
)
SELECT
    trip_date,
    ROUND(daily_avg_fare, 2) AS daily_avg_fare,
    ROUND(
        AVG(daily_avg_fare) OVER (
            ORDER BY trip_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS moving_avg_7_day
FROM daily_fares
ORDER BY trip_date;

-- For the first 6 days, PostgreSQL uses whatever rows are available in the
-- window because there are not yet 6 preceding rows. For example, the first
-- row averages only itself, the second row averages two days, and so on.
-- These values are valid partial-period averages, but they are not yet a full
-- 7-day moving average, so they should be interpreted carefully.

-- Q8 — Ranking ties, using your own view (Intermediate · ROW_NUMBER / RANK / DENSE_RANK)
-- From driver_performance_summary, rank by total_revenue with all three functions side by side
-- Comment: how do the three handle a tie differently, what does the next driver get under each?

-- Q8 — Compare ROW_NUMBER, RANK, and DENSE_RANK on total revenue

SELECT
    driver_id,
    driver_name,
    total_revenue,

    ROW_NUMBER() OVER (
        ORDER BY total_revenue DESC
    ) AS row_number_rank,

    RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS rank_rank,

    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS dense_rank_rank

FROM driver_performance_summary
ORDER BY total_revenue DESC;

-- ROW_NUMBER() always gives every row a unique number, even when values tie.
--
-- RANK() gives tied rows the same rank, but skips the next rank number.
-- Example: 1, 2, 2, 4.
--
-- DENSE_RANK() also gives tied rows the same rank, but does not skip the next
-- rank number. Example: 1, 2, 2, 3.

-- Q8: Construct a temporary revenue tie for ranking comparison

BEGIN;

-- Temporarily increase one completed trip for driver 2 so that
-- driver 2's total revenue equals driver 8's total revenue.
UPDATE trips
SET fare_amount = fare_amount + 135082.74
WHERE trip_id = (
    SELECT trip_id
    FROM trips
    WHERE driver_id = 2
      AND status = 'completed'
    LIMIT 1
);

-- Show ROW_NUMBER, RANK and DENSE_RANK with the constructed tie
SELECT
    driver_id,
    driver_name,
    total_revenue,

    ROW_NUMBER() OVER (
        ORDER BY total_revenue DESC
    ) AS row_number_rank,

    RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS rank_rank,

    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS dense_rank_rank

FROM driver_performance_summary
ORDER BY total_revenue DESC;

-- Restore the database to its original state
ROLLBACK;

-- With the constructed tie, ROW_NUMBER() still assigns each driver a unique
-- position, so the tied drivers receive different row numbers.
--
-- RANK() gives both tied drivers the same rank and skips the next rank.
-- For example: 1, 2, 2, 4.
--
-- DENSE_RANK() also gives both tied drivers the same rank, but does not skip
-- the next rank. For example: 1, 2, 2, 3.
--
-- The transaction is rolled back afterward so the temporary fare change
-- does not permanently modify the dataset.

-- Stretch — KPI, Metric, Dimension (Conceptual · no SQL required)
-- Comment only:
-- 1. Define metric, dimension, KPI in your own words
-- 2. Classify every column of driver_performance_summary as metric or dimension
-- 3. Which metrics in that view would you argue are actual KPIs for a ride-share company, and why?

-- Stretch — KPI, Metric, Dimension

-- 1. Definitions:
-- Metric: a measurable numeric value used to describe performance or activity.
-- Dimension: a descriptive attribute used to group, filter, or categorize data.
-- KPI: a metric that is important enough for the business to set a target for
-- and track over time.

-- 2. Classification of driver_performance_summary columns:
-- driver_id                -> Dimension
-- driver_name              -> Dimension
-- total_rides              -> Metric
-- total_completed_trips    -> Metric
-- total_cancelled_trips    -> Metric
-- completion_rate          -> Metric
-- cancellation_rate        -> Metric
-- total_revenue            -> Metric
-- avg_rating               -> Metric

-- 3. Possible KPIs:
-- completion_rate can be a KPI because the company may set a target for how
-- many requested rides should be successfully completed.
--
-- cancellation_rate can be a KPI because the company may want to keep
-- cancellations below a target threshold.
--
-- total_revenue can be a KPI because leadership will usually track revenue
-- performance against financial targets.
--
-- avg_rating can also be a KPI because it reflects service quality and may
-- have a target such as maintaining a minimum driver rating.
--
-- total_rides, total_completed_trips, and total_cancelled_trips are useful
-- operational metrics, but they are not automatically KPIs unless the company
-- specifically sets targets for them.