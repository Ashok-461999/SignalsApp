"""In-memory registry of latest backtest stats per setup."""

import json
import logging
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.data.models import BacktestResult
from app.signals.setups import SETUP_FUNCTIONS

logger = logging.getLogger(__name__)

_stats_cache: dict[str, dict[str, Any]] = {}


def cache_key(setup_name: str, instrument: str, segment: str = "spot") -> str:
    return f"{setup_name}:{instrument}:{segment}"


def update_cache(setup_name: str, instrument: str, segment: str, stats: dict[str, Any]) -> None:
    _stats_cache[cache_key(setup_name, instrument, segment)] = stats


def get_stats(setup_name: str, instrument: str, segment: str = "spot") -> dict[str, Any]:
    key = cache_key(setup_name, instrument, segment)
    if key in _stats_cache:
        return _stats_cache[key]
    return {
        "tradable": False,
        "win_rate": 0,
        "expectancy": 0,
        "max_drawdown": 0,
        "trade_count": 0,
        "note": "not backtested",
    }


def is_tradable(setup_name: str, instrument: str, segment: str = "spot") -> bool:
    return bool(get_stats(setup_name, instrument, segment).get("tradable", False))


def load_latest_from_db(session: Session) -> None:
    for setup_name in SETUP_FUNCTIONS:
        for instrument in ("NIFTY", "BANKNIFTY", "SENSEX"):
            stmt = (
                select(BacktestResult)
                .where(
                    BacktestResult.setup_name == setup_name,
                    BacktestResult.instrument == instrument,
                )
                .order_by(BacktestResult.created_at.desc())
                .limit(1)
            )
            row = session.execute(stmt).scalar_one_or_none()
            if row:
                try:
                    regime = json.loads(row.regime_breakdown)
                except json.JSONDecodeError:
                    regime = {}
                update_cache(
                    setup_name,
                    instrument,
                    row.segment,
                    {
                        "tradable": row.tradable,
                        "win_rate": row.win_rate,
                        "expectancy": row.expectancy,
                        "avg_rr": row.avg_rr,
                        "max_drawdown": row.max_drawdown,
                        "profit_factor": row.profit_factor,
                        "trade_count": row.trade_count,
                        "regime_breakdown": regime,
                    },
                )


def all_setups_summary() -> list[dict[str, Any]]:
    result = []
    for name in SETUP_FUNCTIONS:
        for instrument in ("NIFTY", "BANKNIFTY", "SENSEX"):
            stats = get_stats(name, instrument)
            result.append(
                {
                    "setup_name": name,
                    "instrument": instrument,
                    "segment": "spot",
                    "tradable": stats.get("tradable", False),
                    "stats": stats,
                }
            )
    return result
