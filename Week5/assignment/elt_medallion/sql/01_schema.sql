-- =============================================================================
-- 01_schema.sql — Week 5 Assignment, Part 3
-- Silver + Gold schemas
-- =============================================================================

CREATE SCHEMA silver;
CREATE SCHEMA gold;


-- =============================================================================
-- Helper casting functions
-- =============================================================================

CREATE FUNCTION ops.try_numeric(t TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN NULLIF(trim(t), '')::NUMERIC;
EXCEPTION WHEN others THEN
    RETURN NULL;
END $$;


CREATE FUNCTION ops.try_timestamp(t TEXT)
RETURNS TIMESTAMP
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN NULLIF(trim(t), '')::TIMESTAMP;
EXCEPTION WHEN others THEN
    RETURN NULL;
END $$;


-- =============================================================================
-- SILVER
-- =============================================================================

CREATE TABLE silver.drivers (
    driver_id      INTEGER PRIMARY KEY,
    name           VARCHAR(100) NOT NULL,
    status         VARCHAR(20) NOT NULL
                   CHECK (status IN ('active', 'inactive', 'suspended')),
    joined_at      TIMESTAMP
);


CREATE TABLE silver.passengers (
    passenger_id   INTEGER PRIMARY KEY,
    name           VARCHAR(100) NOT NULL,
    status         VARCHAR(20) NOT NULL,
    created_at     TIMESTAMP
);


CREATE TABLE silver.locations (
    location_id      INTEGER PRIMARY KEY,
    city_name        VARCHAR(100) NOT NULL,
    state_province   VARCHAR(100),
    country          VARCHAR(100),
    latitude         NUMERIC(9,6),
    longitude        NUMERIC(9,6),
    region           VARCHAR(30)
                     CHECK (
                         region IN (
                             'Northeast',
                             'Midwest',
                             'South',
                             'Southwest',
                             'West',
                             'International'
                         )
                     )
);


CREATE TABLE silver.payment_methods (
    payment_method_id INTEGER PRIMARY KEY,
    name              VARCHAR(30) NOT NULL,
    type              VARCHAR(20),
    is_active         BOOLEAN
);


CREATE TABLE silver.promo_codes (
    promo_code_id     INTEGER PRIMARY KEY,
    code              VARCHAR(30),
    discount_type     VARCHAR(20),
    discount_value    NUMERIC(8,2),
    valid_from        TIMESTAMP,
    valid_until       TIMESTAMP,
    max_uses          INTEGER,
    is_active         BOOLEAN
);


CREATE TABLE silver.trips (
    trip_id               INTEGER PRIMARY KEY,

    source                VARCHAR(50) NOT NULL,

    driver_id             INTEGER NOT NULL,
    passenger_id          INTEGER NOT NULL,
    vehicle_id            INTEGER,

    pickup_location_id    INTEGER NOT NULL,
    dropoff_location_id   INTEGER NOT NULL,

    payment_method_id     INTEGER,
    promo_code_id         INTEGER,

    base_fare             NUMERIC(10,2),
    tip_amount            NUMERIC(8,2) NOT NULL DEFAULT 0,
    discount_amount       NUMERIC(8,2) NOT NULL DEFAULT 0,
    surge_multiplier      NUMERIC(4,2),

    fare_amount           NUMERIC(10,2),

    distance_km           NUMERIC(8,2),

    status                VARCHAR(20) NOT NULL
                          CHECK (
                              status IN (
                                  'completed',
                                  'cancelled',
                                  'no_show'
                              )
                          ),

    requested_at          TIMESTAMP NOT NULL,
    completed_at          TIMESTAMP,

    duration_minutes      NUMERIC(8,1),

    driver_rating         NUMERIC(2,1),
    passenger_rating      NUMERIC(2,1),

    cancelled_by          VARCHAR(20)
                          CHECK (
                              cancelled_by IS NULL
                              OR cancelled_by IN (
                                  'driver',
                                  'passenger',
                                  'system'
                              )
                          ),

    _batch_id             BIGINT NOT NULL
);


CREATE TABLE silver.trips_quarantine (
    quarantine_id     BIGSERIAL PRIMARY KEY,
    trip_id           TEXT,
    raw_row           JSONB NOT NULL,
    reason            TEXT NOT NULL,
    quarantined_at    TIMESTAMP NOT NULL DEFAULT now()
);


-- =============================================================================
-- GOLD DIMENSIONS
-- =============================================================================

CREATE TABLE gold.dim_date (
    date_key        INTEGER PRIMARY KEY,
    full_date       DATE NOT NULL UNIQUE,
    year            SMALLINT NOT NULL,
    quarter         SMALLINT NOT NULL
                    CHECK (quarter BETWEEN 1 AND 4),
    month           SMALLINT NOT NULL
                    CHECK (month BETWEEN 1 AND 12),
    month_name      VARCHAR(10) NOT NULL,
    week_of_year    SMALLINT NOT NULL,
    day_of_week     SMALLINT NOT NULL
                    CHECK (day_of_week BETWEEN 0 AND 6),
    day_name        VARCHAR(10) NOT NULL,
    is_weekend      BOOLEAN NOT NULL
);


CREATE TABLE gold.dim_time (
    time_key        INTEGER PRIMARY KEY,
    hour            SMALLINT NOT NULL
                    CHECK (hour BETWEEN 0 AND 23),
    minute_bucket   SMALLINT NOT NULL
                    CHECK (minute_bucket IN (0, 15, 30, 45)),
    time_label      VARCHAR(8) NOT NULL,
    time_of_day     VARCHAR(12) NOT NULL,
    is_rush_hour    BOOLEAN NOT NULL
);


CREATE TABLE gold.dim_driver (
    driver_key      SERIAL PRIMARY KEY,
    driver_id       INTEGER NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL,
    status          VARCHAR(20) NOT NULL,
    joined_at       TIMESTAMP,
    tenure_bucket   VARCHAR(20)
);


CREATE TABLE gold.dim_passenger (
    passenger_key   SERIAL PRIMARY KEY,
    passenger_id    INTEGER NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL,
    status          VARCHAR(20) NOT NULL,
    cohort_month    VARCHAR(7),
    created_at      TIMESTAMP
);


CREATE TABLE gold.dim_location (
    location_key    SERIAL PRIMARY KEY,
    location_id     INTEGER NOT NULL UNIQUE,
    city_name       VARCHAR(100) NOT NULL,
    state_province  VARCHAR(100),
    country         VARCHAR(100),
    region          VARCHAR(30),
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6)
);


