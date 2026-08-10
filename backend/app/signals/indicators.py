"""pandas-ta wrappers — all indicators computed on underlying OHLCV only."""

import pandas as pd
import pandas_ta as ta


def ensure_ohlcv(df: pd.DataFrame) -> pd.DataFrame:
    required = {"open", "high", "low", "close", "volume"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"DataFrame missing columns: {missing}")
    out = df.copy()
    for col in required:
        out[col] = pd.to_numeric(out[col], errors="coerce")
    return out.dropna(subset=["open", "high", "low", "close"])


def ema(df: pd.DataFrame, length: int = 20) -> pd.Series:
    return ta.ema(ensure_ohlcv(df)["close"], length=length)


def rsi(df: pd.DataFrame, length: int = 14) -> pd.Series:
    return ta.rsi(ensure_ohlcv(df)["close"], length=length)


def atr(df: pd.DataFrame, length: int = 14) -> pd.Series:
    d = ensure_ohlcv(df)
    return ta.atr(d["high"], d["low"], d["close"], length=length)


def vwap(df: pd.DataFrame) -> pd.Series:
    d = ensure_ohlcv(df)
    return ta.vwap(d["high"], d["low"], d["close"], d["volume"])


def supertrend(df: pd.DataFrame, length: int = 10, multiplier: float = 3.0) -> pd.DataFrame:
    d = ensure_ohlcv(df)
    st = ta.supertrend(d["high"], d["low"], d["close"], length=length, multiplier=multiplier)
    if st is None or st.empty:
        return pd.DataFrame(index=d.index)
    return st


def bollinger(df: pd.DataFrame, length: int = 20, std: float = 2.0) -> pd.DataFrame:
    d = ensure_ohlcv(df)
    bb = ta.bbands(d["close"], length=length, std=std)
    if bb is None or bb.empty:
        return pd.DataFrame(index=d.index)
    return bb


def add_standard_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Attach commonly used columns for setups (no indicator soup — explicit adds only)."""
    d = ensure_ohlcv(df)
    d = d.copy()
    d["ema_20"] = ema(d, 20)
    d["ema_50"] = ema(d, 50)
    d["rsi_14"] = rsi(d, 14)
    d["atr_14"] = atr(d, 14)
    d["vwap"] = vwap(d)
    st = supertrend(d)
    if not st.empty:
        for col in st.columns:
            d[col] = st[col]
    bb = bollinger(d)
    if not bb.empty:
        for col in bb.columns:
            d[col] = bb[col]
    d["vol_sma_20"] = d["volume"].rolling(20, min_periods=5).mean()
    return d
