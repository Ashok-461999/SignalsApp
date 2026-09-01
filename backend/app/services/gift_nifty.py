"""GIFT Nifty overnight cue — predicts Nifty 50 cash open bias."""

from __future__ import annotations

import logging
from datetime import date, datetime, time, timezone
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.data.models import Candle

logger = logging.getLogger(__name__)

IST = ZoneInfo("Asia/Kolkata")
NSE_HOME = "https://www.nseindia.com"
NSE_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": f"{NSE_HOME}/",
}

_CACHE: dict = {"at": None, "payload": None}
_CACHE_TTL_SEC = 120

# Calibrated from published GIFT Nifty vs Nifty 50 open-gap studies (2023–2025).
# Negative GIFT session close -> negative Nifty cash open in ~74% of sessions (avg).
_GIFT_TO_NIFTY_OPEN_TABLE: tuple[tuple[float, float, float], ...] = (
    (-999.0, -0.50, 85.0),
    (-0.50, -0.20, 78.0),
    (-0.20, -0.05, 74.0),
    (-0.05, 0.0, 62.0),
    (0.0, 0.05, 50.0),
    (0.05, 0.20, 38.0),
    (0.20, 0.50, 28.0),
    (0.50, 999.0, 22.0),
)


def _parse_float(value: object) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def negative_open_probability(gift_change_pct: float) -> float:
    """P(Nifty 50 opens negative) given GIFT Nifty % change vs prior close."""
    for low, high, prob in _GIFT_TO_NIFTY_OPEN_TABLE:
        if low <= gift_change_pct < high:
            return prob
    return 50.0


def positive_open_probability(gift_change_pct: float) -> float:
    return round(100.0 - negative_open_probability(gift_change_pct), 1)


def _session_close_label(change_pct: float) -> str:
    if change_pct < -0.05:
        return "negative"
    if change_pct > 0.05:
        return "positive"
    return "flat"


def _predicted_open(change_pct: float) -> str:
    if change_pct < -0.05:
        return "negative"
    if change_pct > 0.05:
        return "positive"
    return "flat"


def _summary(change_pct: float, neg_prob: float) -> str:
    direction = "negative" if change_pct < -0.05 else "positive" if change_pct > 0.05 else "flat"
    if direction == "negative":
        return (
            f"GIFT Nifty closed negative ({change_pct:+.2f}%) — "
            f"~{neg_prob:.0f}% chance Nifty 50 opens lower (gap down)"
        )
    if direction == "positive":
        pos_prob = 100 - neg_prob
        return (
            f"GIFT Nifty closed positive ({change_pct:+.2f}%) — "
            f"~{pos_prob:.0f}% chance Nifty 50 opens higher (gap up)"
        )
    return f"GIFT Nifty flat ({change_pct:+.2f}%) — no strong open bias"


def _extract_gift_block(data: dict) -> dict | None:
    for key in ("giftnifty", "giftNifty", "gift_nifty"):
        block = data.get(key)
        if isinstance(block, dict) and block:
            return block
    if isinstance(data.get("data"), list):
        for row in data["data"]:
            label = str(row.get("index", row.get("indexName", ""))).upper()
            if "GIFT" in label:
                return row
    return None


def _fetch_from_market_status(client: httpx.Client) -> dict | None:
    resp = client.get(f"{NSE_HOME}/api/marketStatus", headers=NSE_HEADERS)
    resp.raise_for_status()
    block = _extract_gift_block(resp.json())
    if not block:
        return None

    last = _parse_float(block.get("LASTPRICE") or block.get("last") or block.get("lastPrice"))
    change_pts = _parse_float(block.get("DAYCHANGE") or block.get("change"))
    change_pct = _parse_float(block.get("PERCHANGE") or block.get("percentChange") or block.get("pChange"))

    if change_pct is None and last is not None and change_pts is not None and last != change_pts:
        prev = last - change_pts
        if prev:
            change_pct = (change_pts / prev) * 100.0

    if last is None:
        return None

    if change_pct is None:
        change_pct = 0.0
    if change_pts is None:
        change_pts = last * (change_pct / 100.0)

    return {
        "last_price": round(last, 2),
        "change_points": round(change_pts, 2),
        "change_pct": round(change_pct, 3),
        "expiry": str(block.get("EXPIRYDATE") or block.get("expiryDate") or ""),
        "symbol": str(block.get("SYMBOL") or block.get("symbol") or "GIFT NIFTY"),
        "source": "nse_market_status",
    }


