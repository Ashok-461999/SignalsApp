"""NSE session clock, trader brief, and FII/DII flows."""

from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import httpx

logger = logging.getLogger(__name__)

IST = ZoneInfo("Asia/Kolkata")
MARKET_OPEN = time(9, 15)
MARKET_CLOSE = time(15, 30)
PRE_OPEN_START = time(9, 0)
BAR_MINUTES = 5

NSE_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Referer": "https://www.nseindia.com/",
}

_FII_CACHE: dict = {"at": None, "data": None}
_FII_TTL_SEC = 600


def _now_ist() -> datetime:
    return datetime.now(IST)


def _is_trading_day(d: date) -> bool:
    return d.weekday() < 5


def _next_bar_boundary(now: datetime) -> datetime:
    """Next 5m bar close after market open (9:15 IST)."""
    open_dt = datetime.combine(now.date(), MARKET_OPEN, tzinfo=IST)
    close_dt = datetime.combine(now.date(), MARKET_CLOSE, tzinfo=IST)
    if now < open_dt:
        return open_dt + timedelta(minutes=BAR_MINUTES)
    if now >= close_dt:
        # next trading day 9:20
        nxt = now.date() + timedelta(days=1)
        while not _is_trading_day(nxt):
            nxt += timedelta(days=1)
        return datetime.combine(nxt, MARKET_OPEN, tzinfo=IST) + timedelta(minutes=BAR_MINUTES)

    elapsed = int((now - open_dt).total_seconds() // 60)
    next_offset = ((elapsed // BAR_MINUTES) + 1) * BAR_MINUTES
    candidate = open_dt + timedelta(minutes=next_offset)
    return min(candidate, close_dt)


def market_phase(now: datetime | None = None) -> str:
    now = now or _now_ist()
    if not _is_trading_day(now.date()):
        return "weekend"
    t = now.time()
    if t < PRE_OPEN_START:
        return "pre_market"
    if t < MARKET_OPEN:
        return "pre_open"
    if t <= MARKET_CLOSE:
        return "market_open"
    return "market_closed"


def _trader_pain_tips(phase: str, minutes_to_bar: int | None) -> list[str]:
    tips: list[str] = []
    if phase == "weekend":
        tips.append("Markets closed — review journal & plan Monday levels.")
        tips.append("Check GIFT Nifty Sunday evening for Monday gap bias.")
    elif phase == "pre_market" or phase == "pre_open":
        tips.append("Pre-open: watch GIFT Nifty + News tab before 9:15.")
        tips.append("Avoid buying options until first 5m bar confirms direction.")
    elif phase == "market_open":
        if minutes_to_bar is not None and minutes_to_bar <= 3:
            tips.append("Next 5m bar closing soon — fresh TAKE signal may appear.")
        tips.append("Only take TAKE signals; skip NO_TRADE and SIT_OUT days.")
        tips.append("High IV? Premium is expensive — theta + crush hurt buyers.")
        tips.append("Use 20+ DTE expiry shown on cards — avoids weekly decay.")
    else:
        tips.append("Market closed — signals resume next session at 9:20 IST.")
    return tips[:4]


def fetch_fii_dii() -> dict | None:
    now = datetime.now(timezone.utc)
    cached_at = _FII_CACHE.get("at")
    if cached_at and (now - cached_at).total_seconds() < _FII_TTL_SEC and _FII_CACHE.get("data"):
        return _FII_CACHE["data"]

    try:
        with httpx.Client(timeout=12.0, follow_redirects=True, headers=NSE_HEADERS) as client:
            client.get("https://www.nseindia.com/")
            resp = client.get("https://www.nseindia.com/api/fiidiiTradeReact")
            resp.raise_for_status()
            rows = resp.json()
    except Exception:
        logger.debug("FII/DII fetch failed", exc_info=True)
        return None

    if not rows or not isinstance(rows, list):
        return None

    latest = rows[0] if rows else {}
    try:
        fii_net = float(str(latest.get("fiiNetValue", "0")).replace(",", ""))
        dii_net = float(str(latest.get("diiNetValue", "0")).replace(",", ""))
    except (TypeError, ValueError):
        return None

    payload = {
        "date": str(latest.get("date", "")),
        "fii_net_cr": round(fii_net, 1),
        "dii_net_cr": round(dii_net, 1),
        "summary": (
            f"FII {'bought' if fii_net >= 0 else 'sold'} ₹{abs(fii_net):.0f} Cr · "
            f"DII {'bought' if dii_net >= 0 else 'sold'} ₹{abs(dii_net):.0f} Cr"
        ),
    }
    _FII_CACHE["at"] = now
    _FII_CACHE["data"] = payload
    return payload


def build_market_session() -> dict:
    now = _now_ist()
    phase = market_phase(now)
    next_bar = _next_bar_boundary(now)
    mins_to_bar: int | None = None
    if phase == "market_open":
        mins_to_bar = max(0, int((next_bar - now).total_seconds() // 60))

    fii = fetch_fii_dii()

    return {
        "ist_time": now.strftime("%H:%M IST"),
        "phase": phase,
        "phase_label": {
            "weekend": "Weekend — markets closed",
            "pre_market": "Pre-market",
            "pre_open": "Pre-open (9:00–9:15)",
            "market_open": "Market open",
            "market_closed": "Market closed",
        }.get(phase, phase),
        "is_trading_day": _is_trading_day(now.date()),
        "market_hours": "09:15 – 15:30 IST",
        "next_bar_at": next_bar.strftime("%H:%M IST"),
        "minutes_to_next_bar": mins_to_bar,
        "signals_active": phase == "market_open",
        "fii_dii": fii,
        "trader_tips": _trader_pain_tips(phase, mins_to_bar),
    }


def build_trader_brief(gift: dict | None, regimes: dict | None = None) -> dict:
    """One-screen brief addressing common option buyer pain points."""
    session = build_market_session()
    pains: list[str] = []
    actions: list[str] = []

    phase = session["phase"]
    if phase in ("pre_market", "pre_open"):
        actions.append("Check GIFT Nifty gap probability before open")
        actions.append("Read India + Global news headlines")
    elif phase == "market_open":
        actions.append("Wait for TAKE on 5m close — do not chase")
        if session.get("minutes_to_next_bar") is not None:
            actions.append(f"Next signal scan ~{session['next_bar_at']}")
    else:
        actions.append("Review P&L journal — note what worked")

    gift = gift or {}
    if gift.get("available"):
        chg = float(gift.get("change_pct", 0))
        if chg < -0.05:
            pains.append("GIFT negative — gap-down open likely; be cautious with CE buys")
            actions.append("Prefer PE or wait for first 15m structure")
        elif chg > 0.05:
            pains.append("GIFT positive — gap-up bias; avoid chasing PE at open")

    if regimes:
        for inst, info in regimes.items():
            if isinstance(info, dict) and info.get("regime") == "ranging":
                pains.append(f"{inst} ranging — theta eats option buyers (SIT_OUT)")
                break

    fii = session.get("fii_dii")
    if fii:
        if fii.get("fii_net_cr", 0) < -500:
            pains.append("Heavy FII selling — rallies may fade; tighten stops")
        elif fii.get("fii_net_cr", 0) > 500:
            pains.append("Strong FII buying — dips may get bought")

    pains.extend([
        "Never buy options on SIT_OUT ranging days",
        "IV above 80% — premium crush risk on long options",
        "Hold 20+ DTE — weekly options decay too fast",
    ])

    return {
        "session": session,
        "pain_points": pains[:5],
        "action_items": actions[:4],
        "headline": _brief_headline(session, gift),
    }


def _brief_headline(session: dict, gift: dict) -> str:
    phase = session.get("phase", "")
    if phase == "market_open":
        mins = session.get("minutes_to_next_bar")
        if mins is not None:
            return f"Market live · next 5m scan in {mins} min"
        return "Market live — trade TAKE signals only"
    if gift.get("available"):
        return gift.get("summary", "Check GIFT Nifty before open")
    return session.get("phase_label", "Indian markets")
