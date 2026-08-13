"""Runtime trading toggles — persisted in DB, adjustable from the app."""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, dataclass
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.data.models import AppSecret

logger = logging.getLogger(__name__)

TRADING_SETTINGS_KEY = "trading_settings"


@dataclass
class TradingSettings:
    paper_trading: bool = True
    live_execution_enabled: bool = False
    crypto_paper_trading: bool = True
    crypto_live_enabled: bool = False
    kill_switch: bool = False
    risk_percent: float = 1.0

    @property
    def indian_execution_allowed(self) -> bool:
        return not self.paper_trading and self.live_execution_enabled and not self.kill_switch

    @property
    def crypto_execution_allowed(self) -> bool:
        return not self.crypto_paper_trading and self.crypto_live_enabled and not self.kill_switch


def _from_env(settings: Settings) -> TradingSettings:
    return TradingSettings(
        paper_trading=settings.paper_trading,
        live_execution_enabled=settings.live_execution_enabled,
        crypto_paper_trading=settings.crypto_paper_trading,
        crypto_live_enabled=settings.crypto_live_enabled,
        kill_switch=settings.kill_switch,
        risk_percent=settings.risk_percent,
    )


def load_trading_settings(session: Session) -> TradingSettings:
    row = session.get(AppSecret, TRADING_SETTINGS_KEY)
    if row is None or not row.value_encrypted:
        return _from_env(get_settings())
    try:
        data = json.loads(row.value_encrypted)
        base = _from_env(get_settings())
        return TradingSettings(
            paper_trading=bool(data.get("paper_trading", base.paper_trading)),
            live_execution_enabled=bool(data.get("live_execution_enabled", base.live_execution_enabled)),
            crypto_paper_trading=bool(data.get("crypto_paper_trading", base.crypto_paper_trading)),
            crypto_live_enabled=bool(data.get("crypto_live_enabled", base.crypto_live_enabled)),
            kill_switch=bool(data.get("kill_switch", base.kill_switch)),
            risk_percent=float(data.get("risk_percent", base.risk_percent)),
        )
    except (json.JSONDecodeError, TypeError, ValueError):
        logger.exception("Invalid trading settings in DB — using env defaults")
        return _from_env(get_settings())


def save_trading_settings(session: Session, updates: dict) -> TradingSettings:
    current = load_trading_settings(session)
    data = asdict(current)

    for key in (
        "paper_trading",
        "live_execution_enabled",
        "crypto_paper_trading",
        "crypto_live_enabled",
        "kill_switch",
        "risk_percent",
    ):
        if key in updates and updates[key] is not None:
            data[key] = updates[key]

    if data["live_execution_enabled"]:
        data["paper_trading"] = False
    if data["paper_trading"]:
        data["live_execution_enabled"] = False

    if data["crypto_live_enabled"]:
        data["crypto_paper_trading"] = False
    if data["crypto_paper_trading"]:
        data["crypto_live_enabled"] = False

    data["risk_percent"] = max(0.1, min(float(data["risk_percent"]), 5.0))
    saved = TradingSettings(**data)

    row = session.get(AppSecret, TRADING_SETTINGS_KEY)
    payload = json.dumps(asdict(saved))
    if row is None:
        row = AppSecret(key=TRADING_SETTINGS_KEY, value_encrypted=payload)
        session.add(row)
    else:
        row.value_encrypted = payload
        row.updated_at = datetime.now(timezone.utc)
    session.commit()
    return saved


def trading_settings_dict(settings: TradingSettings) -> dict:
    return {
        **asdict(settings),
        "execution_allowed": settings.indian_execution_allowed,
        "crypto_execution_allowed": settings.crypto_execution_allowed,
    }
