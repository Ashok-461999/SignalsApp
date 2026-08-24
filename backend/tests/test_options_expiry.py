from datetime import date

from app.backtest.options import days_until_expiry, nearest_expiry_min_days


def test_nearest_expiry_at_least_20_days():
    # Tuesday 2026-08-18 — next Tuesday with 20+ DTE is 2026-09-09 (22 days)
    ref = date(2026, 8, 18)
    expiry = nearest_expiry_min_days(from_date=ref, min_days=20, expiry_weekday=1)
    assert (expiry - ref).days >= 20
    assert expiry.weekday() == 1


def test_days_until_expiry_minimum_one():
    assert days_until_expiry(date.today(), date.today()) == 1
