"""Tests for market session helpers."""

from datetime import datetime
from zoneinfo import ZoneInfo

from app.services.market_session import _next_bar_boundary, market_phase

IST = ZoneInfo("Asia/Kolkata")


def test_market_phase_open():
    dt = datetime(2026, 8, 24, 10, 30, tzinfo=IST)  # Monday
    assert market_phase(dt) == "market_open"


def test_market_phase_weekend():
    dt = datetime(2026, 8, 23, 10, 0, tzinfo=IST)  # Sunday
    assert market_phase(dt) == "weekend"


def test_next_bar_during_session():
    dt = datetime(2026, 8, 24, 9, 17, tzinfo=IST)
    nxt = _next_bar_boundary(dt)
    assert nxt.hour == 9 and nxt.minute == 20
