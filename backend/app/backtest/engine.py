"""Backtest engine — replays setups with same logic as live signals."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

import numpy as np
import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.backtest.costs import CostConfig, apply_slippage, round_trip_costs
from app.backtest.options import (
    atm_strike,
    black_scholes_price,
    nearest_weekly_expiry,
    strike_step,
)
from app.data.models import BacktestResult, Candle
from app.signals.schemas import SetupResult
from app.signals.setups import SETUP_FUNCTIONS

logger = logging.getLogger(__name__)

LOT_SIZES = {"NIFTY": 25, "BANKNIFTY": 15, "SENSEX": 10}
DEFAULT_IV = 0.14
HOLDING_BARS = 30


@dataclass
class Trade:
    setup_name: str
    direction: str
    entry_time: datetime
    exit_time: datetime | None
    entry_underlying: float
    exit_underlying: float | None
    entry_premium: float
    exit_premium: float | None
    stop: float
    targets: list[float]
    pnl: float = 0.0
    r_multiple: float = 0.0
    regime: str = "mid"
    exit_reason: str = ""


@dataclass
class BacktestReport:
    setup_name: str
    instrument: str
    segment: str
    interval: str
    from_date: str
    to_date: str
    trade_count: int
    win_rate: float
    expectancy: float
    avg_rr: float
    max_drawdown: float
    profit_factor: float
    tradable: bool
    regime_breakdown: dict[str, Any] = field(default_factory=dict)
    trades: list[Trade] = field(default_factory=list)

    def to_stats_dict(self) -> dict[str, Any]:
        return {
            "trade_count": self.trade_count,
            "win_rate": self.win_rate,
            "expectancy": self.expectancy,
            "avg_rr": self.avg_rr,
            "max_drawdown": self.max_drawdown,
            "profit_factor": self.profit_factor,
            "tradable": self.tradable,
            "regime_breakdown": self.regime_breakdown,
        }


def candles_to_df(candles: list[Candle]) -> pd.DataFrame:
    rows = [
        {
            "timestamp": c.timestamp,
            "open": c.open,
            "high": c.high,
            "low": c.low,
            "close": c.close,
            "volume": c.volume,
        }
        for c in candles
    ]
    df = pd.DataFrame(rows)
    if df.empty:
        return df
    return df.sort_values("timestamp").reset_index(drop=True)


def _atr_regime(df: pd.DataFrame, idx: int) -> str:
    from app.signals.indicators import atr

    if idx < 20:
        return "mid"
    sub = df.iloc[: idx + 1]
    a = atr(sub, 14)
    if a.isna().iloc[-1]:
        return "mid"
    val = float(a.iloc[-1])
    hist = a.iloc[-60:].dropna()
    if len(hist) < 10:
        return "mid"
    p33, p66 = np.percentile(hist, [33, 66])
    if val <= p33:
        return "low_vol"
    if val >= p66:
        return "high_vol"
    return "mid"


def _simulate_trade(
    df: pd.DataFrame,
    entry_idx: int,
    result: SetupResult,
    instrument: str,
    cfg: CostConfig,
) -> Trade | None:
    if not result.fired or result.entry is None or result.stop_loss is None:
        return None

    lot = LOT_SIZES.get(instrument.upper(), 25)
    step = strike_step(instrument)
    direction = result.direction or "bullish"
    opt_type = "call" if direction == "bullish" else "put"
    strike = atm_strike(result.entry, step)
    iv = DEFAULT_IV

    entry_prem = black_scholes_price(result.entry, strike, 7, iv, opt_type)
    entry_prem = apply_slippage(entry_prem, "buy", cfg.slippage_pct)

    trade = Trade(
        setup_name=result.setup_name,
        direction=direction,
        entry_time=df.iloc[entry_idx]["timestamp"],
        exit_time=None,
        entry_underlying=result.entry,
        exit_underlying=None,
        entry_premium=entry_prem,
        exit_premium=None,
        stop=result.stop_loss,
        targets=result.targets,
        regime=_atr_regime(df, entry_idx),
    )

    for j in range(entry_idx + 1, min(entry_idx + HOLDING_BARS + 1, len(df))):
        bar = df.iloc[j]
        high, low, close = float(bar["high"]), float(bar["low"]), float(bar["close"])
        days_left = max(7 - (j - entry_idx) * 0.2, 0.5)

        if direction == "bullish":
            if low <= result.stop_loss:
                trade.exit_underlying = result.stop_loss
                trade.exit_premium = apply_slippage(
                    black_scholes_price(result.stop_loss, strike, days_left, iv, opt_type),
                    "sell",
                    cfg.slippage_pct,
                )
                trade.exit_time = bar["timestamp"]
                trade.exit_reason = "stop"
                break
            for k, tgt in enumerate(result.targets):
                if high >= tgt:
                    trade.exit_underlying = tgt
                    trade.exit_premium = apply_slippage(
                        black_scholes_price(tgt, strike, days_left, iv, opt_type),
                        "sell",
                        cfg.slippage_pct,
                    )
                    trade.exit_time = bar["timestamp"]
                    trade.exit_reason = f"target_{k+1}"
                    break
        else:
            if high >= result.stop_loss:
                trade.exit_underlying = result.stop_loss
                trade.exit_premium = apply_slippage(
                    black_scholes_price(result.stop_loss, strike, days_left, iv, opt_type),
                    "sell",
                    cfg.slippage_pct,
                )
                trade.exit_time = bar["timestamp"]
                trade.exit_reason = "stop"
                break
            for k, tgt in enumerate(result.targets):
                if low <= tgt:
                    trade.exit_underlying = tgt
                    trade.exit_premium = apply_slippage(
                        black_scholes_price(tgt, strike, days_left, iv, opt_type),
                        "sell",
                        cfg.slippage_pct,
                    )
                    trade.exit_time = bar["timestamp"]
                    trade.exit_reason = f"target_{k+1}"
                    break

        if trade.exit_time:
            break

    if trade.exit_time is None:
        last = df.iloc[min(entry_idx + HOLDING_BARS, len(df) - 1)]
        trade.exit_underlying = float(last["close"])
        trade.exit_premium = apply_slippage(
            black_scholes_price(trade.exit_underlying, strike, 1, iv, opt_type),
            "sell",
            cfg.slippage_pct,
        )
        trade.exit_time = last["timestamp"]
        trade.exit_reason = "time_exit"

    gross = (trade.exit_premium - trade.entry_premium) * lot
    costs = round_trip_costs(trade.entry_premium, trade.exit_premium or 0, lot, cfg)
    trade.pnl = gross - costs

    risk = abs(trade.entry_underlying - trade.stop)
    if risk > 0:
        trade.r_multiple = (trade.exit_underlying - trade.entry_underlying) / risk
        if direction == "bearish":
            trade.r_multiple *= -1

    return trade


def run_backtest(
    df: pd.DataFrame,
    setup_name: str,
    instrument: str,
    segment: str = "spot",
    interval: str = "5m",
    from_date: str = "",
    to_date: str = "",
    cfg: CostConfig | None = None,
) -> BacktestReport:
    cfg = cfg or CostConfig()
    fn = SETUP_FUNCTIONS.get(setup_name)
    if fn is None:
        raise ValueError(f"Unknown setup: {setup_name}")

    trades: list[Trade] = []
    min_bars = 60
    cooldown = 5
    last_entry = -cooldown

    for i in range(min_bars, len(df)):
        if i - last_entry < cooldown:
            continue
        window = df.iloc[: i + 1]
        result = fn(window)
        if result.fired:
            trade = _simulate_trade(df, i, result, instrument, cfg)
            if trade:
                trades.append(trade)
                last_entry = i

    if not trades:
        return BacktestReport(
            setup_name=setup_name,
            instrument=instrument,
            segment=segment,
            interval=interval,
            from_date=from_date,
            to_date=to_date,
            trade_count=0,
            win_rate=0.0,
            expectancy=0.0,
            avg_rr=0.0,
            max_drawdown=0.0,
            profit_factor=0.0,
            tradable=False,
        )

    pnls = [t.pnl for t in trades]
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p <= 0]
    win_rate = len(wins) / len(pnls) * 100
    expectancy = float(np.mean(pnls))
    avg_rr = float(np.mean([t.r_multiple for t in trades]))
    gross_profit = sum(wins) if wins else 0
    gross_loss = abs(sum(losses)) if losses else 1
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else gross_profit

    equity = np.cumsum(pnls)
    peak = np.maximum.accumulate(equity)
    dd = peak - equity
    max_dd = float(dd.max()) if len(dd) else 0.0

    regime_breakdown: dict[str, Any] = {}
    for regime in ("low_vol", "mid", "high_vol"):
        rt = [t for t in trades if t.regime == regime]
        if rt:
            regime_breakdown[regime] = {
                "count": len(rt),
                "win_rate": len([t for t in rt if t.pnl > 0]) / len(rt) * 100,
                "expectancy": float(np.mean([t.pnl for t in rt])),
            }

    tradable = expectancy > 0 and profit_factor > 1.0 and win_rate >= 40

    return BacktestReport(
        setup_name=setup_name,
        instrument=instrument,
        segment=segment,
        interval=interval,
        from_date=from_date,
        to_date=to_date,
        trade_count=len(trades),
        win_rate=round(win_rate, 2),
        expectancy=round(expectancy, 2),
        avg_rr=round(avg_rr, 2),
        max_drawdown=round(max_dd, 2),
        profit_factor=round(profit_factor, 2),
        tradable=tradable,
        regime_breakdown=regime_breakdown,
        trades=trades,
    )


def persist_backtest(session: Session, report: BacktestReport) -> BacktestResult:
    row = BacktestResult(
        setup_name=report.setup_name,
        instrument=report.instrument,
        segment=report.segment,
        interval=report.interval,
        from_date=report.from_date,
        to_date=report.to_date,
        trade_count=report.trade_count,
        win_rate=report.win_rate,
        expectancy=report.expectancy,
        avg_rr=report.avg_rr,
        max_drawdown=report.max_drawdown,
        profit_factor=report.profit_factor,
        tradable=report.tradable,
        regime_breakdown=json.dumps(report.regime_breakdown),
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def load_candles_for_backtest(
    session: Session,
    instrument: str,
    segment: str,
    interval: str,
    limit: int = 5000,
) -> pd.DataFrame:
    stmt = (
        select(Candle)
        .where(
            Candle.instrument == instrument.upper(),
            Candle.segment == segment,
            Candle.interval == interval,
        )
        .order_by(Candle.timestamp.asc())
        .limit(limit)
    )
    candles = list(session.execute(stmt).scalars().all())
    return candles_to_df(candles)
