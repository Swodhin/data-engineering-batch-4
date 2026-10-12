import logging

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

logger = logging.getLogger(__name__)


def _make_engine(conn):
    db_url = URL.create(
        drivername="postgresql+psycopg2",
        username=conn.info.user,
        password=conn.info.password,
        host=conn.info.host,
        port=conn.info.port,
        database=conn.info.dbname,
    )

    return create_engine(db_url)


def extract(conn, sql, params=None):
    try:
        engine = _make_engine(conn)

        df = pd.read_sql(
            sql,
            engine,
            params=params,
        )

        logger.info(
            f"Extracted {len(df)} rows from the table"
        )

        return df

    except Exception as e:
        logger.error(str(e))
        raise


def extract_driver(conn):
    sql = """
        SELECT
            driver_id,
            name,
            status,
            joined_at,
            CASE
                WHEN joined_at >= NOW() - INTERVAL '6 months'
                    THEN '0-6 months'
                WHEN joined_at >= NOW() - INTERVAL '1 year'
                    THEN '6-12 months'
                WHEN joined_at >= NOW() - INTERVAL '2 years'
                    THEN '1-2 years'
                ELSE '2+ years'
            END AS tenure_bucket
        FROM drivers;
    """

    return extract(conn, sql)


def extract_passenger(conn):
    sql = """
        SELECT
            passenger_id,
            name,
            status,
            created_at,
            TO_CHAR(created_at, 'YYYY-MM') AS cohort_month
        FROM passengers;
    """

    return extract(conn, sql)


def extract_location(conn):
    sql = """
        SELECT
            location_id,
            city_name,
            state_province,
            country,
            latitude,
            longitude,
            CASE
                WHEN country <> 'USA' THEN 'International'

                WHEN state_province IN (
                    'Connecticut','Maine','Massachusetts',
                    'New Hampshire','New Jersey','New York',
                    'Pennsylvania','Rhode Island','Vermont'
                ) THEN 'Northeast'

                WHEN state_province IN (
                    'Illinois','Indiana','Iowa','Kansas',
                    'Michigan','Minnesota','Missouri','Nebraska',
                    'North Dakota','Ohio','South Dakota','Wisconsin'
                ) THEN 'Midwest'

                WHEN state_province IN (
                    'Alabama','Arkansas','Delaware','Florida',
                    'Georgia','Kentucky','Louisiana','Maryland',
                    'Mississippi','North Carolina','Oklahoma',
                    'South Carolina','Tennessee','Texas',
                    'Virginia','West Virginia'
                ) THEN 'South'

                WHEN state_province IN (
                    'Alaska','Arizona','California','Colorado',
                    'Hawaii','Idaho','Montana','Nevada',
                    'New Mexico','Oregon','Utah','Washington',
                    'Wyoming'
                ) THEN 'West'

                ELSE 'International'
            END AS region
        FROM locations;
    """

    return extract(conn, sql)


def extract_payment_method(conn):
    # payment_method_id is INTEGER in PostgreSQL, but pandas may
    # represent it as float64 when NULL values are present because
    # the standard NumPy integer dtype cannot represent NaN.
    sql = """
        SELECT
            payment_method_id,
            name,
            type,
            is_active
        FROM payment_methods;
    """

    return extract(conn, sql)


def extract_promo_code(conn):
    sql = """
        SELECT
            promo_code_id,
            code,
            discount_type,
            discount_value,
            is_active
        FROM promo_codes;
    """

    return extract(conn, sql)


TRIPS_SQL = """
    SELECT
        t.trip_id,
        t.driver_id,
        t.passenger_id,
        t.pickup_location_id,
        t.dropoff_location_id,
        t.payment_method_id,
        t.promo_code_id,
        t.base_fare,
        t.tip_amount,
        t.discount_amount,
        t.surge_multiplier,
        t.distance_km,
        t.status,
        t.requested_at,
        t.completed_at,
        t.driver_rating,
        t.passenger_rating,
        tc.cancelled_by
    FROM trips t
    LEFT JOIN trip_cancellations tc
        ON t.trip_id = tc.trip_id
"""


def extract_trips_incremental(conn, watermark):
    sql = (
        TRIPS_SQL
        + """
        WHERE t.requested_at > %(watermark)s
        ORDER BY t.requested_at
        """
    )

    return extract(
        conn,
        sql,
        params=watermark,
    )


def extract_trips_full(conn):
    sql = TRIPS_SQL + """
        ORDER BY t.requested_at
    """

    return extract(conn, sql)


def extract_lookup_dim(conn):
    logger.info("Loading lookup tables into memory")

    lookup = {}

    with conn.cursor() as cur:
        cur.execute(
            "SELECT driver_id, driver_key FROM dim_driver"
        )
        lookup["driver"] = {
            row[0]: row[1]
            for row in cur.fetchall()
        }

        cur.execute(
            "SELECT passenger_id, passenger_key FROM dim_passenger"
        )
        lookup["passenger"] = {
            row[0]: row[1]
            for row in cur.fetchall()
        }

        cur.execute(
            "SELECT location_id, location_key FROM dim_location"
        )
        lookup["location"] = {
            row[0]: row[1]
            for row in cur.fetchall()
        }

        cur.execute(
            """
            SELECT
                payment_method_id,
                payment_method_key
            FROM dim_payment_method
            """
        )
        lookup["payment_method"] = {
            row[0]: row[1]
            for row in cur.fetchall()
        }

        cur.execute(
            """
            SELECT
                promo_code_id,
                promo_code_key
            FROM dim_promo_code
            """
        )
        lookup["promo_code"] = {
            row[0]: row[1]
            for row in cur.fetchall()
        }

        cur.execute(
            "SELECT date_key FROM dim_date"
        )
        lookup["date"] = {
            row[0]: True
            for row in cur.fetchall()
        }

    return lookup


def get_watermark(conn):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COALESCE(
                MAX(requested_at),
                '2000-01-01'::TIMESTAMP
            )
            FROM fact_trips
            """
        )

        watermark = cur.fetchone()[0]

    logger.info(f"Watermark: {watermark}")

    return {
        "watermark": watermark
    }