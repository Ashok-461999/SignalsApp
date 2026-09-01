"""Strategy selection matrix — Section 4."""

from __future__ import annotations

from typing import Any


def select_strategy(
    *,
    direction: str,
    htf_trending: bool,
    has_sweep: bool,
    profile_position: str,
    pcr: float,
    iv_percentile: float,
    near_max_pain: bool,
    gex_regime: str,
    confluence_tier: str,
) -> dict[str, str]:
    if profile_position == "inside_va" and iv_percentile > 65:
        return {
            "name": "Iron Condor",
            "legs": "sell OTM CE + PE, buy further OTM wings",
            "type": "spread",
        }
    if iv_percentile < 20:
        return {"name": "Long Straddle", "legs": "buy ATM CE + PE", "type": "volatility"}
    if near_max_pain:
        return {"name": "Iron Butterfly", "legs": "sell ATM straddle, buy OTM wings", "type": "spread"}
    if gex_regime == "negative" and htf_trending:
        return {
            "name": "Ratio Backspread",
            "legs": "sell 1 ATM, buy 2 OTM",
            "type": "spread",
        }
    if confluence_tier == "A+" and has_sweep and htf_trending:
        leg = "CE" if direction == "bullish" else "PE"
        return {
            "name": f"Directional ATM {leg}",
            "legs": f"buy ATM {leg}",
            "type": "directional",
        }
    if direction == "bullish":
        return {"name": "Bull Call Spread", "legs": "buy ATM CE, sell OTM CE", "type": "spread"}
    return {"name": "Bear Put Spread", "legs": "buy ATM PE, sell OTM PE", "type": "spread"}
