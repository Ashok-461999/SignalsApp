"""Advanced move-target models — news + setup engine + momentum for index point targets."""

from __future__ import annotations

import logging
from typing import Any

import pandas as pd
from sqlalchemy.orm import Session

from app.core.index_config import INDEX_SYMBOLS, MOVE_POINT_TARGETS
from app.data.candle_fetcher import candle_fetcher
from app.services.market_predictions import SYMBOL_PROFILES, aggregate_predictions, move_reason_for_symbol
from app.services.gift_nifty import gift_bias_lines
from app.signals.indicators import add_standard_indicators, ensure_ohlcv
from app.signals.setups import SETUP_FUNCTIONS

logger = logging.getLogger(__name__)

STRATEGY_LABELS: dict[str, str] = {
    "fvg_retest": "FVG retest (SMC)",
    "liquidity_sweep": "Liquidity sweep",
    "orb_breakout": "ORB breakout",
    "vwap_trend": "VWAP trend",
    "range_break": "Range expansion",
    "news_momentum": "News momentum",
    "atr_expansion": "ATR expansion",
    "structure_trend": "Market structure",
    "mean_reversion": "Mean reversion",
}


def _df_from_candles(candles: list) -> pd.DataFrame:
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


def _scan_setups(df: pd.DataFrame) -> list[dict[str, Any]]:
    fired: list[dict[str, Any]] = []
    for name, fn in SETUP_FUNCTIONS.items():
        try:
            result = fn(df)
        except Exception:
            logger.debug("Setup %s failed during move prediction", name, exc_info=True)
            continue
        if result.fired:
            fired.append(
                {
                    "name": name,
                    "label": STRATEGY_LABELS.get(name, name),
                    "direction": result.direction,
                    "reason": result.reason,
                }
            )
    return fired


def _structure_bias(d: pd.DataFrame) -> str:
    """Higher-high / lower-low structure — no lagging EMA."""
    if len(d) < 10:
        return "neutral"
    recent = d.tail(8)
    highs = recent["high"].values
    lows = recent["low"].values
    hh = highs[-1] > highs[-4] and highs[-4] > highs[0]
    ll = lows[-1] < lows[-4] and lows[-4] < lows[0]
    if hh and not ll:
        return "bullish"
    if ll and not hh:
        return "bearish"
    return "neutral"


def _technical_bias(df: pd.DataFrame) -> tuple[str, list[str], float]:
    """Return outlook, model tags, momentum score — structure + momentum, not EMA."""
    if len(df) < 20:
        return "neutral", [], 0.0

    d = add_standard_indicators(ensure_ohlcv(df))
    last = d.iloc[-1]
    spot = float(last["close"])
    mom = spot - float(d.iloc[-7]["close"]) if len(d) >= 7 else 0.0
    atr = float(last.get("atr_14", 0) or 0)
    models: list[str] = []

    if atr > 0 and abs(mom) > atr * 1.2:
        models.append(STRATEGY_LABELS["atr_expansion"])
    if mom > 15:
        models.append("Bullish momentum")
        return "bullish", models, mom
    if mom < -15:
        models.append("Bearish momentum")
        return "bearish", models, mom

    struct = _structure_bias(d)
    if struct == "bullish" and mom > 0:
        models.append(STRATEGY_LABELS["structure_trend"])
        return "bullish", models, mom
    if struct == "bearish" and mom < 0:
        models.append(STRATEGY_LABELS["structure_trend"])
        return "bearish", models, mom

    if abs(mom) < 8:
        models.append(STRATEGY_LABELS["mean_reversion"])
    return "neutral", models, mom