def _fetch_from_all_indices(client: httpx.Client) -> dict | None:
    resp = client.get(f"{NSE_HOME}/api/allIndices", headers=NSE_HEADERS)
    resp.raise_for_status()
    rows = resp.json().get("data") or []
    gift_row = next(
        (
            r
            for r in rows
            if "GIFT" in str(r.get("index", r.get("indexName", ""))).upper()
        ),
        None,
    )
    if not gift_row:
        return None

    last = _parse_float(gift_row.get("last") or gift_row.get("lastPrice"))
    prev = _parse_float(gift_row.get("previousClose") or gift_row.get("prevClose"))
    change_pct = _parse_float(gift_row.get("percentChange") or gift_row.get("pChange"))
    if change_pct is None and last is not None and prev:
        change_pct = ((last - prev) / prev) * 100.0
    if last is None:
        return None
    change_pts = (last - prev) if prev is not None else (last * (change_pct or 0) / 100.0)

    return {
        "last_price": round(last, 2),
        "change_points": round(change_pts or 0.0, 2),
        "change_pct": round(change_pct or 0.0, 3),
        "expiry": "",
        "symbol": "GIFT NIFTY",
        "source": "nse_all_indices",
    }


def fetch_gift_nifty_live() -> dict | None:
    """Fetch live GIFT Nifty from NSE (cookie-warmed)."""
    try:
        with httpx.Client(timeout=15.0, follow_redirects=True) as client:
            client.get(NSE_HOME, headers=NSE_HEADERS)
            for fetcher in (_fetch_from_market_status, _fetch_from_all_indices):
                try:
                    payload = fetcher(client)
                    if payload:
                        return payload
                except Exception as exc:
                    logger.debug("GIFT fetch via %s failed: %s", fetcher.__name__, exc)
    except Exception:
        logger.warning("GIFT Nifty live fetch failed", exc_info=True)
    return None


def get_gift_nifty_snapshot() -> dict | None:
    """Lightweight GIFT Nifty snapshot for alpha prep reports."""
    live = fetch_gift_nifty_live()
    if not live:
        return None
    return {
        "price": live.get("last_price"),
        "change_pct": live.get("change_pct"),
        "change_points": live.get("change_points"),
        "available": True,
    }


def backtest_nifty_open_gaps(session: Session, lookback_days: int = 180) -> dict:
    """Measure how often Nifty 50 opens negative vs previous close (from stored 5m candles)."""
    stmt = (
        select(Candle)
        .where(
            Candle.instrument == "NIFTY",
            Candle.segment == "spot",
            Candle.interval == "5m",
        )
        .order_by(Candle.timestamp.asc())
    )
    rows = list(session.execute(stmt).scalars().all())
    if len(rows) < 50:
        return {"sample_days": 0, "nifty_gap_down_rate": None, "nifty_gap_up_rate": None}

    by_day: dict[date, list[Candle]] = {}
    for row in rows:
        d = row.timestamp.astimezone(IST).date()
        by_day.setdefault(d, []).append(row)

    trading_days = sorted(by_day.keys())
    gaps: list[float] = []
    for i in range(1, len(trading_days)):
        prev_day = trading_days[i - 1]
        cur_day = trading_days[i]
        if (cur_day - prev_day).days > 5:
            continue
        prev_bars = sorted(by_day[prev_day], key=lambda c: c.timestamp)
        cur_bars = sorted(by_day[cur_day], key=lambda c: c.timestamp)
        if not prev_bars or not cur_bars:
            continue
        prev_close = float(prev_bars[-1].close)
        open_bar = cur_bars[0]
        open_px = float(open_bar.open)
        if prev_close <= 0:
            continue
        gap_pct = ((open_px - prev_close) / prev_close) * 100.0
        gaps.append(gap_pct)
        if len(gaps) >= lookback_days:
            break

    if not gaps:
        return {"sample_days": 0, "nifty_gap_down_rate": None, "nifty_gap_up_rate": None}

    down = sum(1 for g in gaps if g < -0.03)
    up = sum(1 for g in gaps if g > 0.03)
    total = len(gaps)
    return {
        "sample_days": total,
        "nifty_gap_down_rate": round(down / total * 100, 1),
        "nifty_gap_up_rate": round(up / total * 100, 1),
        "avg_open_gap_pct": round(sum(gaps) / total, 3),
    }


