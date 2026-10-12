"""
Unit tests for pipeline/transform.py — Week 5 Assignment, Part 2.

transform_trips_df() is a pure function: DataFrame + lookup dicts in, two DataFrames
out. That makes it easy to test without a database. One example is written for you.

Run from Week5/assignment/:
    pytest -v
"""

import pandas as pd
import pytest

from transform import transform_trips_df


@pytest.fixture
def lookups():
    return {
        "driver":         {1: 101, 2: 102},
        "passenger":      {7: 207},
        "location":       {3: 303, 4: 304},
        "payment_method": {1: 401},
        "promo_code":     {9: 509},
        "date":           {20250314: True},
    }


@pytest.fixture
def one_trip():
    """One valid completed source trip, shaped like the extract query's output."""
    return pd.DataFrame({
        "trip_id":             [1],
        "driver_id":           [1],
        "passenger_id":        [7],
        "pickup_location_id":  [3],
        "dropoff_location_id": [4],
        "payment_method_id":   [1.0],          # float: pd.read_sql gives float64 for a nullable int column
        "promo_code_id":       [float("nan")],
        "base_fare":           [42.10],
        "tip_amount":          [0.00],
        "discount_amount":     [5.00],
        "surge_multiplier":    [1.25],
        "distance_km":         [21.85],
        "status":              ["completed"],
        "requested_at":        pd.to_datetime(["2025-03-14 14:37:00"]),
        "completed_at":        pd.to_datetime(["2025-03-14 15:29:00"]),
        "driver_rating":       [4.5],
        "passenger_rating":    [5.0],
        "cancelled_by":        [None],
    })


# ── Example (provided) ───────────────────────────────────────────────────────

def test_fare_rounds_half_up(one_trip, lookups):
    # 42.10 * 1.25 + 0.00 - 5.00 = 47.625 exactly. Postgres ROUND (and v_trips) gives 47.63.
    facts, rejects = transform_trips_df(one_trip, lookups)
    assert len(rejects) == 0
    assert facts.loc[0, "fare_amount"] == pytest.approx(47.63, abs=1e-9)


# ── Your tests ───────────────────────────────────────────────────────────────
# TODO: at least these:
#   - time_key: 14:37 -> 1430, 00:00 -> 0, 23:59:59 -> 2345
#   - an unknown driver_id goes to rejects, not to facts
#   - a NULL promo_code_id is NOT a reject
#   - duration_minutes is NULL for a cancelled trip

def test_time_key_1437(one_trip, lookups):
    facts, rejects = transform_trips_df(one_trip, lookups)

    assert len(rejects) == 0
    assert facts.loc[0, "time_key"] == 1430


def test_time_key_midnight(one_trip, lookups):
    trip = one_trip.copy()
    trip.loc[0, "requested_at"] = pd.Timestamp("2025-03-14 00:00:00")

    facts, rejects = transform_trips_df(trip, lookups)

    assert len(rejects) == 0
    assert facts.loc[0, "time_key"] == 0


def test_time_key_235959(one_trip, lookups):
    trip = one_trip.copy()
    trip.loc[0, "requested_at"] = pd.Timestamp("2025-03-14 23:59:59")

    facts, rejects = transform_trips_df(trip, lookups)

    assert len(rejects) == 0
    assert facts.loc[0, "time_key"] == 2345


def test_unknown_driver_goes_to_rejects(one_trip, lookups):
    trip = one_trip.copy()
    trip.loc[0, "driver_id"] = 999

    facts, rejects = transform_trips_df(trip, lookups)

    assert len(facts) == 0
    assert len(rejects) == 1
    assert rejects.iloc[0]["reject_reason"] == "driver_id not in dim_driver"


def test_null_promo_code_is_not_rejected(one_trip, lookups):
    facts, rejects = transform_trips_df(one_trip, lookups)

    assert len(rejects) == 0
    assert len(facts) == 1
    assert pd.isna(facts.loc[0, "promo_code_key"])


def test_cancelled_trip_has_null_duration(one_trip, lookups):
    trip = one_trip.copy()

    trip.loc[0, "status"] = "cancelled"
    trip.loc[0, "completed_at"] = pd.NaT
    trip.loc[0, "cancelled_by"] = "passenger"

    facts, rejects = transform_trips_df(trip, lookups)

    assert len(rejects) == 0
    assert pd.isna(facts.loc[0, "duration_minutes"])

def test_fare_rounding_trip_37(one_trip, lookups):
    trip = one_trip.copy()

    trip.loc[0, "base_fare"] = 93.78
    trip.loc[0, "surge_multiplier"] = 1.25
    trip.loc[0, "tip_amount"] = 11.17
    trip.loc[0, "discount_amount"] = 0.00

    # Exact decimal result:
    # 93.78 * 1.25 + 11.17 = 128.395
    # PostgreSQL half-up rounding -> 128.40
    facts, rejects = transform_trips_df(trip, lookups)

    assert len(rejects) == 0
    assert facts.loc[0, "fare_amount"] == pytest.approx(128.40, abs=1e-9)