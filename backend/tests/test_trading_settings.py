"""Tests for runtime trading settings."""

from app.db.session import SyncSessionLocal
from app.services.trading_settings import (
    TRADING_SETTINGS_KEY,
    load_trading_settings,
    save_trading_settings,
)
from app.data.models import AppSecret


def test_trading_settings_toggle_live_crypto():
    session = SyncSessionLocal()
    try:
        row = session.get(AppSecret, TRADING_SETTINGS_KEY)
        if row is not None:
            session.delete(row)
            session.commit()

        save_trading_settings(session, {"crypto_live_enabled": True})
        loaded = load_trading_settings(session)
        assert loaded.crypto_live_enabled is True
        assert loaded.crypto_paper_trading is False

        save_trading_settings(session, {"crypto_paper_trading": True})
        loaded = load_trading_settings(session)
        assert loaded.crypto_paper_trading is True
        assert loaded.crypto_live_enabled is False
    finally:
        session.close()
