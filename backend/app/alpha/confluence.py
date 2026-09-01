"""7-factor confluence scoring — minimum 70 to issue signal."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.alpha.constants import MIN_CONFLUENCE_SCORE, TIER_LIMITS, TIER_RISK_PCT


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
    profile_pts: int,
    gex_pts: int,
) -> ConfluenceResult:
    factors = {
        "structure": structure_pts,
        "liquidity_sweep": sweep_pts,
        "order_block_fvg": ob_fvg_pts,
        "oi_confluence": oi_pts,
        "pcr_sentiment": pcr_pts,
        "market_profile": profile_pts,
        "gex_volatility": gex_pts,
    }
    total = sum(factors.values())
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
        return 15
    if pcr > PCR_EXTREME_HIGH and direction == "bullish":
        return 15
    if pcr < 0.75 and direction == "bullish":
        return 8
    if pcr > 1.25 and direction == "bearish":
        return 8
    if PCR_NEUTRAL_LOW <= pcr <= PCR_NEUTRAL_HIGH:
        return 0
    return 4


def gex_points(gex: dict[str, Any], direction: str, breakout: bool) -> int:
    regime = gex.get("regime", "neutral")
    if breakout and regime == "negative":
        return 10
    if not breakout and regime == "positive":
        return 10
    if regime == "neutral":
        return 5
    return 0
