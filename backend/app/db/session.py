import logging
from collections.abc import AsyncGenerator, Callable
from pathlib import Path
from threading import Lock

from sqlalchemy import create_engine, event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import Session, sessionmaker

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Ensure parent directory exists for SQLite file
Path(settings.sqlite_path).parent.mkdir(parents=True, exist_ok=True)


def _configure_sqlite(dbapi_conn, _connection_record) -> None:
    """Enable WAL mode for concurrent WebSocket writer + API reader."""
    cursor = dbapi_conn.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.execute("PRAGMA busy_timeout=5000")
    cursor.execute("PRAGMA cache_size=-8000")  # ~8 MB page cache
    cursor.close()


async_engine = create_async_engine(
    settings.database_url,
    echo=False,
    connect_args={"check_same_thread": False},
)
AsyncSessionLocal = async_sessionmaker(async_engine, class_=AsyncSession, expire_on_commit=False)

sync_engine = create_engine(
    settings.database_url_sync,
    echo=False,
    connect_args={"check_same_thread": False},
)
SyncSessionLocal = sessionmaker(sync_engine, class_=Session, expire_on_commit=False)

event.listens_for(sync_engine, "connect")(_configure_sqlite)


@event.listens_for(async_engine.sync_engine, "connect")
def _configure_async_sqlite(dbapi_conn, _connection_record) -> None:
    _configure_sqlite(dbapi_conn, _connection_record)


async def get_async_session() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session


def get_sync_session():
    session = SyncSessionLocal()
    try:
        yield session
    finally:
        session.close()
