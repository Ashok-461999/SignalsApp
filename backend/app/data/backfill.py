import logging
from datetime import date, datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.data.candle_fetcher import candle_fetcher
from app.data.gap_checker import check_gaps
from app.data.instruments import LIVE_INTERVALS, list_enabled_instruments
from app.db.session import SyncSessionLocal

logger = logging.getLogger(__name__)


def backfill_gaps(
    session: Session,
    days: int = 5,
    intervals: tuple[str, ...] = LIVE_INTERVALS,
) -> list[dict]:
    """Backfill missing candles for all enabled instruments using gap-check."""
    to_date = date.today()
    from_date = to_date - timedelta(days=days)
    results: list[dict] = []

    for inst in list_enabled_instruments():
        for interval in intervals:
            try:
                gap_report = check_gaps(
                    session=session,
                    instrument_symbol=inst.symbol,
                    segment=inst.segment,
                    interval=interval,
                    from_date=from_date,
                    to_date=to_date,
                )
            except ValueError as exc:
                logger.warning("Gap check skipped for %s/%s: %s", inst.key, interval, exc)
                continue

            if not gap_report["has_gaps"]:
                results.append(
                    {
                        "instrument": inst.key,
                        "interval": interval,
                        "action": "skipped",
                        "reason": "no gaps",
                    }
                )
                continue

            start_dt = datetime.combine(from_date, datetime.min.time(), tzinfo=timezone.utc)
            end_dt = datetime.now(timezone.utc)

            try:
                sync_result = candle_fetcher.fetch_and_store(
                    session=session,
                    instrument_symbol=inst.symbol,
                    segment=inst.segment,
                    interval=interval,
                    from_date=start_dt,
                    to_date=end_dt,
                )
                sync_result["action"] = "backfilled"
                sync_result["missing_before"] = gap_report["missing_bars"]
                results.append(sync_result)
                logger.info(
                    "Backfilled %s %s %s: inserted %d",
                    inst.key,
                    interval,
                    gap_report["missing_bars"],
                    sync_result["inserted"],
                )
            except Exception as exc:
                logger.exception("Backfill failed for %s %s", inst.key, interval)
                results.append(
                    {
                        "instrument": inst.key,
                        "interval": interval,
                        "action": "failed",
                        "error": str(exc),
                    }
                )

    return results


def run_startup_backfill(days: int = 5) -> list[dict]:
    session = SyncSessionLocal()
    try:
        return backfill_gaps(session, days=days)
    finally:
        session.close()


def sync_all_historical(
    session: Session,
    days: int = 5,
    intervals: tuple[str, ...] = LIVE_INTERVALS,
) -> list[dict]:
    """Fetch historical candles for all enabled instruments."""
    to_date = datetime.now(timezone.utc)
    from_date = to_date - timedelta(days=days)
    results: list[dict] = []

    for inst in list_enabled_instruments():
        for interval in intervals:
            try:
                result = candle_fetcher.fetch_and_store(
                    session=session,
                    instrument_symbol=inst.symbol,
                    segment=inst.segment,
                    interval=interval,
                    from_date=from_date,
                    to_date=to_date,
                )
                result["instrument_key"] = inst.key
                results.append(result)
            except Exception as exc:
                logger.exception("Sync failed for %s %s", inst.key, interval)
                results.append(
                    {"instrument_key": inst.key, "interval": interval, "error": str(exc)}
                )

    return results
