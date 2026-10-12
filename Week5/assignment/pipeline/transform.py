import logging

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


def transform_trip(trip_data, lookups):
    """
    Original class row-by-row transform.
    Kept because benchmark_transform.py compares against it.
    """
    fact_rows = []
    skipped = 0

    for row in trip_data:
        trip_id = row["trip_id"]

        date_key = int(row["requested_at"].strftime("%Y%m%d"))
        if date_key not in lookups["date"]:
            logger.warning(
                f"trip {trip_id}: date_key {date_key} outside dim_date — skipped"
            )
            skipped += 1
            continue

        driver_key = lookups["driver"].get(row["driver_id"])
        if driver_key is None:
            logger.warning(
                f"trip {trip_id}: driver_id {row['driver_id']} missing — skipped"
            )
            skipped += 1
            continue

        passenger_key = lookups["passenger"].get(row["passenger_id"])
        if passenger_key is None:
            logger.warning(
                f"trip {trip_id}: passenger_id {row['passenger_id']} missing — skipped"
            )
            skipped += 1
            continue

        pickup_location_key = lookups["location"].get(
            row["pickup_location_id"]
        )
        if pickup_location_key is None:
            logger.warning(
                f"trip {trip_id}: pickup location missing — skipped"
            )
            skipped += 1
            continue

        dropoff_location_key = lookups["location"].get(
            row["dropoff_location_id"]
        )
        if dropoff_location_key is None:
            logger.warning(
                f"trip {trip_id}: dropoff location missing — skipped"
            )
            skipped += 1
            continue

        payment_method_key = None
        if row["payment_method_id"] is not None:
            payment_method_key = lookups["payment_method"].get(
                row["payment_method_id"]
            )
            if payment_method_key is None:
                skipped += 1
                continue

        promo_code_key = None
        if row["promo_code_id"] is not None:
            promo_code_key = lookups["promo_code"].get(
                row["promo_code_id"]
            )
            if promo_code_key is None:
                skipped += 1
                continue

        base_fare = row["base_fare"] or 0
        tip_amount = row["tip_amount"] or 0
        surge_multiplier = row["surge_multiplier"] or 0
        discount_amount = row["discount_amount"] or 0

        fare_amount = round(
            base_fare * surge_multiplier
            + tip_amount
            - discount_amount,
            2,
        )

        duration_minutes = None

        if row["status"] == "completed" and row["completed_at"]:
            delta = row["completed_at"] - row["requested_at"]
            duration_minutes = round(
                delta.total_seconds() / 60,
                1,
            )

        fact_rows.append(
            {
                "source_trip_id": trip_id,
                "date_key": date_key,
                "driver_key": driver_key,
                "passenger_key": passenger_key,
                "pickup_location_key": pickup_location_key,
                "dropoff_location_key": dropoff_location_key,
                "payment_method_key": payment_method_key,
                "promo_code_key": promo_code_key,
                "status": row["status"],
                "base_fare": base_fare,
                "tip_amount": tip_amount,
                "discount_amount": discount_amount,
                "fare_amount": fare_amount,
                "distance_km": row["distance_km"],
                "duration_minutes": duration_minutes,
                "driver_rating": row["driver_rating"],
                "passenger_rating": row["passenger_rating"],
                "surge_multiplier": surge_multiplier,
                "requested_at": row["requested_at"],
            }
        )

    logger.info(
        f"Transformed {len(fact_rows)} rows, skipped {skipped}"
    )

    return fact_rows


