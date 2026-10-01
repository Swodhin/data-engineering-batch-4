-- Week 4 — Warehouse Migration (Q4)
-- Rename this file to warehouse_migration.sql before committing.
-- Run once against ride_warehouse, AFTER the class etl.py has been run at least twice:
--     psql -d ride_warehouse -f warehouse_migration.sql
-- See sql_assignment.md Q4 for the full requirements.

BEGIN;

-- 1. Deduplicate dim_driver
--    Re-point fact_trips.driver_key to the surviving copy (UPDATE ... FROM),
--    then DELETE the extra copies (DELETE ... USING).



-- 1b. Deduplicate dim_passenger (same pattern)



-- 2. UNIQUE constraints on dim_driver(driver_id) and dim_passenger(passenger_id)



-- 3. New fact_trips columns
--    time_key     INTEGER      -> FK to dim_time(time_key)
--    trip_status  VARCHAR(20)  -> CHECK: completed / cancelled / no_show
--    cancelled_by VARCHAR(10)  -> CHECK: driver / passenger / system



-- 4. Backfill time_key from requested_at (HHMM, minutes rounded down to 15)



COMMIT;
