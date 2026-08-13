import asyncio
import logging
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import (
    backtest,
    candles,
    crypto,
    gaps,
    health,
    iv,
    journal,
    live_candles,
    market,
    monitoring,
    settings as settings_routes,
    setups,
    signals,
    signals_ws,
)
from app.config import get_settings
from app.core.logging import setup_logging
from app.data.backfill import run_startup_backfill
from app.data.instrument_master import initialize_futures_registry
from app.data.websocket_feed import live_feed_service
from app.db.base import Base
from app.db.migrate import migrate_schema
from app.db.session import async_engine, sync_engine
from app.execution import router as execution_router
from app.scheduler import start_scheduler, stop_scheduler
from app.signals.registry import load_latest_from_db

logger = logging.getLogger(__name__)


def _startup_data_layer() -> None:
    settings = get_settings()
    try:
        futures_status = initialize_futures_registry()
        logger.info("Futures registry initialized: %s", futures_status)
    except Exception:
        logger.exception("Futures registry initialization failed")

    session_factory = __import__("app.db.session", fromlist=["SyncSessionLocal"]).SyncSessionLocal
    session = session_factory()
    try:
        load_latest_from_db(session)
    finally:
        session.close()

    if settings.smartapi_configured:
        try:
            results = run_startup_backfill(days=settings.backfill_days)
            filled = sum(1 for r in results if r.get("action") == "backfilled")
            logger.info("Startup gap backfill: %d ranges filled", filled)
        except Exception:
            logger.exception("Startup gap backfill failed")
        if settings.enable_live_feed:
            live_feed_service.start()


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_logging()
    settings = get_settings()
    logger.info("Starting SignalApp backend (%s) v0.9.0", settings.app_env)

    migrate_schema()
    Base.metadata.create_all(bind=sync_engine)

    startup_thread = threading.Thread(target=_startup_data_layer, name="data-startup", daemon=True)
    startup_thread.start()

    loop = asyncio.get_running_loop()
    live_candles.broadcaster.start(loop)
    signals_ws.signal_broadcaster.start(loop)
    start_scheduler()

    yield

    stop_scheduler()
    live_feed_service.stop()
    await live_candles.broadcaster.stop()
    await async_engine.dispose()
    logger.info("Shutdown complete")


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="SignalApp API",
        description="Options signal & backtest backend",
        version="0.9.0",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(health.router)
    app.include_router(monitoring.router)
    app.include_router(candles.router)
    app.include_router(gaps.router)
    app.include_router(live_candles.router)
    app.include_router(signals.router)
    app.include_router(signals_ws.router)
    app.include_router(setups.router)
    app.include_router(backtest.router)
    app.include_router(iv.router)
    app.include_router(journal.router)
    app.include_router(market.router)
    app.include_router(settings_routes.router)
    app.include_router(crypto.router)
    app.include_router(execution_router)
    return app


app = create_app()
