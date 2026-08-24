"""Fair Value Gap (FVG) detection — ICT/SMC style imbalance zones."""

from __future__ import annotations

from dataclasses import dataclass

import pandas as pd

from app.signals.indicators import ensure_ohlcv
from app.signals.schemas import SetupResult


@dataclass
class FvgZone:
    kind: str  # bullish | bearish
    top: float
    bottom: float
    bar_index: int

    @property
    def mid(self) -> float:
        return (self.top + self.bottom) / 2.0

    @property
    def size(self) -> float:
        return abs(self.top - self.bottom)


def find_fvg_zones(df: pd.DataFrame, lookback: int = 40) -> list[FvgZone]:
    """3-candle FVG: gap between candle[i-2] and candle[i]."""
    d = ensure_ohlcv(df)
    zones: list[FvgZone] = []
    start = max(2, len(d) - lookback)
    for i in range(start, len(d)):
        c0 = d.iloc[i - 2]
        c2 = d.iloc[i]
        if float(c0["high"]) < float(c2["low"]):
            zones.append(
                FvgZone(
                    kind="bullish",
                    top=float(c2["low"]),
                    bottom=float(c0["high"]),
                    bar_index=i,
                )
            )
        if float(c0["low"]) > float(c2["high"]):
            zones.append(
                FvgZone(
                    kind="bearish",
                    top=float(c0["low"]),
                    bottom=float(c2["high"]),
                    bar_index=i,
                )
            )
    return zones


def fvg_retest(df: pd.DataFrame) -> SetupResult:
    """Price retests an open FVG and rejects — modern imbalance entry."""
    name = "fvg_retest"
    if len(df) < 25:
        return SetupResult(setup_name=name, fired=False, reason="insufficient bars")

    d = ensure_ohlcv(df)
    bar = d.iloc[-1]
    prev = d.iloc[-2]
    zones = find_fvg_zones(d)
    if not zones:
        return SetupResult(setup_name=name, fired=False, reason="no FVG zones")

    for zone in reversed(zones[-6:]):
        buf = max(zone.size * 0.15, 2.0)
        if zone.kind == "bullish":
            touched = float(bar["low"]) <= zone.top and float(prev["low"]) <= zone.top
            rejected = float(bar["close"]) > zone.mid and float(bar["close"]) > float(prev["close"])
            if touched and rejected and zone.size >= 3:
                entry = float(bar["close"])
                stop = zone.bottom - buf
                risk = entry - stop
                if risk <= 0:
                    continue
                targets = [entry + risk * 2, entry + risk * 3]
                return SetupResult(
                    setup_name=name,
                    fired=True,
                    direction="bullish",
                    entry=entry,
                    stop_loss=stop,
                    targets=targets,
                    reason="bullish FVG retest — price filled imbalance and rejected higher",
                    metadata={"fvg_top": zone.top, "fvg_bottom": zone.bottom},
                )

        if zone.kind == "bearish":
            touched = float(bar["high"]) >= zone.bottom and float(prev["high"]) >= zone.bottom
            rejected = float(bar["close"]) < zone.mid and float(bar["close"]) < float(prev["close"])
            if touched and rejected and zone.size >= 3:
                entry = float(bar["close"])
                stop = zone.top + buf
                risk = stop - entry
                if risk <= 0:
                    continue
                targets = [entry - risk * 2, entry - risk * 3]
                return SetupResult(
                    setup_name=name,
                    fired=True,
                    direction="bearish",
                    entry=entry,
                    stop_loss=stop,
                    targets=targets,
                    reason="bearish FVG retest — price filled imbalance and rejected lower",
                    metadata={"fvg_top": zone.top, "fvg_bottom": zone.bottom},
                )

    return SetupResult(setup_name=name, fired=False, reason="no FVG retest")


def liquidity_sweep(df: pd.DataFrame, swing: int = 12) -> SetupResult:
    """Sweep prior swing high/low then close back inside — SMC liquidity grab."""
    name = "liquidity_sweep"
    if len(df) < swing + 5:
        return SetupResult(setup_name=name, fired=False, reason="insufficient bars")

    d = ensure_ohlcv(df)
    bar = d.iloc[-1]
    window = d.iloc[-(swing + 1) : -1]
    swing_high = float(window["high"].max())
    swing_low = float(window["low"].min())

    # Bearish sweep: wick above highs, close below swing high
    if float(bar["high"]) > swing_high and float(bar["close"]) < swing_high:
        entry = float(bar["close"])
        stop = float(bar["high"]) + max(swing_high - swing_low, 5) * 0.1
        risk = stop - entry
        if risk > 0:
            return SetupResult(
                setup_name=name,
                fired=True,
                direction="bearish",
                entry=entry,
                stop_loss=stop,
                targets=[entry - risk * 2, entry - risk * 3],
                reason="liquidity sweep above highs — reversal short",
                metadata={"sweep_level": swing_high},
            )

    # Bullish sweep: wick below lows, close above swing low
    if float(bar["low"]) < swing_low and float(bar["close"]) > swing_low:
        entry = float(bar["close"])
        stop = float(bar["low"]) - max(swing_high - swing_low, 5) * 0.1
        risk = entry - stop
        if risk > 0:
            return SetupResult(
                setup_name=name,
                fired=True,
                direction="bullish",
                entry=entry,
                stop_loss=stop,
                targets=[entry + risk * 2, entry + risk * 3],
                reason="liquidity sweep below lows — reversal long",
                metadata={"sweep_level": swing_low},
            )

    return SetupResult(setup_name=name, fired=False, reason="no liquidity sweep")
