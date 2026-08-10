import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.config import get_settings
from app.data.smartapi_client import smartapi_client

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/execution", tags=["execution"])

LOT_SIZES = {"NIFTY": 25, "BANKNIFTY": 15, "SENSEX": 10}


class ExecuteRequest(BaseModel):
    instrument: str
    direction: str
    strike: float
    expiry: str
    quantity_lots: int = Field(ge=1, le=10)
    journal_entry_id: int | None = None
    confirm: bool = False


class ExecuteResponse(BaseModel):
    status: str
    message: str
    order_id: str | None = None
    paper: bool = True


@router.post("/place-order", response_model=ExecuteResponse)
def place_order(body: ExecuteRequest) -> ExecuteResponse:
    settings = get_settings()

    if settings.kill_switch:
        raise HTTPException(403, "Kill switch active — all order placement disabled")

    if not body.confirm:
        raise HTTPException(400, "Explicit confirm=true required for every order")

    lot_size = LOT_SIZES.get(body.instrument.upper(), 25)
    total_qty = body.quantity_lots * lot_size

    if settings.paper_trading or not settings.live_execution_enabled:
        logger.info(
            "PAPER order: %s %s strike=%s qty=%d",
            body.instrument,
            body.direction,
            body.strike,
            total_qty,
        )
        return ExecuteResponse(
            status="paper_filled",
            message="Paper trade recorded — no real order placed",
            order_id=f"PAPER-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}",
            paper=True,
        )

    if not settings.execution_allowed:
        raise HTTPException(403, "Live execution not enabled")

    try:
        smartapi_client._ensure_session()
        return ExecuteResponse(
            status="pending",
            message="Live execution gated — wire SmartAPI placeOrder when ready",
            paper=False,
        )
    except Exception as exc:
        raise HTTPException(502, str(exc)) from exc
