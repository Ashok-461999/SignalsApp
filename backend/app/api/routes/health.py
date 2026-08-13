from datetime import datetime, timezone



from fastapi import APIRouter, Depends

from sqlalchemy import text

from sqlalchemy.ext.asyncio import AsyncSession



from app.config import get_settings

from app.data.instruments import DATA_LAYER_STATUS

from app.data.memory_cache import memory_cache

from app.data.smartapi_client import smartapi_client
from app.data.websocket_feed import live_feed_service
from app.db.session import SyncSessionLocal, get_async_session
from app.services.crypto_store import credentials_status, load_credentials



router = APIRouter(tags=["health"])





@router.get("/health")

async def health(session: AsyncSession = Depends(get_async_session)) -> dict:

    settings = get_settings()

    db_ok = False

    db_message = "unknown"



    try:

        await session.execute(text("SELECT 1"))

        db_ok = True

        db_message = "connected"

    except Exception as exc:

        db_message = str(exc)



    smartapi = smartapi_client.health_check()

    feed = live_feed_service.status

    sync_session = SyncSessionLocal()
    try:
        crypto_creds = load_credentials(sync_session)
        crypto_status = credentials_status(crypto_creds)
    finally:
        sync_session.close()

    status = "ok" if db_ok else "degraded"

    return {

        "status": status,

        "environment": settings.app_env,

        "database": {

            "ok": db_ok,

            "message": db_message,

            "engine": "sqlite",

            "path": settings.sqlite_path,

            "wal_mode": True,

        },

        "memory_cache": memory_cache.stats(),

        "smartapi": smartapi,

        "live_feed": feed,

        "data_layer": DATA_LAYER_STATUS,

        "trading": {

            "paper_trading": settings.paper_trading,

            "live_execution_enabled": settings.live_execution_enabled,

            "kill_switch": settings.kill_switch,

            "execution_allowed": settings.execution_allowed,

            "risk_percent": settings.risk_percent,

            "crypto_paper_trading": settings.crypto_paper_trading,

            "crypto_live_enabled": settings.crypto_live_enabled,

        },

        "crypto": crypto_status,

        "timestamp": datetime.now(timezone.utc).isoformat(),

    }

