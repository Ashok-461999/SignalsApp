"""Fetch Indian & global market news headlines (RSS)."""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

logger = logging.getLogger(__name__)

USER_AGENT = (
    "Mozilla/5.0 (compatible; AlphaPulse/1.0; +https://github.com/signalapp)"
)


@dataclass(frozen=True)
class NewsFeed:
    source: str
    url: str
    category: str  # indian | global
    per_fetch: int = 6


RSS_FEEDS: list[NewsFeed] = [
    NewsFeed("Moneycontrol", "https://www.moneycontrol.com/rss/latestnews.xml", "indian", 8),
    NewsFeed("Economic Times", "https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms", "indian", 6),
    NewsFeed("Business Standard", "https://www.business-standard.com/rss/markets-106.rss", "indian", 5),
    NewsFeed("Livemint Markets", "https://www.livemint.com/rss/markets", "indian", 5),
    NewsFeed("Reuters Business", "https://feeds.reuters.com/reuters/businessNews", "global", 6),
    NewsFeed("CNBC World", "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114", "global", 5),
    NewsFeed("BBC Business", "https://feeds.bbci.co.uk/news/business/rss.xml", "global", 5),
]

_CACHE: dict = {"at": None, "headlines": []}
_CACHE_TTL_SEC = 300  # 5 min — fresher feed like Moneycontrol


def _text(el: ET.Element | None) -> str:
    if el is None or not el.text:
        return ""
    return el.text.strip()


def _parse_rss(xml_text: str, feed: NewsFeed) -> list[dict]:
    headlines: list[dict] = []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return headlines

    for item in root.iter("item"):
        title = _text(item.find("title"))
        if len(title) < 10:
            continue
        pub = _text(item.find("pubDate")) or _text(item.find("{http://purl.org/dc/elements/1.1/}date"))
        link = _text(item.find("link"))
        headlines.append(
            {
                "source": feed.source,
                "title": title,
                "category": feed.category,
                "published_at": pub,
                "url": link,
            }
        )
        if len(headlines) >= feed.per_fetch:
            break
    return headlines


def get_enriched_headlines(max_items: int = 30) -> list[dict]:
    from app.services.market_predictions import enrich_headlines

    raw = get_market_headlines(max_items=max_items)
    return enrich_headlines(raw)


def get_market_headlines(max_items: int = 30) -> list[dict]:
    now = datetime.now(timezone.utc)
    cached_at = _CACHE.get("at")
    if cached_at and (now - cached_at).total_seconds() < _CACHE_TTL_SEC:
        return _CACHE["headlines"][:max_items]

    combined: list[dict] = []
    headers = {"User-Agent": USER_AGENT}

    try:
        with httpx.Client(timeout=14.0, follow_redirects=True, headers=headers) as client:
            for feed in RSS_FEEDS:
                try:
                    resp = client.get(feed.url)
                    resp.raise_for_status()
                    combined.extend(_parse_rss(resp.text, feed))
                except Exception as exc:
                    logger.warning("RSS fetch failed %s: %s", feed.source, exc)
    except Exception:
        logger.exception("Market news fetch failed")

    # Interleave Indian + global for a balanced feed
    indian = [h for h in combined if h.get("category") == "indian"]
    global_ = [h for h in combined if h.get("category") == "global"]
    merged: list[dict] = []
    while indian or global_:
        if indian:
            merged.append(indian.pop(0))
        if global_:
            merged.append(global_.pop(0))

    if not merged:
        merged = [
            {
                "source": "AlphaPulse",
                "title": "Live headlines unavailable — pull to refresh.",
                "category": "indian",
            }
        ]

    _CACHE["at"] = now
    _CACHE["headlines"] = merged
    return merged[:max_items]
