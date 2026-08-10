import json
import logging

from sqlalchemy import inspect, text

from app.db.session import sync_engine

logger = logging.getLogger(__name__)


def migrate_schema() -> None:
    """Lightweight schema migration — SQLite compatible."""
    inspector = inspect(sync_engine)
    if not inspector.has_table("candles"):
        return

    columns = {col["name"] for col in inspector.get_columns("candles")}
    dialect = sync_engine.dialect.name

    with sync_engine.begin() as conn:
        if "segment" not in columns:
            logger.info("Adding segment column to candles table")
            conn.execute(
                text("ALTER TABLE candles ADD COLUMN segment VARCHAR(16) NOT NULL DEFAULT 'spot'")
            )

        if dialect == "sqlite":
            indexes = {idx["name"] for idx in inspector.get_indexes("candles")}
            if "uq_candle" not in indexes:
                conn.execute(
                    text(
                        "CREATE UNIQUE INDEX IF NOT EXISTS uq_candle "
                        "ON candles (instrument, exchange, segment, interval, timestamp)"
                    )
                )
        else:
            constraints = {c["name"] for c in inspector.get_unique_constraints("candles")}
            if "uq_candle" in constraints:
                try:
                    conn.execute(text("ALTER TABLE candles DROP CONSTRAINT IF EXISTS uq_candle"))
                except Exception:
                    pass
            conn.execute(
                text(
                    """
                    DO $$
                    BEGIN
                        IF NOT EXISTS (
                            SELECT 1 FROM pg_constraint WHERE conname = 'uq_candle'
                        ) THEN
                            ALTER TABLE candles
                            ADD CONSTRAINT uq_candle
                            UNIQUE (instrument, exchange, segment, interval, timestamp);
                        END IF;
                    END $$;
                    """
                )
            )
