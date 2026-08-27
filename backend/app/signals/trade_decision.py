"""TAKE / NO_TRADE / SIT_OUT decision engine with scalp prediction scoring."""

from app.config import get_settings
from app.signals.regime import Regime, RegimeSnapshot, setup_allowed_in_regime
from app.signals.schemas import SetupResult

MIN_RR_SWING = 2.0
MIN_RR_SCALP = 1.3
IV_EXTREME_SWING = 80.0
IV_EXTREME_SCALP = 75.0
SCALP_SETUPS = frozenset({"fvg_retest", "liquidity_sweep", "orb_breakout", "vwap_trend"})


def _trading_style() -> str:
    return (get_settings().trading_style or "hybrid").lower()


def _min_rr(style: str | None = None) -> float:
    s = (style or _trading_style()).lower()
    return MIN_RR_SCALP if s in ("scalp", "hybrid") else MIN_RR_SWING


def _iv_extreme(style: str | None = None) -> float:
    s = (style or _trading_style()).lower()
    return IV_EXTREME_SCALP if s in ("scalp", "hybrid") else IV_EXTREME_SWING


def compute_take_confidence(
    setup_name: str,
    result: SetupResult,
    regime: RegimeSnapshot,
    iv_percentile: float,
    backtest_stats: dict | None = None,
    trading_style: str | None = None,
    live_setup_stats: dict | None = None,
) -> int:
    """0–100 score: how suitable this signal is for the user's trading style."""
    style = (trading_style or _trading_style()).lower()
    stats = backtest_stats or {}
    rr = result.risk_reward or 0.0
    score = 40

    if regime.regime == Regime.TRENDING:
        score += 18 if regime.adx >= 25 else 10
    elif regime.regime == Regime.VOLATILE:
        score += 6
    else:
        score -= 10

    if rr >= _min_rr(style):
        score += 12
    elif rr >= 1.0:
        score += 4
    else:
        score -= 12

    if iv_percentile < 55:
        score += 12
    elif iv_percentile < _iv_extreme(style):
        score += 4
    else:
        score -= 18

    if setup_name in SCALP_SETUPS:
        score += 8

    wr = float(stats.get("win_rate") or 0)
    if wr > 1:
        wr = wr  # already percent
    elif wr > 0:
        wr *= 100
    if wr >= 50:
        score += 10
    elif wr >= 40:
        score += 4
    elif wr > 0:
        score -= 12

    if result.fired and setup_allowed_in_regime(setup_name, regime.regime):
        score += 6

    live = (live_setup_stats or {}).get(setup_name) or {}
    live_trades = int(live.get("trades") or 0)
    live_wr = float(live.get("win_rate") or 0)
    if live_trades >= 3:
        if live_wr >= 60:
            score += 12
        elif live_wr >= 50:
            score += 6
        elif live_wr < 40:
            score -= 18
        elif live_wr < 50:
            score -= 8

    return int(max(5, min(95, score)))