CREATE TABLE gold.dim_payment_method (
    payment_method_key  SERIAL PRIMARY KEY,
    payment_method_id   INTEGER UNIQUE,
    name                VARCHAR(30) NOT NULL,
    type                VARCHAR(20),
    is_active           BOOLEAN
);


CREATE TABLE gold.dim_promo_code (
    promo_code_key  SERIAL PRIMARY KEY,
    promo_code_id   INTEGER UNIQUE,
    code            VARCHAR(30),
    discount_type   VARCHAR(20),
    discount_value  NUMERIC(8,2),
    is_active       BOOLEAN
);


-- =============================================================================
-- GOLD FACT
-- =============================================================================

CREATE TABLE gold.fact_trips (
    trip_key                SERIAL PRIMARY KEY,

    source_trip_id          INTEGER NOT NULL UNIQUE,

    date_key                INTEGER NOT NULL
                            REFERENCES gold.dim_date(date_key),

    time_key                INTEGER NOT NULL
                            REFERENCES gold.dim_time(time_key),

    driver_key              INTEGER NOT NULL
                            REFERENCES gold.dim_driver(driver_key),

    passenger_key           INTEGER NOT NULL
                            REFERENCES gold.dim_passenger(passenger_key),

    pickup_location_key     INTEGER NOT NULL
                            REFERENCES gold.dim_location(location_key),

    dropoff_location_key    INTEGER NOT NULL
                            REFERENCES gold.dim_location(location_key),

    payment_method_key      INTEGER
                            REFERENCES gold.dim_payment_method(payment_method_key),

    promo_code_key          INTEGER
                            REFERENCES gold.dim_promo_code(promo_code_key),

    trip_status             VARCHAR(20) NOT NULL
                            CHECK (
                                trip_status IN (
                                    'completed',
                                    'cancelled',
                                    'no_show'
                                )
                            ),

    cancelled_by            VARCHAR(20),

    base_fare               NUMERIC(10,2),

    tip_amount              NUMERIC(8,2)
                            NOT NULL DEFAULT 0,

    discount_amount         NUMERIC(8,2)
                            NOT NULL DEFAULT 0,

    fare_amount             NUMERIC(10,2),

    distance_km             NUMERIC(8,2),

    duration_minutes        NUMERIC(8,1),

    trip_count              SMALLINT
                            NOT NULL DEFAULT 1,

    driver_rating           NUMERIC(2,1),

    passenger_rating        NUMERIC(2,1),

    surge_multiplier        NUMERIC(4,2),

    requested_at            TIMESTAMP NOT NULL
);

-- =============================================================================
-- Populate dim_date
-- =============================================================================

INSERT INTO gold.dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name,
    week_of_year,
    day_of_week,
    day_name,
    is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(YEAR FROM d)::SMALLINT,
    EXTRACT(QUARTER FROM d)::SMALLINT,
    EXTRACT(MONTH FROM d)::SMALLINT,
    TRIM(TO_CHAR(d, 'Month')),
    EXTRACT(WEEK FROM d)::SMALLINT,
    EXTRACT(DOW FROM d)::SMALLINT,
    TRIM(TO_CHAR(d, 'Day')),
    EXTRACT(DOW FROM d) IN (0, 6)
FROM generate_series(
    '2023-01-01'::TIMESTAMP,
    '2026-12-31'::TIMESTAMP,
    '1 day'::INTERVAL
) AS d;


-- =============================================================================
-- Populate dim_time
-- =============================================================================

INSERT INTO gold.dim_time (
    time_key,
    hour,
    minute_bucket,
    time_label,
    time_of_day,
    is_rush_hour
)
SELECT
    (h * 100 + m)::INTEGER,

    h::SMALLINT,

    m::SMALLINT,

    LPAD(h::TEXT, 2, '0')
        || ':'
        || LPAD(m::TEXT, 2, '0'),

    CASE
        WHEN h BETWEEN 6 AND 11 THEN 'Morning'
        WHEN h BETWEEN 12 AND 16 THEN 'Afternoon'
        WHEN h BETWEEN 17 AND 20 THEN 'Evening'
        ELSE 'Night'
    END,

    (h BETWEEN 7 AND 8)
        OR (h BETWEEN 17 AND 19)

FROM
    generate_series(0, 23) AS h,
    generate_series(0, 45, 15) AS m

ORDER BY h, m;