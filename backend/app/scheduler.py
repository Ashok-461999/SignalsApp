import logging
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.config import get_settings
from app.data.backfill import run_startup_backfill
from app.data.smartapi_client import smartapi_client
from app.data.websocket_feed import live_feed_service

logger = logging.getLogger(__name__)

_scheduler: BackgroundScheduler | None = None


def _refresh_smartapi_session() -> None:
    settings = get_settings()
    if not settings.smartapi_configured:
        return
    try:
        smartapi_client.refresh_session()
        live_feed_service.reconnect()
        logger.info("Scheduled SmartAPI session refresh completed")
    except Exception:
        logger.exception("Scheduled session refresh failed")


def _run_gap_backfill() -> None:
    settings = get_settings()
    if not settings.smartapi_configured:
        return
    try:
        results = run_startup_backfill(days=settings.backfill_days)
        filled = sum(1 for r in results if r.get("action") == "backfilled")
        logger.info("Scheduled gap backfill complete: %d ranges filled", filled)
    except Exception:
        logger.exception("Scheduled gap backfill failed")


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
    )
    _scheduler.add_job(
        _run_gap_backfill,
        IntervalTrigger(hours=settings.gap_backfill_hours),
        id="gap_backfill",
        replace_existing=True,
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
