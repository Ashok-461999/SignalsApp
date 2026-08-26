"""Live signal scanner with regime-aware TAKE / NO_TRADE / SIT_OUT decisions."""

import json
import logging
from datetime import datetime, timedelta, timezone

import pandas as pd
from sqlalchemy import func, select

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
from app.data.models import Candle, SignalLog, SignalPrediction
from app.db.session import SyncSessionLocal
from app.signals.iv import DEFAULT_IV, compute_iv_percentile
from app.signals.regime import SETUP_DESCRIPTIONS, detect_regime
from app.signals.registry import get_stats, is_tradable
from app.signals.schemas import SignalPayload
from app.signals.setups import SETUP_FUNCTIONS
from app.signals.backtest_verdict import interpret_backtest, rolling_backtest_stats
from app.signals.trade_decision import evaluate_trade_decision
from app.services.market_news import get_enriched_headlines
from app.services.market_predictions import news_bias_for_instrument
from app.services.trading_settings import load_trading_settings
from app.services.signal_performance import load_live_setup_stats
from app.signals.position_sizing import plan_futures_position, plan_option_position

logger = logging.getLogger(__name__)

SCAN_INTERVAL = "5m"
LOOKBACK = 120


class SignalScanner:
    def __init__(self) -> None:
        self._subscribers: list = []
        self._active_signals: list[dict] = []
        self._last_regime: dict[str, dict] = {}
        self._last_scan: dict[str, str] = {}
        self._last_take_at: dict[str, datetime] = {}
        self._take_count_date: str = ""
        self._take_count_today: int = 0

    def subscribe(self, callback) -> None:
        self._subscribers.append(callback)

    def get_active_signals(self) -> list[dict]:
        """Only scalp-approved TAKE signals — ready to trade."""
        return [
            s for s in self._active_signals
            if s.get("can_take") or s.get("trade_decision") == "TAKE"
        ]

    def get_all_evaluations(self) -> list[dict]:
        """Live TAKE signals only — no 70+ NO_TRADE spam."""
        return self.get_active_signals()

    def _ist_today(self) -> str:
        ist = timezone(timedelta(hours=5, minutes=30))
        return datetime.now(ist).strftime("%Y-%m-%d")

    def _refresh_take_count(self, session) -> int:
        today = self._ist_today()
        if today != self._take_count_date:
            self._take_count_date = today
            ist = timezone(timedelta(hours=5, minutes=30))
            start = datetime.now(ist).replace(hour=0, minute=0, second=0, microsecond=0)
            start_utc = start.astimezone(timezone.utc)
            count = session.scalar(
                select(func.count(SignalLog.id)).where(
                    SignalLog.tradable.is_(True),
                    SignalLog.created_at >= start_utc,
                )
            )
            self._take_count_today = int(count or 0)
        return self._take_count_today

    def _in_cooldown(self, setup_name: str, instrument: str) -> bool:
        settings = get_settings()
        key = f"{setup_name}:{instrument}"
        last = self._last_take_at.get(key)
        if not last:
            return False
        gap = timedelta(minutes=max(5, int(settings.signal_cooldown_minutes)))
        return datetime.now(timezone.utc) - last < gap

    def _mark_take(self, setup_name: str, instrument: str) -> None:
        self._last_take_at[f"{setup_name}:{instrument}"] = datetime.now(timezone.utc)
        self._take_count_today += 1

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
                if not ev.get("can_take"):
                    continue
                self._active_signals.append(ev)
                if self._should_persist(session, ev):
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
        trading = load_trading_settings(session)
        capital_inr = trading.trading_capital_inr or settings.trading_capital_inr
        risk_pct = trading.risk_percent or settings.risk_percent
        trade_style = (trading.trading_style or settings.trading_style or "hybrid").lower()
        live_setup_stats = load_live_setup_stats(session)

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
        headlines = get_enriched_headlines(max_items=12)
        news_line = news_bias_for_instrument(instrument, headlines)

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
            stats = get_stats(setup_name, instrument, segment)
            if int(stats.get("trade_count") or 0) < 5:
                stats = rolling_backtest_stats(df, setup_name, instrument, segment)
            bt_info = interpret_backtest(stats)
            decision = evaluate_trade_decision(
                setup_name,
                result,
                regime_snap,
                iv_pct,
                backtest_stats=stats,
                trading_style=trade_style,
                live_setup_stats=live_setup_stats,
            )

            if not result.fired and decision["trade_decision"] == "NO_TRADE":
                continue  # skip silent non-triggers

            tradable = is_tradable(setup_name, instrument, segment)
            if settings.require_backtest_for_signals and not tradable:
                continue

            min_dte = (
                settings.min_option_dte_scalp
                if trade_style == "scalp"
                else settings.min_option_dte
            )

            direction = result.direction or regime_snap.trend_direction
            if direction == "neutral":
                direction = "bullish"

            step = strike_step(instrument)
            entry = result.entry or float(df.iloc[-1]["close"])
            stop = result.stop_loss or entry
            strike = atm_strike(entry, step)
            expiry = nearest_expiry_min_days(
                min_days=min_dte,
                expiry_weekday=expiry_weekday_for(instrument),
            )
            lot = LOT_SIZES.get(instrument, 25)

            risk = abs(entry - stop)
            if risk <= 0 and result.fired:
                continue

            size_mod = decision.get("size_modifier", 1.0)

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

            pos = plan_option_position(
                instrument,
                entry_prem,
                prem_stop,
                capital_inr,
                risk_pct,
                size_mod,
            )
            fut_pos = plan_futures_position(
                instrument,
                entry,
                stop,
                capital_inr,
                risk_pct,
                size_mod,
            )
            size = pos.lots
            futures_action = "BUY" if direction == "bullish" else "SELL"

            if decision.get("can_take") and not pos.can_afford:
                decision = {
                    **decision,
                    "can_take": False,
                    "trade_decision": "NO_TRADE",
                    "decision_reason": pos.reason,
                    "prediction": "Skip — capital too small for this trade",
                }

            take_today = self._refresh_take_count(session)
            if decision.get("can_take") and take_today >= settings.max_take_signals_per_day:
                decision = {
                    **decision,
                    "can_take": False,
                    "trade_decision": "NO_TRADE",
                    "decision_reason": (
                        f"Daily scalp limit ({settings.max_take_signals_per_day} TAKE) reached — "
                        "wait for tomorrow or next session"
                    ),
                    "prediction": "Skip — daily signal cap",
                }
            elif decision.get("can_take") and self._in_cooldown(setup_name, instrument):
                decision = {
                    **decision,
                    "can_take": False,
                    "trade_decision": "NO_TRADE",
                    "decision_reason": (
                        f"Same setup on {instrument} fired recently — "
                        f"wait {settings.signal_cooldown_minutes} min (scalp cooldown)"
                    ),
                    "prediction": "Skip — cooldown",
                }

            target_px = float(result.targets[0]) if result.targets else entry
            opt_bs = "call" if direction == "bullish" else "put"
            prem_target = (
                black_scholes_price(target_px, strike, float(days_to_exp), iv, opt_bs)
                if result.fired
                else 0.0
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
                position_size=size if decision.get("can_take") else 0,
                premium_stop_reference=round(prem_stop, 2),
                backtest_stats=stats,
                timestamp=datetime.now(timezone.utc).isoformat(),
                tradable=bool(decision.get("can_take")),
                trade_decision=decision["trade_decision"],
                decision_reason=decision["decision_reason"],
                regime=decision["regime"],
                strategy_fit=decision.get("strategy_fit", ""),
                option_type=opt_type if result.fired else "",
                entry_premium_estimate=round(entry_prem, 2) if result.fired else 0,
                days_to_expiry=days_to_exp,
                can_take=bool(decision.get("can_take")),
                take_confidence=int(decision.get("take_confidence") or 0),
                trading_style=decision.get("trading_style", trade_style),
                prediction=decision.get("prediction", ""),
            )
            sig = payload.to_dict()
            sig["capital_inr"] = capital_inr
            sig["max_loss_inr"] = pos.max_loss_inr
            sig["premium_required_inr"] = pos.premium_required_inr if pos.can_afford else round(entry_prem * lot, 2)
            sig["hold_hint"] = (
                "Scalp at T1 or hold 2–4 weeks to T2"
                if trade_style == "hybrid"
                else "Quick scalp exit" if trade_style == "scalp"
                else "Hold weeks — 20+ DTE"
            )
            sig["primary_leg"] = "options"
            sig["dual_leg_note"] = (
                "Options first (higher profit potential). "
                "Futures backup if option SL hits but index keeps moving."
            )
            sig["futures_action"] = futures_action if result.fired else ""
            sig["futures_lots"] = fut_pos.lots if decision.get("can_take") else 0
            sig["futures_max_loss_inr"] = fut_pos.max_loss_inr
            sig["futures_margin_inr"] = fut_pos.margin_required_inr or fut_pos.margin_per_lot_inr
            sig["futures_margin_per_lot_inr"] = fut_pos.margin_per_lot_inr
            sig["futures_can_take"] = bool(decision.get("can_take") and fut_pos.can_afford)
            sig["futures_reason"] = fut_pos.reason
            sig["futures_broker_hint"] = (
                f"{futures_action} {instrument} FUT × {fut_pos.lots} lots"
                if decision.get("can_take") and fut_pos.lots > 0
                else ""
            )
            sig["setup_description"] = SETUP_DESCRIPTIONS.get(setup_name, "")
            sig["adx"] = regime_snap.adx
            sig["atr_percentile"] = regime_snap.atr_percentile
            setup_live = live_setup_stats.get(setup_name) or {}
            sig["live_track_record"] = {
                "trades": setup_live.get("trades", 0),
                "wins": setup_live.get("wins", 0),
                "losses": setup_live.get("losses", 0),
                "win_rate": setup_live.get("win_rate", 0),
                "max_drawdown_inr": setup_live.get("max_drawdown_inr", 0),
            }
            sig["backtest_profitable"] = bt_info.get("backtest_profitable", False)
            sig["backtest_verdict"] = bt_info.get("backtest_verdict", "NO_DATA")
            sig["backtest_summary"] = bt_info.get("backtest_summary", "")
            sig["backtest_win_rate"] = bt_info.get("backtest_win_rate", 0)
            sig["backtest_profit_factor"] = bt_info.get("backtest_profit_factor", 0)
            sig["backtest_expectancy"] = bt_info.get("backtest_expectancy", 0)
            sig["backtest_max_drawdown"] = bt_info.get("backtest_max_drawdown", 0)
            sig["backtest_trade_count"] = bt_info.get("backtest_trade_count", 0)
            sig["premium_entry"] = round(entry_prem, 2) if result.fired else 0
            sig["premium_target"] = round(prem_target, 2) if result.fired else 0
            sig["premium_stop"] = round(prem_stop, 2) if result.fired else 0
            if result.fired and entry_prem > 0:
                sig["option_trade_plan"] = (
                    f"Buy ~₹{entry_prem:.0f} · Target ₹{prem_target:.0f} · SL below ₹{prem_stop:.0f}"
                )
                sig["option_trade_plan_en"] = (
                    f"Enter premium ~{entry_prem:.0f}, book profit near {prem_target:.0f}, "
                    f"exit if premium drops below {prem_stop:.0f}"
                )
            else:
                sig["option_trade_plan"] = ""
                sig["option_trade_plan_en"] = ""

            if news_line and decision.get("can_take"):
                sig["decision_reason"] = f"{decision['decision_reason']} | {news_line}"
            elif news_line and result.fired:
                sig["news_bias"] = news_line

            if decision.get("can_take"):
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

    def _should_persist(self, session, sig: dict) -> bool:
        settings = get_settings()
        if settings.persist_take_signals_only and not sig.get("can_take"):
            return False
        return True

    def _persist_signal(self, session, sig: dict) -> None:
        settings = get_settings()
        if sig.get("can_take"):
            self._mark_take(sig.get("setup_name", ""), sig["instrument"])
        row = SignalLog(
            setup_name=sig.get("setup_name", "unknown"),
            instrument=sig["instrument"],
            segment=sig.get("segment", "spot"),
            direction=sig.get("direction", "neutral"),
            payload=json.dumps(sig),
            tradable=bool(sig.get("can_take") or sig.get("trade_decision") == "TAKE"),
        )
        session.add(row)
        session.flush()
        pred = SignalPrediction(
            signal_log_id=row.id,
            setup_name=sig.get("setup_name", "unknown"),
            instrument=sig["instrument"],
            trade_decision=sig.get("trade_decision", "NO_TRADE"),
            can_take=bool(sig.get("can_take")),
            take_confidence=float(sig.get("take_confidence") or 0),
            prediction=sig.get("prediction", ""),
            trading_style=sig.get("trading_style", settings.trading_style),
        )
        session.add(pred)
        session.commit()


signal_scanner = SignalScanner()
