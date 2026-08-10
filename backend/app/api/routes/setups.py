from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.signals.registry import all_setups_summary, load_latest_from_db
from app.db.session import get_sync_session

router = APIRouter(prefix="/setups", tags=["setups"])


@router.get("")
def list_setups(session: Session = Depends(get_sync_session)) -> dict:
    load_latest_from_db(session)
    setups = all_setups_summary()
    tradable = [s for s in setups if s["tradable"]]
    return {
        "count": len(setups),
        "tradable_count": len(tradable),
        "setups": setups,
        "message": (
            "No validated setup — no trade."
            if not tradable
            else f"{len(tradable)} tradable setup(s) available"
        ),
    }
