-- =============================================================================
-- 10_silver.sql — Week 5 Assignment, Part 3
-- Bronze -> Silver
-- Rebuilds silver completely from the append-only bronze layer.
-- =============================================================================

TRUNCATE TABLE
    silver.trips_quarantine,
    silver.trips,
    silver.drivers,
    silver.passengers,
    silver.locations,
    silver.payment_methods,
    silver.promo_codes;


-- =============================================================================
-- S1 — DIMENSIONS
-- Latest bronze copy per natural key.
-- =============================================================================

-- Drivers
WITH ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY driver_id
            ORDER BY _ingested_at DESC, _batch_id DESC
        ) AS rn
    FROM bronze.drivers b
)
INSERT INTO silver.drivers (
    driver_id,
    name,
    status,
    joined_at
)
SELECT
    trim(driver_id)::INTEGER,
    trim(name),
    lower(trim(status)),
    ops.try_timestamp(joined_at)
FROM ranked
WHERE rn = 1;


-- Passengers
WITH ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY passenger_id
            ORDER BY _ingested_at DESC, _batch_id DESC
        ) AS rn
    FROM bronze.passengers b
)
INSERT INTO silver.passengers (
    passenger_id,
    name,
    status,
    created_at
)
SELECT
    trim(passenger_id)::INTEGER,
    trim(name),
    lower(trim(status)),
    ops.try_timestamp(created_at)
FROM ranked
WHERE rn = 1;


-- Locations
WITH ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY location_id
            ORDER BY _ingested_at DESC, _batch_id DESC
        ) AS rn
    FROM bronze.locations b
)
INSERT INTO silver.locations (
    location_id,
    city_name,
    state_province,
    country,
    latitude,
    longitude,
    region
)
SELECT
    trim(location_id)::INTEGER,
    trim(city_name),
    NULLIF(trim(state_province), ''),
    NULLIF(trim(country), ''),

    ops.try_numeric(latitude),
    ops.try_numeric(longitude),

    CASE
        WHEN trim(country) <> 'USA'
            THEN 'International'

        WHEN trim(state_province) IN (
            'Texas',
            'Arizona'
        )
            THEN 'Southwest'

        WHEN trim(state_province) IN (
            'Connecticut',
            'Maine',
            'Massachusetts',
            'New Hampshire',
            'New Jersey',
            'New York',
            'Pennsylvania',
            'Rhode Island',
            'Vermont'
        )
            THEN 'Northeast'

        WHEN trim(state_province) IN (
            'Illinois',
            'Indiana',
            'Iowa',
            'Kansas',
            'Michigan',
            'Minnesota',
            'Missouri',
            'Nebraska',
            'North Dakota',
            'Ohio',
            'South Dakota',
            'Wisconsin'
        )
            THEN 'Midwest'

        WHEN trim(state_province) IN (
            'Alabama',
            'Arkansas',
            'Delaware',
            'Florida',
            'Georgia',
            'Kentucky',
            'Louisiana',
            'Maryland',
            'Mississippi',
            'North Carolina',
            'Oklahoma',
            'South Carolina',
            'Tennessee',
            'Virginia',
            'West Virginia'
        )
            THEN 'South'

        WHEN trim(state_province) IN (
            'Alaska',
            'California',
            'Colorado',
            'Hawaii',
            'Idaho',
            'Montana',
            'Nevada',
            'New Mexico',
            'Oregon',
            'Utah',
            'Washington',
            'Wyoming'
        )
            THEN 'West'

        ELSE 'International'
    END AS region

FROM ranked
WHERE rn = 1;


-- Payment methods
WITH ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY payment_method_id
            ORDER BY _ingested_at DESC, _batch_id DESC
        ) AS rn
    FROM bronze.payment_methods b
)
INSERT INTO silver.payment_methods (
    payment_method_id,
    name,
    type,
    is_active
)
SELECT
    trim(payment_method_id)::INTEGER,
    trim(name),
    lower(NULLIF(trim(type), '')),

    CASE lower(trim(is_active))
        WHEN 'true' THEN TRUE
        WHEN 't' THEN TRUE
        WHEN '1' THEN TRUE
        WHEN 'false' THEN FALSE
        WHEN 'f' THEN FALSE
        WHEN '0' THEN FALSE
        ELSE NULL
    END

