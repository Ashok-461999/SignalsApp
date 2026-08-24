import json
import logging
from datetime import date, datetime, timedelta, timezone
from functools import lru_cache
from typing import Any

import httpx

from app.config import get_settings
from app.data.instruments import (
    BASE_SYMBOLS,
    Instrument,
    WS_BSE_FO,
    WS_NSE_FO,
    register_futures_instrument,
    set_sensex_futures_status,
)
from app.data.smartapi_client import smartapi_client

logger = logging.getLogger(__name__)

SCRIP_MASTER_URL = (
    "https://margincalculator.angelbroking.com/OpenAPI_File/files/OpenAPIScripMaster.json"
)

FUTURES_CONFIG = {
    "NIFTY": {"exchange": "NFO", "ws_exchange_type": WS_NSE_FO, "name": "NIFTY"},
    "BANKNIFTY": {"exchange": "NFO", "ws_exchange_type": WS_NSE_FO, "name": "BANKNIFTY"},
    "FINNIFTY": {"exchange": "NFO", "ws_exchange_type": WS_NSE_FO, "name": "FINNIFTY"},
    "SENSEX": {"exchange": "BFO", "ws_exchange_type": WS_BSE_FO, "name": "SENSEX"},
}


@lru_cache(maxsize=1)
def _fetch_scrip_master() -> list[dict[str, Any]]:
    logger.info("Downloading instrument master from Angel One")
    with httpx.Client(timeout=60) as client:
        response = client.get(SCRIP_MASTER_URL)
        response.raise_for_status()
        return response.json()


def _parse_expiry(expiry_str: str) -> date | None:
    if not expiry_str:
        return None
    for fmt in ("%d%b%Y", "%d-%b-%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(expiry_str.upper(), fmt).date()
        except ValueError:
            continue
    return None


def resolve_nearest_future(symbol: str) -> Instrument | None:
    """Resolve the nearest non-expired futures contract for a base symbol."""
    cfg = FUTURES_CONFIG.get(symbol)
    if not cfg:
        return None

    today = date.today()
    candidates: list[tuple[date, dict[str, Any]]] = []

    for row in _fetch_scrip_master():
        if row.get("exch_seg") != cfg["exchange"]:
            continue
        if row.get("instrumenttype") != "FUTIDX":
            continue
        if row.get("name", "").upper() != cfg["name"]:
            continue
        expiry = _parse_expiry(row.get("expiry", ""))
        if expiry and expiry >= today:
            candidates.append((expiry, row))

    if not candidates:
        logger.warning("No futures contract found for %s on %s", symbol, cfg["exchange"])
        return None

    candidates.sort(key=lambda x: x[0])
    expiry, row = candidates[0]
    token = str(row["token"])

    return Instrument(
        symbol=symbol,
        name=f"{symbol} Futures",
        exchange=cfg["exchange"],
        token=token,
        segment="futures",
        ws_token=token,
        ws_exchange_type=cfg["ws_exchange_type"],
        expiry=expiry,
        enabled=True,
    )


def verify_bse_fo_data(futures_inst: Instrument) -> bool:
    """Probe SmartAPI historical endpoint for SENSEX BFO futures."""
    to_date = datetime.now(timezone.utc)
    from_date = to_date - timedelta(days=3)
    try:
        rows = smartapi_client.get_candle_data(
            exchange=futures_inst.exchange,
            symbol_token=futures_inst.token,
            interval="FIVE_MINUTE",
            from_date=from_date,
            to_date=to_date,
        )
        return len(rows) > 0
    except Exception as exc:
        logger.warning("BSE F&O verification failed for SENSEX: %s", exc)
        return False


def initialize_futures_registry() -> dict[str, Any]:
    """Resolve futures contracts and verify BSE F&O availability."""
    settings = get_settings()
    if not settings.smartapi_configured:
        logger.warning("SmartAPI not configured — skipping futures registry initialization")
        return {"skipped": True, "reason": "SmartAPI credentials not set"}

    results: dict[str, Any] = {"futures": {}, "sensex_futures": {}}

    for symbol in BASE_SYMBOLS:
        fut = resolve_nearest_future(symbol)
        if not fut:
            results["futures"][symbol] = {"resolved": False}
            continue

        if symbol == "SENSEX":
            available = verify_bse_fo_data(fut)
            if available:
                register_futures_instrument(fut)
                set_sensex_futures_status(
                    True,
                    f"SENSEX BFO futures verified (expiry {fut.expiry})",
                )
                results["sensex_futures"] = {
                    "available": True,
                    "token": fut.token,
                    "expiry": fut.expiry.isoformat() if fut.expiry else None,
                }
            else:
                set_sensex_futures_status(
                    False,
                    "SmartAPI returned no BSE F&O historical data for SENSEX — NSE-only mode for futures",
                )
                results["sensex_futures"] = {
                    "available": False,
                    "note": "Falling back to NSE-only. SENSEX futures disabled.",
                }
            results["futures"][symbol] = {
                "resolved": True,
                "enabled": available,
                "expiry": fut.expiry.isoformat() if fut.expiry else None,
            }
        else:
            register_futures_instrument(fut)
            results["futures"][symbol] = {
                "resolved": True,
                "enabled": True,
                "expiry": fut.expiry.isoformat() if fut.expiry else None,
            }

    return results
