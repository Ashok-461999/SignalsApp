"""Fetch Indian market news headlines for AI context."""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

import httpx

logger = logging.getLogger(__name__)

RSS_FEEDS = [
    ("Economic Times", "https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms"),
    ("Moneycontrol", "https://www.moneycontrol.com/rss/latestnews.xml"),
]

_CACHE: dict = {"at": None, "headlines": []}
_CACHE_TTL_SEC = 900  # 15 minutes


def _parse_rss(xml_text: str, source: str, limit: int = 5) -> list[dict]:
    headlines: list[dict] = []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return headlines

    for item in root.iter("item"):
        title_el = item.find("title")
        if title_el is None or not title_el.text:
            continue
        title = title_el.text.strip()
        if len(title) < 10:
            continue
        headlines.append({"source": source, "title": title})
        if len(headlines) >= limit:
            break
    return headlines


def get_enriched_headlines(max_items: int = 15) -> list[dict]:
    from app.services.market_predictions import enrich_headlines

    raw = get_market_headlines(max_items=max_items)
    return enrich_headlines(raw)


def get_market_headlines(max_items: int = 12) -> list[dict]:
    now = datetime.now(timezone.utc)
    cached_at = _CACHE.get("at")
    if cached_at and (now - cached_at).total_seconds() < _CACHE_TTL_SEC:
        return _CACHE["headlines"][:max_items]

    combined: list[dict] = []
    try:
        with httpx.Client(timeout=12.0, follow_redirects=True) as client:
            for source, url in RSS_FEEDS:
                try:
                    resp = client.get(url, headers={"User-Agent": "SignalApp/1.0"})
                    resp.raise_for_status()
                    combined.extend(_parse_rss(resp.text, source, limit=6))
                except Exception as exc:
                    logger.warning("RSS fetch failed %s: %s", source, exc)
    except Exception:
        logger.exception("Market news fetch failed")

    if not combined:
        combined = [
            {
                "source": "SignalApp",
                "title": "Live headlines unavailable — analysis uses technical setup only.",
            }
        ]

    _CACHE["at"] = now
    _CACHE["headlines"] = combined[:max_items]
    return _CACHE["headlines"]
