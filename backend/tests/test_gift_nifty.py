"""Tests for GIFT Nifty open-bias probability model."""

from app.services.gift_nifty import (
    negative_open_probability,
    positive_open_probability,
    _predicted_open,
    _session_close_label,
)


def test_negative_gift_high_negative_open_probability():
    prob = negative_open_probability(-0.35)
    assert prob >= 74.0
    assert _session_close_label(-0.35) == "negative"
    assert _predicted_open(-0.35) == "negative"


def test_positive_gift_low_negative_open_probability():
    prob = negative_open_probability(0.40)
    assert prob <= 30.0
    assert _session_close_label(0.40) == "positive"
    assert _predicted_open(0.40) == "positive"


def test_flat_gift_neutral_probability():
    assert negative_open_probability(0.02) == 50.0
    assert positive_open_probability(0.02) == 50.0
    assert _session_close_label(0.02) == "flat"


def test_strong_negative_gift_very_high_probability():
    assert negative_open_probability(-0.80) >= 85.0
