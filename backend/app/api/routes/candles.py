from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.data.backfill import sync_all_historical
from app.data.candle_fetcher import candle_fetcher
from app.data.instruments import DATA_LAYER_STATUS, INSTRUMENTS, INTERVALS, list_enabled_instruments
from app.db.session import get_sync_session

router = APIRouter(prefix="/candles", tags=["candles"])


class CandleOut(BaseModel):
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float


class CandlesResponse(BaseModel):
    instrument: str
    segment: str
    interval: str
    count: int
    candles: list[CandleOut]


class SyncRequest(BaseModel):
    instrument: str = "NIFTY"
    segment: str = "spot"
    interval: str = "5m"
    days: int = Field(default=5, ge=1, le=200)


class SyncAllRequest(BaseModel):
    days: int = Field(default=5, ge=1, le=200)
    intervals: list[str] = Field(default_factory=lambda: ["1m", "5m", "15m"])


class SyncResponse(BaseModel):
    instrument: str
    symbol: str | None = None
    segment: str
    interval: str
    from_date: str
    to_date: str
    fetched: int
    inserted: int
    chunks: int


@router.get("", response_model=CandlesResponse)
def get_candles(
    instrument: str = Query("NIFTY", description="NIFTY, BANKNIFTY, or SENSEX"),
    segment: str = Query("spot", description="spot or futures"),
    interval: str = Query("5m", description="1m, 5m, 15m, 1h, 1d"),
    limit: int = Query(200, ge=1, le=2000),
    from_date: date | None = None,
    to_date: date | None = None,
    session: Session = Depends(get_sync_session),
) -> CandlesResponse:
    if interval.lower() not in INTERVALS:
        raise HTTPException(400, f"Invalid interval. Use one of: {list(INTERVALS)}")

    from_dt = datetime.combine(from_date, datetime.min.time(), tzinfo=timezone.utc) if from_date else None
    to_dt = datetime.combine(to_date, datetime.max.time(), tzinfo=timezone.utc) if to_date else None

    try:
        candles = candle_fetcher.get_candles(
            session=session,
            instrument_symbol=instrument,
            interval=interval,
            from_date=from_dt,
            to_date=to_dt,
            limit=limit,
            segment=segment,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc

    return CandlesResponse(
        instrument=instrument.upper(),
        segment=segment.lower(),
        interval=interval.lower(),
        count=len(candles),
        candles=[
            CandleOut(
                timestamp=c.timestamp,
                open=c.open,
                high=c.high,
                low=c.low,
                close=c.close,
                volume=c.volume,
            )
            for c in candles
        ],
    )


@router.post("/sync", response_model=SyncResponse)
def sync_candles(
    body: SyncRequest,
    session: Session = Depends(get_sync_session),
) -> SyncResponse:
    if body.interval.lower() not in INTERVALS:
        raise HTTPException(400, f"Invalid interval. Use one of: {list(INTERVALS)}")

    to_date = datetime.now(timezone.utc)
    from_date = to_date - timedelta(days=body.days)

    try:
        result = candle_fetcher.fetch_and_store(
            session=session,
            instrument_symbol=body.instrument,
            segment=body.segment,
            interval=body.interval,
            from_date=from_date,
            to_date=to_date,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(502, str(exc)) from exc

    return SyncResponse(**result)


@router.post("/sync-all")
def sync_all(
    body: SyncAllRequest,
    session: Session = Depends(get_sync_session),
) -> dict:
    for interval in body.intervals:
        if interval.lower() not in INTERVALS:
            raise HTTPException(400, f"Invalid interval: {interval}")

    results = sync_all_historical(
        session=session,
        days=body.days,
        intervals=tuple(body.intervals),
    )
    return {"count": len(results), "results": results}


@router.get("/instruments")
def list_instruments() -> dict:
    enabled_keys = {inst.key for inst in list_enabled_instruments()}
    disabled = [inst for inst in INSTRUMENTS.values() if inst.key not in enabled_keys]

    return {
        "instruments": [
            {
                "key": inst.key,
                "symbol": inst.symbol,
                "name": inst.name,
                "exchange": inst.exchange,
                "token": inst.token,
                "segment": inst.segment,
                "enabled": inst.enabled,
                "expiry": inst.expiry.isoformat() if inst.expiry else None,
                "availability_note": inst.availability_note,
            }
            for inst in list_enabled_instruments()
        ]
        + [
            {
                "key": inst.key,
                "symbol": inst.symbol,
                "name": inst.name,
                "exchange": inst.exchange,
                "token": inst.token,
                "segment": inst.segment,
                "enabled": False,
                "expiry": inst.expiry.isoformat() if inst.expiry else None,
                "availability_note": inst.availability_note,
            }
            for inst in disabled
        ],
        "intervals": list(INTERVALS.keys()),
        "live_intervals": ["1m", "5m", "15m"],
        "data_layer_status": DATA_LAYER_STATUS,
    }
