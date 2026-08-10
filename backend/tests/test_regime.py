"""Tests for regime detection and trade decisions."""

import pandas as pd
import numpy as np

from app.signals.regime import Regime, detect_regime, setup_allowed_in_regime
from app.signals.schemas import SetupResult
from app.signals.trade_decision import evaluate_trade_decision
from app.signals.regime import RegimeSnapshot


def _trending_df(n=80):
    close = 24000 + np.cumsum(np.ones(n) * 15)
    return pd.DataFrame({
        "open": close - 5,
        "high": close + 10,
        "low": close - 10,
        "close": close,
        "volume": np.full(n, 2000.0),
    })


def test_ranging_regime_sit_out():
    # Flat chop — low ADX expected
    n = 80
    close = 24000 + np.sin(np.linspace(0, 8, n)) * 20
    df = pd.DataFrame({
        "open": close,
        "high": close + 5,
        "low": close - 5,
        "close": close,
        "volume": np.full(n, 500.0),
    })
    snap = detect_regime(df, iv_percentile=50)
    result = SetupResult(setup_name="orb_breakout", fired=False, reason="no trigger")
    decision = evaluate_trade_decision("orb_breakout", result, snap, 50)
    if snap.regime == Regime.RANGING:
        assert decision["trade_decision"] == "SIT_OUT"


def test_take_on_trending_ema_setup():
    snap = RegimeSnapshot(
        regime=Regime.TRENDING,
        adx=30,
        atr_percentile=40,
        trend_direction="bullish",
        summary="trending",
    )
    result = SetupResult(
        setup_name="ema_trend_continuation",
        fired=True,
        direction="bullish",
        entry=24500,
        stop_loss=24450,
        targets=[24600, 24650],
        reason="EMA pullback",
    )
    decision = evaluate_trade_decision("ema_trend_continuation", result, snap, iv_percentile=45)
    assert decision["trade_decision"] == "TAKE"
    assert setup_allowed_in_regime("ema_trend_continuation", Regime.TRENDING)


def test_no_trade_wrong_regime():
    snap = RegimeSnapshot(
        regime=Regime.RANGING,
        adx=15,
        atr_percentile=30,
        trend_direction="neutral",
        summary="ranging",
    )
    result = SetupResult(
        setup_name="ema_trend_continuation",
        fired=True,
        direction="bullish",
        entry=24500,
        stop_loss=24450,
        targets=[24600],
    )
    decision = evaluate_trade_decision("ema_trend_continuation", result, snap, 50)
    assert decision["trade_decision"] == "SIT_OUT"


def test_no_trade_high_iv():
    snap = RegimeSnapshot(
        regime=Regime.TRENDING,
        adx=28,
        atr_percentile=50,
        trend_direction="bullish",
        summary="trending",
    )
    result = SetupResult(
        setup_name="orb_breakout",
        fired=True,
        direction="bullish",
        entry=24500,
        stop_loss=24400,
        targets=[24700],
    )
    decision = evaluate_trade_decision("orb_breakout", result, snap, iv_percentile=85)
    assert decision["trade_decision"] == "NO_TRADE"
