import logging
import threading
from datetime import datetime, timedelta, timezone
from typing import Any

import pyotp
from SmartApi import SmartConnect

from app.config import get_settings
from app.core.rate_limit import smartapi_rate_limiter

logger = logging.getLogger(__name__)
IST = timezone(timedelta(hours=5, minutes=30))


class SmartAPIClient:
    """Thread-safe SmartAPI session with TOTP auth, token refresh, and feed tokens."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._obj: SmartConnect | None = None
        self._session_expiry: datetime | None = None
        self._auth_token: str | None = None
        self._feed_token: str | None = None
        self._refresh_token: str | None = None
        self._settings = get_settings()

    def _generate_totp(self) -> str:
        return pyotp.TOTP(self._settings.smartapi_totp_secret).now()

    def _login(self) -> SmartConnect:
        if not self._settings.smartapi_configured:
            raise RuntimeError(
                "SmartAPI credentials not configured. Copy .env.example to .env and fill values."
            )

        obj = SmartConnect(api_key=self._settings.smartapi_api_key)
        totp = self._generate_totp()
        session = obj.generateSession(
            self._settings.smartapi_client_code,
            self._settings.smartapi_password,
            totp,
        )

        if not session or not session.get("status"):
            message = session.get("message", "Unknown error") if session else "No response"
            raise RuntimeError(f"SmartAPI login failed: {message}")

        self._obj = obj
        self._auth_token = obj.access_token
        self._feed_token = obj.feed_token
        self._refresh_token = obj.refresh_token
        self._session_expiry = datetime.now(timezone.utc) + timedelta(hours=7)
        logger.info("SmartAPI session established for %s", self._settings.smartapi_client_code)
        return self._obj

    def _refresh_session(self) -> SmartConnect:
        if self._obj and self._refresh_token:
            try:
                response = self._obj.generateToken(self._refresh_token)
                if response and response.get("status"):
                    self._auth_token = self._obj.access_token
                    self._feed_token = self._obj.feed_token
                    self._session_expiry = datetime.now(timezone.utc) + timedelta(hours=7)
                    logger.info("SmartAPI session refreshed via refresh token")
                    return self._obj
            except Exception:
                logger.warning("Token refresh failed, performing full re-login")

        return self._login()

    def _ensure_session(self, force: bool = False) -> SmartConnect:
        with self._lock:
            now = datetime.now(timezone.utc)
            if (
                not force
                and self._obj
                and self._session_expiry
                and now < self._session_expiry
            ):
                return self._obj

            if self._obj and self._refresh_token and not force:
                return self._refresh_session()
            return self._login()

    def refresh_session(self) -> dict[str, str]:
        """Force session refresh — used by WebSocket reconnect and scheduler."""
        with self._lock:
            self._refresh_session()
            return self.get_tokens()

    def get_tokens(self) -> dict[str, str]:
        self._ensure_session()
        if not self._auth_token or not self._feed_token:
            raise RuntimeError("SmartAPI tokens unavailable after login")
        return {
            "auth_token": self._auth_token,
            "feed_token": self._feed_token,
            "api_key": self._settings.smartapi_api_key,
            "client_code": self._settings.smartapi_client_code,
        }

    def get_candle_data(
        self,
        exchange: str,
        symbol_token: str,
        interval: str,
        from_date: datetime,
        to_date: datetime,
    ) -> list[list[Any]]:
        obj = self._ensure_session()
        smartapi_rate_limiter.acquire()

        params = {
            "exchange": exchange,
            "symboltoken": symbol_token,
            "interval": interval,
            "fromdate": from_date.astimezone(IST).strftime("%Y-%m-%d %H:%M"),
            "todate": to_date.astimezone(IST).strftime("%Y-%m-%d %H:%M"),
        }

        response = obj.getCandleData(params)
        if not response or not response.get("status"):
            message = response.get("message", "Unknown error") if response else "No response"
            raise RuntimeError(f"getCandleData failed: {message}")

        return response.get("data") or []

    def health_check(self) -> dict[str, Any]:
        if not self._settings.smartapi_configured:
            return {"configured": False, "connected": False, "message": "Credentials not set"}
        try:
            self._ensure_session()
            expiry = self._session_expiry.isoformat() if self._session_expiry else None
            return {
                "configured": True,
                "connected": True,
                "message": "Session active",
                "session_expires_at": expiry,
            }
        except Exception as exc:
            logger.exception("SmartAPI health check failed")
            return {"configured": True, "connected": False, "message": str(exc)}


smartapi_client = SmartAPIClient()
