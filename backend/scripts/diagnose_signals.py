"""Diagnose why signals are blocked — run inside backend container."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pandas as pd
from sqlalchemy import select

from app.config import get_settings
from app.data.models import Candle
from app.db.session import SyncSessionLocal
from app.signals.backtest_verdict import interpret_backtest, rolling_backtest_stats
from app.signals.iv import compute_iv_percentile
from app.signals.position_sizing import plan_option_position
from app.signals.regime import Regime, detect_regime
from app.signals.registry import get_stats
from app.signals.setups import SETUP_FUNCTIONS
from app.signals.trade_decision import evaluate_trade_decision
from app.services.signal_performance import load_live_setup_stats
from app.services.trading_settings import load_trading_settings
from app.backtest.options import (
    atm_strike,
    black_scholes_price,
    days_until_expiry,
    expiry_weekday_for,
    nearest_expiry_min_days,
    premium_at_underlying_stop,
    strike_step,
)
from app.signals.iv import DEFAULT_IV

INSTRUMENTS = ["NIFTY", "BANKNIFTY", "FINNIFTY", "SENSEX"]


def main() -> None:
    session = SyncSessionLocal()
    settings = get_settings()
    trading = load_trading_settings(session)
    live = load_live_setup_stats(session)
    style = trading.trading_style or settings.trading_style or "hybrid"
    capital = trading.trading_capital_inr or settings.trading_capital_inr
    risk = trading.risk_percent or settings.risk_percent

    out: dict = {
        "capital_inr": capital,
        "min_confidence": settings.scalp_min_confidence,
        "style": style,
        "instruments": {},
        "take_candidates": [],
        "block_reasons": {},
    }

    for inst in INSTRUMENTS:
        candles = list(
            session.execute(
                select(Candle)
                .where(
                    Candle.instrument == inst,
                    Candle.segment == "spot",
                    Candle.interval == "5m",
                )
                .order_by(Candle.timestamp.desc())
                .limit(120)
            ).scalars()
        )
        info: dict = {"bars": len(candles), "setups": []}
        if len(candles) < 60:
            info["error"] = "insufficient bars"
            out["instruments"][inst] = info
            continue

        rows = [
            {
                "timestamp": c.timestamp,
                "open": c.open,
                "high": c.high,
                "low": c.low,
                "close": c.close,
                "volume": c.volume,
            }
            for c in reversed(candles)
        ]
        df = pd.DataFrame(rows)
        iv_data = compute_iv_percentile(session, inst, "spot", "5m")
        iv_pct = iv_data["iv_percentile"]
        iv = iv_data.get("current_iv_proxy", DEFAULT_IV)
        regime = detect_regime(df, iv_pct)
        info["regime"] = regime.regime.value
        info["adx"] = regime.adx
        info["last_close"] = float(df.iloc[-1]["close"])

        for name, fn in SETUP_FUNCTIONS.items():
            try:
                result = fn(df)
            except Exception as exc:
                info["setups"].append({"setup": name, "error": str(exc)})
                continue

            stats = get_stats(name, inst, "spot")
            if int(stats.get("trade_count") or 0) < 5:
                stats = rolling_backtest_stats(df, name, inst, "spot")
            bt = interpret_backtest(stats)
            dec = evaluate_trade_decision(
                name, result, regime, iv_pct, stats, style, live
            )

            entry = result.entry or float(df.iloc[-1]["close"])
            stop = result.stop_loss or entry
            direction = result.direction or regime.trend_direction or "bullish"
            step = strike_step(inst)
            strike = atm_strike(entry, step)
            expiry = nearest_expiry_min_days(
                min_days=settings.min_option_dte_scalp,
                expiry_weekday=expiry_weekday_for(inst),
            )
            days_to_exp = days_until_expiry(expiry)
            prem_stop = premium_at_underlying_stop(
                entry, strike, stop, days_to_exp, iv, direction
            )
            entry_prem = black_scholes_price(
                entry,
                strike,
                float(days_to_exp),
                iv,
                "call" if direction == "bullish" else "put",
            )
            pos = plan_option_position(
                inst, entry_prem, prem_stop, capital, risk, 1.0
            )

            row = {
                "setup": name,
                "fired": result.fired,
                "decision": dec["trade_decision"],
                "confidence": dec.get("take_confidence"),
                "bt_verdict": bt.get("backtest_verdict"),
                "can_afford": pos.can_afford,
                "afford_reason": pos.reason if not pos.can_afford else "",
                "reason": (dec.get("decision_reason") or "")[:160],
            }
            info["setups"].append(row)

            if result.fired or dec["trade_decision"] != "NO_TRADE":
                key = row["reason"][:80] or dec["trade_decision"]
                out["block_reasons"][key] = out["block_reasons"].get(key, 0) + 1

            if dec.get("can_take") and pos.can_afford:
                out["take_candidates"].append(
                    {"instrument": inst, "setup": name, "confidence": dec.get("take_confidence")}
                )

        out["instruments"][inst] = info

    session.close()
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