FROM ranked
WHERE rn = 1;


-- Promo codes
WITH ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY promo_code_id
            ORDER BY _ingested_at DESC, _batch_id DESC
        ) AS rn
    FROM bronze.promo_codes b
)
INSERT INTO silver.promo_codes (
    promo_code_id,
    code,
    discount_type,
    discount_value,
    valid_from,
    valid_until,
    max_uses,
    is_active
)
SELECT
    trim(promo_code_id)::INTEGER,
    NULLIF(trim(code), ''),
    lower(NULLIF(trim(discount_type), '')),
    ops.try_numeric(discount_value),
    ops.try_timestamp(valid_from),
    ops.try_timestamp(valid_until),

    CASE
        WHEN trim(max_uses) ~ '^[0-9]+$'
            THEN trim(max_uses)::INTEGER
        ELSE NULL
    END,

    CASE lower(trim(is_active))
        WHEN 'true' THEN TRUE
        WHEN 't' THEN TRUE
        WHEN '1' THEN TRUE
        WHEN 'false' THEN FALSE
        WHEN 'f' THEN FALSE
        WHEN '0' THEN FALSE
        ELSE NULL
    END

FROM ranked
WHERE rn = 1;


-- =============================================================================
-- S2 — TRIPS
--
-- latest:
--     latest bronze copy of each trip
--
-- typed:
--     cleaned + safely typed values
--
-- checked:
--     first failed validation rule becomes reject_reason
-- =============================================================================

DROP TABLE IF EXISTS silver_trip_work;

CREATE TEMP TABLE silver_trip_work AS

WITH latest AS (
    SELECT *
    FROM (
        SELECT
            b.*,

            ROW_NUMBER() OVER (
                PARTITION BY trip_id
                ORDER BY _ingested_at DESC, _batch_id DESC
            ) AS rn

        FROM bronze.trips b
    ) x
    WHERE rn = 1
),

typed AS (
    SELECT
        b.*,

        -- Keep original bronze row for quarantine.
        to_jsonb(b) AS raw_row,

        CASE
            WHEN trim(b.trip_id) ~ '^[0-9]+$'
                THEN trim(b.trip_id)::INTEGER
            ELSE NULL
        END AS typed_trip_id,

        CASE
            WHEN trim(b.driver_id) ~ '^[0-9]+$'
                THEN trim(b.driver_id)::INTEGER
            ELSE NULL
        END AS typed_driver_id,

        CASE
            WHEN trim(b.passenger_id) ~ '^[0-9]+$'
                THEN trim(b.passenger_id)::INTEGER
            ELSE NULL
        END AS typed_passenger_id,

        CASE
            WHEN NULLIF(trim(b.vehicle_id), '') IS NULL
                THEN NULL
            WHEN trim(b.vehicle_id) ~ '^[0-9]+$'
                THEN trim(b.vehicle_id)::INTEGER
            ELSE NULL
        END AS typed_vehicle_id,

        CASE
            WHEN trim(b.pickup_location_id) ~ '^[0-9]+$'
                THEN trim(b.pickup_location_id)::INTEGER
            ELSE NULL
        END AS typed_pickup_location_id,

        CASE
            WHEN trim(b.dropoff_location_id) ~ '^[0-9]+$'
                THEN trim(b.dropoff_location_id)::INTEGER
            ELSE NULL
        END AS typed_dropoff_location_id,

        CASE
            WHEN NULLIF(trim(b.payment_method_id), '') IS NULL
                THEN NULL
            WHEN trim(b.payment_method_id) ~ '^[0-9]+$'
                THEN trim(b.payment_method_id)::INTEGER
            ELSE NULL
        END AS typed_payment_method_id,

        CASE
            WHEN NULLIF(trim(b.promo_code_id), '') IS NULL
                THEN NULL
            WHEN trim(b.promo_code_id) ~ '^[0-9]+$'
                THEN trim(b.promo_code_id)::INTEGER
            ELSE NULL
        END AS typed_promo_code_id,

        ops.try_numeric(b.base_fare)
            AS typed_base_fare,

        COALESCE(
            ops.try_numeric(b.tip_amount),
            0
        ) AS typed_tip_amount,

        COALESCE(
            ops.try_numeric(b.discount_amount),
            0
        ) AS typed_discount_amount,

        ops.try_numeric(b.surge_multiplier)
            AS typed_surge_multiplier,

        ops.try_numeric(b.distance_km)
            AS typed_distance_km,

        lower(trim(b.status))
            AS typed_status,

        ops.try_timestamp(b.requested_at)
            AS typed_requested_at,

        ops.try_timestamp(b.completed_at)
            AS typed_completed_at,

        ops.try_numeric(b.driver_rating)
            AS typed_driver_rating,

        ops.try_numeric(b.passenger_rating)
            AS typed_passenger_rating

    FROM latest b
),

