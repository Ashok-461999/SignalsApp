import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.data.models import JournalEntry
from app.api.routes.journal_stats import build_journal_summary, calc_option_pnl
from app.db.session import get_sync_session

router = APIRouter(prefix="/journal", tags=["journal"])


class JournalCreate(BaseModel):
    setup_name: str
    instrument: str
    segment: str = "spot"
    direction: str
    underlying_entry: float
    underlying_stop_loss: float
    underlying_target: list[float]
    suggested_strike: float | None = None
    suggested_expiry: str | None = None
    planned_size: int = 1
    status: str = "approved"
    notes: str = ""


class JournalUpdate(BaseModel):
    actual_fill_price: float | None = None
    exit_price: float | None = None
    pnl: float | None = None
    status: str | None = None
    notes: str | None = None


class JournalOut(BaseModel):
    id: int
    setup_name: str
    instrument: str
    segment: str
    direction: str
    status: str
    underlying_entry: float
    underlying_stop_loss: float
    underlying_target: list[float]
    suggested_strike: float | None
    suggested_expiry: str | None
    planned_size: int
    actual_fill_price: float | None
    exit_price: float | None
    pnl: float | None
    notes: str
    created_at: datetime

    class Config:
        from_attributes = True


def _to_out(entry: JournalEntry) -> JournalOut:
    try:
        targets = json.loads(entry.underlying_target)
    except json.JSONDecodeError:
        targets = []
    return JournalOut(
        id=entry.id,
        setup_name=entry.setup_name,
        instrument=entry.instrument,
        segment=entry.segment,
        direction=entry.direction,
        status=entry.status,
        underlying_entry=entry.underlying_entry,
        underlying_stop_loss=entry.underlying_stop_loss,
        underlying_target=targets,
        suggested_strike=entry.suggested_strike,
        suggested_expiry=entry.suggested_expiry,
        planned_size=entry.planned_size,
        actual_fill_price=entry.actual_fill_price,
        exit_price=entry.exit_price,
        pnl=entry.pnl,
        notes=entry.notes,
        created_at=entry.created_at,
    )


@router.get("")
def list_journal(session: Session = Depends(get_sync_session)) -> dict:
    rows = session.execute(
        select(JournalEntry).order_by(JournalEntry.created_at.desc()).limit(200)
    ).scalars().all()
    entries = [_to_out(r) for r in rows]
    return {
        "count": len(entries),
        "entries": entries,
        "summary": build_journal_summary(entries),
    }


@router.post("", response_model=JournalOut)
def create_journal(
    body: JournalCreate,
    session: Session = Depends(get_sync_session),
) -> JournalOut:
    entry = JournalEntry(
        setup_name=body.setup_name,
        instrument=body.instrument,
        segment=body.segment,
        direction=body.direction,
        status=body.status,
        underlying_entry=body.underlying_entry,
        underlying_stop_loss=body.underlying_stop_loss,
        underlying_target=json.dumps(body.underlying_target),
        suggested_strike=body.suggested_strike,
        suggested_expiry=body.suggested_expiry,
        planned_size=body.planned_size,
        notes=body.notes,
        signal_timestamp=datetime.now(timezone.utc),
    )
    session.add(entry)
    session.commit()
    session.refresh(entry)
    return _to_out(entry)


@router.patch("/{entry_id}", response_model=JournalOut)
def update_journal(
    entry_id: int,
    body: JournalUpdate,
    session: Session = Depends(get_sync_session),
) -> JournalOut:
    entry = session.get(JournalEntry, entry_id)
    if not entry:
        raise HTTPException(404, "Journal entry not found")
    updates = body.model_dump(exclude_unset=True)
    for field, value in updates.items():
        setattr(entry, field, value)

    fill = entry.actual_fill_price
    exit_p = entry.exit_price
    if entry.pnl is None and fill is not None and exit_p is not None:
        entry.pnl = calc_option_pnl(
            fill, exit_p, entry.instrument, entry.planned_size or 1
        )
        if entry.status not in ("rejected", "closed"):
            entry.status = "closed"

    entry.updated_at = datetime.now(timezone.utc)
    session.commit()
    session.refresh(entry)
    return _to_out(entry)


@router.get("/{entry_id}", response_model=JournalOut)
def get_journal(entry_id: int, session: Session = Depends(get_sync_session)) -> JournalOut:
    entry = session.get(JournalEntry, entry_id)
    if not entry:
        raise HTTPException(404, "Journal entry not found")
    return _to_out(entry)
