"""Daily signal caps and session state."""

from __future__ import annotations

from datetime import datetime, timezone, timedelta

from app.alpha.constants import MAX_SIGNALS_PER_DAY, TIER_LIMITS

IST = timezone(timedelta(hours=5, minutes=30))


class AlphaSessionState:
    def __init__(self) -> None:
        self._date = ""
        self._tier_counts: dict[str, int] = {"A+": 0, "A": 0, "B": 0}
        self._total = 0
        self._sl_hits = 0
        self._active_instruments: set[str] = set()
        self._signals: list[dict] = []

    def _refresh(self) -> None:
        today = datetime.now(IST).strftime("%Y-%m-%d")
        if today != self._date:
            self._date = today
            self._tier_counts = {"A+": 0, "A": 0, "B": 0}
            self._total = 0
            self._sl_hits = 0
            self._active_instruments = set()
            self._signals = []

    def can_emit(self, tier: str) -> tuple[bool, str]:
        self._refresh()
        if self._total >= MAX_SIGNALS_PER_DAY:
            return False, f"Daily cap {MAX_SIGNALS_PER_DAY} reached"
        limit = TIER_LIMITS.get(tier, 0)
        if self._tier_counts.get(tier, 0) >= limit:
            return False, f"Tier {tier} daily limit reached"
        return True, ""

    def record_signal(self, signal: dict) -> None:
        self._refresh()
        tier = signal.get("tier", "B")
        self._tier_counts[tier] = self._tier_counts.get(tier, 0) + 1
        self._total += 1
        self._active_instruments.add(signal.get("instrument", ""))
        self._signals.append(signal)

    def record_sl_hit(self) -> None:
        self._refresh()
        self._sl_hits += 1

    @property
    def sl_hits_today(self) -> int:
        self._refresh()
        return self._sl_hits

    @property
    def signal_count(self) -> int:
        self._refresh()
        return self._total

    @property
    def signals_today(self) -> list[dict]:
        self._refresh()
        return list(self._signals)

    @property
    def tier_counts(self) -> dict[str, int]:
        self._refresh()
        return dict(self._tier_counts)


alpha_session = AlphaSessionState()
