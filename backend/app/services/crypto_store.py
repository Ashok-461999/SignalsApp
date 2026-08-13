"""Encrypted crypto API credential storage (server-side only)."""

from __future__ import annotations

import base64
import hashlib
import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.data.models import AppSecret

logger = logging.getLogger(__name__)

CRYPTO_SECRET_KEY = "crypto_credentials"


@dataclass
class CryptoCredentials:
    exchange: str
    api_key: str
    api_secret: str
    passphrase: str = ""

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key.strip() and self.api_secret.strip())

    @property
    def key_hint(self) -> str:
        key = self.api_key.strip()
        if len(key) <= 4:
            return "****"
        return f"…{key[-4:]}"


def _fernet() -> Fernet:
    settings = get_settings()
    secret = settings.crypto_storage_secret or settings.smartapi_api_key or "signalapp-dev-key"
    digest = hashlib.sha256(secret.encode()).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def _encrypt(payload: dict) -> str:
    raw = json.dumps(payload).encode()
    return _fernet().encrypt(raw).decode()


def _decrypt(blob: str) -> dict:
    try:
        raw = _fernet().decrypt(blob.encode())
    except InvalidToken as exc:
        raise ValueError("Failed to decrypt crypto credentials") from exc
    return json.loads(raw.decode())


def save_credentials(session: Session, creds: CryptoCredentials) -> None:
    payload = {
        "exchange": creds.exchange,
        "api_key": creds.api_key,
        "api_secret": creds.api_secret,
        "passphrase": creds.passphrase,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    encrypted = _encrypt(payload)
    row = session.get(AppSecret, CRYPTO_SECRET_KEY)
    if row is None:
        row = AppSecret(key=CRYPTO_SECRET_KEY, value_encrypted=encrypted)
        session.add(row)
    else:
        row.value_encrypted = encrypted
        row.updated_at = datetime.now(timezone.utc)
    session.commit()


def load_credentials(session: Session) -> CryptoCredentials | None:
    row = session.get(AppSecret, CRYPTO_SECRET_KEY)
    if row is None or not row.value_encrypted:
        return None
    try:
        data = _decrypt(row.value_encrypted)
    except ValueError:
        logger.exception("Crypto credentials decrypt failed")
        return None
    return CryptoCredentials(
        exchange=data.get("exchange", "binance"),
        api_key=data.get("api_key", ""),
        api_secret=data.get("api_secret", ""),
        passphrase=data.get("passphrase", ""),
    )


def clear_credentials(session: Session) -> None:
    row = session.get(AppSecret, CRYPTO_SECRET_KEY)
    if row is not None:
        session.delete(row)
        session.commit()


def credentials_status(creds: CryptoCredentials | None) -> dict:
    if creds is None or not creds.is_configured:
        return {"configured": False, "exchange": "binance", "api_key_hint": None}
    return {
        "configured": True,
        "exchange": creds.exchange,
        "api_key_hint": creds.key_hint,
    }
