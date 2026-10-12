-- =============================================================================
-- 20_gold.sql — Week 5 Assignment, Part 3
-- Silver -> Gold
--
-- Dimensions use SCD Type 1 upserts.
-- Facts use source_trip_id so corrected source rows update the existing fact.
-- Running this repeatedly does not duplicate dimensions or facts.
-- =============================================================================


-- =============================================================================
-- G1 — DIMENSIONS
-- =============================================================================


-- Drivers
INSERT INTO gold.dim_driver (
    driver_id,
    name,
    status,
    joined_at,
    tenure_bucket
)
SELECT
    driver_id,
    name,
    status,
    joined_at,

    CASE
        WHEN joined_at >= CURRENT_TIMESTAMP - INTERVAL '6 months'
            THEN '0-6 months'

        WHEN joined_at >= CURRENT_TIMESTAMP - INTERVAL '1 year'
            THEN '6-12 months'

        WHEN joined_at >= CURRENT_TIMESTAMP - INTERVAL '2 years'
            THEN '1-2 years'

        ELSE '2+ years'
    END AS tenure_bucket

FROM silver.drivers

ON CONFLICT (driver_id)
DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    joined_at = EXCLUDED.joined_at,
    tenure_bucket = EXCLUDED.tenure_bucket;


-- Passengers
INSERT INTO gold.dim_passenger (
    passenger_id,
    name,
    status,
    cohort_month,
    created_at
)
SELECT
    passenger_id,
    name,
    status,
    TO_CHAR(created_at, 'YYYY-MM'),
    created_at

FROM silver.passengers

ON CONFLICT (passenger_id)
DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status,
    cohort_month = EXCLUDED.cohort_month,
    created_at = EXCLUDED.created_at;


-- Locations
INSERT INTO gold.dim_location (
    location_id,
    city_name,
    state_province,
    country,
    region,
    latitude,
    longitude
)
SELECT
    location_id,
    city_name,
    state_province,
    country,
    region,
    latitude,
    longitude

FROM silver.locations

ON CONFLICT (location_id)
DO UPDATE SET
    city_name = EXCLUDED.city_name,
    state_province = EXCLUDED.state_province,
    country = EXCLUDED.country,
    region = EXCLUDED.region,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude;


-- Payment methods
INSERT INTO gold.dim_payment_method (
    payment_method_id,
    name,
    type,
    is_active
)
SELECT
    payment_method_id,
    name,
    type,
    is_active

FROM silver.payment_methods

ON CONFLICT (payment_method_id)
DO UPDATE SET
    name = EXCLUDED.name,
    type = EXCLUDED.type,
    is_active = EXCLUDED.is_active;


-- Promo codes
INSERT INTO gold.dim_promo_code (
    promo_code_id,
    code,
    discount_type,
    discount_value,
    is_active
)
SELECT
    promo_code_id,
    code,
    discount_type,
    discount_value,
    is_active

FROM silver.promo_codes

ON CONFLICT (promo_code_id)
DO UPDATE SET
    code = EXCLUDED.code,
    discount_type = EXCLUDED.discount_type,
    discount_value = EXCLUDED.discount_value,
    is_active = EXCLUDED.is_active;


-- =============================================================================
-- G2 — FACT
-- =============================================================================

INSERT INTO gold.fact_trips (
    source_trip_id,

    date_key,
    time_key,

    driver_key,
    passenger_key,

    pickup_location_key,
    dropoff_location_key,

    payment_method_key,
    promo_code_key,

    trip_status,
    cancelled_by,

    base_fare,
    tip_amount,
    discount_amount,
    fare_amount,

    distance_km,
    duration_minutes,

    driver_rating,
    passenger_rating,

    surge_multiplier,
    requested_at
)
SELECT
    s.trip_id,

    TO_CHAR(
        s.requested_at,
        'YYYYMMDD'
    )::INTEGER AS date_key,

    (
        EXTRACT(HOUR FROM s.requested_at)::INTEGER * 100
        +
        (
            EXTRACT(MINUTE FROM s.requested_at)::INTEGER / 15
        ) * 15
    ) AS time_key,

    d.driver_key,
    p.passenger_key,

    pickup.location_key,
    dropoff.location_key,

    pm.payment_method_key,
    promo.promo_code_key,

    s.status,
    s.cancelled_by,

    s.base_fare,
    s.tip_amount,
    s.discount_amount,
    s.fare_amount,

    s.distance_km,
    s.duration_minutes,

    s.driver_rating,
    s.passenger_rating,

    s.surge_multiplier,
    s.requested_at

FROM silver.trips s

JOIN gold.dim_driver d
    ON d.driver_id = s.driver_id

JOIN gold.dim_passenger p
    ON p.passenger_id = s.passenger_id

JOIN gold.dim_location pickup
    ON pickup.location_id = s.pickup_location_id

JOIN gold.dim_location dropoff
    ON dropoff.location_id = s.dropoff_location_id

LEFT JOIN gold.dim_payment_method pm
    ON pm.payment_method_id = s.payment_method_id

LEFT JOIN gold.dim_promo_code promo
    ON promo.promo_code_id = s.promo_code_id


ON CONFLICT (source_trip_id)
DO UPDATE SET

    date_key = EXCLUDED.date_key,
    time_key = EXCLUDED.time_key,

    driver_key = EXCLUDED.driver_key,
    passenger_key = EXCLUDED.passenger_key,

    pickup_location_key = EXCLUDED.pickup_location_key,
    dropoff_location_key = EXCLUDED.dropoff_location_key,

    payment_method_key = EXCLUDED.payment_method_key,
    promo_code_key = EXCLUDED.promo_code_key,

    trip_status = EXCLUDED.trip_status,
    cancelled_by = EXCLUDED.cancelled_by,

    base_fare = EXCLUDED.base_fare,
    tip_amount = EXCLUDED.tip_amount,
    discount_amount = EXCLUDED.discount_amount,
    fare_amount = EXCLUDED.fare_amount,

    distance_km = EXCLUDED.distance_km,
    duration_minutes = EXCLUDED.duration_minutes,

    driver_rating = EXCLUDED.driver_rating,
    passenger_rating = EXCLUDED.passenger_rating,

    surge_multiplier = EXCLUDED.surge_multiplier,
    requested_at = EXCLUDED.requested_at;


-- =============================================================================
-- G3 — MART
-- Monthly performance by pickup region.
-- =============================================================================

CREATE OR REPLACE VIEW gold.mart_monthly_region_revenue AS

SELECT
    d.year,
    d.month,
    d.month_name,

    l.region,

    COUNT(*) FILTER (
        WHERE f.trip_status = 'completed'
    ) AS completed_trips,

    ROUND(
        COALESCE(
            SUM(f.fare_amount) FILTER (
                WHERE f.trip_status = 'completed'
            ),
            0
        ),
        2
    ) AS revenue,

    ROUND(
        AVG(f.fare_amount) FILTER (
            WHERE f.trip_status = 'completed'
        ),
        2
    ) AS avg_fare,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE f.trip_status = 'cancelled'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS cancellation_rate_pct

FROM gold.fact_trips f

JOIN gold.dim_date d
    ON d.date_key = f.date_key

JOIN gold.dim_location l
    ON l.location_key = f.pickup_location_key

GROUP BY
    d.year,
    d.month,
    d.month_name,
    l.region;