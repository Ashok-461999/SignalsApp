"""Sector rotation heat map (Section 2F)."""

from __future__ import annotations

from typing import Any


SECTOR_PROXY: dict[str, str] = {
    "Bank": "BANKNIFTY",
    "IT": "NIFTY",
    "Auto": "NIFTY",
    "Pharma": "NIFTY",
    "FMCG": "NIFTY",
    "Metal": "NIFTY",
    "Energy": "NIFTY",
    "Realty": "NIFTY",
    "Infra": "NIFTY",
}


def sector_points(instrument: str, direction: str, instruments_data: dict[str, dict]) -> tuple[int, dict[str, Any]]:
    """Score sector alignment for index instruments."""
    sector = {"BANKNIFTY": "Bank", "NIFTY": "Index", "SENSEX": "Index"}.get(instrument, "Index")
    proxy = instruments_data.get(instrument) or {}
    trend = proxy.get("htf_bias", "neutral")
    chain = proxy.get("chain_analytics") or {}
    pcr = float(chain.get("pcr") or 1)

    if trend == direction and trend in ("bullish", "bearish"):
        pts = 10
        flow = "Inflow"
        preferred = "CALLS" if direction == "bullish" else "PUTS"
    elif trend == "neutral":
        pts = 5
        flow = "Neutral"
        preferred = "SPREADS"
    else:
        pts = 0
        flow = "Outflow" if trend != direction else "Neutral"
        preferred = "CAUTION"

    if pcr < 0.7 and direction == "bullish":
        flow = "Inflow"
    elif pcr > 1.3 and direction == "bearish":
        flow = "Inflow"

    return pts, {
        "sector": sector,
        "sector_trend": trend,
        "oi_flow": flow,
        "sector_rank": "#1 Hot" if pts >= 10 else "Neutral",
        "preferred": preferred,
        "implication": f"Sector {'tailwind' if pts >= 10 else 'headwind' if pts == 0 else 'neutral'} for {direction}",
    }


def build_sector_heatmap(instruments_data: dict[str, dict]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    bank = instruments_data.get("BANKNIFTY", {})
    nifty = instruments_data.get("NIFTY", {})
    bank_trend = bank.get("htf_bias", "neutral")
    nifty_trend = nifty.get("htf_bias", "neutral")

    def row(name: str, trend: str, proxy: dict) -> dict[str, str]:
        pcr = float((proxy.get("chain_analytics") or {}).get("pcr") or 1)
        if trend == "bullish":
            pref = "CALLS"
            flow = "Inflow"
        elif trend == "bearish":
            pref = "PUTS"
            flow = "Inflow"
        else:
            pref = "SPREADS"
            flow = "Neutral"
        if pcr > 1.2:
            flow = "Outflow" if trend == "bullish" else flow
        return {"sector": name, "trend": trend.title(), "oi_flow": flow, "preferred": pref}

    rows.append(row("Bank", bank_trend, bank))
    rows.append(row("Index", nifty_trend, nifty))
    sensex = instruments_data.get("SENSEX", {})
    rows.append(row("Broad Market", sensex.get("htf_bias", nifty_trend), sensex or nifty))
    return rows