def evaluate_trade_decision(
    setup_name: str,
    result: SetupResult,
    regime: RegimeSnapshot,
    iv_percentile: float,
    backtest_stats: dict | None = None,
    trading_style: str | None = None,
    live_setup_stats: dict | None = None,
) -> dict:
    """
    Returns trade_decision, can_take, take_confidence, and plain-English guidance.

    TAKE       — setup matches regime, R:R ok, IV acceptable, confidence high enough
    NO_TRADE   — setup fired but filters failed or scalp confidence too low
    SIT_OUT    — ranging/choppy day, no directional option buys
    """
    style = (trading_style or _trading_style()).lower()
    min_rr = _min_rr(style)
    iv_extreme = _iv_extreme(style)
    min_conf = get_settings().scalp_min_confidence
    rr = result.risk_reward or 0.0
    confidence = compute_take_confidence(
        setup_name,
        result,
        regime,
        iv_percentile,
        backtest_stats,
        trading_style=style,
        live_setup_stats=live_setup_stats,
    )
    live = (live_setup_stats or {}).get(setup_name) or {}
    live_trades = int(live.get("trades") or 0)
    live_wr = float(live.get("win_rate") or 0)

    base = {
        "regime": regime.regime.value,
        "adx": regime.adx,
        "atr_percentile": regime.atr_percentile,
        "trend_direction": regime.trend_direction,
        "regime_summary": regime.summary,
        "iv_percentile": iv_percentile,
        "risk_reward": round(rr, 2),
        "trading_style": style,
        "take_confidence": confidence,
        "can_take": False,
        "prediction": "Skip — conditions not met",
    }

    if not result.fired:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": result.reason or "Setup did not trigger",
            "strategy_fit": "waiting",
            "prediction": "Wait — no setup yet",
        }

    if regime.regime == Regime.RANGING and not setup_allowed_in_regime(setup_name, regime.regime):
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"Ranging market (ADX {regime.adx:.0f}) — only liquidity sweep setups. "
                f"{setup_name} not suitable."
            ),
            "strategy_fit": "ranging — wrong setup",
            "prediction": "Skip — ranging day, wrong setup",
        }

    if not setup_allowed_in_regime(setup_name, regime.regime):
        fit_map = {
            Regime.TRENDING: "Scalp FVG retest, liquidity sweep, or ORB on trending days",
            Regime.RANGING: "Liquidity sweep only",
            Regime.VOLATILE: "FVG + sweep only, half size",
        }
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"{setup_name} does not fit {regime.regime.value} regime. "
                f"{fit_map.get(regime.regime, '')}"
            ),
            "strategy_fit": "mismatch",
            "prediction": "Skip — wrong setup for regime",
        }

    if rr < min_rr:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"R:R {rr:.1f} below scalp minimum {min_rr:.1f} — skip"
                if style == "scalp"
                else f"R:R {rr:.1f} below minimum {min_rr:.0f} — skip"
            ),
            "strategy_fit": "poor risk-reward",
            "prediction": "Skip — R:R too low",
        }

    if iv_percentile >= iv_extreme and setup_name != "range_break":
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"IV {iv_percentile:.0f}% too high — premium expensive for scalping."
            ),
            "strategy_fit": "IV too elevated",
            "prediction": "Skip — IV crush risk",
        }

    from app.signals.backtest_verdict import interpret_backtest

    stats = backtest_stats or {}
    rolling = stats.get("note") == "rolling_backtest"
    roll_trades = int(stats.get("trade_count") or 0)

    bt = interpret_backtest(backtest_stats)
    bt_verdict = bt.get("backtest_verdict", "NO_DATA")
    if bt_verdict == "NOT_PROFITABLE":
        if rolling and roll_trades < 15:
            confidence = max(0, confidence - 8)
            base["take_confidence"] = confidence
            bt_verdict = "MARGINAL"
        else:
            return {
                **base,
                "trade_decision": "NO_TRADE",
                "decision_reason": bt.get("backtest_summary", "Backtest not profitable"),
                "strategy_fit": "backtest failed",
                "prediction": "Skip — backtest not profitable",
            }
    if bt_verdict == "NO_DATA":
        confidence = max(0, confidence - 6)
        base["take_confidence"] = confidence
    elif bt_verdict == "MARGINAL" and confidence < min_conf + 8:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"{bt.get('backtest_summary', 'Marginal backtest')} — need {min_conf + 8}%+ confidence"
            ),
            "strategy_fit": "marginal backtest",
            "prediction": "Skip — marginal backtest",
        }

    if confidence < min_conf:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"Scalp confidence {confidence}% below {min_conf}% — skip this bar. "
                f"Wait for stronger FVG/sweep + trend alignment."
            ),
            "strategy_fit": "low confidence",
            "prediction": f"Skip — confidence {confidence}%",
        }

    if live_trades >= 5 and live_wr < 35:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"Live track record weak — {setup_name} only {live_wr:.0f}% win "
                f"over last {live_trades} TAKE signals. Skip until setup improves."
            ),
            "strategy_fit": "poor live accuracy",
            "prediction": f"Skip — live win rate {live_wr:.0f}%",
        }

    size_mod = 1.0
    if regime.regime == Regime.RANGING:
        size_mod = 0.5
        reason = (
            f"Ranging day — TAKE with half size. Confidence {confidence}%, R:R {rr:.1f}"
        )
        prediction = f"Can take (cautious) — {confidence}% · ranging scalp"
    elif regime.regime == Regime.VOLATILE:
        size_mod = 0.5
        reason = (
            f"Volatile — TAKE with half size. Confidence {confidence}%, R:R {rr:.1f}"
        )
        prediction = f"Can take (cautious) — {confidence}% confidence"
    else:
        hold_hint = ""
        if style == "hybrid":
            hold_hint = " Scalp T1 or hold 2–4 weeks to T2."
        elif style == "swing":
            hold_hint = " Hold 2+ weeks — 20+ DTE option."
        reason = (
            f"Confidence {confidence}%, R:R {rr:.1f}."
            f"{hold_hint}"
        )
        if bt_verdict == "PROFITABLE":
            reason = f"{bt.get('backtest_summary', '')} | {reason}"
        prediction = f"Can take — {confidence}% · backtest OK"

    return {
        **base,
        "trade_decision": "TAKE",
        "can_take": True,
        "decision_reason": reason,
        "strategy_fit": "scalp T1 or swing hold" if style == "hybrid" else (
            "scalp — quick target" if style == "scalp" else "swing — hold weeks"
        ),
        "size_modifier": size_mod,
        "prediction": prediction,
    }
