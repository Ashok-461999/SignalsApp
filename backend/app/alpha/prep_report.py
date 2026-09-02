"""Market Prep + News Digest (Section 14)."""

from __future__ import annotations

from datetime import datetime, timezone, timedelta
from typing import Any

from app.alpha.sector_rotation import build_sector_heatmap
from app.services.market_news import get_enriched_headlines
from app.services.market_predictions import analyze_headline, enrich_headlines

IST = timezone(timedelta(hours=5, minutes=30))


def build_prep_report(
    instruments_data: dict[str, dict[str, Any]],
    gift_nifty: dict[str, Any] | None = None,
) -> dict[str, Any]:
    now = datetime.now(IST)
    headlines = []
    try:
        headlines = enrich_headlines(get_enriched_headlines(max_items=8))
    except Exception:
        pass

    news_digest = []
    for h in headlines[:5]:
        title = h.get("title", "")
        analysis = h if "sentiment" in h else analyze_headline(title)
        news_digest.append(
            {
                "headline": title[:140],
                "impact": "High" if analysis.get("score", 50) > 70 or analysis.get("score", 50) < 30 else "Medium",
                "sentiment": analysis.get("sentiment", "neutral"),
            }
        )

    report = {
        "type": "MARKET_PREP",
        "date": now.strftime("%Y-%m-%d"),
        "time_ist": now.strftime("%H:%M"),
        "title": f"MARKET PREP + NEWS DIGEST — {now.strftime('%d %b %Y')} — {now.strftime('%H:%M')} IST",
        "global_cues": {
            "gift_nifty": (gift_nifty or {}).get("price"),
            "gift_change_pct": (gift_nifty or {}).get("change_pct"),
        },
        "news_digest": news_digest,
        "sector_heatmap": build_sector_heatmap(instruments_data),
        "indices": {},
        "options_map": {},
        "watchlist": [],
        "message": "Fewer than 5 valid setups — prep mode. Wait for sweep + structure + news alignment.",
    }
    for inst, data in instruments_data.items():
        chain = data.get("chain_analytics") or {}
        profile = data.get("market_profile") or {}
        report["indices"][inst] = {
            "spot": data.get("spot"),
            "trend": data.get("htf_bias", "neutral"),
        }
        report["options_map"][inst] = {
            "call_wall": chain.get("call_wall_strike"),
            "put_wall": chain.get("put_wall_strike"),
            "pcr": chain.get("pcr"),
            "max_pain": chain.get("max_pain"),
        }
        report["watchlist"].append(
            {
                "instrument": inst,
                "note": f"PCR {chain.get('pcr')} — POC {profile.get('poc')} — wait for sweep at VAH/VAL",
            }
        )
    return report
