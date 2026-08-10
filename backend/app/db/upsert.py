from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.db.session import sync_engine


def dialect_insert(model):
    """Return a dialect-appropriate INSERT for upsert helpers."""
    if sync_engine.dialect.name == "postgresql":
        return pg_insert(model)
    return sqlite_insert(model)


def upsert_do_nothing(stmt, constraint: str | None = None, index_elements: list | None = None):
    """Apply on_conflict_do_nothing for SQLite or PostgreSQL."""
    if sync_engine.dialect.name == "sqlite":
        if index_elements:
            return stmt.on_conflict_do_nothing(index_elements=index_elements)
        return stmt.on_conflict_do_nothing()
    return stmt.on_conflict_do_nothing(constraint=constraint)
