"""Live signal performance — win rate, drawdown, setup accuracy from stored predictions."""

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.data.models import SignalPrediction


def _max_drawdown(pnls: list[float]) -> float:
    peak = 0.0
    max_dd = 0.0
    cumulative = 0.0
    for pnl in pnls:
        cumulative += pnl
        peak = max(peak, cumulative)
        max_dd = max(max_dd, peak - cumulative)
    return round(max_dd, 2)


def _win_rate(wins: int, closed: int) -> float:
    if closed <= 0:
        return 0.0
    return round(wins / closed * 100, 1)


def load_live_setup_stats(session: Session, min_samples: int = 3) -> dict[str, dict[str, Any]]:
    """Per-setup live stats from resolved TAKE predictions (options leg)."""
    rows = session.execute(
        select(SignalPrediction)
        .where(
            SignalPrediction.can_take.is_(True),
            SignalPrediction.resolved.is_(True),
            SignalPrediction.options_outcome != "",
        )
        .order_by(SignalPrediction.created_at.asc())
    ).scalars().all()

    buckets: dict[str, list[SignalPrediction]] = {}
    for row in rows:
        buckets.setdefault(row.setup_name, []).append(row)

    stats: dict[str, dict[str, Any]] = {}
    for setup, preds in buckets.items():
        closed = [p for p in preds if p.options_outcome in ("profit", "sl_hit", "time_exit")]
        if len(closed) < min_samples:
            continue
        wins = sum(1 for p in closed if p.options_outcome == "profit")
        losses = len(closed) - wins
        pnls = [float(p.options_pnl or 0) for p in closed]
        stats[setup] = {
            "trades": len(closed),
            "wins": wins,
            "losses": losses,
            "win_rate": _win_rate(wins, len(closed)),
            "max_drawdown_inr": _max_drawdown(pnls),
            "total_pnl_inr": round(sum(pnls), 2),
        }
    return stats


def load_global_live_stats(session: Session) -> dict[str, Any]:
    """Aggregate live TAKE options performance."""
    rows = session.execute(
        select(SignalPrediction)
        .where(
            SignalPrediction.can_take.is_(True),
            SignalPrediction.resolved.is_(True),
            SignalPrediction.options_outcome != "",
        )
        .order_by(SignalPrediction.created_at.asc())
    ).scalars().all()

    closed = [r for r in rows if r.options_outcome in ("profit", "sl_hit", "time_exit")]
    wins = sum(1 for r in closed if r.options_outcome == "profit")
    losses = len(closed) - wins
    pnls = [float(r.options_pnl or 0) for r in closed]
    fut_closed = [
        r for r in rows
        if r.futures_outcome in ("profit", "sl_hit", "time_exit")
    ]
    fut_wins = sum(1 for r in fut_closed if r.futures_outcome == "profit")

    return {
        "take_trades": len(closed),
        "take_wins": wins,
        "take_losses": losses,
        "take_win_rate": _win_rate(wins, len(closed)),
        "take_max_drawdown_inr": _max_drawdown(pnls),
        "take_total_pnl_inr": round(sum(pnls), 2),
        "futures_win_rate": _win_rate(fut_wins, len(fut_closed)),
        "setup_stats": load_live_setup_stats(session, min_samples=2),
    }
