"""Tests for Options Alpha Engine modules."""

from app.alpha.chain_metrics import chain_analytics
from app.alpha.confluence import compute_confluence, pcr_points, score_to_tier
from app.alpha.greeks import breakeven_buyer, compute_greeks, projection_matrix
from app.alpha.gex import compute_gex
from app.alpha.no_trade import check_no_trade, is_signal_window


def test_compute_greeks_call():
    g = compute_greeks(24000, 24000, 7, 0.16, "call")
    assert 0.4 < g.delta < 0.6
    assert g.fair_value > 0
    assert g.theta_daily < 0


def test_projection_matrix():
    rows = projection_matrix(24000, 24000, 7, 0.16, 120.0, "call", 25)
    assert len(rows) == 4
    up = next(r for r in rows if r["spot_move_pct"] == 1.0)
    down = next(r for r in rows if r["spot_move_pct"] == -1.0)
    assert up["pnl_per_lot_inr"] > down["pnl_per_lot_inr"]


def test_breakeven_buyer():
    assert breakeven_buyer(24000, 100, "call") == 24100
    assert breakeven_buyer(24000, 100, "put") == 23900


def test_confluence_scoring():
    result = compute_confluence(20, 15, 15, 15, 15, 10, 10)
    assert result.total == 100
    assert result.tier == "A+"
    assert result.can_signal is True
    assert result.risk_pct == 1.5


def test_confluence_below_threshold():
    result = compute_confluence(10, 0, 0, 0, 0, 0, 0)
    assert result.can_signal is False
    assert score_to_tier(result.total) == "NO_SIGNAL"


def test_pcr_points_contrarian():
    assert pcr_points(0.5, "bearish") == 15
    assert pcr_points(1.5, "bullish") == 15
    assert pcr_points(1.0, "bullish") == 0


def test_chain_analytics():
    chain = {
        "spot": 24000,
        "contracts": [
            {"strike": 24000, "option_type": "CE", "oi": 100000, "iv": 0.16},
            {"strike": 24000, "option_type": "PE", "oi": 120000, "iv": 0.17},
            {"strike": 24100, "option_type": "CE", "oi": 200000, "iv": 0.15},
            {"strike": 23900, "option_type": "PE", "oi": 180000, "iv": 0.18},
        ],
    }
    a = chain_analytics(chain)
    assert a["pcr"] > 0
    assert a["call_wall_strike"] == 24100
    assert a["put_wall_strike"] in (23900, 24000)


def test_gex_compute():
    chain = {
        "instrument": "NIFTY",
        "spot": 24000,
        "dte": 7,
        "contracts": [
            {"strike": 23900, "option_type": "PE", "oi": 50000, "iv": 0.16},
            {"strike": 24000, "option_type": "CE", "oi": 80000, "iv": 0.16},
            {"strike": 24000, "option_type": "PE", "oi": 70000, "iv": 0.16},
            {"strike": 24100, "option_type": "CE", "oi": 60000, "iv": 0.16},
        ],
    }
    gex = compute_gex(chain)
    assert gex["regime"] in ("positive", "negative", "neutral", "unknown")
    assert "implication" in gex


def test_no_trade_inside_va():
    blocked, reason = check_no_trade(
        profile_position="inside_va",
        vix=15,
        pcr=1.0,
        has_ob_fvg=True,
        has_sweep=True,
        chain_analytics={"call_wall_strike": 24100, "put_wall_strike": 23900},
        iv_percentile=50,
        sl_hits_today=0,
        active_on_instrument=False,
        portfolio_risk_pct=0,
    )
    assert blocked is True
    assert "Value Area" in reason


def test_signal_window_returns_tuple():
    ok, msg = is_signal_window()
    assert isinstance(ok, bool)
    assert isinstance(msg, str)
