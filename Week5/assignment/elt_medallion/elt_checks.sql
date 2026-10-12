-- =============================================================================
-- Week 5 Part 3 — ELT verification checks
-- =============================================================================


-- Step (a): Gold must contain 10,000 source trips.
SELECT COUNT(*) AS gold_trip_count
FROM gold.fact_trips;


-- Step (a): Gold completed revenue.
SELECT ROUND(SUM(fare_amount), 2) AS gold_completed_revenue
FROM gold.fact_trips
WHERE trip_status = 'completed';


-- Step (b): Silver and Gold row counts after partner feed.
SELECT COUNT(*) AS silver_trip_count
FROM silver.trips;

SELECT COUNT(*) AS quarantine_count
FROM silver.trips_quarantine;

SELECT COUNT(*) AS gold_trip_count
FROM gold.fact_trips;


-- Step (b): Valid partner rows.
SELECT
    trip_id,
    status,
    fare_amount,
    cancelled_by
FROM silver.trips
WHERE trip_id IN (900001, 900009)
ORDER BY trip_id;


-- Step (b): Quarantined partner rows and reasons.
SELECT
    trip_id,
    reason
FROM silver.trips_quarantine
ORDER BY trip_id;


-- Step (b): Corrected trip 2 must have rating 3.0 in silver.
SELECT
    trip_id,
    driver_rating
FROM silver.trips
WHERE trip_id = 2;


-- Step (b): Corrected trip 2 must also update Gold.
SELECT
    source_trip_id,
    driver_rating
FROM gold.fact_trips
WHERE source_trip_id = 2;


-- Step (c): New Southwest region must appear.
SELECT DISTINCT region
FROM gold.mart_monthly_region_revenue
ORDER BY region;


-- Step (c): Show Southwest mart rows.
SELECT *
FROM gold.mart_monthly_region_revenue
WHERE region = 'Southwest'
ORDER BY year, month;