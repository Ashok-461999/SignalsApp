"""CLI entry points for data sync."""

import argparse
import logging
from datetime import datetime, timedelta, timezone

from app.data.backfill import run_startup_backfill, sync_all_historical
from app.data.candle_fetcher import candle_fetcher
from app.data.instrument_master import initialize_futures_registry
from app.db.base import Base
from app.db.migrate import migrate_schema
from app.db.session import SyncSessionLocal, sync_engine

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def init_db() -> None:
    migrate_schema()
    Base.metadata.create_all(bind=sync_engine)
    logger.info("Database tables created")


def sync_candles(instrument: str, interval: str, days: int, segment: str = "spot") -> None:
    init_db()
    session = SyncSessionLocal()
    try:
        to_date = datetime.now(timezone.utc)
        from_date = to_date - timedelta(days=days)
        result = candle_fetcher.fetch_and_store(
            session=session,
            instrument_symbol=instrument,
            segment=segment,
            interval=interval,
            from_date=from_date,
            to_date=to_date,
        )
        logger.info("Sync complete: %s", result)
    finally:
        session.close()


def sync_all(days: int, intervals: list[str]) -> None:
    init_db()
    initialize_futures_registry()
    session = SyncSessionLocal()
    try:
        results = sync_all_historical(session, days=days, intervals=tuple(intervals))
        logger.info("Sync-all complete: %d jobs", len(results))
        for result in results:
            logger.info("  %s", result)
    finally:
        session.close()


def backfill(days: int) -> None:
    init_db()
    initialize_futures_registry()
    results = run_startup_backfill(days=days)
    logger.info("Backfill complete: %d jobs", len(results))


def main() -> None:
    parser = argparse.ArgumentParser(description="SignalApp data CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("init-db", help="Create/migrate database tables")

    sync_parser = sub.add_parser("sync", help="Fetch candles from SmartAPI into Postgres")
    sync_parser.add_argument("--instrument", default="NIFTY")
    sync_parser.add_argument("--segment", default="spot", choices=["spot", "futures"])
    sync_parser.add_argument("--interval", default="5m")
    sync_parser.add_argument("--days", type=int, default=5)

    sync_all_parser = sub.add_parser("sync-all", help="Sync all enabled instruments")
    sync_all_parser.add_argument("--days", type=int, default=5)
    sync_all_parser.add_argument("--intervals", nargs="+", default=["1m", "5m", "15m"])

    backfill_parser = sub.add_parser("backfill", help="Gap-check and backfill missing candles")
    backfill_parser.add_argument("--days", type=int, default=5)

    args = parser.parse_args()

    if args.command == "init-db":
        init_db()
    elif args.command == "sync":
        sync_candles(args.instrument, args.interval, args.days, args.segment)
    elif args.command == "sync-all":
        sync_all(args.days, args.intervals)
    elif args.command == "backfill":
        backfill(args.days)


if __name__ == "__main__":
    main()
