"""TAKE / NO_TRADE / SIT_OUT decision engine."""

from app.signals.regime import Regime, RegimeSnapshot, setup_allowed_in_regime
from app.signals.schemas import SetupResult

MIN_RR = 2.0
IV_EXTREME = 80.0


def evaluate_trade_decision(
    setup_name: str,
    result: SetupResult,
    regime: RegimeSnapshot,
    iv_percentile: float,
) -> dict:
    """
    Returns trade_decision, regime info, and plain-English guidance.

    TAKE       — setup matches regime, R:R ok, IV acceptable
    NO_TRADE   — setup fired but wrong regime or poor R:R
    SIT_OUT    — ranging/choppy day, no directional option buys
    """
    rr = result.risk_reward or 0.0

    base = {
        "regime": regime.regime.value,
        "adx": regime.adx,
        "atr_percentile": regime.atr_percentile,
        "trend_direction": regime.trend_direction,
        "regime_summary": regime.summary,
        "iv_percentile": iv_percentile,
        "risk_reward": round(rr, 2),
    }

    # Ranging day — default sit out for option buyers
    if regime.regime == Regime.RANGING:
        return {
            **base,
            "trade_decision": "SIT_OUT",
            "decision_reason": (
                "Ranging market — directional option buying bleeds to theta. "
                "No trade today unless using spreads."
            ),
            "strategy_fit": "none — sit out",
        }

    if not result.fired:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": result.reason or "Setup did not trigger",
            "strategy_fit": "waiting",
        }

    if not setup_allowed_in_regime(setup_name, regime.regime):
        fit_map = {
            Regime.TRENDING: "Use ORB, EMA pullback, or VWAP trend on trending days",
            Regime.RANGING: "Sit out or use spreads",
            Regime.VOLATILE: "Breakout with reduced size only",
        }
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"{setup_name} does not fit {regime.regime.value} regime. "
                f"{fit_map.get(regime.regime, '')}"
            ),
            "strategy_fit": "mismatch",
        }

    if rr < MIN_RR:
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": f"R:R {rr:.1f} below minimum {MIN_RR:.0f} — skip",
            "strategy_fit": "poor risk-reward",
        }

    if iv_percentile >= IV_EXTREME and setup_name != "range_break":
        return {
            **base,
            "trade_decision": "NO_TRADE",
            "decision_reason": (
                f"IV percentile {iv_percentile:.0f}% too high — premium expensive, crush risk. Stay flat."
            ),
            "strategy_fit": "IV too elevated",
        }

    # Volatile regime — allow but warn on size
    if regime.regime == Regime.VOLATILE:
        return {
            **base,
            "trade_decision": "TAKE",
            "decision_reason": (
                f"Volatile breakout valid — TAKE with reduced size and wider stops. "
                f"IV {iv_percentile:.0f}%, R:R {rr:.1f}"
            ),
            "strategy_fit": "volatile breakout — size down",
            "size_modifier": 0.5,
        }

    # Trending — best environment for option buyers
    return {
        **base,
        "trade_decision": "TAKE",
        "decision_reason": (
            f"Trending day, setup matches regime, R:R {rr:.1f}. "
            f"{'ORB best in first hour.' if setup_name == 'orb_breakout' else 'Clean directional setup.'}"
        ),
        "strategy_fit": "trending — directional buy",
        "size_modifier": 1.0,
    }
