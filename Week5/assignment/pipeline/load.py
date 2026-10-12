import logging
import pandas as pd
from psycopg2.extras import execute_values

logger = logging.getLogger(__name__)
def load_dim_driver(conn,driver_data):
    insert_dim_driver_sql = """
 INSERT INTO dim_driver
    (driver_id, name, status, joined_at,tenure_bucket)
    VALUES ( %(driver_id)s ,
             %(name)s,
             %(status)s,
            %(joined_at)s,
            %(tenure_bucket)s
            )
    ON CONFLICT DO NOTHING
"""
    try:
        with conn.cursor() as curr:
            curr.executemany(
                insert_dim_driver_sql,
                driver_data.to_dict("records")
            )
            logger.info(f"{curr.rowcount} inserted to dim_driver")
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise



def load_dim_passenger(conn, passenger_data):
    insert_dim_passenger_sql = """
 INSERT INTO dim_passenger
    (passenger_id, name, status, cohort_month, created_at)
    VALUES ( %(passenger_id)s,
             %(name)s,
             %(status)s,
             %(cohort_month)s,
             %(created_at)s
            )
    ON CONFLICT DO NOTHING
"""
    try:
        with conn.cursor() as curr:
            curr.executemany(
                insert_dim_passenger_sql,
                passenger_data.to_dict("records")
            )
            logger.info(f"{curr.rowcount} inserted to dim_passenger")
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise



def load_dim_location(conn, location_data):
    insert_dim_location_sql = """
 INSERT INTO dim_location
    (location_id, city_name, state_province, country, region, latitude, longitude)
    VALUES ( %(location_id)s,
             %(city_name)s,
             %(state_province)s,
             %(country)s,
             %(region)s,
             %(latitude)s,
             %(longitude)s
            )
    ON CONFLICT (location_id) DO NOTHING
"""
    try:
        with conn.cursor() as curr:
            curr.executemany(
                insert_dim_location_sql,
                location_data.to_dict("records")
            )
            logger.info(f"{curr.rowcount} inserted to dim_location")
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise



def load_dim_payment_method(conn, payment_method_data):
    insert_dim_payment_method_sql = """
 INSERT INTO dim_payment_method
    (payment_method_id, name, type, is_active)
    VALUES ( %(payment_method_id)s,
             %(name)s,
             %(type)s,
             %(is_active)s
            )
    ON CONFLICT (payment_method_id) DO NOTHING
"""
    try:
        with conn.cursor() as curr:
            curr.executemany(
                insert_dim_payment_method_sql,
                payment_method_data.to_dict("records")
            )
            logger.info(f"{curr.rowcount} inserted to dim_payment_method")
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise



def load_dim_promo_code(conn, promo_code_data):
    insert_dim_promo_code_sql = """
 INSERT INTO dim_promo_code
    (promo_code_id, code, discount_type, discount_value, is_active)
    VALUES ( %(promo_code_id)s,
             %(code)s,
             %(discount_type)s,
             %(discount_value)s,
             %(is_active)s
            )
    ON CONFLICT (promo_code_id) DO NOTHING
"""
    try:
        with conn.cursor() as curr:
            curr.executemany(
                insert_dim_promo_code_sql,
                promo_code_data.to_dict("records")
            )
            logger.info(f"{curr.rowcount} inserted to dim_promo_code")
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise


        

def load_fact_trips(conn, fact_data):
    if fact_data is None or len(fact_data) == 0:
        logger.info("No fact rows to load — skipping")
        return

    columns = [
        "source_trip_id",
        "date_key",
        "time_key",
        "driver_key",
        "passenger_key",
        "pickup_location_key",
        "dropoff_location_key",
        "payment_method_key",
        "promo_code_key",
        "trip_status",
        "cancelled_by",
        "base_fare",
        "tip_amount",
        "discount_amount",
        "fare_amount",
        "distance_km",
        "duration_minutes",
        "driver_rating",
        "passenger_rating",
        "surge_multiplier",
        "requested_at",
    ]

    df = fact_data[columns].copy()

    # Convert NaN / NaT to None so PostgreSQL stores NULL instead of NaN.
    df = df.astype(object).where(pd.notna(df), None)

    # Convert NumPy scalar values into normal Python values.
    rows = [
        tuple(
            value.item() if hasattr(value, "item") else value
            for value in row
        )
        for row in df.itertuples(index=False, name=None)
    ]

    sql = """
        INSERT INTO fact_trips (
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
        VALUES %s

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
            requested_at = EXCLUDED.requested_at
    """

    try:
        with conn.cursor() as curr:
            execute_values(
                curr,
                sql,
                rows,
                page_size=10000,
            )

        conn.commit()

        logger.info(
            f"{len(rows)} rows bulk loaded to fact_trips"
        )

    except Exception as e:
        conn.rollback()
        logger.error(str(e))
        raise