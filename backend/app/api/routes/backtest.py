from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.backtest.engine import load_candles_for_backtest, persist_backtest, run_backtest
from app.signals.registry import update_cache
from app.db.session import get_sync_session

router = APIRouter(prefix="/backtest", tags=["backtest"])


class BacktestRequest(BaseModel):
    setup_name: str
    instrument: str = "NIFTY"
    segment: str = "spot"
    interval: str = "5m"
    limit: int = Field(default=2000, ge=100, le=10000)


@router.post("")
def run_setup_backtest(
    body: BacktestRequest,
    session: Session = Depends(get_sync_session),
) -> dict:
    df = load_candles_for_backtest(
        session, body.instrument, body.segment, body.interval, body.limit
    )
    if df.empty:
        raise HTTPException(400, "No candle data — sync historical data first")

    from_date = str(df.iloc[0]["timestamp"].date())
    to_date = str(df.iloc[-1]["timestamp"].date())

    try:
        report = run_backtest(
            df,
            body.setup_name,
            body.instrument,
            body.segment,
            body.interval,
            from_date,
            to_date,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc

    row = persist_backtest(session, report)
    update_cache(body.setup_name, body.instrument, body.segment, report.to_stats_dict())

    return {
        "id": row.id,
        "setup_name": report.setup_name,
        "instrument": report.instrument,
        "tradable": report.tradable,
        "stats": report.to_stats_dict(),
        "from_date": from_date,
        "to_date": to_date,
    }
