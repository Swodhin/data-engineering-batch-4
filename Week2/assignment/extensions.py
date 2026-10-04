"""
extensions.py
─────────────
P1: parameterized query function
P2: generic table printer (cursor.description)
P3: handle a bad insert gracefully (FK violation + rollback)
"""

import os

import psycopg2
from dotenv import load_dotenv


def get_connection():
    load_dotenv()
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


# ── P1: parameterized query function ──────────────────────────────────────
def get_rides_for_driver(cur, driver_name):
    """Return every trip for the given driver name (case-insensitive)."""

    # Parameterized queries prevent user input from being treated as SQL code.
    # Building SQL with string concatenation could allow SQL injection.
    cur.execute(
        """
        SELECT
            t.trip_id,
            d.name,
            t.fare_amount,
            t.status,
            t.requested_at
        FROM trips t
        JOIN drivers d
            ON t.driver_id = d.driver_id
        WHERE d.name ILIKE %s
        ORDER BY t.requested_at;
        """,
        (driver_name,)
    )

    return cur.fetchall()

# ── P2: generic table printer ─────────────────────────────────────────────
def run_and_print(cur, sql):
    """Run any SELECT query and print an aligned table using cur.description."""

    cur.execute(sql)
    rows = cur.fetchall()

    # Get column names dynamically from the query result
    headers = [desc[0] for desc in cur.description]

    # Convert everything to strings so we can calculate column widths
    string_rows = [
        ["" if value is None else str(value) for value in row]
        for row in rows
    ]

    widths = [
        max(
            len(headers[i]),
            max((len(row[i]) for row in string_rows), default=0)
        )
        for i in range(len(headers))
    ]

    # Print header
    print(
        " | ".join(
            headers[i].ljust(widths[i])
            for i in range(len(headers))
        )
    )

    # Print separator
    print(
        "-+-".join("-" * width for width in widths)
    )

    # Print rows
    for row in string_rows:
        print(
            " | ".join(
                row[i].ljust(widths[i])
                for i in range(len(row))
            )
        )


# ── P3: handle a bad insert gracefully ────────────────────────────────────
def insert_trip_with_bad_driver(conn):
    """Attempt an INSERT with a driver_id that doesn't exist; recover cleanly."""

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
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
                VALUES (
                    999999,
                    1,
                    1,
                    2,
                    500.00,
                    10.00,
                    'completed',
                    CURRENT_TIMESTAMP
                );
                """
            )

        conn.commit()

    except psycopg2.Error as e:
        print("\n-- Expected database error --")
        print(f"Insert failed: {e.pgerror.strip()}")

        # Reset the failed transaction so the connection can be used again
        conn.rollback()

    # Prove the connection still works after rollback
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM trips;")
        total_trips = cur.fetchone()[0]

    print(f"Connection recovered successfully. Total trips: {total_trips}")


def main():
    conn = get_connection()

    try:
        with conn.cursor() as cur:
            # P1: Parameterized query
            print("\n-- P1: Trips for Rajan Pandey --")
            rows = get_rides_for_driver(cur, "Rajan Pandey")

            for row in rows[:5]:
                print(row)

            # P2: Generic table printer - Q1
            print("\n-- P2: Q1 Rides per driver --")
            run_and_print(
                cur,
                """
                SELECT
                    d.name,
                    COUNT(*) AS total_rides
                FROM drivers d
                JOIN trips t
                    ON d.driver_id = t.driver_id
                WHERE t.status = 'completed'
                GROUP BY d.driver_id, d.name
                ORDER BY total_rides DESC;
                """
            )

            # P2: Generic table printer - Q3
            print("\n-- P2: Q3 Average fare per pickup city --")
            run_and_print(
                cur,
                """
                SELECT
                    l.city_name,
                    ROUND(AVG(t.fare_amount), 2) AS avg_fare
                FROM trips t
                JOIN locations l
                    ON t.pickup_location_id = l.location_id
                GROUP BY l.location_id, l.city_name
                ORDER BY avg_fare DESC;
                """
            )

            # P2: Generic table printer - Q6
            print("\n-- P2: Q6 Qualified drivers --")
            run_and_print(
                cur,
                """
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
                """
            )

        # P3: Bad insert + rollback + recovery
        print("\n-- P3: Foreign key error handling --")
        insert_trip_with_bad_driver(conn)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
