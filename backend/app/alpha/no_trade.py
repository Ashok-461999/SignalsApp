"""No-trade kill conditions from spec Section 7."""

from __future__ import annotations

from datetime import datetime, time, timezone, timedelta
from typing import Any

IST = timezone(timedelta(hours=5, minutes=30))


def check_no_trade(
    *,
    profile_position: str,
    vix: float | None,
    pcr: float,
    has_ob_fvg: bool,
    has_sweep: bool,
    chain_analytics: dict[str, Any],
    iv_percentile: float,
    sl_hits_today: int,
    active_on_instrument: bool,
    portfolio_risk_pct: float,
    is_expiry_after_1pm: bool = False,
) -> tuple[bool, str]:
    if profile_position == "inside_va":
        return True, "Price inside Market Profile Value Area — no directional edge"
    if vix is not None and vix > 25:
        return True, f"India VIX {vix:.1f} > 25 — too volatile"
    if 0.85 <= pcr <= 1.15:
        return True, f"PCR {pcr:.2f} neutral — no sentiment edge"
    if not has_ob_fvg:
        return True, "No clean Order Block or FVG for entry"
    if not has_sweep:
        return True, "No liquidity sweep in last 10 candles"
    if not chain_analytics.get("call_wall_strike") and not chain_analytics.get("put_wall_strike"):
        return True, "OI scattered — no clear call/put wall"
    if is_expiry_after_1pm:
        return True, "Expiry day after 1:00 PM — theta bomb"
    if iv_percentile > 85:
        return True, f"IV percentile {iv_percentile:.0f}% — too expensive for buyers"
    if active_on_instrument:
        return True, "Previous signal on same instrument still active"
    if portfolio_risk_pct > 5:
        return True, "Portfolio risk exceeds 5%"
    if sl_hits_today >= 2:
        return True, "2 stop losses hit today — stop for the day"
    return False, ""


def is_signal_window() -> tuple[bool, str]:
    now = datetime.now(IST).time()
    if now < time(9, 30):
        return False, "Opening auction — observe only until 9:30"
    if now >= time(14, 30):
        return False, "After 2:30 PM — no new signals"
    return True, ""