checked AS (
    SELECT
        t.*,

        CASE
            -- Required integer fields
            WHEN typed_trip_id IS NULL
                THEN 'invalid trip_id'

            WHEN typed_driver_id IS NULL
                THEN 'invalid driver_id'

            WHEN typed_passenger_id IS NULL
                THEN 'invalid passenger_id'

            WHEN typed_pickup_location_id IS NULL
                THEN 'invalid pickup_location_id'

            WHEN typed_dropoff_location_id IS NULL
                THEN 'invalid dropoff_location_id'


            -- Optional integer values that were present but invalid
            WHEN NULLIF(trim(vehicle_id), '') IS NOT NULL
                 AND typed_vehicle_id IS NULL
                THEN 'invalid vehicle_id'

            WHEN NULLIF(trim(payment_method_id), '') IS NOT NULL
                 AND typed_payment_method_id IS NULL
                THEN 'invalid payment_method_id'

            WHEN NULLIF(trim(promo_code_id), '') IS NOT NULL
                 AND typed_promo_code_id IS NULL
                THEN 'invalid promo_code_id'


            -- Numeric values
            WHEN NULLIF(trim(base_fare), '') IS NOT NULL
                 AND typed_base_fare IS NULL
                THEN 'invalid base_fare'

            WHEN NULLIF(trim(tip_amount), '') IS NOT NULL
                 AND ops.try_numeric(tip_amount) IS NULL
                THEN 'invalid tip_amount'

            WHEN NULLIF(trim(discount_amount), '') IS NOT NULL
                 AND ops.try_numeric(discount_amount) IS NULL
                THEN 'invalid discount_amount'

            WHEN NULLIF(trim(surge_multiplier), '') IS NOT NULL
                 AND typed_surge_multiplier IS NULL
                THEN 'invalid surge_multiplier'

            WHEN NULLIF(trim(distance_km), '') IS NOT NULL
                 AND typed_distance_km IS NULL
                THEN 'invalid distance_km'

            WHEN NULLIF(trim(driver_rating), '') IS NOT NULL
                 AND typed_driver_rating IS NULL
                THEN 'invalid driver_rating'

            WHEN NULLIF(trim(passenger_rating), '') IS NOT NULL
                 AND typed_passenger_rating IS NULL
                THEN 'invalid passenger_rating'


            -- Timestamp values
            WHEN NULLIF(trim(requested_at), '') IS NOT NULL
                 AND typed_requested_at IS NULL
                THEN 'invalid requested_at'

            WHEN NULLIF(trim(completed_at), '') IS NOT NULL
                 AND typed_completed_at IS NULL
                THEN 'invalid completed_at'


            -- Status
            WHEN typed_status NOT IN (
                'completed',
                'cancelled',
                'no_show'
            )
                THEN 'invalid status'


            -- Foreign/business keys
            WHEN NOT EXISTS (
                SELECT 1
                FROM silver.drivers d
                WHERE d.driver_id = typed_driver_id
            )
                THEN 'unknown driver'

            WHEN NOT EXISTS (
                SELECT 1
                FROM silver.passengers p
                WHERE p.passenger_id = typed_passenger_id
            )
                THEN 'unknown passenger'

            WHEN NOT EXISTS (
                SELECT 1
                FROM silver.locations l
                WHERE l.location_id = typed_pickup_location_id
            )
                THEN 'unknown pickup location'

            WHEN NOT EXISTS (
                SELECT 1
                FROM silver.locations l
                WHERE l.location_id = typed_dropoff_location_id
            )
                THEN 'unknown dropoff location'


            -- Completed time consistency
            WHEN typed_status = 'completed'
                 AND typed_completed_at IS NULL
                THEN 'completed trip missing completed_at'

            WHEN typed_status = 'completed'
                 AND typed_completed_at < typed_requested_at
                THEN 'completed_at earlier than requested_at'


            -- Fare validation
            WHEN typed_base_fare < 0
                THEN 'negative base_fare'

            WHEN typed_tip_amount < 0
                THEN 'negative tip_amount'

            WHEN typed_discount_amount < 0
                THEN 'negative discount_amount'

            WHEN typed_surge_multiplier < 1.00
                THEN 'surge_multiplier below 1.00'

            ELSE NULL
        END AS reject_reason

    FROM typed t
)

