"""Options Alpha Engine — main orchestrator."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import pandas as pd
from sqlalchemy import select

from app.alpha.chain_metrics import chain_analytics
from app.alpha.confluence import compute_confluence, gex_points, pcr_points
from app.alpha.constants import ALPHA_INSTRUMENTS, DISCLAIMER, INSTRUMENT_SPECS, MIN_SIGNALS_FOR_PREP_ONLY
from app.alpha.formatter import format_signal_card
from app.alpha.gex import compute_gex
from app.alpha.greeks import breakeven_buyer, compute_greeks, projection_matrix
from app.alpha.market_profile import compute_market_profile
from app.alpha.no_trade import check_no_trade, is_signal_window
from app.alpha.prep_report import build_prep_report
from app.alpha.state import alpha_session
from app.alpha.strategies import select_strategy
from app.config import get_settings
from app.data.models import Candle
from app.data.option_chain import fetch_option_chain
from app.services.gift_nifty import get_gift_nifty_snapshot
from app.services.trading_settings import load_trading_settings
from app.signals.fvg import fvg_retest, liquidity_sweep
from app.signals.regime import _structure_trend
from app.signals.setups import orb_breakout

logger = logging.getLogger(__name__)


def _load_df(session, instrument: str, interval: str = "5m", limit: int = 120) -> pd.DataFrame:
    candles = list(
        session.execute(
            select(Candle)
            .where(Candle.instrument == instrument, Candle.segment == "spot", Candle.interval == interval)
            .order_by(Candle.timestamp.desc())
            .limit(limit)
        ).scalars()
    )
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


def _htf_bias(df: pd.DataFrame) -> tuple[str, int]:
    if df.empty or len(df) < 30:
        return "neutral", 0
    trend = _structure_trend(df)
    if trend == "bullish":
        return "bullish", 20
    if trend == "bearish":
        return "bearish", 20
    return "neutral", 0


def _best_setup(df: pd.DataFrame) -> tuple[Any, int, int, int]:
    """Returns setup result, structure pts, sweep pts, ob/fvg pts."""
    sweep_pts = ob_pts = 0
    best = None
    for fn in (liquidity_sweep, fvg_retest, orb_breakout):
        try:
            r = fn(df)
        except Exception:
            continue
        if r.fired and (best is None or (r.risk_reward or 0) > (best.risk_reward or 0)):
            best = r
    if best is None:
        return None, 0, 0, 0
    name = best.setup_name
    if name == "liquidity_sweep":
        sweep_pts = 15
        ob_pts = 8
    elif name == "fvg_retest":
        sweep_pts = 8
        ob_pts = 15
    else:
        sweep_pts = 8
        ob_pts = 10
    return best, 20, sweep_pts, ob_pts


def evaluate_instrument(session, instrument: str, spot: float) -> dict[str, Any]:
    df5 = _load_df(session, instrument, "5m", 120)
    df1 = _load_df(session, instrument, "1m", 200)
    htf_bias, struct_pts = _htf_bias(df5)
    setup, s_pts, sw_pts, ob_pts = _best_setup(df5)
    profile = compute_market_profile(df1 if len(df1) >= 20 else df5)
    prof_pts = 10 if profile["position"] in ("above_vah", "below_val") else 5 if profile["position"] != "inside_va" else 0

    chain = fetch_option_chain(instrument, spot)
    analytics = chain_analytics(chain)
    gex = compute_gex(chain)
    oi_pts = 15 if analytics.get("call_wall_strike") or analytics.get("put_wall_strike") else 0

    direction = setup.direction if setup and setup.fired else htf_bias
    if direction == "neutral":
        direction = "bullish"

    pcr_pts = pcr_points(float(analytics.get("pcr") or 1), direction)
    gex_pts = gex_points(gex, direction, breakout=bool(setup and setup.fired))

    conf = compute_confluence(struct_pts, sw_pts, ob_pts, oi_pts, pcr_pts, prof_pts, gex_pts)

    return {
        "instrument": instrument,
        "spot": spot,
        "htf_bias": htf_bias,
        "setup": setup,
        "sweep_pts": sw_pts,
        "ob_pts": ob_pts,
        "chain": chain,
        "chain_analytics": analytics,
        "gex": gex,
        "market_profile": profile,
        "confluence": conf,
        "direction": direction,
    }


def try_emit_signal(session, instrument: str, spot: float, capital_inr: float) -> dict[str, Any] | None:
    window_ok, window_msg = is_signal_window()
    if not window_ok:
        return {"skipped": True, "reason": window_msg}

    ev = evaluate_instrument(session, instrument, spot)
    conf = ev["confluence"]
    if not conf.can_signal:
        return {"skipped": True, "reason": f"Confluence {conf.total}/100 below 70", "instrument": instrument}

    setup = ev["setup"]
    if not setup or not setup.fired:
        return {"skipped": True, "reason": "No setup fired", "instrument": instrument}

    analytics = ev["chain_analytics"]
    profile = ev["market_profile"]
    blocked, reason = check_no_trade(
        profile_position=profile.get("position", "inside_va"),
        vix=None,
        pcr=float(analytics.get("pcr") or 1),
        has_ob_fvg=True,
        has_sweep=ev["confluence"].factors.get("liquidity_sweep", 0) >= 8,
        chain_analytics=analytics,
        iv_percentile=float(analytics.get("iv_percentile_proxy") or 50),
        sl_hits_today=alpha_session.sl_hits_today,
        active_on_instrument=instrument in alpha_session._active_instruments,
        portfolio_risk_pct=0,
    )
    if blocked:
        return {"skipped": True, "reason": reason, "instrument": instrument}

    ok, cap_reason = alpha_session.can_emit(conf.tier)
    if not ok:
        return {"skipped": True, "reason": cap_reason, "instrument": instrument}

    spec = INSTRUMENT_SPECS[instrument]
    lot_size = spec["lot_size"]
    strike = setup.entry or spot
    from app.backtest.options import atm_strike, strike_step

    atm = atm_strike(spot, strike_step(instrument))
    opt_type = "call" if ev["direction"] == "bullish" else "put"
    dte = int(ev["chain"].get("dte") or 7)
    iv = 0.16
    for c in ev["chain"].get("contracts") or []:
        if c["strike"] == atm and c["option_type"] in ("CE", "PE"):
            iv = float(c.get("iv") or iv)
            market_ltp = float(c.get("ltp") or 0)
            break
    else:
        market_ltp = 0.0

    greeks = compute_greeks(spot, atm, dte, iv, opt_type)
    entry_prem = market_ltp or greeks.fair_value
    stop_prem = max(entry_prem * 0.75, entry_prem - abs(setup.entry - setup.stop_loss) * greeks.delta * 0.5)
    projections = projection_matrix(spot, atm, dte, iv, entry_prem, opt_type, lot_size)
    proj_up = next((p for p in projections if p["spot_move_pct"] == 1.0), {})
    proj_dn = next((p for p in projections if p["spot_move_pct"] == -1.0), {})

    risk_inr = capital_inr * (conf.risk_pct / 100)
    prem_risk = max(entry_prem - stop_prem, entry_prem * 0.15)
    lots = max(1, int(risk_inr / (prem_risk * lot_size))) if prem_risk > 0 else 0
    max_loss_inr = round(prem_risk * lot_size * lots, 2)

    strategy = select_strategy(
        direction=ev["direction"],
        htf_trending=ev["htf_bias"] in ("bullish", "bearish"),
        has_sweep=ev.get("sweep_pts", 0) >= 15,
        profile_position=profile.get("position", ""),
        pcr=float(analytics.get("pcr") or 1),
        iv_percentile=float(analytics.get("iv_percentile_proxy") or 50),
        near_max_pain=float(analytics.get("max_pain_distance_pct") or 99) < 1.5,
        gex_regime=ev["gex"].get("regime", "neutral"),
        confluence_tier=conf.tier,
    )

    payload = {
        "instrument": instrument,
        "tier": conf.tier,
        "grade_emoji": conf.grade_emoji,
        "confluence_score": conf.total,
        "confidence": conf.total,
        "strategy": strategy["name"],
        "strikes": f"{atm:.0f} {'CE' if opt_type == 'call' else 'PE'}",
        "expiry": ev["chain"].get("expiry"),
        "htf_bias": f"{ev['htf_bias'].title()} — structure on 5m",
        "sweep_summary": setup.reason or "Liquidity event",
        "entry_zone": f"Underlying {setup.entry:.2f} | Option ₹{entry_prem:.0f}–₹{entry_prem * 1.05:.0f}",
        "invalidation": f"Close through ₹{setup.stop_loss:.2f}",
        "call_wall": analytics.get("call_wall_strike"),
        "call_wall_oi": f"{(analytics.get('call_wall_oi') or 0) / 100000:.1f}L",
        "put_wall": analytics.get("put_wall_strike"),
        "put_wall_oi": f"{(analytics.get('put_wall_oi') or 0) / 100000:.1f}L",
        "pcr": analytics.get("pcr"),
        "pcr_label": analytics.get("pcr_label"),
        "max_pain": analytics.get("max_pain"),
        "max_pain_dist": analytics.get("max_pain_distance_pct"),
        "iv_percentile": analytics.get("iv_percentile_proxy"),
        "iv_regime": analytics.get("iv_regime"),
        "zero_gamma": ev["gex"].get("zero_gamma_level"),
        "gex_regime": ev["gex"].get("regime"),
        "gex_implication": ev["gex"].get("implication"),
        "poc": profile.get("poc"),
        "vah": profile.get("vah"),
        "val": profile.get("val"),
        "profile_position": profile.get("position_label"),
        "spot": round(spot, 2),
        "strike": atm,
        "dte": dte,
        "fair_value": greeks.fair_value,
        "market_ltp": round(market_ltp or entry_prem, 2),
        "delta": greeks.delta,
        "gamma": greeks.gamma,
        "theta": abs(greeks.theta_daily),
        "vega": greeks.vega,
        "proj_up_price": proj_up.get("option_price"),
        "proj_up_pnl": proj_up.get("pnl_per_lot_inr"),
        "proj_down_price": proj_dn.get("option_price"),
        "proj_down_pnl": proj_dn.get("pnl_per_lot_inr"),
        "breakeven": breakeven_buyer(atm, entry_prem, opt_type),
        "max_profit_inr": round((proj_up.get("pnl_per_lot_inr") or 0) * lots, 2),
        "max_loss_inr": max_loss_inr,
        "sl_rule": f"Exit if premium below ₹{stop_prem:.0f}",
        "lots": lots,
        "risk_pct": conf.risk_pct,
        "risk_inr": round(risk_inr, 2),
        "holding_period": "Intraday",
        "direction": ev["direction"],
        "underlying_entry": setup.entry,
        "underlying_stop": setup.stop_loss,
        "premium_entry": entry_prem,
        "premium_stop": stop_prem,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "disclaimer": DISCLAIMER,
    }
    payload["formatted"] = format_signal_card(payload)
    alpha_session.record_signal(payload)
    return payload


def run_alpha_scan(session, spots: dict[str, float]) -> dict[str, Any]:
    settings = get_settings()
    trading = load_trading_settings(session)
    capital = trading.trading_capital_inr or settings.trading_capital_inr

    emitted: list[dict] = []
    instrument_data: dict[str, dict] = {}
    for inst in ALPHA_INSTRUMENTS:
        spot = spots.get(inst)
        if not spot or spot <= 0:
            continue
        try:
            ev = evaluate_instrument(session, inst, spot)
            instrument_data[inst] = ev
            sig = try_emit_signal(session, inst, spot, capital)
            if sig and not sig.get("skipped"):
                emitted.append(sig)
        except Exception:
            logger.exception("Alpha scan failed for %s", inst)

    prep = None
    if alpha_session.signal_count < MIN_SIGNALS_FOR_PREP_ONLY:
        try:
            gift = get_gift_nifty_snapshot()
        except Exception:
            gift = None
        prep = build_prep_report(instrument_data, gift)

    return {
        "signals": emitted,
        "signal_count_today": alpha_session.signal_count,
        "prep_report": prep,
        "instruments": list(instrument_data.keys()),
    }