def transform_trips_df(
    trips: pd.DataFrame,
    lookups: dict,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Vectorized pandas transform.

    Returns:
        facts, rejects
    """

    df = trips.copy()

    # ---------------------------------------------------------
    # Natural keys -> surrogate keys
    # ---------------------------------------------------------

    df["driver_key"] = df["driver_id"].map(
        lookups["driver"]
    )

    df["passenger_key"] = df["passenger_id"].map(
        lookups["passenger"]
    )

    df["pickup_location_key"] = df[
        "pickup_location_id"
    ].map(
        lookups["location"]
    )

    df["dropoff_location_key"] = df[
        "dropoff_location_id"
    ].map(
        lookups["location"]
    )

    df["payment_method_key"] = df[
        "payment_method_id"
    ].map(
        lookups["payment_method"]
    )

    df["promo_code_key"] = df[
        "promo_code_id"
    ].map(
        lookups["promo_code"]
    )

    # ---------------------------------------------------------
    # Date and time keys
    # ---------------------------------------------------------

    df["date_key"] = (
        df["requested_at"]
        .dt.strftime("%Y%m%d")
        .astype("int64")
    )

    df["time_key"] = (
        df["requested_at"].dt.hour * 100
        + (
            df["requested_at"].dt.minute // 15
        ) * 15
    )

    # ---------------------------------------------------------
    # Reject handling
    # ---------------------------------------------------------

    reject_reason = pd.Series(
        pd.NA,
        index=df.index,
        dtype="object",
    )

    reject_reason = reject_reason.mask(
        df["driver_key"].isna(),
        "driver_id not in dim_driver",
    )

    reject_reason = reject_reason.mask(
        reject_reason.isna()
        & df["passenger_key"].isna(),
        "passenger_id not in dim_passenger",
    )

    reject_reason = reject_reason.mask(
        reject_reason.isna()
        & df["pickup_location_key"].isna(),
        "pickup_location_id not in dim_location",
    )

    reject_reason = reject_reason.mask(
        reject_reason.isna()
        & df["dropoff_location_key"].isna(),
        "dropoff_location_id not in dim_location",
    )

    reject_reason = reject_reason.mask(
        reject_reason.isna()
        & ~df["date_key"].isin(
            lookups["date"].keys()
        ),
        "date_key outside dim_date",
    )

    # NULL payment methods are allowed.
    reject_reason = reject_reason.mask(
        reject_reason.isna()
        & df["payment_method_id"].notna()
        & df["payment_method_key"].isna(),
        "payment_method_id not in dim_payment_method",
    )

    # NULL promo codes are allowed.
    reject_reason = reject_reason.mask(
        reject_reason.isna()
        & df["promo_code_id"].notna()
        & df["promo_code_key"].isna(),
        "promo_code_id not in dim_promo_code",
    )

    valid = reject_reason.isna()

    rejects = df.loc[~valid].copy()
    rejects["reject_reason"] = reject_reason.loc[
        ~valid
    ]

    facts = df.loc[valid].copy()

    # ---------------------------------------------------------
    # Fare calculation
    #
    # Do arithmetic using integer cents to avoid binary
    # floating-point and banker's-rounding differences.
    # ---------------------------------------------------------

    base_cents = np.rint(
        pd.to_numeric(
            facts["base_fare"],
            errors="coerce",
        ).fillna(0)
        * 100
    ).astype("int64")

    tip_cents = np.rint(
        pd.to_numeric(
            facts["tip_amount"],
            errors="coerce",
        ).fillna(0)
        * 100
    ).astype("int64")

    discount_cents = np.rint(
        pd.to_numeric(
            facts["discount_amount"],
            errors="coerce",
        ).fillna(0)
        * 100
    ).astype("int64")

    surge_hundredths = np.rint(
        pd.to_numeric(
            facts["surge_multiplier"],
            errors="coerce",
        ).fillna(0)
        * 100
    ).astype("int64")

    fare_hundredths_of_cent = (
        base_cents * surge_hundredths
        + tip_cents * 100
        - discount_cents * 100
    )

    fare_cents = (
        fare_hundredths_of_cent + 50
    ) // 100

    facts["fare_amount"] = (
        fare_cents / 100.0
    )

    # ---------------------------------------------------------
    # Duration
    # ---------------------------------------------------------

    duration = (
        facts["completed_at"]
        - facts["requested_at"]
    ).dt.total_seconds() / 60

    facts["duration_minutes"] = np.where(
        facts["status"].eq("completed"),
        np.round(duration, 1),
        np.nan,
    )

    # ---------------------------------------------------------
    # Final fields
    # ---------------------------------------------------------

    facts["source_trip_id"] = facts["trip_id"]
    facts["trip_status"] = facts["status"]

    fact_columns = [
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

    facts = facts[fact_columns].copy()

    logger.info(
        f"Transformed {len(facts)} rows, "
        f"rejected {len(rejects)}"
    )

    return facts, rejects


# -------------------------------------------------------------
# Assignment rounding explanation
# -------------------------------------------------------------

# np.round(42.10 * 1.25 - 5.00, 2)
# starts mathematically from 47.625.
# NumPy uses round-to-even behaviour, so this becomes 47.62
# rather than PostgreSQL NUMERIC half-up rounding to 47.63.
#
# 93.78 * 1.25 + 11.17 mathematically equals 128.395.
# Python binary floating-point cannot represent many decimal
# fractions exactly, so it may store a nearby value instead.
#
# The vectorized transform avoids this problem by doing the
# fare calculation using integer cents and rounding only once.