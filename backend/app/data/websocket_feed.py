import logging
import threading
from datetime import datetime, timezone
from typing import Any

from SmartApi.smartWebSocketV2 import SmartWebSocketV2

from app.config import get_settings
from app.data.instruments import list_enabled_instruments
from app.data.smartapi_client import smartapi_client
from app.data.tick_aggregator import tick_aggregator

logger = logging.getLogger(__name__)


class LiveFeedService:
    """SmartAPI WebSocket V2 feed — subscribes to spot indices, aggregates ticks."""

    def __init__(self) -> None:
        self._thread: threading.Thread | None = None
        self._ws: SmartWebSocketV2 | None = None
        self._running = False
        self._token_map: dict[str, str] = {}
        self._status: dict[str, Any] = {
            "running": False,
            "connected": False,
            "subscribed_tokens": [],
            "last_tick_at": None,
            "last_error": None,
            "reconnect_count": 0,
        }
        self._lock = threading.Lock()

    @property
    def status(self) -> dict[str, Any]:
        with self._lock:
            return dict(self._status)

    def _build_token_map(self) -> dict[str, tuple[str, str, str, str]]:
        """Map ws_token -> (instrument_key, symbol, segment, exchange)."""
        mapping: dict[str, tuple[str, str, str, str]] = {}
        for inst in list_enabled_instruments():
            if inst.segment != "spot":
                continue
            mapping[inst.ws_token] = (inst.key, inst.symbol, inst.segment, inst.exchange)
        return mapping

    def _build_subscription(self) -> list[dict]:
        by_exchange: dict[int, list[str]] = {}
        for inst in list_enabled_instruments():
            if inst.segment != "spot":
                continue
            by_exchange.setdefault(inst.ws_exchange_type, []).append(inst.ws_token)

        return [{"exchangeType": et, "tokens": tokens} for et, tokens in by_exchange.items()]

    def _on_data(self, _wsapp: Any, message: dict) -> None:
        token = str(message.get("token", "")).strip()
        ltp = message.get("last_traded_price")
        if ltp is None:
            return

        price = float(ltp) / 100.0
        info = self._token_map.get(token)
        if not info:
            return

        instrument_key, symbol, segment, exchange = info
        ts_ms = message.get("exchange_timestamp") or message.get("packet_received_time")
        ts = (
            datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)
            if ts_ms
            else datetime.now(timezone.utc)
        )

        tick_aggregator.process_tick(
            instrument_key=instrument_key,
            symbol=symbol,
            segment=segment,
            exchange=exchange,
            price=price,
            volume=0.0,
            ts=ts,
        )

        with self._lock:
            self._status["last_tick_at"] = datetime.now(timezone.utc).isoformat()

    def _on_open(self, _wsapp: Any) -> None:
        logger.info("SmartAPI WebSocket connected, subscribing to indices")
        with self._lock:
            self._status["connected"] = True
            self._status["last_error"] = None

        if self._ws:
            token_list = self._build_subscription()
            self._ws.subscribe("signalapp", SmartWebSocketV2.LTP_MODE, token_list)
            with self._lock:
                self._status["subscribed_tokens"] = [
                    t for group in token_list for t in group["tokens"]
                ]

    def _on_error(self, _wsapp: Any, error: Any) -> None:
        logger.error("SmartAPI WebSocket error: %s", error)
        with self._lock:
            self._status["last_error"] = str(error)
            self._status["connected"] = False

    def _on_close(self, _wsapp: Any) -> None:
        logger.info("SmartAPI WebSocket closed")
        with self._lock:
            self._status["connected"] = False

    def _connect(self) -> None:
        settings = get_settings()
        if not settings.smartapi_configured:
            logger.warning("SmartAPI not configured — live feed disabled")
            return

        while self._running:
            try:
                tokens = smartapi_client.get_tokens()
                self._token_map = {
                    inst.ws_token: (inst.key, inst.symbol, inst.segment, inst.exchange)
                    for inst in list_enabled_instruments()
                    if inst.segment == "spot"
                }

                self._ws = SmartWebSocketV2(
                    auth_token=tokens["auth_token"],
                    api_key=tokens["api_key"],
                    client_code=tokens["client_code"],
                    feed_token=tokens["feed_token"],
                    max_retry_attempt=3,
                    retry_strategy=1,
                    retry_delay=5,
                    retry_multiplier=2,
                    retry_duration=60,
                )
                self._ws.on_open = self._on_open
                self._ws.on_data = self._on_data
                self._ws.on_error = self._on_error
                self._ws.on_close = self._on_close
                self._ws.connect()
            except Exception as exc:
                logger.exception("Live feed connection failed")
                with self._lock:
                    self._status["last_error"] = str(exc)
                    self._status["reconnect_count"] += 1

                if not self._running:
                    break

                try:
                    smartapi_client.refresh_session()
                except Exception:
                    logger.exception("Session refresh during reconnect failed")

                threading.Event().wait(10)

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        with self._lock:
            self._status["running"] = True
        self._thread = threading.Thread(target=self._connect, name="live-feed", daemon=True)
        self._thread.start()
        logger.info("Live feed service started")

    def stop(self) -> None:
        self._running = False
        with self._lock:
            self._status["running"] = False
            self._status["connected"] = False
        if self._ws:
            try:
                self._ws.close_connection()
            except Exception:
                pass
        logger.info("Live feed service stopped")

    def reconnect(self) -> None:
        """Force reconnect after session refresh."""
        if self._ws:
            try:
                self._ws.close_connection()
            except Exception:
                pass


live_feed_service = LiveFeedService()
