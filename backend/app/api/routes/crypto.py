import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db.session import get_sync_session
from app.services.crypto_client import CRYPTO_WATCHLIST, CryptoClient
from app.services.crypto_store import (
    clear_credentials,
    credentials_status,
    load_credentials,
    save_credentials,
)
from app.services.crypto_store import CryptoCredentials as StoredCredentials

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/crypto", tags=["crypto"])


class CredentialsBody(BaseModel):
    exchange: str = Field(default="binance", pattern="^(binance|bybit|coindcx)$")
    api_key: str = Field(min_length=1)
    api_secret: str = Field(min_length=1)
    passphrase: str = ""


class PlaceOrderBody(BaseModel):
    symbol: str = Field(min_length=2, max_length=16)
    side: str = Field(pattern="^(buy|sell|BUY|SELL)$")
    quantity: float = Field(gt=0)
    order_type: str = "MARKET"
    confirm: bool = False


@router.get("/credentials")
def get_crypto_credentials(session: Session = Depends(get_sync_session)) -> dict:
    creds = load_credentials(session)
    return credentials_status(creds)


@router.put("/credentials")
def save_crypto_credentials(
    body: CredentialsBody, session: Session = Depends(get_sync_session)
) -> dict:
    creds = StoredCredentials(
        exchange=body.exchange.lower(),
        api_key=body.api_key.strip(),
        api_secret=body.api_secret.strip(),
        passphrase=body.passphrase.strip(),
    )
    save_credentials(session, creds)
    return {"ok": True, **credentials_status(creds)}


@router.delete("/credentials")
def delete_crypto_credentials(session: Session = Depends(get_sync_session)) -> dict:
    clear_credentials(session)
    return {"ok": True, "configured": False}


@router.post("/credentials/test")
def test_crypto_credentials(
    body: CredentialsBody | None = None,
    session: Session = Depends(get_sync_session),
) -> dict:
    if body is not None:
        creds = StoredCredentials(
            exchange=body.exchange.lower(),
            api_key=body.api_key.strip(),
            api_secret=body.api_secret.strip(),
            passphrase=body.passphrase.strip(),
        )
    else:
        creds = load_credentials(session)
    if creds is None or not creds.is_configured:
        raise HTTPException(400, "Crypto API keys not configured")
    try:
        msg = CryptoClient(creds).test_connection()
        return {"ok": True, "message": msg}
    except Exception as exc:
        logger.exception("Crypto credentials test failed")
        raise HTTPException(502, str(exc)) from exc


@router.get("/watchlist")
def crypto_watchlist(session: Session = Depends(get_sync_session)) -> dict:
    creds = load_credentials(session)
    exchange = creds.exchange if creds and creds.is_configured else "binance"
    client = CryptoClient(StoredCredentials(exchange=exchange, api_key="", api_secret=""))
    return {"instruments": CRYPTO_WATCHLIST, "exchange": exchange}


@router.get("/prices")
def crypto_prices(session: Session = Depends(get_sync_session)) -> dict:
    creds = load_credentials(session)
    exchange = creds.exchange if creds and creds.is_configured else "binance"
    client = CryptoClient(StoredCredentials(exchange=exchange, api_key="", api_secret=""))
    try:
        prices = client.get_prices()
        return {"prices": prices, "exchange": exchange}
    except Exception as exc:
        logger.exception("Crypto prices failed")
        raise HTTPException(502, str(exc)) from exc


@router.get("/candles")
def crypto_candles(
    symbol: str = "BTC",
    interval: str = "5m",
    limit: int = 120,
    session: Session = Depends(get_sync_session),
) -> dict:
    creds = load_credentials(session)
    exchange = creds.exchange if creds and creds.is_configured else "binance"
    client = CryptoClient(StoredCredentials(exchange=exchange, api_key="", api_secret=""))
    try:
        candles = client.get_candles(symbol=symbol.upper(), interval=interval, limit=limit)
        return {"symbol": symbol.upper(), "interval": interval, "candles": candles}
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc


@router.get("/balances")
def crypto_balances(session: Session = Depends(get_sync_session)) -> dict:
    creds = load_credentials(session)
    if creds is None or not creds.is_configured:
        raise HTTPException(400, "Add crypto API keys in Settings first")
    try:
        balances = CryptoClient(creds).get_balances()
        return {"balances": balances, "exchange": creds.exchange}
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc


@router.get("/trades")
def crypto_trades(
    symbol: str = "BTC",
    limit: int = 20,
    session: Session = Depends(get_sync_session),
) -> dict:
    creds = load_credentials(session)
    if creds is None or not creds.is_configured:
        return {"trades": [], "message": "Configure crypto API keys for trade history"}
    try:
        trades = CryptoClient(creds).get_recent_trades(symbol=symbol.upper(), limit=limit)
        return {"trades": trades, "symbol": symbol.upper()}
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc


@router.post("/orders")
def crypto_place_order(
    body: PlaceOrderBody, session: Session = Depends(get_sync_session)
) -> dict:
    settings = get_settings()
    if settings.kill_switch:
        raise HTTPException(403, "Kill switch active — crypto orders disabled")
    if not body.confirm:
        raise HTTPException(400, "confirm=true required for every order")

    creds = load_credentials(session)
    paper = settings.crypto_paper_trading or not creds or not creds.is_configured
    if not paper and not settings.crypto_live_enabled:
        raise HTTPException(403, "Live crypto trading not enabled on server")

    client = CryptoClient(creds)
    try:
        result = client.place_order(
            symbol=body.symbol.upper(),
            side=body.side.upper(),
            quantity=body.quantity,
            order_type=body.order_type.upper(),
            paper=paper,
        )
        return result
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc
