"""Market Profile — POC, VAH, VAL from session volume."""

from __future__ import annotations

from typing import Any

import pandas as pd


def compute_market_profile(df: pd.DataFrame, value_area_pct: float = 0.70) -> dict[str, Any]:
    """Volume profile from 1m/5m OHLCV for current session."""
    if df is None or len(df) < 20:
        return {"poc": 0, "vah": 0, "val": 0, "position": "unknown"}

    d = df.copy()
    if "timestamp" in d.columns:
        d = d.sort_values("timestamp")

    # Price bins from session range
    low, high = float(d["low"].min()), float(d["high"].max())
    if high <= low:
        mid = float(d["close"].iloc[-1])
        return {"poc": mid, "vah": mid, "val": mid, "position": "inside_va"}

    bins = max(20, min(50, int((high - low) / max(1, (high - low) / 40))))
    step = (high - low) / bins
    vol_by_price: dict[float, float] = {}
    for _, row in d.iterrows():
        typical = (float(row["high"]) + float(row["low"]) + float(row["close"])) / 3
        bucket = low + round((typical - low) / step) * step
        vol_by_price[bucket] = vol_by_price.get(bucket, 0) + float(row["volume"] or 0)

    if not vol_by_price:
        mid = float(d["close"].iloc[-1])
        return {"poc": mid, "vah": mid, "val": mid, "position": "inside_va"}

    poc = max(vol_by_price, key=vol_by_price.get)
    total_vol = sum(vol_by_price.values())
    target = total_vol * value_area_pct
    sorted_levels = sorted(vol_by_price.items(), key=lambda x: x[1], reverse=True)
    cum = 0.0
    va_levels: list[float] = []
    for price, vol in sorted_levels:
        cum += vol
        va_levels.append(price)
        if cum >= target:
            break
    vah, val = max(va_levels), min(va_levels)
    spot = float(d["close"].iloc[-1])

    if spot > vah:
        position = "above_vah"
    elif spot < val:
        position = "below_val"
    else:
        position = "inside_va"

    return {
        "poc": round(poc, 2),
        "vah": round(vah, 2),
        "val": round(val, 2),
        "position": position,
        "position_label": {
            "above_vah": "Above VAH — premium zone",
            "below_val": "Below VAL — discount zone",
            "inside_va": "Inside VA — chop, no directional edge",
        }.get(position, position),
    }
