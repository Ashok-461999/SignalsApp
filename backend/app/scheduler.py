import logging
import threading

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.config import get_settings
from app.core.timeouts import run_with_timeout
from app.data.backfill import run_startup_backfill
from app.data.smartapi_client import smartapi_client

logger = logging.getLogger(__name__)

_scheduler: BackgroundScheduler | None = None
_backfill_running = threading.Lock()


def _refresh_smartapi_session() -> None:
    settings = get_settings()
    if not settings.smartapi_configured:
        return

    def _work() -> None:
        smartapi_client.refresh_session()
        # Feed thread reconnects on its own when WS drops — do not call reconnect()
        # from here (it was blocking the scheduler for days).

    result = run_with_timeout(_work, timeout_seconds=25, label="SmartAPI session refresh")
    if result is None:
        logger.error("SmartAPI session refresh skipped (timeout or error)")
    else:
        logger.info("Scheduled SmartAPI session refresh completed")


def _gap_backfill_worker() -> None:
    settings = get_settings()
    if not settings.smartapi_configured:
        return
    try:
        results = run_startup_backfill(days=settings.backfill_days)
        filled = sum(1 for r in results if r.get("action") == "backfilled")
        logger.info("Scheduled gap backfill complete: %d ranges filled", filled)
    except Exception:
        logger.exception("Scheduled gap backfill failed")


def _run_gap_backfill() -> None:
    """Fire-and-forget — never block the scheduler thread on long backfills."""
    if not _backfill_running.acquire(blocking=False):
        logger.info("Gap backfill already running — skipping")
        return

    def _runner() -> None:
        try:
            _gap_backfill_worker()
        finally:
            _backfill_running.release()

    threading.Thread(target=_runner, name="gap-backfill", daemon=True).start()


def _backtest_worker() -> None:
    from app.backtest.engine import load_candles_for_backtest, persist_backtest, run_backtest
    from app.core.index_config import INDEX_SYMBOLS
    from app.db.session import SyncSessionLocal
    from app.signals.registry import load_latest_from_db
    from app.signals.setups import SETUP_FUNCTIONS

    session = SyncSessionLocal()
    try:
        for instrument in INDEX_SYMBOLS:
            df = load_candles_for_backtest(session, instrument, "spot", "5m", limit=8000)
            if df.empty or len(df) < 120:
                continue
            from_date = str(df.iloc[0].get("timestamp", ""))[:10]
            to_date = str(df.iloc[-1].get("timestamp", ""))[:10]
            for setup_name in SETUP_FUNCTIONS:
                try:
                    report = run_backtest(
                        df, setup_name, instrument, "spot", "5m", from_date, to_date
                    )
                    persist_backtest(session, report)
                except Exception:
                    logger.exception("Backtest failed %s %s", setup_name, instrument)
        load_latest_from_db(session)
        logger.info("Scheduled setup backtests completed")
    except Exception:
        logger.exception("Scheduled backtest job failed")
    finally:
        session.close()


def _run_setup_backtests() -> None:
    threading.Thread(target=_backtest_worker, name="setup-backtests", daemon=True).start()


def _alpha_scan_worker() -> None:
    try:
        from app.alpha.scanner import alpha_scanner

        alpha_scanner.scan()
    except Exception:
        logger.exception("Alpha scan job failed")


def _run_alpha_scan() -> None:
    threading.Thread(target=_alpha_scan_worker, name="alpha-scan", daemon=True).start()


def start_scheduler() -> BackgroundScheduler | None:
    global _scheduler
    settings = get_settings()
    if not settings.enable_scheduler:
        logger.info("Scheduler disabled")
        return None

    _scheduler = BackgroundScheduler(timezone="Asia/Kolkata")
    _scheduler.add_job(
        _refresh_smartapi_session,
        IntervalTrigger(hours=settings.session_refresh_hours),
        id="session_refresh",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        misfire_grace_time=300,
    )
    _scheduler.add_job(
        _run_gap_backfill,
        IntervalTrigger(hours=settings.gap_backfill_hours),
        id="gap_backfill",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        misfire_grace_time=600,
    )
    _scheduler.add_job(
        _run_setup_backtests,
        IntervalTrigger(hours=24),
        id="setup_backtests",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        misfire_grace_time=3600,
    )
    if settings.enable_alpha_engine:
        _scheduler.add_job(
            _run_alpha_scan,
            IntervalTrigger(minutes=settings.alpha_scan_minutes),
            id="alpha_scan",
            replace_existing=True,
            max_instances=1,
            coalesce=True,
            misfire_grace_time=120,
        )
    _scheduler.start()
    logger.info("Background scheduler started")
    return _scheduler


def stop_scheduler() -> None:
    global _scheduler
    if _scheduler:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("Background scheduler stopped")
