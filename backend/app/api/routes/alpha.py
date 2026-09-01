"""REST endpoints for Options Alpha Engine."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.alpha.constants import ALPHA_INSTRUMENTS, DISCLAIMER
from app.alpha.engine import evaluate_instrument
from app.alpha.scanner import alpha_scanner
from app.alpha.state import alpha_session
from app.data.option_chain import fetch_option_chain
from app.db.session import get_sync_session
from app.services.gift_nifty import get_gift_nifty_snapshot

router = APIRouter(prefix="/alpha", tags=["alpha"])


def _latest_spot(session: Session, instrument: str) -> float:
    from sqlalchemy import select

    from app.data.models import Candle

    row = session.execute(
        select(Candle)
        .where(Candle.instrument == instrument, Candle.segment == "spot", Candle.interval == "5m")
        .order_by(Candle.timestamp.desc())
        .limit(1)
    ).scalar_one_or_none()
    if not row or not row.close:
        raise HTTPException(status_code=404, detail=f"No spot data for {instrument}")
    return float(row.close)


@router.get("/signals")
def get_alpha_signals() -> dict:
    """Today's alpha signals with full Section 10 cards."""
    signals = alpha_scanner.get_signals()
    return {
        "count": len(signals),
        "signal_count_today": alpha_session.signal_count,
        "tier_counts": alpha_session.tier_counts,
        "signals": signals,
        "disclaimer": DISCLAIMER,
        "message": (
            f"{len(signals)} alpha signal(s) today"
            if signals
            else "No alpha signals yet — waiting for confluence ≥70"
        ),
    }


@router.post("/scan")
def trigger_alpha_scan() -> dict:
    """Manually trigger alpha scan (also runs every 5 min on scheduler)."""
    return alpha_scanner.scan()


@router.get("/prep")
def get_prep_report(session: Session = Depends(get_sync_session)) -> dict:
    """Market prep report when fewer than 5 valid signals."""
    last = alpha_scanner.get_last_result()
    if last and last.get("prep_report"):
        return last["prep_report"]

    spots = {}
    instrument_data = {}
    for inst in ALPHA_INSTRUMENTS:
        try:
            spot = _latest_spot(session, inst)
            spots[inst] = spot
            instrument_data[inst] = evaluate_instrument(session, inst, spot)
        except HTTPException:
            continue

    from app.alpha.prep_report import build_prep_report

    gift = get_gift_nifty_snapshot()
    return build_prep_report(instrument_data, gift)


@router.get("/chain/{instrument}")
def get_option_chain(
    instrument: str,
    session: Session = Depends(get_sync_session),
) -> dict:
    """Live option chain with OI walls, PCR, max pain."""
    inst = instrument.upper()
    if inst not in ALPHA_INSTRUMENTS:
        raise HTTPException(status_code=400, detail=f"Unsupported instrument: {instrument}")
    spot = _latest_spot(session, inst)
    chain = fetch_option_chain(inst, spot)
    from app.alpha.chain_metrics import chain_analytics
    from app.alpha.gex import compute_gex

    analytics = chain_analytics(chain)
    gex = compute_gex(chain)
    return {"chain": chain, "analytics": analytics, "gex": gex}


@router.get("/evaluate/{instrument}")
def evaluate_alpha_instrument(
    instrument: str,
    session: Session = Depends(get_sync_session),
) -> dict:
    """Full alpha evaluation for one instrument (no signal emission)."""
    inst = instrument.upper()
    if inst not in ALPHA_INSTRUMENTS:
        raise HTTPException(status_code=400, detail=f"Unsupported instrument: {instrument}")
    spot = _latest_spot(session, inst)
    return evaluate_instrument(session, inst, spot)


@router.get("/status")
def alpha_status() -> dict:
    """Engine status and last scan metadata."""
    last = alpha_scanner.get_last_result() or {}
    return {
        "signal_count_today": alpha_session.signal_count,
        "sl_hits_today": alpha_session.sl_hits_today,
        "last_scan": alpha_scanner._last_scan,
        "instruments_scanned": last.get("instruments", []),
        "last_signal_count": len(last.get("signals") or []),
        "has_prep_report": bool(last.get("prep_report")),
    }