def build_move_targets(
    session: Session,
    headlines: list[dict],
    gift_insight: dict | None = None,
) -> list[dict]:
    """Per-index advanced outlook with ~100pt (scaled) move targets."""
    news_map = {p["symbol"]: p for p in aggregate_predictions(headlines)}
    gift = gift_insight or {}
    gift_bull, gift_bear = gift_bias_lines(gift) if gift.get("available") else (None, None)
    targets: list[dict] = []

    for symbol in INDEX_SYMBOLS:
        profile = SYMBOL_PROFILES.get(symbol) or {
            "name": symbol,
            "type": "index",
        }
        move_pts = MOVE_POINT_TARGETS.get(symbol, 100)

        try:
            candles = candle_fetcher.get_candles(
                session=session,
                instrument_symbol=symbol,
                interval="5m",
                limit=80,
                segment="spot",
            )
        except Exception as exc:
            logger.debug("No candles for %s move target: %s", symbol, exc)
            candles = []

        df = _df_from_candles(candles)
        spot = float(df.iloc[-1]["close"]) if not df.empty else 0.0

        setup_hits = _scan_setups(df) if not df.empty else []
        tech_outlook, tech_models, mom = _technical_bias(df) if not df.empty else ("neutral", [], 0.0)

        news = news_map.get(symbol, {})
        news_outlook = news.get("outlook", "neutral")
        news_conf = int(news.get("confidence", 50))
        confidence_boost = 0

        # News-first weighted direction score
        score = 0
        if news_outlook == "bullish":
            score += 3
        elif news_outlook == "bearish":
            score -= 3
        if tech_outlook == "bullish":
            score += 1
        elif tech_outlook == "bearish":
            score -= 1
        for hit in setup_hits:
            if hit["direction"] == "bullish":
                score += 4
            elif hit["direction"] == "bearish":
                score -= 4

        # GIFT Nifty pre-open cue (Nifty 50 only — strongest overnight indicator)
        if symbol == "NIFTY" and gift.get("available"):
            gift_chg = float(gift.get("change_pct", 0))
            if gift_chg < -0.05:
                score -= 3
            elif gift_chg > 0.05:
                score += 3
            neg_prob = float(gift.get("negative_open_probability", 50))
            if gift_chg < -0.05 and neg_prob >= 70:
                confidence_boost = 8

        if score >= 2:
            direction = "up"
            outlook = "bullish"
        elif score <= -2:
            direction = "down"
            outlook = "bearish"
        else:
            direction = "flat"
            outlook = "neutral"
            move_pts = max(move_pts // 2, 50 if symbol in ("NIFTY", "FINNIFTY") else move_pts // 2)

        primary_strategy = "Consolidation — wait for TAKE"
        models: list[str] = list(tech_models)
        if setup_hits:
            primary_strategy = setup_hits[0]["label"]
            models.insert(0, primary_strategy)
        elif news_conf >= 60 and news_outlook != "neutral":
            primary_strategy = STRATEGY_LABELS["news_momentum"]
            models.insert(0, primary_strategy)

        confidence = min(
            95,
            max(35, news_conf + len(setup_hits) * 8 + (10 if abs(mom) > 20 else 0) + confidence_boost),
        )

        why_bull, why_bear, move_reason = move_reason_for_symbol(
            symbol, outlook, setup_hits, news_outlook, tech_outlook, move_pts, direction
        )
        if symbol == "NIFTY" and gift_bull:
            why_bull.insert(0, gift_bull)
        if symbol == "NIFTY" and gift_bear:
            why_bear.insert(0, gift_bear)
        if symbol == "NIFTY" and gift.get("available") and gift.get("summary"):
            move_reason = f"{gift['summary']}. {move_reason}"
        # Merge headline-specific reasons from news aggregate
        news_why_bull = news.get("why_bullish") or []
        news_why_bear = news.get("why_bearish") or []
        for line in news_why_bull:
            if line not in why_bull:
                why_bull.insert(0, line)
        for line in news_why_bear:
            if line not in why_bear:
                why_bear.insert(0, line)
        why_bull = why_bull[:5]
        why_bear = why_bear[:5]

        target_price = round(spot + (move_pts if direction == "up" else -move_pts if direction == "down" else 0), 1)
        if spot <= 0:
            target_price = 0.0

        move_text = (
            f"{'+' if direction == 'up' else '-' if direction == 'down' else '±'}{move_pts} pts"
            if direction != "flat"
            else f"Range ±{move_pts // 2} pts"
        )

        targets.append(
            {
                "symbol": symbol,
                "name": profile.get("name", symbol),
                "type": "index",
                "outlook": outlook,
                "confidence": confidence,
                "headline_count": news.get("headline_count", 0),
                "spot_price": round(spot, 2) if spot else None,
                "move_points": move_pts,
                "move_direction": direction,
                "target_price": target_price if target_price else None,
                "strategy": primary_strategy,
                "models": models[:5],
                "prediction": (
                    f"{profile.get('name', symbol)}: {move_text} "
                    f"({'toward ' + str(target_price) if target_price else 'await breakout'}). "
                    f"Strategy: {primary_strategy}."
                ),
                "option_hint": (
                    f"Buy {'CE' if outlook == 'bullish' else 'PE' if outlook == 'bearish' else 'ATM spreads'} "
                    f"for ~{move_pts}pt move (20+ DTE)."
                ),
                "why_bullish": why_bull,
                "why_bearish": why_bear,
                "move_reason": move_reason,
                "gift_nifty": gift if symbol == "NIFTY" and gift.get("available") else None,
            }
        )

    return targets


def merge_predictions_with_moves(news_predictions: list[dict], move_targets: list[dict]) -> list[dict]:
    """Indices use advanced move model; stocks keep news-only predictions."""
    move_map = {m["symbol"]: m for m in move_targets}
    merged: list[dict] = []
    seen: set[str] = set()

    for symbol in INDEX_SYMBOLS:
        if symbol in move_map:
            merged.append(move_map[symbol])
            seen.add(symbol)

    for pred in news_predictions:
        sym = pred["symbol"]
        if sym in seen:
            continue
        if pred.get("type") == "index" and sym in move_map:
            merged.append(move_map[sym])
            seen.add(sym)
        else:
            merged.append(pred)

    return merged
