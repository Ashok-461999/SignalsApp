"""Market regime detection — ADX, ATR, IV drive setup selection."""

from dataclasses import dataclass
from enum import Enum

import pandas as pd

from app.signals.indicators import add_standard_indicators, atr


class Regime(str, Enum):
    TRENDING = "trending"
    RANGING = "ranging"
    VOLATILE = "volatile"


# Which regimes each setup is valid for (option buyer, directional)
SETUP_REGIME_MAP: dict[str, set[Regime]] = {
    "orb_breakout": {Regime.TRENDING, Regime.VOLATILE},
    "ema_trend_continuation": {Regime.TRENDING},
    "vwap_trend": {Regime.TRENDING},
    "range_break": {Regime.VOLATILE},  # breakout from compression, not chop
}

SETUP_DESCRIPTIONS: dict[str, str] = {
    "orb_breakout": "Opening range breakout — first 15–30 min, volume confirm, trend direction",
    "ema_trend_continuation": "EMA20 pullback in established trend — tight stop, high R:R",
    "vwap_trend": "Pullback to VWAP in intraday trend — institutional reference level",
    "range_break": "Volatility expansion breakout — size down, wide stops, IV-aware",
}


@dataclass
class RegimeSnapshot:
    regime: Regime
    adx: float
    atr_percentile: float
    trend_direction: str  # bullish | bearish | neutral
    summary: str


def adx(df: pd.DataFrame, length: int = 14) -> pd.Series:
    import pandas_ta as ta

    d = df
    result = ta.adx(d["high"], d["low"], d["close"], length=length)
    if result is None or result.empty:
        return pd.Series(dtype=float)
    col = [c for c in result.columns if c.startswith("ADX")][0]
    return result[col]


def detect_regime(df: pd.DataFrame, iv_percentile: float = 50.0) -> RegimeSnapshot:
    d = add_standard_indicators(df)
    adx_series = adx(d)
    adx_val = float(adx_series.iloc[-1]) if len(adx_series) and not pd.isna(adx_series.iloc[-1]) else 20.0

    atr_series = atr(d, 14)
    atr_hist = atr_series.dropna().tail(60)
    current_atr = float(atr_series.iloc[-1]) if not pd.isna(atr_series.iloc[-1]) else 0.0
    if len(atr_hist) >= 10:
        atr_pct = float((atr_hist < current_atr).sum() / len(atr_hist) * 100)
    else:
        atr_pct = 50.0

    bar = d.iloc[-1]
    if bar["ema_20"] > bar["ema_50"] * 1.001:
        trend_dir = "bullish"
    elif bar["ema_20"] < bar["ema_50"] * 0.999:
        trend_dir = "bearish"
    else:
        trend_dir = "neutral"

    # Regime priority: extreme IV/ATR → volatile; ADX high → trending; ADX low → ranging
    if iv_percentile >= 75 or atr_pct >= 75:
        regime = Regime.VOLATILE
        summary = "Elevated volatility — size down, IV-aware entries only"
    elif adx_val >= 25:
        regime = Regime.TRENDING
        summary = f"Trending market (ADX {adx_val:.0f}) — directional buying favoured"
    elif adx_val < 20:
        regime = Regime.RANGING
        summary = f"Ranging/choppy (ADX {adx_val:.0f}) — sit out option buys, theta wins"
    else:
        regime = Regime.VOLATILE
        summary = f"Transitional (ADX {adx_val:.0f}) — trade only A+ setups"

    return RegimeSnapshot(
        regime=regime,
        adx=round(adx_val, 1),
        atr_percentile=round(atr_pct, 1),
        trend_direction=trend_dir,
        summary=summary,
    )


def setup_allowed_in_regime(setup_name: str, regime: Regime) -> bool:
    allowed = SETUP_REGIME_MAP.get(setup_name, set())
    return regime in allowed
