"""Market regime detection — ADX, ATR, structure (no lagging EMA for trend)."""

from dataclasses import dataclass
from enum import Enum

import pandas as pd

from app.signals.indicators import add_standard_indicators, atr


class Regime(str, Enum):
    TRENDING = "trending"
    RANGING = "ranging"
    VOLATILE = "volatile"


# Modern setups — FVG/SMC first, EMA removed from live scanner
SETUP_REGIME_MAP: dict[str, set[Regime]] = {
    "fvg_retest": {Regime.TRENDING, Regime.VOLATILE},
    "liquidity_sweep": {Regime.TRENDING, Regime.VOLATILE, Regime.RANGING},
    "orb_breakout": {Regime.TRENDING, Regime.VOLATILE},
    "vwap_trend": {Regime.TRENDING},
    "range_break": {Regime.VOLATILE},
}

SETUP_DESCRIPTIONS: dict[str, str] = {
    "fvg_retest": "Fair Value Gap retest — price fills imbalance zone and rejects (SMC/ICT)",
    "liquidity_sweep": "Liquidity sweep — stop hunt above/below swing then reversal",
    "orb_breakout": "Opening range breakout — first 15 min, volume confirm",
    "vwap_trend": "VWAP reclaim or rejection — institutional reference, no EMA lag",
    "range_break": "Volatility expansion breakout — size down, IV-aware",
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


def _structure_trend(d: pd.DataFrame) -> str:
    """Higher-high / lower-low structure instead of EMA crossover."""
    if len(d) < 10:
        return "neutral"
    recent = d.tail(8)
    highs = recent["high"].values
    lows = recent["low"].values
    hh = highs[-1] > highs[-4] and highs[-4] > highs[0]
    ll = lows[-1] < lows[-4] and lows[-4] < lows[0]
    if hh and not ll:
        return "bullish"
    if ll and not hh:
        return "bearish"
    return "neutral"


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

    trend_dir = _structure_trend(d)

    if iv_percentile >= 75 or atr_pct >= 75:
        regime = Regime.VOLATILE
        summary = "Elevated volatility — FVG + sweep setups only, size down"
    elif adx_val >= 25:
        regime = Regime.TRENDING
        summary = f"Trending (ADX {adx_val:.0f}) — FVG retest + ORB favoured"
    elif adx_val < 20:
        regime = Regime.RANGING
        summary = f"Ranging/choppy (ADX {adx_val:.0f}) — sit out option buys, theta wins"
    else:
        regime = Regime.VOLATILE
        summary = f"Transitional (ADX {adx_val:.0f}) — news + FVG A+ only"

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
