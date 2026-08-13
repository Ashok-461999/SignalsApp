"""Crypto exchange REST client — Binance, Bybit, CoinDCX."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import time
from typing import Any
from urllib.parse import urlencode

import httpx

from app.services.crypto_store import CryptoCredentials

logger = logging.getLogger(__name__)

CRYPTO_WATCHLIST = [
    {"symbol": "BTC", "pair": "BTCUSDT", "name": "Bitcoin"},
    {"symbol": "ETH", "pair": "ETHUSDT", "name": "Ethereum"},
    {"symbol": "SOL", "pair": "SOLUSDT", "name": "Solana"},
    {"symbol": "BNB", "pair": "BNBUSDT", "name": "BNB"},
]

INTERVAL_MAP = {
    "1m": "1m",
    "5m": "5m",
    "15m": "15m",
    "1h": "1h",
    "4h": "4h",
    "1d": "1d",
}


class CryptoClient:
    def __init__(self, creds: CryptoCredentials | None = None) -> None:
        self.creds = creds
        self.exchange = (creds.exchange if creds else "binance").lower()

    def test_connection(self) -> str:
        if self.creds is None or not self.creds.is_configured:
            raise ValueError("Crypto API keys not configured on server")
        balances = self.get_balances()
        count = len(balances)
        label = self.exchange.capitalize()
        return f"{label} connected — {count} balance line(s) OK"

    def get_prices(self) -> list[dict[str, Any]]:
        if self.exchange == "binance":
            return self._binance_prices()
        if self.exchange == "bybit":
            return self._bybit_prices()
        return self._coindcx_prices()

    def get_candles(self, symbol: str, interval: str = "5m", limit: int = 120) -> list[dict]:
        pair = self._pair(symbol)
        iv = INTERVAL_MAP.get(interval, "5m")
        if self.exchange == "binance":
            return self._binance_klines(pair, iv, limit)
        if self.exchange == "bybit":
            return self._bybit_klines(pair, iv, limit)
        return self._coindcx_klines(pair, iv, limit)

    def get_balances(self) -> list[dict[str, Any]]:
        if self.creds is None or not self.creds.is_configured:
            raise ValueError("Crypto API keys not configured on server")
        if self.exchange == "binance":
            return self._binance_balances()
        if self.exchange == "bybit":
            return self._bybit_balances()
        return self._coindcx_balances()

    def place_order(
        self,
        symbol: str,
        side: str,
        quantity: float,
        order_type: str = "MARKET",
        paper: bool = True,
    ) -> dict[str, Any]:
        pair = self._pair(symbol)
        side_u = side.upper()
        if paper:
            return {
                "status": "paper_filled",
                "paper": True,
                "symbol": pair,
                "side": side_u,
                "quantity": quantity,
                "order_type": order_type,
                "order_id": f"PAPER-{int(time.time())}",
                "message": "Paper trade — no real order sent",
            }
        if self.creds is None or not self.creds.is_configured:
            raise ValueError("Crypto API keys not configured on server")
        if self.exchange == "binance":
            return self._binance_order(pair, side_u, quantity, order_type)
        if self.exchange == "bybit":
            return self._bybit_order(pair, side_u, quantity, order_type)
        return self._coindcx_order(pair, side_u, quantity, order_type)

    def get_recent_trades(self, symbol: str, limit: int = 20) -> list[dict[str, Any]]:
        if self.creds is None or not self.creds.is_configured:
            return []
        pair = self._pair(symbol)
        if self.exchange == "binance":
            return self._binance_my_trades(pair, limit)
        if self.exchange == "bybit":
            return self._bybit_recent_trades(pair, limit)
        return []

    # --- helpers ---

    def _pair(self, symbol: str) -> str:
        sym = symbol.upper().replace("USDT", "")
        return f"{sym}USDT"

    def _hmac_sha256(self, message: str, secret: str) -> str:
        return hmac.new(secret.encode(), message.encode(), hashlib.sha256).hexdigest()

    def _binance_prices(self) -> list[dict[str, Any]]:
        pairs = [w["pair"] for w in CRYPTO_WATCHLIST]
        r = httpx.get(
            "https://api.binance.com/api/v3/ticker/24hr",
            params={"symbols": json.dumps(pairs)},
            timeout=15,
        )
        r.raise_for_status()
        by_symbol = {t["symbol"]: t for t in r.json()}
        out: list[dict[str, Any]] = []
        for w in CRYPTO_WATCHLIST:
            t = by_symbol.get(w["pair"], {})
            out.append(
                {
                    "symbol": w["symbol"],
                    "pair": w["pair"],
                    "name": w["name"],
                    "price": float(t.get("lastPrice") or 0),
                    "change_pct_24h": float(t.get("priceChangePercent") or 0),
                    "volume_24h": float(t.get("volume") or 0),
                }
            )
        return out

    def _bybit_prices(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for w in CRYPTO_WATCHLIST:
            r = httpx.get(
                "https://api.bybit.com/v5/market/tickers",
                params={"category": "spot", "symbol": w["pair"]},
                timeout=15,
            )
            r.raise_for_status()
            items = (r.json().get("result") or {}).get("list") or []
            t = items[0] if items else {}
            out.append(
                {
                    "symbol": w["symbol"],
                    "pair": w["pair"],
                    "name": w["name"],
                    "price": float(t.get("lastPrice") or 0),
                    "change_pct_24h": float(t.get("price24hPcnt") or 0) * 100,
                    "volume_24h": float(t.get("volume24h") or 0),
                }
            )
        return out

    def _coindcx_prices(self) -> list[dict[str, Any]]:
        r = httpx.get("https://api.coindcx.com/exchange/ticker", timeout=15)
        r.raise_for_status()
        tickers = {t["market"]: t for t in r.json()}
        out: list[dict[str, Any]] = []
        for w in CRYPTO_WATCHLIST:
            market = f"{w['symbol']}USDT"
            t = tickers.get(market, {})
            out.append(
                {
                    "symbol": w["symbol"],
                    "pair": market,
                    "name": w["name"],
                    "price": float(t.get("last_price") or 0),
                    "change_pct_24h": float(t.get("change_24_hour") or 0),
                    "volume_24h": float(t.get("volume") or 0),
                }
            )
        return out

    def _binance_klines(self, pair: str, interval: str, limit: int) -> list[dict]:
        r = httpx.get(
            "https://api.binance.com/api/v3/klines",
            params={"symbol": pair, "interval": interval, "limit": limit},
            timeout=20,
        )
        r.raise_for_status()
        return [
            {
                "timestamp": row[0],
                "open": float(row[1]),
                "high": float(row[2]),
                "low": float(row[3]),
                "close": float(row[4]),
                "volume": float(row[5]),
            }
            for row in r.json()
        ]

    def _bybit_klines(self, pair: str, interval: str, limit: int) -> list[dict]:
        bybit_iv = {"1m": "1", "5m": "5", "15m": "15", "1h": "60", "4h": "240", "1d": "D"}.get(
            interval, "5"
        )
        r = httpx.get(
            "https://api.bybit.com/v5/market/kline",
            params={"category": "spot", "symbol": pair, "interval": bybit_iv, "limit": limit},
            timeout=20,
        )
        r.raise_for_status()
        rows = list(reversed((r.json().get("result") or {}).get("list") or []))
        return [
            {
                "timestamp": int(row[0]),
                "open": float(row[1]),
                "high": float(row[2]),
                "low": float(row[3]),
                "close": float(row[4]),
                "volume": float(row[5]),
            }
            for row in rows
        ]

    def _coindcx_klines(self, pair: str, interval: str, limit: int) -> list[dict]:
        resolution = {"1m": 1, "5m": 5, "15m": 15, "1h": 60, "4h": 240, "1d": 1440}.get(interval, 5)
        r = httpx.get(
            "https://public.coindcx.com/market_data/candles",
            params={"pair": pair, "interval": resolution, "limit": limit},
            timeout=20,
        )
        r.raise_for_status()
        return [
            {
                "timestamp": int(row["time"]),
                "open": float(row["open"]),
                "high": float(row["high"]),
                "low": float(row["low"]),
                "close": float(row["close"]),
                "volume": float(row.get("volume") or 0),
            }
            for row in r.json()
        ]

    def _binance_signed_get(self, path: str, params: dict | None = None) -> dict:
        assert self.creds is not None
        p = dict(params or {})
        p["timestamp"] = int(time.time() * 1000)
        query = urlencode(p)
        sig = self._hmac_sha256(query, self.creds.api_secret)
        r = httpx.get(
            f"https://api.binance.com{path}",
            params={**p, "signature": sig},
            headers={"X-MBX-APIKEY": self.creds.api_key},
            timeout=20,
        )
        r.raise_for_status()
        return r.json()

    def _binance_signed_post(self, path: str, params: dict) -> dict:
        assert self.creds is not None
        p = dict(params)
        p["timestamp"] = int(time.time() * 1000)
        query = urlencode(p)
        sig = self._hmac_sha256(query, self.creds.api_secret)
        r = httpx.post(
            f"https://api.binance.com{path}",
            params={**p, "signature": sig},
            headers={"X-MBX-APIKEY": self.creds.api_key},
            timeout=20,
        )
        r.raise_for_status()
        return r.json()

    def _binance_balances(self) -> list[dict[str, Any]]:
        data = self._binance_signed_get("/api/v3/account")
        out = []
        for b in data.get("balances", []):
            free = float(b.get("free") or 0)
            locked = float(b.get("locked") or 0)
            if free + locked > 0:
                out.append({"asset": b["asset"], "free": free, "locked": locked})
        return sorted(out, key=lambda x: x["free"] + x["locked"], reverse=True)

    def _binance_order(self, pair: str, side: str, quantity: float, order_type: str) -> dict:
        data = self._binance_signed_post(
            "/api/v3/order",
            {
                "symbol": pair,
                "side": side,
                "type": order_type,
                "quantity": quantity,
            },
        )
        return {
            "status": data.get("status", "submitted").lower(),
            "paper": False,
            "order_id": str(data.get("orderId")),
            "symbol": pair,
            "side": side,
            "quantity": quantity,
            "message": "Live order submitted to Binance",
        }

    def _binance_my_trades(self, pair: str, limit: int) -> list[dict[str, Any]]:
        data = self._binance_signed_get("/api/v3/myTrades", {"symbol": pair, "limit": limit})
        return [
            {
                "id": str(t.get("id")),
                "symbol": pair,
                "side": "BUY" if t.get("isBuyer") else "SELL",
                "price": float(t.get("price") or 0),
                "quantity": float(t.get("qty") or 0),
                "time": int(t.get("time") or 0),
            }
            for t in data
        ]

    def _bybit_signed_get(self, path: str, params: dict | None = None) -> dict:
        assert self.creds is not None
        ts = str(int(time.time() * 1000))
        query = urlencode(params or {})
        payload = f"{ts}{self.creds.api_key}{query}"
        sig = self._hmac_sha256(payload, self.creds.api_secret)
        r = httpx.get(
            f"https://api.bybit.com{path}",
            params=params,
            headers={
                "X-BAPI-API-KEY": self.creds.api_key,
                "X-BAPI-TIMESTAMP": ts,
                "X-BAPI-SIGN": sig,
            },
            timeout=20,
        )
        r.raise_for_status()
        return r.json()

    def _bybit_balances(self) -> list[dict[str, Any]]:
        data = self._bybit_signed_get("/v5/account/wallet-balance", {"accountType": "UNIFIED"})
        if data.get("retCode") != 0:
            raise ValueError(data.get("retMsg", "Bybit balance fetch failed"))
        out: list[dict[str, Any]] = []
        for acct in (data.get("result") or {}).get("list") or []:
            for c in acct.get("coin") or []:
                free = float(c.get("walletBalance") or 0)
                if free > 0:
                    out.append({"asset": c.get("coin"), "free": free, "locked": 0.0})
        return out

    def _bybit_order(self, pair: str, side: str, quantity: float, order_type: str) -> dict:
        ts = str(int(time.time() * 1000))
        body = {
            "category": "spot",
            "symbol": pair,
            "side": side.capitalize(),
            "orderType": order_type.capitalize(),
            "qty": str(quantity),
        }
        raw = json.dumps(body)
        sig = self._hmac_sha256(f"{ts}{self.creds.api_key}{raw}", self.creds.api_secret)  # type: ignore[union-attr]
        r = httpx.post(
            "https://api.bybit.com/v5/order/create",
            content=raw,
            headers={
                "X-BAPI-API-KEY": self.creds.api_key,  # type: ignore[union-attr]
                "X-BAPI-TIMESTAMP": ts,
                "X-BAPI-SIGN": sig,
                "Content-Type": "application/json",
            },
            timeout=20,
        )
        r.raise_for_status()
        data = r.json()
        if data.get("retCode") != 0:
            raise ValueError(data.get("retMsg", "Bybit order failed"))
        oid = (data.get("result") or {}).get("orderId")
        return {
            "status": "submitted",
            "paper": False,
            "order_id": str(oid),
            "symbol": pair,
            "side": side,
            "quantity": quantity,
            "message": "Live order submitted to Bybit",
        }

    def _bybit_recent_trades(self, pair: str, limit: int) -> list[dict[str, Any]]:
        data = self._bybit_signed_get(
            "/v5/execution/list",
            {"category": "spot", "symbol": pair, "limit": limit},
        )
        if data.get("retCode") != 0:
            return []
        return [
            {
                "id": t.get("execId"),
                "symbol": pair,
                "side": (t.get("side") or "").upper(),
                "price": float(t.get("execPrice") or 0),
                "quantity": float(t.get("execQty") or 0),
                "time": int(t.get("execTime") or 0),
            }
            for t in (data.get("result") or {}).get("list") or []
        ]

    def _coindcx_signed_post(self, path: str, body: dict) -> Any:
        assert self.creds is not None
        ts = int(time.time() * 1000)
        payload = json.dumps({**body, "timestamp": ts})
        sig = self._hmac_sha256(payload, self.creds.api_secret)
        r = httpx.post(
            f"https://api.coindcx.com{path}",
            content=payload,
            headers={
                "X-AUTH-APIKEY": self.creds.api_key,
                "X-AUTH-SIGNATURE": sig,
                "Content-Type": "application/json",
            },
            timeout=20,
        )
        r.raise_for_status()
        return r.json()

    def _coindcx_balances(self) -> list[dict[str, Any]]:
        data = self._coindcx_signed_post("/exchange/v1/users/balances", {})
        if not isinstance(data, list):
            raise ValueError("CoinDCX balance response invalid")
        out = []
        for b in data:
            free = float(b.get("balance") or 0)
            locked = float(b.get("locked_balance") or 0)
            if free + locked > 0:
                out.append({"asset": b.get("currency"), "free": free, "locked": locked})
        return out

    def _coindcx_order(self, pair: str, side: str, quantity: float, order_type: str) -> dict:
        market = pair.replace("USDT", "_USDT")
        body = {
            "side": side.lower(),
            "order_type": order_type.lower(),
            "market": market,
            "total_quantity": quantity,
        }
        data = self._coindcx_signed_post("/exchange/v1/orders/create", body)
        return {
            "status": "submitted",
            "paper": False,
            "order_id": str(data.get("id") or data.get("order_id") or ""),
            "symbol": pair,
            "side": side,
            "quantity": quantity,
            "message": "Live order submitted to CoinDCX",
        }
