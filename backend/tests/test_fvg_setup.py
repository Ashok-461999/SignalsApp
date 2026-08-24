"""Tests for FVG and liquidity sweep setups."""

import numpy as np
import pandas as pd

from app.signals.fvg import find_fvg_zones, fvg_retest, liquidity_sweep


def _ohlcv_from_closes(close: np.ndarray) -> pd.DataFrame:
    return pd.DataFrame({
        "open": close - 2,
        "high": close + 5,
        "low": close - 5,
        "close": close,
        "volume": np.full(len(close), 1000.0),
    })


def test_find_fvg_zones_detects_bullish_gap():
    close = np.linspace(100, 120, 30)
    df = _ohlcv_from_closes(close)
    # Force bullish FVG at end: candle i-2 high << candle i low
    df.loc[df.index[-1], "low"] = df.iloc[-3]["high"] + 8
    df.loc[df.index[-1], "close"] = df.iloc[-1]["low"] + 2
    zones = find_fvg_zones(df)
    assert any(z.kind == "bullish" for z in zones)


def test_fvg_retest_no_crash_on_short_data():
    df = _ohlcv_from_closes(np.linspace(24000, 24050, 10))
    result = fvg_retest(df)
    assert result.setup_name == "fvg_retest"
    assert result.fired is False


def test_liquidity_sweep_evaluates():
    n = 40
    close = np.full(n, 24500.0)
    df = _ohlcv_from_closes(close)
    result = liquidity_sweep(df)
    assert result.setup_name == "liquidity_sweep"
    assert isinstance(result.fired, bool)
