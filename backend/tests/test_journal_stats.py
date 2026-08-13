from datetime import datetime, timezone
from types import SimpleNamespace

from app.api.routes.journal_stats import build_journal_summary, calc_option_pnl


def test_calc_option_pnl_nifty():
    assert calc_option_pnl(100, 120, "NIFTY", 2) == 1000.0  # 20 * 25 * 2


def test_summary_includes_losses_in_total():
    entries = [
        SimpleNamespace(
            pnl=500.0,
            status="closed",
            created_at=datetime.now(timezone.utc),
            instrument="NIFTY",
            planned_size=1,
        ),
        SimpleNamespace(
            pnl=-300.0,
            status="closed",
            created_at=datetime.now(timezone.utc),
            instrument="NIFTY",
            planned_size=1,
        ),
    ]
    summary = build_journal_summary(entries)
    assert summary["total_pnl"] == 200.0
    assert summary["wins"] == 1
    assert summary["losses"] == 1
