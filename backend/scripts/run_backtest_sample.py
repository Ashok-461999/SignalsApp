"""Run sample NIFTY backtest for all setups."""

import logging

from app.backtest.engine import load_candles_for_backtest, persist_backtest, run_backtest
from app.db.base import Base
from app.db.session import SyncSessionLocal, sync_engine
from app.signals.registry import update_cache
from app.signals.setups import SETUP_FUNCTIONS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main() -> None:
    Base.metadata.create_all(bind=sync_engine)
    session = SyncSessionLocal()
    try:
        df = load_candles_for_backtest(session, "NIFTY", "spot", "5m")
        if df.empty:
            logger.error("No NIFTY candles — run: python -m scripts.sync_candles sync-all")
            return

        from_date = str(df.iloc[0]["timestamp"].date())
        to_date = str(df.iloc[-1]["timestamp"].date())

        for setup_name in SETUP_FUNCTIONS:
            report = run_backtest(df, setup_name, "NIFTY", "spot", "5m", from_date, to_date)
            persist_backtest(session, report)
            update_cache(setup_name, "NIFTY", "spot", report.to_stats_dict())
            logger.info(
                "%s: trades=%d win_rate=%.1f%% tradable=%s",
                setup_name,
                report.trade_count,
                report.win_rate,
                report.tradable,
            )
    finally:
        session.close()


if __name__ == "__main__":
    main()
