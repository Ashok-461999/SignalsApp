"""News sentiment and symbol-level market predictions from live headlines."""

from __future__ import annotations

import re
from collections import defaultdict

# Indices + liquid F&O stocks (NSE)
SYMBOL_PROFILES: dict[str, dict] = {
    "NIFTY": {"name": "Nifty 50", "type": "index", "aliases": ["nifty 50", "nifty50", "nifty", "nse index"]},
    "BANKNIFTY": {"name": "Bank Nifty", "type": "index", "aliases": ["bank nifty", "banknifty", "nifty bank"]},
    "FINNIFTY": {"name": "Fin Nifty", "type": "index", "aliases": ["fin nifty", "finnifty", "nifty financial", "financial services"]},
    "SENSEX": {"name": "Sensex", "type": "index", "aliases": ["sensex", "bse sensex", "bse index"]},
    "RELIANCE": {"name": "Reliance", "type": "stock", "aliases": ["reliance", "ril", "jio", "ambani"]},
    "TCS": {"name": "TCS", "type": "stock", "aliases": ["tcs", "tata consultancy"]},
    "HDFCBANK": {"name": "HDFC Bank", "type": "stock", "aliases": ["hdfc bank", "hdfcbank", "hdfc"]},
    "INFY": {"name": "Infosys", "type": "stock", "aliases": ["infosys", "infy"]},
    "ICICIBANK": {"name": "ICICI Bank", "type": "stock", "aliases": ["icici bank", "icicibank", "icici"]},
    "SBIN": {"name": "SBI", "type": "stock", "aliases": ["sbi", "state bank"]},
    "BHARTIARTL": {"name": "Bharti Airtel", "type": "stock", "aliases": ["airtel", "bharti"]},
    "ITC": {"name": "ITC", "type": "stock", "aliases": ["itc"]},
    "KOTAKBANK": {"name": "Kotak Bank", "type": "stock", "aliases": ["kotak", "kotak bank"]},
    "LT": {"name": "L&T", "type": "stock", "aliases": ["larsen", "l&t", " l&t "]},
    "AXISBANK": {"name": "Axis Bank", "type": "stock", "aliases": ["axis bank", "axisbank"]},
    "TATAMOTORS": {"name": "Tata Motors", "type": "stock", "aliases": ["tata motors", "tatamotors"]},
}

BULLISH_WORDS = (
    "surge", "rally", "gain", "gains", "rise", "rises", "rising", "jump", "jumps",
    "record high", "beat", "beats", "growth", "upgrade", "bullish", "inflow", "buy",
    "outperform", "strong", "recovery", "rebound", "soar", "soars", "positive",
)
BEARISH_WORDS = (
    "fall", "falls", "drop", "drops", "decline", "declines", "crash", "selloff",
    "sell-off", "down", "miss", "misses", "cut", "cuts", "bearish", "outflow",
    "weak", "slump", "slumps", "concern", "fear", "negative", "underperform",
)


def _match_symbols(text: str) -> list[str]:
    lower = f" {text.lower()} "
    matched: list[str] = []
    for symbol, profile in SYMBOL_PROFILES.items():
        for alias in profile["aliases"]:
            if alias in lower:
                matched.append(symbol)
                break
    return matched or []


def analyze_headline(title: str) -> dict:
    lower = title.lower()
    bull = sum(1 for w in BULLISH_WORDS if w in lower)
    bear = sum(1 for w in BEARISH_WORDS if w in lower)
    if bull > bear + 1:
        sentiment = "bullish"
        score = min(95, 55 + bull * 8)
    elif bear > bull + 1:
        sentiment = "bearish"
        score = max(5, 45 - bear * 8)
    else:
        sentiment = "neutral"
        score = 50

    symbols = _match_symbols(title)
    if not symbols and any(w in lower for w in ("market", "stocks", "indices", "nifty", "sensex")):
        symbols = ["NIFTY", "BANKNIFTY"]

    prediction = _prediction_text(sentiment, symbols)
    return {
        "sentiment": sentiment,
        "score": score,
        "symbols": symbols,
        "prediction": prediction,
    }


def _prediction_text(sentiment: str, symbols: list[str]) -> str:
    if not symbols:
        return "Broad market — watch index options for direction."
    primary = symbols[0]
    profile = SYMBOL_PROFILES.get(primary, {})
    name = profile.get("name", primary)
    kind = profile.get("type", "index")
    if sentiment == "bullish":
        action = "CE / long bias" if kind == "index" else "bullish options bias (CE)"
        return f"{name}: news supports {action} — confirm with 5m setup."
    if sentiment == "bearish":
        action = "PE / cautious" if kind == "index" else "bearish options bias (PE)"
        return f"{name}: news cautious — prefer {action} or sit out."
    return f"{name}: mixed headlines — wait for TAKE signal on 5m close."


def enrich_headlines(headlines: list[dict]) -> list[dict]:
    out: list[dict] = []
    for h in headlines:
        title = h.get("title", "")
        analysis = analyze_headline(title)
        out.append({**h, **analysis})
    return out


def aggregate_predictions(headlines: list[dict]) -> list[dict]:
    """Per-symbol outlook from all headlines."""
    scores: dict[str, list[int]] = defaultdict(list)
    sentiments: dict[str, list[str]] = defaultdict(list)
    headlines_by_symbol: dict[str, list[str]] = defaultdict(list)

    for h in headlines:
        title = h.get("title", "")
        analysis = h if "sentiment" in h else analyze_headline(title)
        for sym in analysis.get("symbols") or []:
            scores[sym].append(int(analysis.get("score", 50)))
            sentiments[sym].append(analysis["sentiment"])
            headlines_by_symbol[sym].append(title)

    predictions: list[dict] = []
    for symbol in SYMBOL_PROFILES:
        if symbol not in scores:
            continue
        avg = sum(scores[symbol]) // len(scores[symbol])
        bulls = sentiments[symbol].count("bullish")
        bears = sentiments[symbol].count("bearish")
        if bulls > bears:
            outlook = "bullish"
        elif bears > bulls:
            outlook = "bearish"
        else:
            outlook = "neutral"
        profile = SYMBOL_PROFILES[symbol]
        predictions.append({
            "symbol": symbol,
            "name": profile["name"],
            "type": profile["type"],
            "outlook": outlook,
            "confidence": avg,
            "headline_count": len(headlines_by_symbol[symbol]),
            "prediction": _prediction_text(outlook, [symbol]),
            "option_hint": _option_hint(symbol, outlook),
        })

    predictions.sort(key=lambda p: (-p["headline_count"], p["symbol"]))
    return predictions


def _option_hint(symbol: str, outlook: str) -> str:
    profile = SYMBOL_PROFILES.get(symbol, {})
    if profile.get("type") == "index":
        if outlook == "bullish":
            return "Index options: prefer CE on TAKE signals"
        if outlook == "bearish":
            return "Index options: prefer PE or reduce size"
        return "Index options: wait for scanner TAKE"
    if outlook == "bullish":
        return "Stock F&O: bullish news — CE on pullbacks"
    if outlook == "bearish":
        return "Stock F&O: bearish news — PE or avoid longs"
    return "Stock F&O: neutral — follow index direction"


def news_bias_for_instrument(instrument: str, headlines: list[dict]) -> str | None:
    """Short bias line for signal cards (indices)."""
    enriched = enrich_headlines(headlines)
    preds = aggregate_predictions(enriched)
    match = next((p for p in preds if p["symbol"] == instrument), None)
    if not match or match["headline_count"] == 0:
        return None
    return f"News: {match['outlook']} ({match['confidence']}% conf) — {match['option_hint']}"
