"""
Unit tests for pipeline/quality.py — Week 5 Assignment, Part 2.

Four example tests are written for you. Add the rest: every check gets one test
where it passes and one where it fails, and the failing test breaks ONE thing in
good_facts.

Run from Week5/assignment/:
    pytest -v
"""

import pytest

import quality
from quality import DataQualityError, run_quality_checks

REQUIRED_KEYS = {"check", "passed", "detail"}


# ── Examples (provided) ──────────────────────────────────────────────────────

def test_good_batch_passes_every_check(good_facts):
    results = run_quality_checks(good_facts)
    failed = [r["check"] for r in results if not r["passed"]]
    assert failed == []


def test_every_check_returns_the_same_keys(good_facts):
    # In the class quality.py some checks returned "details" and others "detail".
    # This test stops that from coming back.
    for result in run_quality_checks(good_facts):
        assert set(result) == REQUIRED_KEYS, result["check"]


def test_negative_fare_fails(good_facts):
    bad = good_facts.copy()
    bad.loc[0, "fare_amount"] = -1.00
    result = quality.check_no_negative_fare(bad)
    assert result["passed"] is False


def test_run_reports_every_failure_not_just_the_first(good_facts):
    bad = good_facts.copy()
    bad.loc[0, "fare_amount"] = -1.00                 # breaks no_negative_fare
    bad.loc[1, "trip_status"] = "Completed "          # breaks valid_status
    with pytest.raises(DataQualityError) as exc:
        run_quality_checks(bad)
    assert "no_negative_fare" in str(exc.value)
    assert "valid_status" in str(exc.value)


# ── Your tests ───────────────────────────────────────────────────────────────
# TODO: one passing and one failing test per check, plus:
#   - an empty batch (empty_facts fixture) does not raise
#   - fare_formula fails on a fare rounded the wrong way (47.62 instead of 47.63)

def test_row_count_passes(good_facts):
    result = quality.check_row_count(good_facts)
    assert result["passed"] is True


def test_empty_batch_passes(empty_facts):
    results = run_quality_checks(empty_facts)
    assert all(r["passed"] for r in results)


def test_negative_fare_passes(good_facts):
    result = quality.check_no_negative_fare(good_facts)
    assert result["passed"] is True


def test_null_required_keys_passes(good_facts):
    result = quality.check_no_null_required_keys(good_facts)
    assert result["passed"] is True


def test_null_required_key_fails(good_facts):
    bad = good_facts.copy()
    bad.loc[0, "driver_key"] = None

    result = quality.check_no_null_required_keys(bad)

    assert result["passed"] is False


def test_completed_have_duration_passes(good_facts):
    result = quality.check_completed_have_duration(good_facts)
    assert result["passed"] is True


def test_completed_without_duration_fails(good_facts):
    bad = good_facts.copy()
    bad.loc[0, "duration_minutes"] = None

    result = quality.check_completed_have_duration(bad)

    assert result["passed"] is False


def test_valid_status_passes(good_facts):
    result = quality.check_valid_status(good_facts)
    assert result["passed"] is True


def test_invalid_status_fails(good_facts):
    bad = good_facts.copy()
    bad.loc[0, "trip_status"] = "invalid"

    result = quality.check_valid_status(bad)

    assert result["passed"] is False


def test_unique_source_trip_id_passes(good_facts):
    result = quality.check_unique_source_trip_id(good_facts)
    assert result["passed"] is True


def test_duplicate_source_trip_id_fails(good_facts):
    bad = good_facts.copy()
    bad.loc[1, "source_trip_id"] = bad.loc[0, "source_trip_id"]

    result = quality.check_unique_source_trip_id(bad)

    assert result["passed"] is False


def test_fare_formula_passes(good_facts):
    result = quality.check_fare_formula(good_facts)
    assert result["passed"] is True


def test_fare_formula_wrong_rounding_fails(good_facts):
    bad = good_facts.copy()

    # Correct half-up value is 47.63.
    # 47.62 represents the wrong round-to-even result.
    bad.loc[1, "fare_amount"] = 47.62

    result = quality.check_fare_formula(bad)

    assert result["passed"] is False


def test_cancellation_consistent_passes(good_facts):
    result = quality.check_cancellation_consistent(good_facts)
    assert result["passed"] is True


def test_cancelled_without_cancelled_by_fails(good_facts):
    bad = good_facts.copy()
    bad.loc[2, "cancelled_by"] = None

    result = quality.check_cancellation_consistent(bad)

    assert result["passed"] is False


def test_reject_rate_passes(good_facts):
    rejects = good_facts.iloc[0:0].copy()

    result = quality.check_reject_rate(
        good_facts,
        rejects,
    )

    assert result["passed"] is True


def test_reject_rate_fails(good_facts):
    rejects = good_facts.iloc[[0]].copy()

    result = quality.check_reject_rate(
        good_facts,
        rejects,
    )

    assert result["passed"] is False