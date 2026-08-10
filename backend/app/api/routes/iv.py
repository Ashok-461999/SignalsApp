from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.signals.iv import compute_iv_percentile
from app.db.session import get_sync_session

router = APIRouter(tags=["iv"])


@router.get("/iv-percentile")
def iv_percentile(
    instrument: str = Query("NIFTY"),
    segment: str = Query("spot"),
    interval: str = Query("5m"),
    session: Session = Depends(get_sync_session),
) -> dict:
    return compute_iv_percentile(session, instrument, segment, interval)
