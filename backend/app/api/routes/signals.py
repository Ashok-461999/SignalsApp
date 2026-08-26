"""REST endpoints for live signals."""

import json
import logging

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.index_config import INDEX_SYMBOLS
from app.data.models import SignalLog
from app.db.session import get_sync_session
from app.services.signal_outcomes import build_history_summary, enrich_history_row
from app.services.signal_performance import load_global_live_stats
from app.signals.scanner import signal_scanner

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/signals", tags=["signals"])


@router.get("")
def get_active_signals() -> dict:
    """TAKE signals only — trade these in your broker app."""
    signals = signal_scanner.get_active_signals()
    regimes = {
        inst: signal_scanner.get_regime(inst)
        for inst in INDEX_SYMBOLS
        if signal_scanner.get_regime(inst)
    }
    return {
        "count": len(signals),
        "signals": signals,
        "regimes": regimes,
        "message": (
            "No trade — sit out or wait for setup"
            if not signals
            else f"{len(signals)} TAKE signal(s) — trade in your app"
        ),
    }


@router.get("/evaluations")
def get_all_evaluations() -> dict:
    """All evaluations including NO_TRADE and SIT_OUT with reasons."""
    return {
        "count": len(signal_scanner.get_all_evaluations()),
        "evaluations": signal_scanner.get_all_evaluations(),
    }


@router.get("/regime")
def get_regimes() -> dict:
    """Current market regime per index (trending / ranging / volatile)."""
    return {
        "regimes": {
            inst: signal_scanner.get_regime(inst)
            for inst in INDEX_SYMBOLS
        },
        "strategy_guide": {
            "trending": "FVG retest, liquidity sweep, ORB, VWAP — directional buying works",
            "ranging": "SIT OUT — theta eats option buyers; use spreads or skip",
            "volatile": "FVG + sweep only, size down, IV-aware",
        },
    }


@router.get("/history")
def get_signal_history(
    limit: int = Query(50, ge=1, le=200),
    session: Session = Depends(get_sync_session),
) -> dict:
    """Recent TAKE signals from the log (fast — capped enrich)."""
    rows = (
        session.execute(
            select(SignalLog)
            .where(SignalLog.tradable.is_(True))
            .order_by(SignalLog.created_at.desc())
            .limit(limit)
        )
        .scalars()
        .all()
    )
    signals = []
    for row in rows:
        try:
            payload = json.loads(row.payload)
            if payload.get("options_result"):
                signals.append({**payload, "log_id": row.id, "logged_at": row.created_at.isoformat() if row.created_at else ""})
            else:
                signals.append(enrich_history_row(session, row, payload))
        except json.JSONDecodeError:
            continue
    session.commit()
    return {
        "count": len(signals),
        "summary": build_history_summary(signals),
        "live_performance": load_global_live_stats(session),
        "signals": signals,
    }


@router.get("/performance")
def get_signal_performance(session: Session = Depends(get_sync_session)) -> dict:
    """Live tracked win rate and drawdown from stored predictions."""
    return load_global_live_stats(session)
