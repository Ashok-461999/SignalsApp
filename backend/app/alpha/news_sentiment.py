"""News sentiment scoring for confluence (Section 3B)."""

from __future__ import annotations

from typing import Any

from app.services.market_news import get_enriched_headlines
from app.services.market_predictions import aggregate_predictions, enrich_headlines


def news_confluence_for_instrument(instrument: str, direction: str) -> tuple[int, dict[str, Any]]:
    """Returns points (0-10) and news metadata. Penalty if news opposes direction."""
    try:
        headlines = get_enriched_headlines(max_items=20)
        enriched = enrich_headlines(headlines)
        preds = aggregate_predictions(enriched)
        match = next((p for p in preds if p["symbol"] == instrument), None)
    except Exception:
        return 0, {"headline": "News unavailable", "sentiment_score": 0, "effect": "Neutral"}

    if not match or match.get("headline_count", 0) == 0:
        return 0, {"headline": "No instrument-specific news", "sentiment_score": 0, "effect": "Neutral"}

    outlook = match.get("outlook", "neutral")
    conf = int(match.get("confidence", 50))
    sentiment_score = conf if outlook == "bullish" else -conf if outlook == "bearish" else 0

    confirming = (outlook == "bullish" and direction == "bullish") or (
        outlook == "bearish" and direction == "bearish"
    )
    opposing = (outlook == "bullish" and direction == "bearish") or (
        outlook == "bearish" and direction == "bullish"
    )

    if opposing and abs(sentiment_score) >= 55:
        pts = -10
        effect = "Contradictory — news wins"
    elif confirming and conf >= 60:
        pts = 10
        effect = "Strongly confirming"
    elif confirming:
        pts = 5
        effect = "Confirming"
    else:
        pts = 0
        effect = "Neutral"

    top_headline = ""
    for h in enriched:
        syms = h.get("symbols") or []
        if instrument in syms or not syms:
            top_headline = h.get("title", "")[:120]
            break

    return pts, {
        "headline": top_headline or match.get("rationale", ""),
        "sentiment_score": sentiment_score,
        "outlook": outlook,
        "confidence": conf,
        "effect": effect,
        "option_hint": match.get("option_hint", ""),
    }
