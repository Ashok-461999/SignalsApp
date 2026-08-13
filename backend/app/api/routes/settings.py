from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_sync_session
from app.services.trading_settings import (
    load_trading_settings,
    save_trading_settings,
    trading_settings_dict,
)

router = APIRouter(prefix="/settings", tags=["settings"])


class TradingSettingsBody(BaseModel):
    paper_trading: bool | None = None
    live_execution_enabled: bool | None = None
    crypto_paper_trading: bool | None = None
    crypto_live_enabled: bool | None = None
    kill_switch: bool | None = None
    risk_percent: float | None = Field(default=None, ge=0.1, le=5.0)


@router.get("/trading")
def get_trading_settings(session: Session = Depends(get_sync_session)) -> dict:
    settings = load_trading_settings(session)
    return trading_settings_dict(settings)


@router.patch("/trading")
def update_trading_settings(
    body: TradingSettingsBody,
    session: Session = Depends(get_sync_session),
) -> dict:
    updates = body.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(400, "No settings to update")
    saved = save_trading_settings(session, updates)
    return trading_settings_dict(saved)
