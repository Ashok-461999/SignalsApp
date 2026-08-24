"""Isolated setup functions — pure, no shared state, underlying-only logic."""

import pandas as pd

from app.signals.fvg import fvg_retest, liquidity_sweep
from app.signals.indicators import add_standard_indicators, ensure_ohlcv
from app.signals.schemas import SetupResult

ORB_BARS = 3  # 15 min opening range on 5m candles
RANGE_LOOKBACK = 20
CONSOLIDATION_ATR_MULT = 1.5


def _latest_bar(df: pd.DataFrame) -> pd.Series:
    return df.iloc[-1]


def _targets_from_r(entry: float, stop: float, r_multiples: tuple[float, ...] = (2.0, 3.0)) -> list[float]:
    risk = abs(entry - stop)
    if risk <= 0:
        return []
    sign = 1 if entry > stop else -1
    return [entry + sign * risk * m for m in r_multiples]


def orb_breakout(df: pd.DataFrame, orb_bars: int = ORB_BARS) -> SetupResult:
    """Opening-range breakout with volume confirmation on the underlying."""
    name = "orb_breakout"
    if len(df) < orb_bars + 5:
        return SetupResult(setup_name=name, fired=False, reason="insufficient bars")

    d = add_standard_indicators(ensure_ohlcv(df))
    i = len(d) - 1
    or_slice = d.iloc[:orb_bars]
    or_high = or_slice["high"].max()
    or_low = or_slice["low"].min()
    bar = d.iloc[i]
    prev = d.iloc[i - 1]

    vol_ok = bar["volume"] > bar.get("vol_sma_20", bar["volume"]) * 1.1

    if bar["close"] > or_high and prev["close"] <= or_high and vol_ok:
        entry = float(bar["close"])
        stop = float(or_low)
        return SetupResult(
            setup_name=name,
            fired=True,
            direction="bullish",
            entry=entry,
            stop_loss=stop,
            targets=_targets_from_r(entry, stop),
            reason="break above opening range with volume",
            metadata={"or_high": or_high, "or_low": or_low},
        )

    if bar["close"] < or_low and prev["close"] >= or_low and vol_ok:
        entry = float(bar["close"])
        stop = float(or_high)
        return SetupResult(
            setup_name=name,
            fired=True,
            direction="bearish",
            entry=entry,
            stop_loss=stop,
            targets=_targets_from_r(entry, stop),
            reason="break below opening range with volume",
            metadata={"or_high": or_high, "or_low": or_low},
        )

    return SetupResult(setup_name=name, fired=False, reason="no ORB trigger")


def ema_trend_continuation(df: pd.DataFrame) -> SetupResult:
    """Deprecated — EMA pullbacks disabled in live scanner (low edge in 2025+ markets)."""
    return SetupResult(setup_name="ema_trend_continuation", fired=False, reason="EMA setup disabled — use FVG")


def vwap_trend(df: pd.DataFrame) -> SetupResult:
    """Pullback to VWAP — institutional level, no lagging EMA filter."""
    name = "vwap_trend"
    if len(df) < 30:
        return SetupResult(setup_name=name, fired=False, reason="insufficient bars")

    d = add_standard_indicators(ensure_ohlcv(df))
    i = len(d) - 1
    bar = d.iloc[i]
    prev = d.iloc[i - 1]

    if pd.isna(bar["vwap"]):
        return SetupResult(setup_name=name, fired=False, reason="VWAP not ready")

    vwap_val = float(bar["vwap"])
    touched_vwap = prev["low"] <= prev["vwap"] <= prev["high"] if not pd.isna(prev["vwap"]) else False

    if bar["close"] > vwap_val and touched_vwap and bar["close"] > prev["close"]:
        entry = float(bar["close"])
        stop = float(min(vwap_val, d.iloc[i - 3 : i]["low"].min()))
        return SetupResult(
            setup_name=name,
            fired=True,
            direction="bullish",
            entry=entry,
            stop_loss=stop,
            targets=_targets_from_r(entry, stop),
            reason="bullish VWAP reclaim — institutional level hold",
            metadata={"vwap": vwap_val},
        )

    if bar["close"] < vwap_val and touched_vwap and bar["close"] < prev["close"]:
        entry = float(bar["close"])
        stop = float(max(vwap_val, d.iloc[i - 3 : i]["high"].max()))
        return SetupResult(
            setup_name=name,
            fired=True,
            direction="bearish",
            entry=entry,
            stop_loss=stop,
            targets=_targets_from_r(entry, stop),
            reason="bearish VWAP rejection",
            metadata={"vwap": vwap_val},
        )

    return SetupResult(setup_name=name, fired=False, reason="no VWAP trigger")


def range_break(df: pd.DataFrame, lookback: int = RANGE_LOOKBACK) -> SetupResult:
    """Consolidation range break on the underlying."""
    name = "range_break"
    if len(df) < lookback + 5:
        return SetupResult(setup_name=name, fired=False, reason="insufficient bars")

    d = add_standard_indicators(ensure_ohlcv(df))
    i = len(d) - 1
    window = d.iloc[i - lookback : i]
    bar = d.iloc[i]
    prev = d.iloc[i - 1]

    range_high = window["high"].max()
    range_low = window["low"].min()
    range_width = range_high - range_low
    atr_val = float(bar["atr_14"]) if not pd.isna(bar["atr_14"]) else range_width

    if range_width > CONSOLIDATION_ATR_MULT * atr_val:
        return SetupResult(setup_name=name, fired=False, reason="not consolidating")

    if bar["close"] > range_high and prev["close"] <= range_high:
        entry = float(bar["close"])
        stop = float(range_low)
        height = range_high - range_low
        t1 = entry + height
        t2 = entry + height * 1.5
        return SetupResult(
            setup_name=name,
            fired=True,
            direction="bullish",
            entry=entry,
            stop_loss=stop,
            targets=[t1, t2],
            reason="bullish range break",
            metadata={"range_high": float(range_high), "range_low": float(range_low)},
        )

    if bar["close"] < range_low and prev["close"] >= range_low:
        entry = float(bar["close"])
        stop = float(range_high)
        height = range_high - range_low
        t1 = entry - height
        t2 = entry - height * 1.5
        return SetupResult(
            setup_name=name,
            fired=True,
            direction="bearish",
            entry=entry,
            stop_loss=stop,
            targets=[t1, t2],
            reason="bearish range break",
            metadata={"range_high": float(range_high), "range_low": float(range_low)},
        )

    return SetupResult(setup_name=name, fired=False, reason="no range break")


SETUP_FUNCTIONS = {
    "fvg_retest": fvg_retest,
    "liquidity_sweep": liquidity_sweep,
    "orb_breakout": orb_breakout,
    "vwap_trend": vwap_trend,
    "range_break": range_break,
}
