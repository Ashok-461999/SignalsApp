"""Fetch and normalize options chain from Angel One scrip master + market quotes."""

from __future__ import annotations

import logging
from datetime import date, datetime
from functools import lru_cache
from typing import Any

from app.alpha.constants import ALPHA_INSTRUMENTS, INSTRUMENT_SPECS
from app.data.instrument_master import _fetch_scrip_master, _parse_expiry
from app.data.smartapi_client import smartapi_client

logger = logging.getLogger(__name__)

BATCH_SIZE = 45


def _expiry_str(d: date) -> str:
    return d.strftime("%d%b%Y").upper()


@lru_cache(maxsize=8)
def _chain_rows_for(instrument: str, expiry_iso: str) -> tuple[dict[str, Any], ...]:
    spec = INSTRUMENT_SPECS[instrument]
    exchange = spec["exchange"]
    expiry = date.fromisoformat(expiry_iso)
    rows: list[dict[str, Any]] = []
    for row in _fetch_scrip_master():
        if row.get("exch_seg") != exchange:
            continue
        if row.get("instrumenttype") != "OPTIDX":
            continue
        if row.get("name", "").upper() != instrument:
            continue
        ex = _parse_expiry(row.get("expiry", ""))
        if ex != expiry:
            continue
        sym = str(row.get("symbol", ""))
        opt_type = "CE" if sym.endswith("CE") else "PE" if sym.endswith("PE") else ""
        if not opt_type:
            continue
        strike = float(row.get("strike", 0) or 0) / 100.0 if float(row.get("strike", 0) or 0) > 10000 else float(row.get("strike", 0) or 0)
        if strike <= 0:
            # Angel stores strike in rupees in symbol sometimes
            try:
                strike = float(str(row.get("strike", "0")))
            except ValueError:
                continue
        rows.append(
            {
                "token": str(row["token"]),
                "symbol": sym,
                "strike": strike,
                "option_type": opt_type,
                "expiry": expiry_iso,
            }
        )
    return tuple(rows)


def nearest_expiries(instrument: str, count: int = 2) -> list[date]:
    spec = INSTRUMENT_SPECS[instrument]
    exchange = spec["exchange"]
    today = date.today()
    exps: set[date] = set()
    for row in _fetch_scrip_master():
        if row.get("exch_seg") != exchange or row.get("instrumenttype") != "OPTIDX":
            continue
        if row.get("name", "").upper() != instrument:
            continue
        ex = _parse_expiry(row.get("expiry", ""))
        if ex and ex >= today:
            exps.add(ex)
    return sorted(exps)[:count]


def fetch_option_chain(instrument: str, spot: float, strike_window: int = 12) -> dict[str, Any]:
    """Live option chain with OI, volume, LTP for ATM ± strike_window."""
    instrument = instrument.upper()
    if instrument not in ALPHA_INSTRUMENTS:
        raise ValueError(f"Unsupported instrument: {instrument}")

    exps = nearest_expiries(instrument, 2)
    if not exps:
        return {"instrument": instrument, "error": "no expiries", "contracts": []}

    expiry = exps[0]
    dte = (expiry - date.today()).days
    if dte < 5 and len(exps) > 1:
        expiry = exps[1]
        dte = (expiry - date.today()).days

    spec = INSTRUMENT_SPECS[instrument]
    step = spec["strike_step"]
    atm = round(spot / step) * step
    min_strike = atm - step * strike_window
    max_strike = atm + step * strike_window

    meta_rows = [r for r in _chain_rows_for(instrument, expiry.isoformat()) if min_strike <= r["strike"] <= max_strike]
    if not meta_rows:
        return {"instrument": instrument, "expiry": expiry.isoformat(), "dte": dte, "contracts": []}

    exchange = spec["exchange"]
    quotes: dict[str, dict] = {}
    tokens = [r["token"] for r in meta_rows]
    for i in range(0, len(tokens), BATCH_SIZE):
        batch = tokens[i : i + BATCH_SIZE]
        try:
            fetched = smartapi_client.market_quote({exchange: batch})
            for q in fetched:
                quotes[str(q.get("symbolToken", ""))] = q
        except Exception:
            logger.exception("marketQuote batch failed for %s", instrument)

    contracts: list[dict[str, Any]] = []
    for m in meta_rows:
        q = quotes.get(m["token"], {})
        ltp = float(q.get("ltp") or q.get("lastPrice") or 0)
        oi = int(float(q.get("opnInterest") or q.get("openInterest") or 0))
        vol = int(float(q.get("tradeVolume") or q.get("volume") or 0))
        bid = float(q.get("bid") or q.get("buyPrice") or 0)
        ask = float(q.get("ask") or q.get("sellPrice") or 0)
        iv = float(q.get("iv") or 0)
        contracts.append(
            {
                **m,
                "ltp": ltp,
                "oi": oi,
                "volume": vol,
                "bid": bid,
                "ask": ask,
                "iv": iv if iv > 0 else 0.16,
                "spread_pct": round((ask - bid) / ltp * 100, 3) if ltp > 0 and ask > bid else 0,
            }
        )

    return {
        "instrument": instrument,
        "spot": spot,
        "expiry": expiry.isoformat(),
        "dte": dte,
        "atm_strike": atm,
        "contracts": contracts,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }
