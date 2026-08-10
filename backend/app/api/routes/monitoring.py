"""Monitoring endpoint for feed health and session status."""

from datetime import datetime, timezone

from fastapi import APIRouter

from app.config import get_settings
from app.data.smartapi_client import smartapi_client
from app.data.websocket_feed import live_feed_service
from app.signals.scanner import signal_scanner

router = APIRouter(prefix="/monitoring", tags=["monitoring"])


@router.get("")
def monitoring() -> dict:
    settings = get_settings()
    feed = live_feed_service.status
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "feed": feed,
        "smartapi": smartapi_client.health_check(),
        "active_signals": len(signal_scanner.get_active_signals()),
        "paper_trading": settings.paper_trading,
        "live_execution_enabled": settings.live_execution_enabled,
        "kill_switch": settings.kill_switch,
        "last_candle_times": getattr(signal_scanner, "_last_scan", {}),
    }
