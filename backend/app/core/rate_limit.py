"""Token-bucket rate limiter for SmartAPI REST calls."""

import logging
import threading
import time

logger = logging.getLogger(__name__)


class RateLimiter:
    def __init__(self, max_calls: int = 8, period: float = 1.0) -> None:
        self._max = max_calls
        self._period = period
        self._lock = threading.Lock()
        self._timestamps: list[float] = []

    def acquire(self) -> None:
        with self._lock:
            now = time.monotonic()
            self._timestamps = [t for t in self._timestamps if now - t < self._period]
            if len(self._timestamps) >= self._max:
                sleep_for = self._period - (now - self._timestamps[0])
                if sleep_for > 0:
                    logger.debug("Rate limit: sleeping %.2fs", sleep_for)
                    time.sleep(sleep_for)
            self._timestamps.append(time.monotonic())


smartapi_rate_limiter = RateLimiter(max_calls=5, period=1.0)
