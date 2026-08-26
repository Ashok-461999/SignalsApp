"""Interpret backtest stats — profitable or not before you trade."""

from __future__ import annotations

from typing import Any

import pandas as pd

from app.backtest.engine import run_backtest


def interpret_backtest(stats: dict[str, Any] | None) -> dict[str, Any]:
    stats = stats or {}
    trade_count = int(stats.get("trade_count") or 0)
    note = str(stats.get("note") or "")

    if note == "not backtested" or trade_count < 3:
        return {
            "backtest_profitable": False,
            "backtest_verdict": "NO_DATA",
            "backtest_summary": "No backtest yet — wait for data or skip",
            "backtest_tradable": False,
            "backtest_win_rate": 0.0,
            "backtest_profit_factor": 0.0,
            "backtest_expectancy": 0.0,
            "backtest_max_drawdown": 0.0,
            "backtest_trade_count": trade_count,
        }

    tradable = bool(stats.get("tradable"))
    wr = float(stats.get("win_rate") or 0)
    pf = float(stats.get("profit_factor") or 0)
    exp = float(stats.get("expectancy") or 0)
    mdd = float(stats.get("max_drawdown") or 0)
    rolling = note == "rolling_backtest"

    if tradable:
        verdict = "PROFITABLE"
        summary = (
            f"Backtest profitable — {wr:.0f}% win · PF {pf:.1f} · "
            f"+{exp:.1f} pts/trade · max DD {mdd:.0f}"
        )
    elif wr >= 38 and pf >= 0.95 and exp >= 0:
        verdict = "MARGINAL"
        summary = (
            f"Backtest marginal — {wr:.0f}% win · PF {pf:.1f} · "
            "only take with high confidence"
        )
    else:
        verdict = "NOT_PROFITABLE"
        summary = (
            f"Backtest not profitable — {wr:.0f}% win · PF {pf:.1f} · skip this setup"
        )

    if rolling:
        summary = f"Recent bars: {summary}"

    return {
        "backtest_profitable": tradable,
        "backtest_verdict": verdict,
        "backtest_summary": summary,
        "backtest_tradable": tradable,
        "backtest_win_rate": wr,
        "backtest_profit_factor": pf,
        "backtest_expectancy": exp,
        "backtest_max_drawdown": mdd,
        "backtest_trade_count": trade_count,
    }


def rolling_backtest_stats(
    df: pd.DataFrame,
    setup_name: str,
    instrument: str,
    segment: str = "spot",
) -> dict[str, Any]:
    """Quick backtest on loaded candle window when DB stats are missing or stale."""
    if df is None or len(df) < 80:
        return {"note": "not backtested", "trade_count": 0, "tradable": False}
    try:
        from_date = str(df.iloc[0].get("timestamp", ""))[:10]
        to_date = str(df.iloc[-1].get("timestamp", ""))[:10]
        report = run_backtest(df, setup_name, instrument, segment, "5m", from_date, to_date)
        return {
            "tradable": report.tradable,
            "win_rate": report.win_rate,
            "expectancy": report.expectancy,
            "avg_rr": report.avg_rr,
            "max_drawdown": report.max_drawdown,
            "profit_factor": report.profit_factor,
            "trade_count": report.trade_count,
            "note": "rolling_backtest",
        }
    except Exception:
        return {"note": "not backtested", "trade_count": 0, "tradable": False}
