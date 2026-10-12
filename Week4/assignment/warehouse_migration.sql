-- Week 4 — Warehouse Migration (Q4)
-- Rename this file to warehouse_migration.sql before committing.
-- Run once against ride_warehouse, AFTER the class etl.py has been run at least twice:
--     psql -d ride_warehouse -f warehouse_migration.sql
-- See sql_assignment.md Q4 for the full requirements.

BEGIN;

-- 1. Deduplicate dim_driver
--    Re-point fact_trips.driver_key to the surviving copy (UPDATE ... FROM),
--    then DELETE the extra copies (DELETE ... USING).

WITH driver_map AS (
    SELECT
        driver_id,
        MIN(driver_key) AS keep_key
    FROM dim_driver
    GROUP BY driver_id
)
UPDATE fact_trips f
SET driver_key = m.keep_key
FROM dim_driver d
JOIN driver_map m
    ON d.driver_id = m.driver_id
WHERE f.driver_key = d.driver_key
  AND d.driver_key <> m.keep_key;

WITH driver_map AS (
    SELECT
        driver_id,
        MIN(driver_key) AS keep_key
    FROM dim_driver
    GROUP BY driver_id
)
DELETE FROM dim_driver d
USING driver_map m
WHERE d.driver_id = m.driver_id
  AND d.driver_key <> m.keep_key;


-- 1b. Deduplicate dim_passenger (same pattern)

WITH passenger_map AS (
    SELECT
        passenger_id,
        MIN(passenger_key) AS keep_key
    FROM dim_passenger
    GROUP BY passenger_id
)
UPDATE fact_trips f
SET passenger_key = m.keep_key
FROM dim_passenger p
JOIN passenger_map m
    ON p.passenger_id = m.passenger_id
WHERE f.passenger_key = p.passenger_key
  AND p.passenger_key <> m.keep_key;

WITH passenger_map AS (
    SELECT
        passenger_id,
        MIN(passenger_key) AS keep_key
    FROM dim_passenger
    GROUP BY passenger_id
)
DELETE FROM dim_passenger p
USING passenger_map m
WHERE p.passenger_id = m.passenger_id
  AND p.passenger_key <> m.keep_key;


-- 2. UNIQUE constraints on dim_driver(driver_id) and dim_passenger(passenger_id)

ALTER TABLE dim_driver
ADD CONSTRAINT uq_dim_driver_driver_id UNIQUE (driver_id);

ALTER TABLE dim_passenger
ADD CONSTRAINT uq_dim_passenger_passenger_id UNIQUE (passenger_id);


-- 3. New fact_trips columns
--    time_key      INTEGER      -> FK to dim_time(time_key)
--    trip_status   VARCHAR(20)  -> CHECK: completed / cancelled / no_show
--    cancelled_by  VARCHAR(10)  -> CHECK: driver / passenger / system

ALTER TABLE fact_trips
ADD COLUMN time_key INTEGER REFERENCES dim_time(time_key);

ALTER TABLE fact_trips
ADD COLUMN trip_status VARCHAR(20)
CHECK (trip_status IN ('completed', 'cancelled', 'no_show'));

ALTER TABLE fact_trips
ADD COLUMN cancelled_by VARCHAR(10)
CHECK (cancelled_by IN ('driver', 'passenger', 'system'));


-- 4. Backfill time_key from requested_at (HHMM, minutes rounded down to 15)

UPDATE fact_trips
SET time_key =
    EXTRACT(HOUR FROM requested_at)::INTEGER * 100
    +
    (EXTRACT(MINUTE FROM requested_at)::INTEGER / 15) * 15;

COMMIT;