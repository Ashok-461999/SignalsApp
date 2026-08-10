from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.data.gap_checker import check_gaps
from app.data.instruments import INTERVALS
from app.db.session import get_sync_session

router = APIRouter(prefix="/gaps", tags=["gaps"])


@router.get("")
def get_gaps(
    instrument: str = Query("NIFTY"),
    segment: str = Query("spot"),
    interval: str = Query("5m"),
    from_date: date | None = None,
    to_date: date | None = None,
    session: Session = Depends(get_sync_session),
) -> dict:
    if interval.lower() not in INTERVALS:
        raise HTTPException(400, f"Invalid interval. Use one of: {list(INTERVALS)}")

    if to_date is None:
        to_date = date.today()
    if from_date is None:
        from_date = to_date - timedelta(days=5)

    if from_date > to_date:
        raise HTTPException(400, "from_date must be <= to_date")

    try:
        return check_gaps(
            session=session,
            instrument_symbol=instrument,
            segment=segment,
            interval=interval,
            from_date=from_date,
            to_date=to_date,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
