-- Week 2 Queries — Answers
-- Fill in each query below. See sql_assignment.md for the full scenario text.
-- Rename this file to week2_queries.sql before committing.


-- Q1 — Rides per driver (Basic · JOIN + GROUP BY)
-- name, total_rides — completed rides only, ordered by total_rides desc

SELECT
    d.name,
    COUNT(*) AS total_rides
FROM drivers d
JOIN trips t
    ON d.driver_id = t.driver_id
WHERE t.status = 'completed'
GROUP BY d.driver_id, d.name
ORDER BY total_rides DESC;

-- Q2 — Drivers with zero completed rides (Intermediate · anti-join)
-- name of every driver with no completed trip (LEFT JOIN, not a subquery)

SELECT
    d.name
FROM drivers d
LEFT JOIN trips t
    ON d.driver_id = t.driver_id
    AND t.status = 'completed'
WHERE t.trip_id IS NULL;

-- Q3 — Average fare per pickup city (Intermediate · 3-table JOIN + AVG)
-- city_name, avg_fare (2 decimals) — ordered by avg_fare desc

SELECT
    l.city_name,
    ROUND(AVG(t.fare_amount), 2) AS avg_fare
FROM trips t
JOIN locations l
    ON t.pickup_location_id = l.location_id
GROUP BY l.location_id, l.city_name
ORDER BY avg_fare DESC;

-- Q4 — Same-city driver/passenger trips (Basic–Intermediate · schema thinking)
-- Partial query + written explanation (as a comment) of what the schema is missing

-- Q4: Trips where driver and passenger are from the same city
-- The current schema cannot answer this because drivers and passengers
-- do not have a home city stored anywhere.

-- If home-city foreign keys existed, the query would look like this:
-- SELECT
--     t.trip_id,
--     d.name AS driver_name,
--     p.name AS passenger_name
-- FROM trips t
-- JOIN drivers d
--     ON t.driver_id = d.driver_id
-- JOIN passengers p
--     ON t.passenger_id = p.passenger_id
-- WHERE d.home_location_id = p.home_location_id;

-- To support this properly, add a home_location_id foreign key to both
-- drivers and passengers, referencing locations(location_id).
--
-- Adding plain text home_city columns instead would duplicate city names
-- and could create inconsistent values such as 'Kathmandu', 'kathmandu',
-- or misspelled versions, which defeats normalization.

-- Q5 — Re-run Week 1's revenue query (Basic · verification)
-- Total revenue from completed rides — must match your Week 1 answer

SELECT
    SUM(fare_amount) AS total_revenue
FROM trips
WHERE status = 'completed';

-- Q6 — WHERE and HAVING, together (Intermediate · WHERE + GROUP BY + HAVING)
-- Drivers with > 280 completed rides AND total revenue > NPR 140,000

SELECT
    d.name,
    COUNT(*) AS completed_rides,
    SUM(t.fare_amount) AS total_revenue
FROM drivers d
JOIN trips t
    ON d.driver_id = t.driver_id
WHERE t.status = 'completed'
GROUP BY d.driver_id, d.name
HAVING COUNT(*) > 280
   AND SUM(t.fare_amount) > 140000
ORDER BY completed_rides DESC;

-- Q7 — Clean the phone numbers (Intermediate · REGEXP_REPLACE)
-- Scratch copy (TEMP temp_rides, same as day1_class_query.sql) + ALTER TABLE + UPDATE to add
-- messy phone_number values, then a digits-only SELECT
-- Comment: why REPLACE() alone can't do this

SELECT * INTO TEMP temp_rides
FROM rides;

ALTER TABLE temp_rides
ADD COLUMN phone_number VARCHAR(20);

UPDATE temp_rides
SET phone_number = '98-4100 1234'
WHERE ride_id = 1;

UPDATE temp_rides
SET phone_number = '986 123 4567'
WHERE ride_id = 2;

SELECT
    ride_id,
    phone_number,
    REGEXP_REPLACE(phone_number, '\D', '', 'g') AS cleaned_phone_number
FROM temp_rides
WHERE phone_number IS NOT NULL;


-- Q8 — Prove the city data is clean (Intermediate · STRPOS / ILIKE)
-- Version 1: STRPOS
-- Version 2: ILIKE

SELECT
    location_id,
    city_name
FROM locations
WHERE STRPOS(city_name, ' ') > 0;

-- Q8b: Same check using ILIKE
SELECT
    location_id,
    city_name
FROM locations
WHERE city_name ILIKE '% %';

-- Q9 — Self-join: drivers who overlapped (Advanced · self-join + date functions)
-- Pairs of different drivers, same pickup location, same calendar day

SELECT DISTINCT
    d1.name AS driver_1,
    d2.name AS driver_2,
    l.city_name AS pickup_city,
    t1.requested_at::date AS pickup_date
FROM trips t1
JOIN trips t2
    ON t1.pickup_location_id = t2.pickup_location_id
    AND t1.requested_at::date = t2.requested_at::date
    AND t1.driver_id < t2.driver_id
JOIN drivers d1
    ON t1.driver_id = d1.driver_id
JOIN drivers d2
    ON t2.driver_id = d2.driver_id
JOIN locations l
    ON t1.pickup_location_id = l.location_id
ORDER BY pickup_date, pickup_city, driver_1, driver_2;

-- Q10 — Design challenge: promo codes (Design · no SQL required)
-- Written answer only — table(s), keys, and the normal-form problem with the flat-column approach

/*
Q10: Promo code design

I would add a promo_codes table:

promo_codes
-----------
promo_code_id      PRIMARY KEY
code               UNIQUE NOT NULL
discount_pct       NOT NULL
expiry_date        NOT NULL

Then I would add a nullable promo_code_id foreign key to trips:

trips.promo_code_id
    REFERENCES promo_codes(promo_code_id)

This allows the same promo code to be reused by many different trips
without storing its discount percentage and expiry date repeatedly.

If promo_code, discount_pct, and promo_expiry were stored directly
inside trips, the same promo-code information would be duplicated
across many rows. If the discount or expiry changed, multiple trip rows
would need to be updated, which creates update anomalies and breaks
normalization.
*/