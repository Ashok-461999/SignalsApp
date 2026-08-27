"""Resolve historical signal outcomes — SL hit vs profit for options and futures."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.backtest.costs import CostConfig, apply_slippage, round_trip_costs
from app.backtest.engine import HOLDING_BARS
from app.backtest.options import black_scholes_price
from app.config import get_settings
from app.core.index_config import LOT_SIZES
from app.data.models import Candle, SignalLog, SignalPrediction

logger = logging.getLogger(__name__)

def _holding_bars_for_signal(session: Session | None, sig: dict) -> int:
    settings = get_settings()
    style = (sig.get("trading_style") or settings.trading_style or "hybrid").lower()
    if session is not None:
        from app.services.trading_settings import load_trading_settings

        trading = load_trading_settings(session)
        style = (trading.trading_style or style).lower()
    if style == "scalp":
        return max(3, int(settings.scalp_holding_bars))
    if style == "hybrid":
        return max(int(settings.scalp_holding_bars) * 4, HOLDING_BARS)
    return HOLDING_BARS


def _holding_bars(session: Session | None = None) -> int:
    settings = get_settings()
    style = (settings.trading_style or "hybrid").lower()
    if session is not None:
        from app.services.trading_settings import load_trading_settings

        trading = load_trading_settings(session)
        style = (trading.trading_style or style).lower()
    if style == "scalp":
        return max(3, int(settings.scalp_holding_bars))
    return HOLDING_BARS


DEFAULT_IV = 0.14


def _parse_ts(value: str | datetime | None) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def _outcome_label(outcome: str, premium_stop: float = 0) -> str:
    if outcome == "sl_hit" and premium_stop > 0:
        return f"SL hit — exit below ₹{premium_stop:.0f}"
    return {
        "profit": "Target hit",
        "sl_hit": "SL hit",
        "time_exit": "Time exit",
        "open": "Still open",
        "na": "No trade",
    }.get(outcome, outcome)


def _result_dict(
    outcome: str,
    pnl_value: float | None = None,
    pnl_pct: float | None = None,
    exit_reason: str = "",
    premium_stop: float = 0,
) -> dict[str, Any]:
    return {
        "outcome": outcome,
        "label": _outcome_label(outcome, premium_stop),
        "pnl_value": round(pnl_value, 2) if pnl_value is not None else None,
        "pnl_pct": round(pnl_pct, 2) if pnl_pct is not None else None,
        "exit_reason": exit_reason,
        "premium_stop_hit": premium_stop if outcome == "sl_hit" and premium_stop > 0 else None,
    }


def _load_candles_after(
    session: Session,
    instrument: str,
    segment: str,
    after: datetime,
    limit: int | None = None,
    sig: dict | None = None,
) -> list[Candle]:
    bars = limit or (_holding_bars_for_signal(session, sig or {}) + 5)
    stmt = (
        select(Candle)
        .where(
            Candle.instrument == instrument,
            Candle.segment == segment,
            Candle.interval == "5m",
            Candle.timestamp > after,
        )
        .order_by(Candle.timestamp.asc())
        .limit(bars)
    )
    return list(session.execute(stmt).scalars().all())


def resolve_outcomes(session: Session, sig: dict, logged_at: datetime | None = None) -> dict[str, Any]:
    """Simulate futures + options result for a logged signal."""
    entry = float(sig.get("underlying_entry") or 0)
    stop = float(sig.get("underlying_stop_loss") or 0)
    targets = sig.get("underlying_target") or []
    direction = sig.get("direction") or "neutral"
    instrument = sig.get("instrument") or ""
    segment = sig.get("segment") or "spot"
    trade_decision = sig.get("trade_decision") or "NO_TRADE"
    position_size = int(sig.get("position_size") or 1)
    entry_prem = float(sig.get("entry_premium_estimate") or sig.get("premium_entry") or 0)
    strike = float(sig.get("suggested_strike") or 0)
    days_to_exp = float(sig.get("days_to_expiry") or 7)
    iv_pct = float(sig.get("iv_percentile") or 50)
    iv = max(0.08, min(0.45, iv_pct / 100.0 * 0.2 + 0.1))
    prem_sl_ref = float(
        sig.get("premium_stop") or sig.get("strict_sl_premium") or sig.get("premium_stop_reference") or 0
    )

    holding = _holding_bars_for_signal(session, sig)

    if trade_decision == "SIT_OUT" or entry <= 0 or stop <= 0 or not targets:
        return {
            "futures_result": _result_dict("na"),
            "options_result": _result_dict("na"),
        }

    signal_ts = _parse_ts(sig.get("timestamp")) or logged_at
    if signal_ts is None:
        return {
            "futures_result": _result_dict("na"),
            "options_result": _result_dict("na"),
        }

    candles = _load_candles_after(session, instrument, segment, signal_ts, sig=sig)
    if not candles:
        return {
            "futures_result": _result_dict("open"),
            "options_result": _result_dict("open"),
        }

    target = float(targets[0])
    opt_type = "call" if direction == "bullish" else "put"
    lot = LOT_SIZES.get(instrument.upper(), 25)
    cfg = CostConfig()

    exit_underlying: float | None = None
    exit_reason = ""
    exit_bar_idx = 0

    for idx, bar in enumerate(candles[:holding]):
        high, low = float(bar.high), float(bar.low)
        exit_bar_idx = idx

        if direction == "bullish":
            if low <= stop:
                exit_underlying = stop
                exit_reason = "stop"
                break
            if high >= target:
                exit_underlying = target
                exit_reason = "target_1"
                break
        elif direction == "bearish":
            if high >= stop:
                exit_underlying = stop
                exit_reason = "stop"
                break
            if low <= target:
                exit_underlying = target
                exit_reason = "target_1"
                break

    if exit_underlying is None:
        last = candles[min(holding - 1, len(candles) - 1)]
        exit_underlying = float(last.close)
        exit_reason = "time_exit"
        exit_bar_idx = min(holding - 1, len(candles) - 1)

    if exit_reason == "stop":
        outcome = "sl_hit"
    elif exit_reason.startswith("target"):
        outcome = "profit"
    else:
        outcome = "time_exit"

    # Futures P&L (points)
    if direction == "bullish":
        fut_points = exit_underlying - entry
    elif direction == "bearish":
        fut_points = entry - exit_underlying
    else:
        fut_points = 0.0
    fut_pct = (fut_points / entry * 100) if entry > 0 else 0.0
    fut_outcome = outcome if fut_points >= 0 and outcome == "profit" else (
        "sl_hit" if exit_reason == "stop" else outcome
    )
    if exit_reason == "stop":
        fut_outcome = "sl_hit"
    elif exit_reason.startswith("target"):
        fut_outcome = "profit"

    futures_result = _result_dict(fut_outcome, fut_points, fut_pct, exit_reason, prem_sl_ref)

    # Options P&L estimate
    if strike <= 0 or entry_prem <= 0:
        options_result = _result_dict("na")
    else:
        days_left = max(days_to_exp - exit_bar_idx * (5 / (24 * 60)) * 0.2, 0.5)
        if exit_reason == "stop" and prem_sl_ref > 0:
            exit_prem = apply_slippage(prem_sl_ref, "sell", cfg.slippage_pct)
        else:
            exit_prem = black_scholes_price(exit_underlying, strike, days_left, iv, opt_type)
            exit_prem = apply_slippage(exit_prem, "sell", cfg.slippage_pct)
        entry_prem_adj = apply_slippage(entry_prem, "buy", cfg.slippage_pct)
        gross = (exit_prem - entry_prem_adj) * lot * max(position_size, 1)
        costs = round_trip_costs(entry_prem_adj, exit_prem, lot, cfg) * max(position_size, 1)
        opt_pnl = gross - costs
        opt_pct = (opt_pnl / (entry_prem_adj * lot * max(position_size, 1)) * 100) if entry_prem_adj > 0 else 0
        opt_outcome = "profit" if opt_pnl > 0 else "sl_hit" if opt_pnl < 0 else "time_exit"
        if exit_reason == "stop":
            opt_outcome = "sl_hit"
        elif exit_reason.startswith("target"):
            opt_outcome = "profit" if opt_pnl >= 0 else "sl_hit"
        options_result = _result_dict(opt_outcome, opt_pnl, opt_pct, exit_reason, prem_sl_ref)

    return {
        "futures_result": futures_result,
        "options_result": options_result,
    }


def _verdict_for_result(result: dict) -> str:
    outcome = (result or {}).get("outcome") or ""
    pnl = (result or {}).get("pnl_value")
    if outcome == "profit":
        return "WIN"
    if outcome == "sl_hit":
        return "FAIL"
    if outcome == "time_exit":
        if pnl is not None and float(pnl) < 0:
            return "FAIL"
        if pnl is not None and float(pnl) > 0:
            return "WIN"
        return "FLAT"
    if outcome == "open":
        return "OPEN"
    return "—"


def _max_drawdown(pnls: list[float]) -> float:
    peak = 0.0
    max_dd = 0.0
    cumulative = 0.0
    for pnl in pnls:
        cumulative += pnl
        peak = max(peak, cumulative)
        max_dd = max(max_dd, peak - cumulative)
    return round(max_dd, 2)


def enrich_history_row(session: Session, row: SignalLog, payload: dict) -> dict:
    outcomes = resolve_outcomes(session, payload, row.created_at)
    _update_prediction_record(session, row.id, outcomes)
    opt = outcomes.get("options_result") or {}
    fut = outcomes.get("futures_result") or {}
    return {
        **payload,
        "log_id": row.id,
        "logged_at": row.created_at.isoformat() if row.created_at else "",
        **outcomes,
        "options_verdict": _verdict_for_result(opt),
        "futures_verdict": _verdict_for_result(fut),
    }


def _update_prediction_record(session: Session, log_id: int, outcomes: dict) -> None:
    pred = session.execute(
        select(SignalPrediction).where(SignalPrediction.signal_log_id == log_id)
    ).scalar_one_or_none()
    if not pred:
        return
    opt = outcomes.get("options_result") or {}
    fut = outcomes.get("futures_result") or {}
    pred.options_outcome = opt.get("outcome") or ""
    pred.futures_outcome = fut.get("outcome") or ""
    pred.options_pnl = opt.get("pnl_value")
    pred.resolved = opt.get("outcome") not in ("", "open", "na")
    session.flush()


def build_history_summary(signals: list[dict]) -> dict[str, Any]:
    def _count(subs: list[dict], result_key: str, outcome: str) -> int:
        return sum(1 for s in subs if (s.get(result_key) or {}).get("outcome") == outcome)

    take_only = [s for s in signals if s.get("can_take") or s.get("trade_decision") == "TAKE"]
    all_fired = [s for s in signals if float(s.get("underlying_entry") or 0) > 0 and s.get("trade_decision") != "SIT_OUT"]

    def _win_rate(subs: list[dict], key: str) -> float:
        closed = [s for s in subs if (s.get(key) or {}).get("outcome") in ("profit", "sl_hit", "time_exit")]
        if not closed:
            return 0.0
        wins = sum(1 for s in closed if (s.get(key) or {}).get("outcome") == "profit")
        return round(wins / len(closed) * 100, 1)

    def _verdict_counts(subs: list[dict], verdict_key: str) -> dict[str, int]:
        return {
            "win": sum(1 for s in subs if s.get(verdict_key) == "WIN"),
            "fail": sum(1 for s in subs if s.get(verdict_key) == "FAIL"),
            "open": sum(1 for s in subs if s.get(verdict_key) == "OPEN"),
        }

    take_opt_closed = [
        s for s in take_only
        if (s.get("options_result") or {}).get("outcome") in ("profit", "sl_hit", "time_exit")
    ]
    opt_pnls = [
        float((s.get("options_result") or {}).get("pnl_value") or 0)
        for s in take_opt_closed
    ]
    fut_pnls = [
        float((s.get("futures_result") or {}).get("pnl_value") or 0)
        for s in take_only
        if (s.get("futures_result") or {}).get("outcome") in ("profit", "sl_hit", "time_exit")
    ]
    opt_verdicts = _verdict_counts(take_only, "options_verdict")

    setup_stats: dict[str, dict[str, Any]] = {}
    for setup in {s.get("setup_name") for s in take_only if s.get("setup_name")}:
        subset = [s for s in take_only if s.get("setup_name") == setup]
        closed = [
            s for s in subset
            if (s.get("options_result") or {}).get("outcome") in ("profit", "sl_hit", "time_exit")
        ]
        wins = sum(1 for s in closed if s.get("options_verdict") == "WIN")
        pnls = [float((s.get("options_result") or {}).get("pnl_value") or 0) for s in closed]
        setup_stats[setup] = {
            "trades": len(closed),
            "wins": wins,
            "losses": len(closed) - wins,
            "win_rate": round(wins / len(closed) * 100, 1) if closed else 0.0,
            "max_drawdown_inr": _max_drawdown(pnls),
        }

    return {
        "total": len(signals),
        "take_signals": len(take_only),
        "resolved_trades": len(all_fired),
        "options_profit": _count(all_fired, "options_result", "profit"),
        "options_sl_hit": _count(all_fired, "options_result", "sl_hit"),
        "options_open": _count(all_fired, "options_result", "open"),
        "futures_profit": _count(all_fired, "futures_result", "profit"),
        "futures_sl_hit": _count(all_fired, "futures_result", "sl_hit"),
        "futures_open": _count(all_fired, "futures_result", "open"),
        "take_options_win_rate": _win_rate(take_only, "options_result"),
        "take_futures_win_rate": _win_rate(take_only, "futures_result"),
        "take_options_wins": opt_verdicts["win"],
        "take_options_fails": opt_verdicts["fail"],
        "take_options_open": opt_verdicts["open"],
        "take_max_drawdown_inr": _max_drawdown(opt_pnls),
        "take_total_pnl_inr": round(sum(opt_pnls), 2),
        "take_futures_max_drawdown_pts": _max_drawdown(fut_pnls),
        "setup_stats": setup_stats,
        "scalp_holding_bars": get_settings().scalp_holding_bars,
        "note": "Win rate & drawdown from TAKE signals — options primary leg",
    }
