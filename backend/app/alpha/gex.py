"""Gamma exposure (GEX) from option chain."""

from __future__ import annotations

import math
from typing import Any

from scipy.stats import norm

from app.alpha.greeks import RISK_FREE_RATE


def _gamma_per_contract(spot: float, strike: float, iv: float, dte: int) -> float:
    t = max(dte, 1) / 365.0
    iv = max(iv, 0.05)
    d1 = (math.log(spot / strike) + (RISK_FREE_RATE + 0.5 * iv**2) * t) / (iv * math.sqrt(t))
    return norm.pdf(d1) / (spot * iv * math.sqrt(t)) if spot > 0 else 0.0


def compute_gex(chain: dict[str, Any]) -> dict[str, Any]:
    spot = float(chain.get("spot") or 0)
    dte = int(chain.get("dte") or 7)
    contracts = chain.get("contracts") or []
    if not contracts or spot <= 0:
        return {"zero_gamma_level": None, "by_strike": [], "regime": "unknown"}

    lot = {"NIFTY": 25, "BANKNIFTY": 15, "SENSEX": 10}.get(chain.get("instrument", ""), 25)
    by_strike: dict[float, float] = {}
    for c in contracts:
        g = _gamma_per_contract(spot, c["strike"], c["iv"], dte)
        sign = 1 if c["option_type"] == "CE" else -1
        # Dealers short options → negative gamma exposure for market
        net = -sign * g * c["oi"] * lot * spot * 0.01
        by_strike[c["strike"]] = by_strike.get(c["strike"], 0) + net

    rows = [{"strike": k, "net_gex": round(v, 2)} for k, v in sorted(by_strike.items())]
    zero_level = _zero_gamma(spot, rows)
    atm_row = min(rows, key=lambda r: abs(r["strike"] - spot), default={"net_gex": 0})
    regime = "positive" if atm_row["net_gex"] > 0 else "negative" if atm_row["net_gex"] < 0 else "neutral"
    return {
        "zero_gamma_level": zero_level,
        "by_strike": rows[:25],
        "net_gex_at_spot": atm_row["net_gex"],
        "regime": regime,
        "implication": (
            "Pinning expected — magnetic strike"
            if regime == "positive"
            else "Trend acceleration possible"
            if regime == "negative"
            else "Neutral"
        ),
    }


def _zero_gamma(spot: float, rows: list[dict]) -> float | None:
    if len(rows) < 2:
        return None
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        if a["net_gex"] * b["net_gex"] <= 0:
            return round((a["strike"] + b["strike"]) / 2, 2)
    return round(spot, 2)
