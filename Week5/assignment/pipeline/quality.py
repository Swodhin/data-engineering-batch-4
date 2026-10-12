import logging

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


class DataQualityError(Exception):
    pass


"""
Bugs in the original class quality.py:

1. The result dictionaries were inconsistent:
   some checks returned "details" while others returned "detail".
   run_quality_check() later accessed "details", so a failing check
   could raise KeyError instead of DataQualityError.

2. check_row_count() failed on an empty batch.
   An empty incremental batch is valid when no new trips arrived,
   so row_count should report the count but never fail.
"""


def check_row_count(facts: pd.DataFrame) -> dict:
    count = len(facts)

    return {
        "check": "row_count",
        "passed": True,
        "detail": f"{count} rows in batch",
    }


def check_no_negative_fare(facts: pd.DataFrame) -> dict:
    bad = int(facts["fare_amount"].lt(0).sum())

    return {
        "check": "no_negative_fare",
        "passed": bool(bad == 0),
        "detail": f"{bad} rows with fare_amount < 0",
    }


def check_no_null_required_keys(facts: pd.DataFrame) -> dict:
    required = [
        "driver_key",
        "passenger_key",
        "pickup_location_key",
        "dropoff_location_key",
        "date_key",
    ]

    bad = int(
        facts[required]
        .isna()
        .any(axis=1)
        .sum()
    )

    return {
        "check": "no_null_required_keys",
        "passed": bool(bad == 0),
        "detail": f"{bad} rows with NULL required keys",
    }


def check_completed_have_duration(facts: pd.DataFrame) -> dict:
    bad = int(
        (
            facts["trip_status"].eq("completed")
            & facts["duration_minutes"].isna()
        ).sum()
    )

    return {
        "check": "completed_have_duration",
        "passed": bool(bad == 0),
        "detail": f"{bad} completed trips with NULL duration_minutes",
    }


def check_valid_status(facts: pd.DataFrame) -> dict:
    valid = {"completed", "cancelled", "no_show"}

    bad = int(
        (~facts["trip_status"].isin(valid)).sum()
    )

    return {
        "check": "valid_status",
        "passed": bool(bad == 0),
        "detail": f"{bad} rows with invalid trip_status",
    }


def check_unique_source_trip_id(facts: pd.DataFrame) -> dict:
    bad = int(
        facts["source_trip_id"]
        .duplicated(keep=False)
        .sum()
    )

    return {
        "check": "unique_source_trip_id",
        "passed": bool(bad == 0),
        "detail": f"{bad} rows with duplicate source_trip_id",
    }


def check_fare_formula(facts: pd.DataFrame) -> dict:
    base_cents = np.rint(
        pd.to_numeric(
            facts["base_fare"],
            errors="coerce",
        ).fillna(0) * 100
    ).astype("int64")

    tip_cents = np.rint(
        pd.to_numeric(
            facts["tip_amount"],
            errors="coerce",
        ).fillna(0) * 100
    ).astype("int64")

    discount_cents = np.rint(
        pd.to_numeric(
            facts["discount_amount"],
            errors="coerce",
        ).fillna(0) * 100
    ).astype("int64")

    surge_hundredths = np.rint(
        pd.to_numeric(
            facts["surge_multiplier"],
            errors="coerce",
        ).fillna(0) * 100
    ).astype("int64")

    expected_cents = (
        base_cents * surge_hundredths
        + tip_cents * 100
        - discount_cents * 100
        + 50
    ) // 100

    actual_cents = np.rint(
        pd.to_numeric(
            facts["fare_amount"],
            errors="coerce",
        ).fillna(0) * 100
    ).astype("int64")

    bad = int(
        (actual_cents != expected_cents).sum()
    )

    return {
        "check": "fare_formula",
        "passed": bool(bad == 0),
        "detail": f"{bad} rows with incorrect fare_amount",
    }


def check_cancellation_consistent(facts: pd.DataFrame) -> dict:
    cancelled_missing = (
        facts["trip_status"].eq("cancelled")
        & facts["cancelled_by"].isna()
    )

    non_cancelled_has_value = (
        ~facts["trip_status"].eq("cancelled")
        & facts["cancelled_by"].notna()
    )

    bad = int(
        (cancelled_missing | non_cancelled_has_value).sum()
    )

    return {
        "check": "cancellation_consistent",
        "passed": bool(bad == 0),
        "detail": f"{bad} rows with inconsistent cancellation data",
    }


def check_reject_rate(
    facts: pd.DataFrame,
    rejects: pd.DataFrame | None = None,
) -> dict:
    reject_count = 0 if rejects is None else len(rejects)
    total = len(facts) + reject_count

    rate = 0 if total == 0 else reject_count / total

    return {
        "check": "reject_rate",
        "passed": bool(rate <= 0.01),
        "detail": (
            f"{reject_count} rejects out of {total} rows "
            f"({rate:.2%})"
        ),
    }


def run_quality_checks(
    facts: pd.DataFrame,
    rejects: pd.DataFrame | None = None,
):
    checks = [
        check_row_count(facts),
        check_no_negative_fare(facts),
        check_no_null_required_keys(facts),
        check_completed_have_duration(facts),
        check_valid_status(facts),
        check_unique_source_trip_id(facts),
        check_fare_formula(facts),
        check_cancellation_consistent(facts),
        check_reject_rate(facts, rejects),
    ]

    for result in checks:
        status = "PASS" if result["passed"] else "FAIL"

        logger.info(
            f"{status} {result['check']}: {result['detail']}"
        )

    failed = [
        result["check"]
        for result in checks
        if not result["passed"]
    ]

    if failed:
        raise DataQualityError(
            "Quality checks failed: " + ", ".join(failed)
        )

    return checks