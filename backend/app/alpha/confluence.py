"""9-factor confluence scoring — minimum 70 to issue signal (India Alpha v2)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.alpha.constants import MIN_CONFLUENCE_SCORE, TIER_RISK_PCT


@dataclass
class ConfluenceResult:
    total: int
    tier: str
    grade_emoji: str
    factors: dict[str, int]
    can_signal: bool
    risk_pct: float


def score_to_tier(total: int) -> str:
    if total >= 90:
        return "A+"
    if total >= 75:
        return "A"
    if total >= MIN_CONFLUENCE_SCORE:
        return "B"
    return "NO_SIGNAL"


def compute_confluence(
    structure_pts: int,
    sweep_pts: int,
    ob_fvg_pts: int,
    oi_pts: int,
    pcr_pts: int,
    news_pts: int,
    sector_pts: int,
    profile_pts: int,
    gex_pts: int,
) -> ConfluenceResult:
    factors = {
        "structure": min(structure_pts, 18),
        "liquidity_sweep": min(sweep_pts, 12),
        "order_block_fvg": min(ob_fvg_pts, 12),
        "oi_confluence": min(oi_pts, 12),
        "pcr_sentiment": min(pcr_pts, 12),
        "news_sentiment": max(-10, min(news_pts, 10)),
        "sector_rotation": min(sector_pts, 10),
        "market_profile": min(profile_pts, 8),
        "gex_volatility": min(gex_pts, 6),
    }
    total = max(0, sum(factors.values()))
    tier = score_to_tier(total)
    emoji = {"A+": "🟢", "A": "🟡", "B": "🟠", "NO_SIGNAL": "⚫"}.get(tier, "⚫")
    return ConfluenceResult(
        total=total,
        tier=tier,
        grade_emoji=emoji,
        factors=factors,
        can_signal=total >= MIN_CONFLUENCE_SCORE,
        risk_pct=TIER_RISK_PCT.get(tier, 0),
    )


def pcr_points(pcr: float, direction: str) -> int:
    from app.alpha.constants import PCR_EXTREME_HIGH, PCR_EXTREME_LOW, PCR_NEUTRAL_HIGH, PCR_NEUTRAL_LOW

    if pcr < PCR_EXTREME_LOW and direction == "bearish":
        return 12
    if pcr > PCR_EXTREME_HIGH and direction == "bullish":
        return 12
    if pcr < 0.75 and direction == "bullish":
        return 6
    if pcr > 1.25 and direction == "bearish":
        return 6
    if PCR_NEUTRAL_LOW <= pcr <= PCR_NEUTRAL_HIGH:
        return 0
    return 3


def gex_points(gex: dict[str, Any], direction: str, breakout: bool) -> int:
    regime = gex.get("regime", "neutral")
    if breakout and regime == "negative":
        return 6
    if not breakout and regime == "positive":
        return 6
    if regime == "neutral":
        return 3
    return 0
