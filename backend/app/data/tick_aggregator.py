import logging
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.data.instruments import INTERVAL_MINUTES, LIVE_INTERVALS
from app.data.memory_cache import memory_cache
from app.data.models import Candle
from app.db.session import SyncSessionLocal
from app.db.upsert import dialect_insert, upsert_do_nothing

logger = logging.getLogger(__name__)
IST = ZoneInfo("Asia/Kolkata")
MARKET_OPEN = (9, 15)
MARKET_CLOSE = (15, 30)


@dataclass
class FormingCandle:
    instrument: str
    segment: str
    exchange: str
    interval: str
    timestamp: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0

    def to_dict(self, forming: bool = True) -> dict:
        return {
            "instrument": self.instrument,
            "segment": self.segment,
            "exchange": self.exchange,
            "interval": self.interval,
            "timestamp": self.timestamp.isoformat(),
            "open": self.open,
            "high": self.high,
            "low": self.low,
            "close": self.close,
            "volume": self.volume,
            "forming": forming,
        }

    def update_tick(self, price: float, volume: float = 0.0) -> None:
        self.high = max(self.high, price)
        self.low = min(self.low, price)
        self.close = price
        self.volume += volume


def floor_to_bar_start(ts: datetime, interval: str) -> datetime:
    minutes = INTERVAL_MINUTES[interval]
    local = ts.astimezone(IST)
    session_open = local.replace(
        hour=MARKET_OPEN[0], minute=MARKET_OPEN[1], second=0, microsecond=0
    )
    if local < session_open:
        return session_open
    elapsed_min = int((local - session_open).total_seconds() // 60)
    bar_offset = (elapsed_min // minutes) * minutes
    return session_open + timedelta(minutes=bar_offset)


def _persist_candle(session: Session, candle: FormingCandle) -> None:
    record = {
        "instrument": candle.instrument,
        "exchange": candle.exchange,
        "segment": candle.segment,
        "interval": candle.interval,
        "timestamp": candle.timestamp,
        "open": candle.open,
        "high": candle.high,
        "low": candle.low,
        "close": candle.close,
        "volume": candle.volume,
    }
    stmt = dialect_insert(Candle.__table__).values(record)
    stmt = upsert_do_nothing(
        stmt,
        constraint="uq_candle",
        index_elements=["instrument", "exchange", "segment", "interval", "timestamp"],
    )
    session.execute(stmt)
    session.commit()


class TickAggregator:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._forming: dict[tuple[str, str, str], FormingCandle] = {}
        self._on_update: Callable[[dict], None] | None = None

    def set_update_callback(self, callback: Callable[[dict], None]) -> None:
        self._on_update = callback

    def process_tick(
        self,
        instrument_key: str,
        symbol: str,
        segment: str,
        exchange: str,
        price: float,
        volume: float,
        ts: datetime | None = None,
    ) -> list[dict]:
        ts = ts or datetime.now(timezone.utc)
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)

        updates: list[dict] = []
        with self._lock:
            for interval in LIVE_INTERVALS:
                bar_start = floor_to_bar_start(ts, interval)
                key = (instrument_key, segment, interval)
                current = self._forming.get(key)

                if current and current.timestamp != bar_start:
                    completed = current.to_dict(forming=False)
                    self._flush_completed(current)
                    memory_cache.set_latest_candle(completed)
                    updates.append(completed)
                    current = None

                if current is None:
                    current = FormingCandle(
                        instrument=symbol,
                        segment=segment,
                        exchange=exchange,
                        interval=interval,
                        timestamp=bar_start,
                        open=price,
                        high=price,
                        low=price,
                        close=price,
                        volume=volume,
                    )
                    self._forming[key] = current
                else:
                    current.update_tick(price, volume)

                forming_dict = current.to_dict(forming=True)
                memory_cache.set_forming_candle(forming_dict)
                updates.append(forming_dict)

        for item in updates:
            memory_cache.publish_live_candle(item)
            if self._on_update:
                self._on_update(item)

        return updates

    def _flush_completed(self, candle: FormingCandle) -> None:
        session = SyncSessionLocal()
        try:
            _persist_candle(session, candle)
        except Exception:
            logger.exception("Failed to persist completed candle %s", candle.instrument)
        finally:
            session.close()

        if candle.interval == "5m":
            try:
                from app.signals.scanner import signal_scanner

                signal_scanner.on_bar_close(
                    candle.instrument,
                    candle.segment,
                    candle.exchange,
                    candle.interval,
                    candle.timestamp,
                )
            except Exception:
                logger.exception("Signal scanner failed after bar close")

            try:
                from app.alpha.scanner import alpha_scanner
                from app.config import get_settings

                if get_settings().enable_alpha_engine:
                    alpha_scanner.on_bar_close(candle.instrument, candle.interval)
            except Exception:
                logger.exception("Alpha scanner failed after bar close")


tick_aggregator = TickAggregator()
