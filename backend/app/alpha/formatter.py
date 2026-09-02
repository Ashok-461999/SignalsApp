"""Format India Alpha v2 signal cards (Section 13)."""

from __future__ import annotations

from typing import Any

from app.alpha.constants import DISCLAIMER


def format_signal_card(payload: dict[str, Any]) -> str:
    proj_lines = []
    for key, label in (
        ("proj_up_price", "+1%"),
        ("proj_down_price", "-1%"),
        ("proj_up2_price", "+2%"),
        ("proj_down2_price", "-2%"),
    ):
        if payload.get(key) is not None:
            pnl_key = key.replace("_price", "_pnl")
            proj_lines.append(
                f"   ├─ If Spot {label}: Option → ₹{payload.get(key)} │ P&L: ₹{payload.get(pnl_key)}/lot"
            )
    if not proj_lines:
        proj_lines = [
            f"   ├─ If Spot +1%: Option → ₹{payload.get('proj_up_price')} │ P&L: ₹{payload.get('proj_up_pnl')}/lot",
            f"   ├─ If Spot -1%: Option → ₹{payload.get('proj_down_price')} │ P&L: ₹{payload.get('proj_down_pnl')}/lot",
        ]

    lines = [
        "▓" * 60,
        f"🎯 {payload.get('tier')} ALPHA SIGNAL",
        f"{payload.get('strategy')} — {payload.get('instrument')} — {payload.get('strikes')} — {payload.get('expiry')}",
        "▓" * 60,
        "",
        f"📊 CONFLUENCE: {payload.get('confluence_score')}/100 │ TIER: {payload.get('tier')} │ "
        f"CONFIDENCE: {payload.get('confidence')}% {payload.get('grade_emoji', '')}",
        "",
        "🔮 PREDICTION",
        f"   {payload.get('prediction', '')}",
        "",
        "📰 NEWS & EVENTS",
        f"   ├─ Headline: \"{payload.get('news_headline', 'N/A')}\"",
        f"   ├─ Sentiment Score: {payload.get('news_sentiment_score', 0)}",
        f"   └─ Effect: {payload.get('news_effect', 'Neutral')}",
        "",
        "🏭 SECTOR ANALYSIS",
        f"   ├─ Sector: {payload.get('sector_name', 'Index')}",
        f"   ├─ Trend: {payload.get('sector_trend', 'neutral')}",
        f"   ├─ OI Flow: {payload.get('sector_oi_flow', 'Neutral')}",
        f"   └─ Implication: {payload.get('sector_implication', '')}",
        "",
        "🏗️ STRUCTURE",
        f"   ├─ HTF Bias: {payload.get('htf_bias')}",
        f"   ├─ Liquidity Sweep: {payload.get('sweep_summary')}",
        f"   ├─ Entry Zone: {payload.get('entry_zone')}",
        f"   └─ Invalidation: {payload.get('invalidation')}",
        "",
        "📊 OPTIONS ANALYTICS",
        f"   ├─ Call Wall: {payload.get('call_wall')} │ OI: {payload.get('call_wall_oi')}",
        f"   ├─ Put Wall: {payload.get('put_wall')} │ OI: {payload.get('put_wall_oi')}",
        f"   ├─ PCR: {payload.get('pcr')} — {payload.get('pcr_label')}",
        f"   └─ IV Percentile: {payload.get('iv_percentile')}% — {payload.get('iv_regime')}",
        "",
        "⚡ GEX",
        f"   ├─ Zero Gamma: {payload.get('zero_gamma')}",
        f"   └─ Regime: {payload.get('gex_regime')} — {payload.get('gex_implication')}",
        "",
        "💰 PRICING & GREEKS",
        f"   ├─ Spot: {payload.get('spot')} │ Strike: {payload.get('strike')} │ DTE: {payload.get('dte')}",
        f"   ├─ Fair Value: ₹{payload.get('fair_value')} │ LTP: ₹{payload.get('market_ltp')}",
        f"   ├─ Δ {payload.get('delta')} │ Γ {payload.get('gamma')} │ Θ -₹{payload.get('theta')}/day │ V {payload.get('vega')}",
        *proj_lines,
        f"   └─ Breakeven: {payload.get('breakeven')}",
        "",
        f"📍 ENTRY: {payload.get('entry_zone')}",
        f"🛑 MAX LOSS: ₹{payload.get('max_loss_inr')} │ SL: {payload.get('sl_rule')}",
        f"📏 SIZE: {payload.get('lots')} lots │ Risk {payload.get('risk_pct')}% = ₹{payload.get('risk_inr')}",
        "",
        DISCLAIMER,
    ]
    return "\n".join(lines)