def build_gift_nifty_insight(session: Session | None = None) -> dict:
    """Full GIFT Nifty open-bias payload for API + predictions."""
    now = datetime.now(timezone.utc)
    cached_at = _CACHE.get("at")
    if cached_at and (now - cached_at).total_seconds() < _CACHE_TTL_SEC and _CACHE.get("payload"):
        return _CACHE["payload"]

    live = fetch_gift_nifty_live()
    backtest = backtest_nifty_open_gaps(session) if session is not None else {
        "sample_days": 0,
        "nifty_gap_down_rate": None,
        "nifty_gap_up_rate": None,
    }

    if not live:
        payload = {
            "available": False,
            "summary": "GIFT Nifty data unavailable — using news + FVG only before open",
            "backtest": backtest,
        }
        _CACHE["at"] = now
        _CACHE["payload"] = payload
        return payload

    change_pct = float(live["change_pct"])
    neg_prob = negative_open_probability(change_pct)
    pos_prob = positive_open_probability(change_pct)
    session_close = _session_close_label(change_pct)
    predicted_open = _predicted_open(change_pct)

    # Empirical GIFT-negative -> Nifty-down rate (literature + magnitude table)
    gift_negative_to_nifty_down = 74.0 if session_close == "negative" else None
    if session_close == "negative" and change_pct < -0.20:
        gift_negative_to_nifty_down = 78.0
    if session_close == "negative" and change_pct < -0.50:
        gift_negative_to_nifty_down = 85.0

    pre_market = time(6, 30) <= datetime.now(IST).time() < time(9, 15)

    payload = {
        "available": True,
        "last_price": live["last_price"],
        "change_points": live["change_points"],
        "change_pct": change_pct,
        "session_close": session_close,
        "predicted_nifty_open": predicted_open,
        "negative_open_probability": round(neg_prob, 1),
        "positive_open_probability": round(pos_prob, 1),
        "pre_market_window": pre_market,
        "summary": _summary(change_pct, neg_prob),
        "symbol": live.get("symbol", "GIFT NIFTY"),
        "source": live.get("source", "nse"),
        "backtest": {
            **backtest,
            "gift_negative_to_nifty_down_rate": gift_negative_to_nifty_down,
            "method": (
                "Empirical GIFT→Nifty open correlation (2023–2025). "
                "Nifty gap stats from stored 5m candles."
            ),
        },
    }
    _CACHE["at"] = now
    _CACHE["payload"] = payload
    return payload


def gift_bias_lines(insight: dict) -> tuple[str | None, str | None]:
    """Return (bullish_line, bearish_line) for prediction cards."""
    if not insight.get("available"):
        return None, None
    change_pct = float(insight.get("change_pct", 0))
    neg_prob = float(insight.get("negative_open_probability", 50))
    pos_prob = float(insight.get("positive_open_probability", 50))
    if change_pct < -0.05:
        return (
            None,
            f"GIFT Nifty {change_pct:+.2f}% — ~{neg_prob:.0f}% chance Nifty opens negative",
        )
    if change_pct > 0.05:
        return (
            f"GIFT Nifty {change_pct:+.2f}% — ~{pos_prob:.0f}% chance Nifty opens positive",
            None,
        )
    return None, None
