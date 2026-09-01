"""PCR, OI walls, max pain, IV skew from option chain."""

from __future__ import annotations

from typing import Any


def chain_analytics(chain: dict[str, Any]) -> dict[str, Any]:
    contracts = chain.get("contracts") or []
    if not contracts:
        return {"error": "empty chain"}

    call_oi = sum(c["oi"] for c in contracts if c["option_type"] == "CE")
    put_oi = sum(c["oi"] for c in contracts if c["option_type"] == "PE")
    pcr = round(put_oi / call_oi, 3) if call_oi > 0 else 0.0

    call_wall = max((c for c in contracts if c["option_type"] == "CE"), key=lambda x: x["oi"], default=None)
    put_wall = max((c for c in contracts if c["option_type"] == "PE"), key=lambda x: x["oi"], default=None)

    max_pain = _max_pain(contracts)
    spot = float(chain.get("spot") or 0)
    mp_dist_pct = round(abs(spot - max_pain) / spot * 100, 2) if spot > 0 and max_pain else 0

    ivs = [c["iv"] for c in contracts if c.get("iv")]
    iv_avg = sum(ivs) / len(ivs) if ivs else 0.16
    otm_puts = [c for c in contracts if c["option_type"] == "PE" and c["strike"] < spot]
    otm_calls = [c for c in contracts if c["option_type"] == "CE" and c["strike"] > spot]
    put_iv = sum(c["iv"] for c in otm_puts) / len(otm_puts) if otm_puts else iv_avg
    call_iv = sum(c["iv"] for c in otm_calls) / len(otm_calls) if otm_calls else iv_avg
    iv_skew = round(put_iv - call_iv, 4)

    pcr_label = _pcr_label(pcr)
    return {
        "pcr": pcr,
        "pcr_label": pcr_label,
        "total_call_oi": call_oi,
        "total_put_oi": put_oi,
        "call_wall_strike": call_wall["strike"] if call_wall else None,
        "call_wall_oi": call_wall["oi"] if call_wall else 0,
        "put_wall_strike": put_wall["strike"] if put_wall else None,
        "put_wall_oi": put_wall["oi"] if put_wall else 0,
        "max_pain": max_pain,
        "max_pain_distance_pct": mp_dist_pct,
        "iv_percentile_proxy": round(min(99, max(5, iv_avg / 0.20 * 50)), 1),
        "iv_skew": iv_skew,
        "iv_regime": _iv_regime(iv_avg),
    }


def _pcr_label(pcr: float) -> str:
    from app.alpha.constants import PCR_EXTREME_HIGH, PCR_EXTREME_LOW, PCR_NEUTRAL_HIGH, PCR_NEUTRAL_LOW

    if pcr < PCR_EXTREME_LOW:
        return "Extreme Bullish (contrarian bearish)"
    if pcr > PCR_EXTREME_HIGH:
        return "Extreme Bearish (contrarian bullish)"
    if PCR_NEUTRAL_LOW <= pcr <= PCR_NEUTRAL_HIGH:
        return "Neutral"
    if pcr < 1.0:
        return "Directional Bullish"
    return "Directional Bearish"


def _iv_regime(iv: float) -> str:
    pct = iv / 0.20 * 50
    if pct < 20:
        return "Cheap"
    if pct > 80:
        return "Expensive"
    return "Fair"


def _max_pain(contracts: list[dict]) -> float:
    strikes = sorted({c["strike"] for c in contracts})
    if not strikes:
        return 0.0
    ce_by_k = {c["strike"]: c["oi"] for c in contracts if c["option_type"] == "CE"}
    pe_by_k = {c["strike"]: c["oi"] for c in contracts if c["option_type"] == "PE"}
    best_k, best_pain = strikes[0], float("inf")
    for s in strikes:
        pain = 0.0
        for k, oi in ce_by_k.items():
            pain += max(0, s - k) * oi
        for k, oi in pe_by_k.items():
            pain += max(0, k - s) * oi
        if pain < best_pain:
            best_pain = pain
            best_k = s
    return float(best_k)
