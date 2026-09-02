"""Trade prediction text (Section 3C)."""

from __future__ import annotations

from typing import Any


def build_prediction(
    instrument: str,
    direction: str,
    spot: float,
    setup_reason: str,
    news: dict[str, Any],
    sector: dict[str, Any],
    confidence: int,
) -> str:
    move = "+1.5% to +2.5%" if direction == "bullish" else "-1.5% to -2.5%"
    reasons = [
        setup_reason or "structure break",
        f"sector {sector.get('sector_trend', 'neutral')}",
    ]
    if news.get("headline"):
        reasons.append(f"news: {news.get('outlook', 'neutral')}")
    reason_text = " + ".join(reasons[:3])
    target = round(spot * (1.02 if direction == "bullish" else 0.98), 2)
    return (
        f"PREDICTION: {instrument} expected to move {move} toward ~{target} in next 1-3 sessions "
        f"based on {reason_text}. Confidence: {confidence}%."
    )
