"""Tests for crypto credential storage."""

from app.data.models import AppSecret
from app.db.session import SyncSessionLocal
from app.services.crypto_store import (
    clear_credentials,
    credentials_status,
    load_credentials,
    save_credentials,
)
from app.services.crypto_store import CryptoCredentials


def test_crypto_credentials_roundtrip():
    session = SyncSessionLocal()
    try:
        clear_credentials(session)
        creds = CryptoCredentials(
            exchange="binance",
            api_key="test-key-1234",
            api_secret="test-secret",
        )
        save_credentials(session, creds)
        loaded = load_credentials(session)
        assert loaded is not None
        assert loaded.api_key == "test-key-1234"
        assert loaded.api_secret == "test-secret"
        status = credentials_status(loaded)
        assert status["configured"] is True
        assert status["api_key_hint"].endswith("1234")
        clear_credentials(session)
        assert load_credentials(session) is None
    finally:
        session.close()
