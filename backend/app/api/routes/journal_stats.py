"""Journal P&L summary helpers."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Protocol

from app.core.index_config import LOT_SIZES


class _JournalLike(Protocol):
    pnl: float | None
    status: str
    created_at: datetime
    instrument: str
    planned_size: int


def lot_size_for(instrument: str) -> int:
    return LOT_SIZES.get(instrument.upper(), 25)


def calc_option_pnl(
    fill: float,
    exit_price: float,
    instrument: str,
    lots: int,
) -> float:
    """Long option buyer P&L: (exit - entry) × lot size × lots."""
    return round((exit_price - fill) * lot_size_for(instrument) * lots, 2)


def _ist_day_start(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    ist = dt + timedelta(hours=5, minutes=30)
    start_ist = ist.replace(hour=0, minute=0, second=0, microsecond=0)
    return start_ist - timedelta(hours=5, minutes=30)


def build_journal_summary(entries: list[_JournalLike]) -> dict:
    now = datetime.now(timezone.utc)
    today_start = _ist_day_start(now)
    week_start = today_start - timedelta(days=_ist_day_start(now).weekday())

    closed = [e for e in entries if e.pnl is not None]
    open_trades = [
        e
        for e in entries
        if e.status in ("approved", "filled", "planned") and e.pnl is None
    ]
    wins = [e for e in closed if e.pnl > 0]
    losses = [e for e in closed if e.pnl < 0]
    breakeven = [e for e in closed if e.pnl == 0]

    total_pnl = sum(e.pnl for e in closed)
    today_pnl = sum(
        e.pnl for e in closed if _ist_day_start(e.created_at) >= today_start
    )
    week_pnl = sum(
        e.pnl for e in closed if _ist_day_start(e.created_at) >= week_start
    )

    gross_profit = sum(e.pnl for e in wins)
    gross_loss = abs(sum(e.pnl for e in losses))
    avg_win = gross_profit / len(wins) if wins else 0.0
    avg_loss = gross_loss / len(losses) if losses else 0.0
    profit_factor = (
        round(gross_profit / gross_loss, 2) if gross_loss > 0 else None
    )
    expectancy = total_pnl / len(closed) if closed else 0.0

    return {
        "total_pnl": round(total_pnl, 2),
        "today_pnl": round(today_pnl, 2),
        "week_pnl": round(week_pnl, 2),
        "closed_trades": len(closed),
        "open_trades": len(open_trades),
        "wins": len(wins),
        "losses": len(losses),
        "breakeven": len(breakeven),
        "win_rate": round(len(wins) / len(closed) * 100, 1) if closed else 0.0,
        "avg_win": round(avg_win, 2),
        "avg_loss": round(avg_loss, 2),
        "largest_win": round(max((e.pnl for e in wins), default=0.0), 2),
        "largest_loss": round(min((e.pnl for e in losses), default=0.0), 2),
        "profit_factor": profit_factor,
        "expectancy": round(expectancy, 2),
        "gross_profit": round(gross_profit, 2),
        "gross_loss": round(gross_loss, 2),
    }
