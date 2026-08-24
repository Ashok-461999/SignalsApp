"""Live signal scanner with regime-aware TAKE / NO_TRADE / SIT_OUT decisions."""

import json
import logging
from datetime import datetime, timezone

import pandas as pd
from sqlalchemy import select

from app.backtest.options import (
    atm_strike,
    black_scholes_price,
    days_until_expiry,
    expiry_weekday_for,
    nearest_expiry_min_days,
    premium_at_underlying_stop,
    strike_step,
)
from app.config import get_settings
from app.core.index_config import INDEX_SYMBOLS, LOT_SIZES
from app.data.models import Candle, SignalLog
from app.db.session import SyncSessionLocal
from app.signals.iv import DEFAULT_IV, compute_iv_percentile
from app.signals.regime import SETUP_DESCRIPTIONS, detect_regime
from app.signals.registry import get_stats, is_tradable
from app.signals.schemas import SignalPayload
from app.signals.setups import SETUP_FUNCTIONS
from app.signals.trade_decision import evaluate_trade_decision

logger = logging.getLogger(__name__)

SCAN_INTERVAL = "5m"
LOOKBACK = 120


class SignalScanner:
    def __init__(self) -> None:
        self._subscribers: list = []
        self._active_signals: list[dict] = []
        self._last_regime: dict[str, dict] = {}
        self._last_scan: dict[str, str] = {}

    def subscribe(self, callback) -> None:
        self._subscribers.append(callback)

    def get_active_signals(self) -> list[dict]:
        """Only TAKE signals — ready to trade in your other app."""
        return [s for s in self._active_signals if s.get("trade_decision") == "TAKE"]

    def get_all_evaluations(self) -> list[dict]:
        return list(self._active_signals)

    def get_regime(self, instrument: str) -> dict | None:
        return self._last_regime.get(instrument)

    def on_bar_close(
        self,
        instrument: str,
        segment: str,
        exchange: str,
        interval: str,
        timestamp: datetime,
    ) -> None:
        if interval != SCAN_INTERVAL:
            return

        session = SyncSessionLocal()
        try:
            evaluations = self._scan_instrument(session, instrument, segment, exchange)
            self._active_signals = [
                s for s in self._active_signals if s.get("instrument") != instrument
            ]
            for ev in evaluations:
                self._active_signals.append(ev)
                self._persist_signal(session, ev)
                for cb in self._subscribers:
                    try:
                        cb(ev)
                    except Exception:
                        logger.exception("Signal subscriber failed")
        except Exception:
            logger.exception("Scanner failed for %s", instrument)
        finally:
            session.close()
            self._last_scan[f"{instrument}:{segment}"] = datetime.now(timezone.utc).isoformat()

    def _load_df(self, session, instrument: str, segment: str, interval: str) -> pd.DataFrame:
        stmt = (
            select(Candle)
            .where(
                Candle.instrument == instrument,
                Candle.segment == segment,
                Candle.interval == interval,
            )
            .order_by(Candle.timestamp.desc())
            .limit(LOOKBACK)
        )
        candles = list(session.execute(stmt).scalars().all())
        if not candles:
            return pd.DataFrame()
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
        return pd.DataFrame(rows)

    def _scan_instrument(
        self, session, instrument: str, segment: str, exchange: str
    ) -> list[dict]:
        df = self._load_df(session, instrument, segment, SCAN_INTERVAL)
        if df.empty or len(df) < 60:
            return []

        settings = get_settings()
        iv_data = compute_iv_percentile(session, instrument, segment, SCAN_INTERVAL)
        iv_pct = iv_data["iv_percentile"]
        iv = iv_data.get("current_iv_proxy", DEFAULT_IV)

        regime_snap = detect_regime(df, iv_pct)
        self._last_regime[instrument] = {
            "instrument": instrument,
            "regime": regime_snap.regime.value,
            "adx": regime_snap.adx,
            "summary": regime_snap.summary,
            "trend_direction": regime_snap.trend_direction,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        evaluations: list[dict] = []

        # Ranging day sit-out advisory (no setup needed)
        from app.signals.regime import Regime

        if regime_snap.regime == Regime.RANGING:
            entry = float(df.iloc[-1]["close"])
            step = strike_step(instrument)
            strike = atm_strike(entry, step)
            expiry = nearest_expiry_min_days(
                min_days=settings.min_option_dte,
                expiry_weekday=expiry_weekday_for(instrument),
            )
            sit = {
                "setup_name": "regime_advisory",
                "instrument": instrument,
                "segment": segment,
                "direction": "neutral",
                "underlying_entry": entry,
                "underlying_stop_loss": 0,
                "underlying_target": [],
                "suggested_strike": strike,
                "suggested_expiry": expiry.isoformat(),
                "iv_percentile": iv_pct,
                "risk_reward": 0,
                "position_size": 0,
                "premium_stop_reference": 0,
                "entry_premium_estimate": 0,
                "option_type": "",
                "days_to_expiry": days_until_expiry(expiry),
                "backtest_stats": {},
                "tradable": False,
                "trade_decision": "SIT_OUT",
                "decision_reason": regime_snap.summary,
                "regime": regime_snap.regime.value,
                "strategy_fit": "sit out — ranges kill option buyers",
                "adx": regime_snap.adx,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
            evaluations.append(sit)
            logger.info("SIT_OUT %s — ranging market ADX=%.1f", instrument, regime_snap.adx)

        for setup_name, fn in SETUP_FUNCTIONS.items():
            result = fn(df)
            decision = evaluate_trade_decision(setup_name, result, regime_snap, iv_pct)

            if not result.fired and decision["trade_decision"] == "NO_TRADE":
                continue  # skip silent non-triggers

            stats = get_stats(setup_name, instrument, segment)
            tradable = is_tradable(setup_name, instrument, segment)
            if settings.require_backtest_for_signals and not tradable:
                continue

            direction = result.direction or regime_snap.trend_direction
            if direction == "neutral":
                direction = "bullish"

            step = strike_step(instrument)
            entry = result.entry or float(df.iloc[-1]["close"])
            stop = result.stop_loss or entry
            strike = atm_strike(entry, step)
            expiry = nearest_expiry_min_days(
                min_days=settings.min_option_dte,
                expiry_weekday=expiry_weekday_for(instrument),
            )
            lot = LOT_SIZES.get(instrument, 25)

            risk = abs(entry - stop)
            if risk <= 0 and result.fired:
                continue

            size_mod = decision.get("size_modifier", 1.0)
            capital_risk = settings.risk_percent / 100.0
            max_loss_per_lot = max(risk * 0.5, 1)
            size = max(1, int((capital_risk * 100000) / (max_loss_per_lot * lot)))
            size = max(1, int(size * size_mod))

            days_to_exp = days_until_expiry(expiry)
            prem_stop = premium_at_underlying_stop(entry, strike, stop, days_to_exp, iv, direction)
            opt_type = "CE" if direction == "bullish" else "PE"
            entry_prem = black_scholes_price(
                entry,
                strike,
                float(days_to_exp),
                iv,
                "call" if direction == "bullish" else "put",
            )

            payload = SignalPayload(
                setup_name=setup_name,
                instrument=instrument,
                segment=segment,
                direction=direction if result.fired else "neutral",
                underlying_entry=entry if result.fired else float(df.iloc[-1]["close"]),
                underlying_stop_loss=stop if result.fired else 0,
                underlying_target=result.targets if result.fired else [],
                suggested_strike=strike,
                suggested_expiry=expiry.isoformat(),
                iv_percentile=iv_pct,
                risk_reward=result.risk_reward or 0,
                position_size=size if decision["trade_decision"] == "TAKE" else 0,
                premium_stop_reference=round(prem_stop, 2),
                backtest_stats=stats,
                timestamp=datetime.now(timezone.utc).isoformat(),
                tradable=decision["trade_decision"] == "TAKE",
                trade_decision=decision["trade_decision"],
                decision_reason=decision["decision_reason"],
                regime=decision["regime"],
                strategy_fit=decision.get("strategy_fit", ""),
                option_type=opt_type if result.fired else "",
                entry_premium_estimate=round(entry_prem, 2) if result.fired else 0,
                days_to_expiry=days_to_exp,
            )
            sig = payload.to_dict()
            sig["setup_description"] = SETUP_DESCRIPTIONS.get(setup_name, "")
            sig["adx"] = regime_snap.adx
            sig["atr_percentile"] = regime_snap.atr_percentile

            if decision["trade_decision"] == "TAKE":
                logger.info(
                    "TAKE %s %s %s — %s",
                    setup_name,
                    instrument,
                    direction,
                    decision["decision_reason"],
                )
            elif result.fired:
                logger.info(
                    "NO_TRADE %s %s — %s",
                    setup_name,
                    instrument,
                    decision["decision_reason"],
                )

            evaluations.append(sig)

        return evaluations

    def _persist_signal(self, session, sig: dict) -> None:
        row = SignalLog(
            setup_name=sig.get("setup_name", "unknown"),
            instrument=sig["instrument"],
            segment=sig.get("segment", "spot"),
            direction=sig.get("direction", "neutral"),
            payload=json.dumps(sig),
            tradable=sig.get("trade_decision") == "TAKE",
        )
        session.add(row)
        session.commit()


signal_scanner = SignalScanner()
