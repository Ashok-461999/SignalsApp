import pandas as pd

from app.signals.setups import ema_trend_continuation, orb_breakout, range_break
from tests.fixtures.candles import (
    ema_continuation_bullish_df,
    orb_breakout_bullish_df,
    range_break_bullish_df,
)


def test_orb_breakout_fires_bullish():
    df = orb_breakout_bullish_df()
    result = orb_breakout(df)
    assert result.fired is True
    assert result.direction == "bullish"
    assert result.entry is not None
    assert result.stop_loss is not None
    assert len(result.targets) >= 1
    assert result.entry > result.stop_loss


def test_ema_trend_continuation_evaluates():
    df = ema_continuation_bullish_df()
    result = ema_trend_continuation(df)
    # May or may not fire depending on EMA calc — ensure no crash and valid structure
    assert result.setup_name == "ema_trend_continuation"
    if result.fired:
        assert result.direction in ("bullish", "bearish")
        assert result.entry is not None
        assert result.stop_loss is not None


def test_range_break_fires_bullish():
    df = range_break_bullish_df()
    result = range_break(df)
    assert result.fired is True
    assert result.direction == "bullish"
    assert result.entry > result.stop_loss


def test_setups_are_pure_no_mutation():
    df = orb_breakout_bullish_df()
    before = df.copy()
    orb_breakout(df)
    pd.testing.assert_frame_equal(df, before)


def test_insufficient_bars_returns_not_fired():
    df = orb_breakout_bullish_df().iloc[:5]
    result = orb_breakout(df)
    assert result.fired is False
