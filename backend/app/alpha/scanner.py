"""Alpha engine scanner — scheduled + bar-close triggers."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from sqlalchemy import select

from app.alpha.constants import ALPHA_INSTRUMENTS
from app.alpha.engine import run_alpha_scan
from app.alpha.state import alpha_session
from app.config import get_settings
from app.data.models import Candle
from app.db.session import SyncSessionLocal

logger = logging.getLogger(__name__)


class AlphaScanner:
    def __init__(self) -> None:
        self._last_scan: dict[str, str] = {}
        self._last_result: dict | None = None
        self._subscribers: list = []

    def subscribe(self, callback) -> None:
        self._subscribers.append(callback)

    def get_signals(self) -> list[dict]:
        return alpha_session.signals_today

    def get_last_result(self) -> dict | None:
        return self._last_result

    def _fetch_spots(self, session) -> dict[str, float]:
        spots: dict[str, float] = {}
        for inst in ALPHA_INSTRUMENTS:
            row = session.execute(
                select(Candle)
                .where(Candle.instrument == inst, Candle.segment == "spot", Candle.interval == "5m")
                .order_by(Candle.timestamp.desc())
                .limit(1)
            ).scalar_one_or_none()
            if row and row.close:
                spots[inst] = float(row.close)
        return spots

    def scan(self) -> dict:
        settings = get_settings()
        if not settings.enable_alpha_engine:
            return {"skipped": True, "reason": "Alpha engine disabled"}

        session = SyncSessionLocal()
        try:
            spots = self._fetch_spots(session)
            if not spots:
                return {"skipped": True, "reason": "No spot prices available", "signals": []}

            result = run_alpha_scan(session, spots)
            self._last_result = result
            now = datetime.now(timezone.utc).isoformat()
            for inst in spots:
                self._last_scan[inst] = now

            for sig in result.get("signals") or []:
                for cb in self._subscribers:
                    try:
                        cb(sig)
                    except Exception:
                        logger.exception("Alpha subscriber callback failed")

            logger.info(
                "Alpha scan: %d signal(s), prep=%s",
                len(result.get("signals") or []),
                bool(result.get("prep_report")),
            )
            return result
        except Exception:
            logger.exception("Alpha scan failed")
            return {"error": "scan_failed", "signals": []}
        finally:
            session.close()

    def on_bar_close(self, instrument: str, interval: str) -> None:
        if interval != "5m" or instrument not in ALPHA_INSTRUMENTS:
            return
        self.scan()


alpha_scanner = AlphaScanner()
