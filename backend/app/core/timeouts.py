"""Run blocking calls with a hard timeout so API/scheduler threads never hang forever."""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from typing import Callable, TypeVar

logger = logging.getLogger(__name__)

T = TypeVar("T")


def run_with_timeout(func: Callable[[], T], timeout_seconds: float, label: str = "operation") -> T | None:
    """Return func() result or None if it exceeds timeout_seconds."""
    with ThreadPoolExecutor(max_workers=1, thread_name_prefix="timeout") as pool:
        future = pool.submit(func)
        try:
            return future.result(timeout=timeout_seconds)
        except FuturesTimeout:
            logger.warning("%s timed out after %.0fs", label, timeout_seconds)
            return None
        except Exception:
            logger.exception("%s failed", label)
            return None
