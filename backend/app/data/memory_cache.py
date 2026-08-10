import logging
from collections import deque
from threading import Lock
from typing import Any, Callable

logger = logging.getLogger(__name__)

MAX_RECENT_EVENTS = 500


class MemoryCache:
    """In-process cache replacing Redis for live candle state on single-VM deploy."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._forming: dict[str, dict[str, Any]] = {}
        self._latest: dict[str, dict[str, Any]] = {}
        self._recent: deque[dict[str, Any]] = deque(maxlen=MAX_RECENT_EVENTS)
        self._subscribers: list[Callable[[dict[str, Any]], None]] = []

    def ping(self) -> bool:
        return True

    def _key(self, instrument: str, segment: str, interval: str) -> str:
        return f"{instrument}:{segment}:{interval}"

    def subscribe(self, callback: Callable[[dict[str, Any]], None]) -> None:
        with self._lock:
            self._subscribers.append(callback)

    def set_forming_candle(self, candle: dict[str, Any]) -> None:
        key = self._key(candle["instrument"], candle["segment"], candle["interval"])
        with self._lock:
            self._forming[key] = candle

    def set_latest_candle(self, candle: dict[str, Any]) -> None:
        key = self._key(candle["instrument"], candle["segment"], candle["interval"])
        with self._lock:
            self._latest[key] = candle

    def get_forming_candle(self, instrument: str, segment: str, interval: str) -> dict | None:
        key = self._key(instrument, segment, interval)
        with self._lock:
            return self._forming.get(key)

    def get_all_forming(self) -> list[dict]:
        with self._lock:
            return list(self._forming.values())

    def publish_live_candle(self, candle: dict[str, Any]) -> None:
        key = self._key(candle["instrument"], candle["segment"], candle["interval"])
        with self._lock:
            if candle.get("forming"):
                self._forming[key] = candle
            else:
                self._latest[key] = candle
            self._recent.append(candle)
            subscribers = list(self._subscribers)

        for callback in subscribers:
            try:
                callback(candle)
            except Exception:
                logger.exception("Live candle subscriber callback failed")

    def stats(self) -> dict[str, Any]:
        with self._lock:
            return {
                "forming_count": len(self._forming),
                "latest_count": len(self._latest),
                "recent_events": len(self._recent),
                "subscribers": len(self._subscribers),
            }


memory_cache = MemoryCache()
