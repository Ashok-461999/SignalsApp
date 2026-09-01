"""Format alpha signals per Section 10."""

from __future__ import annotations

from typing import Any

from app.alpha.constants import DISCLAIMER


def format_signal_card(payload: dict[str, Any]) -> str:
    lines = [
        "━" * 60,
        f"🎯 {payload.get('tier')} SIGNAL — {payload.get('strategy')} — "
        f"{payload.get('instrument')} — {payload.get('strikes')} — {payload.get('expiry')}",
        "━" * 60,
        "",
        f"📊 CONFLUENCE SCORE: {payload.get('confluence_score')}/100  │  "
        f"TIER: {payload.get('tier')}  │  CONFIDENCE: {payload.get('confidence')}%  │  "
        f"{payload.get('grade_emoji', '')}",
        "",
        "🏗️ STRUCTURE ANALYSIS",
        f"   ├─ HTF Bias: {payload.get('htf_bias')}",
        f"   ├─ Liquidity Sweep: {payload.get('sweep_summary')}",
        f"   ├─ Entry Zone: {payload.get('entry_zone')}",
        f"   └─ Invalidation: {payload.get('invalidation')}",
        "",
        "📊 OPTIONS ANALYTICS",
        f"   ├─ Call Wall: {payload.get('call_wall')} │ OI: {payload.get('call_wall_oi')}",
        f"   ├─ Put Wall: {payload.get('put_wall')} │ OI: {payload.get('put_wall_oi')}",
        f"   ├─ PCR: {payload.get('pcr')} — {payload.get('pcr_label')}",
        f"   ├─ Max Pain: {payload.get('max_pain')} │ Spot Distance: {payload.get('max_pain_dist')}%",
        f"   └─ IV Percentile: {payload.get('iv_percentile')}% — {payload.get('iv_regime')}",
        "",
        "⚡ GAMMA EXPOSURE",
        f"   ├─ Zero Gamma Level: {payload.get('zero_gamma')}",
        f"   ├─ Net GEX at Entry Strike: {payload.get('gex_regime')}",
        f"   └─ Implication: {payload.get('gex_implication')}",
        "",
        "📐 MARKET PROFILE",
        f"   ├─ POC: {payload.get('poc')} │ VAH: {payload.get('vah')} │ VAL: {payload.get('val')}",
        f"   ├─ Position: {payload.get('profile_position')}",
        f"   └─ Opening Type: {payload.get('opening_type', 'Pending')}",
        "",
        "💰 OPTIONS PRICING & PROJECTION",
        f"   ├─ Spot: {payload.get('spot')} │ Strike: {payload.get('strike')} │ DTE: {payload.get('dte')}",
        f"   ├─ Fair Value (BS): ₹{payload.get('fair_value')} │ Market LTP: ₹{payload.get('market_ltp')}",
        f"   ├─ Greeks: Δ {payload.get('delta')} │ Γ {payload.get('gamma')} │ "
        f"Θ -₹{payload.get('theta')}/day │ V {payload.get('vega')}",
        f"   ├─ If Spot +1%: Option → ₹{payload.get('proj_up_price')} │ P&L: ₹{payload.get('proj_up_pnl')}/lot",
        f"   ├─ If Spot -1%: Option → ₹{payload.get('proj_down_price')} │ P&L: ₹{payload.get('proj_down_pnl')}/lot",
        f"   ├─ Breakeven at Expiry: {payload.get('breakeven')}",
        f"   └─ Max Profit: ₹{payload.get('max_profit_inr')} │ Max Loss: ₹{payload.get('max_loss_inr')}",
        "",
        f"📍 ENTRY: {payload.get('entry_zone')}",
        f"🛑 MAX LOSS: ₹{payload.get('max_loss_inr')} per lot │ SL: {payload.get('sl_rule')}",
        f"📏 POSITION SIZE: {payload.get('lots')} lots │ Risk: {payload.get('risk_pct')}% = ₹{payload.get('risk_inr')}",
        "",
        f"⏱️ HOLDING PERIOD: {payload.get('holding_period', 'Intraday')}",
        f"⚠️ INVALIDATION: {payload.get('invalidation')}",
        "",
        DISCLAIMER,
    ]
    return "\n".join(lines)
