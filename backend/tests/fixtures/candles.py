"""Fixture candle data for setup unit tests."""

import pandas as pd
import numpy as np


def _base_df(n: int = 80, start_price: float = 24000.0) -> pd.DataFrame:
    ts = pd.date_range("2026-01-02 09:15", periods=n, freq="5min", tz="Asia/Kolkata")
    close = start_price + np.cumsum(np.random.default_rng(42).normal(0, 5, n))
    high = close + 10
    low = close - 10
    open_ = close - 2
    volume = np.full(n, 1000.0)
    return pd.DataFrame(
        {"timestamp": ts, "open": open_, "high": high, "low": low, "close": close, "volume": volume}
    )


def orb_breakout_bullish_df() -> pd.DataFrame:
    df = _base_df(30, 24000)
    # Opening range bars 0-2: tight range
    df.loc[0:2, "high"] = 24050
    df.loc[0:2, "low"] = 24000
    df.loc[0:2, "close"] = 24030
    df.loc[0:2, "volume"] = 800
    # Breakout bar
    df.loc[29, "close"] = 24080
    df.loc[29, "high"] = 24085
    df.loc[29, "low"] = 24040
    df.loc[29, "volume"] = 2500
    df.loc[28, "close"] = 24045
    return df


def ema_continuation_bullish_df() -> pd.DataFrame:
    df = _base_df(70, 23500)
    # Uptrend
    for i in range(50, 70):
        df.loc[i, "close"] = 24000 + (i - 50) * 8
        df.loc[i, "high"] = df.loc[i, "close"] + 15
        df.loc[i, "low"] = df.loc[i, "close"] - 5
        df.loc[i, "open"] = df.loc[i, "close"] - 3
    # Pullback touch EMA zone on prev bar
    df.loc[68, "low"] = df.loc[68, "close"] - 40
    df.loc[69, "close"] = df.loc[68, "close"] + 20
    df.loc[69, "high"] = df.loc[69, "close"] + 10
    return df


def range_break_bullish_df() -> pd.DataFrame:
    df = _base_df(50, 24500)
    # Consolidation
    for i in range(25, 48):
        df.loc[i, "high"] = 24520
        df.loc[i, "low"] = 24480
        df.loc[i, "close"] = 24500
    # Breakout
    df.loc[49, "close"] = 24550
    df.loc[49, "high"] = 24560
    df.loc[48, "close"] = 24515
    return df