SELECT *
FROM checked;


-- =============================================================================
-- Latest cancellation record per trip.
-- =============================================================================

DROP TABLE IF EXISTS silver_latest_cancellation;

CREATE TEMP TABLE silver_latest_cancellation AS
SELECT
    trip_id,
    lower(trim(cancelled_by)) AS cancelled_by
FROM (
    SELECT
        c.*,

        ROW_NUMBER() OVER (
            PARTITION BY trip_id
            ORDER BY _ingested_at DESC, _batch_id DESC
        ) AS rn

    FROM bronze.trip_cancellations c
) x
WHERE rn = 1;


-- =============================================================================
-- Valid rows -> silver.trips
-- =============================================================================

INSERT INTO silver.trips (
    trip_id,
    source,

    driver_id,
    passenger_id,
    vehicle_id,

    pickup_location_id,
    dropoff_location_id,

    payment_method_id,
    promo_code_id,

    base_fare,
    tip_amount,
    discount_amount,
    surge_multiplier,
    fare_amount,

    distance_km,

    status,
    requested_at,
    completed_at,
    duration_minutes,

    driver_rating,
    passenger_rating,

    cancelled_by,

    _batch_id
)
SELECT
    w.typed_trip_id,
    w._source,

    w.typed_driver_id,
    w.typed_passenger_id,
    w.typed_vehicle_id,

    w.typed_pickup_location_id,
    w.typed_dropoff_location_id,

    w.typed_payment_method_id,
    w.typed_promo_code_id,

    w.typed_base_fare,
    w.typed_tip_amount,
    w.typed_discount_amount,
    w.typed_surge_multiplier,

    ROUND(
        w.typed_base_fare
        * w.typed_surge_multiplier
        + w.typed_tip_amount
        - w.typed_discount_amount,
        2
    ) AS fare_amount,

    w.typed_distance_km,

    w.typed_status,
    w.typed_requested_at,
    w.typed_completed_at,

    CASE
        WHEN w.typed_status = 'completed'
        THEN ROUND(
            EXTRACT(
                EPOCH FROM (
                    w.typed_completed_at
                    - w.typed_requested_at
                )
            ) / 60.0,
            1
        )
        ELSE NULL
    END AS duration_minutes,

    w.typed_driver_rating,
    w.typed_passenger_rating,

    CASE
        WHEN w.typed_status = 'cancelled'
        THEN c.cancelled_by
        ELSE NULL
    END AS cancelled_by,

    w._batch_id

FROM silver_trip_work w

LEFT JOIN silver_latest_cancellation c
    ON c.trip_id = w.trip_id

WHERE w.reject_reason IS NULL;


-- =============================================================================
-- Invalid rows -> quarantine
-- =============================================================================

INSERT INTO silver.trips_quarantine (
    trip_id,
    raw_row,
    reason
)
SELECT
    trip_id,
    raw_row,
    reject_reason

FROM silver_trip_work

WHERE reject_reason IS NOT NULL;