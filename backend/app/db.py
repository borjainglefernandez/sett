"""Engine / session factory. Initialized once from Settings; tests bypass this
module entirely by overriding the `get_session` dependency."""

from __future__ import annotations

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from .config import Settings

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def _enable_sqlite_fks(engine: AsyncEngine) -> None:
    @event.listens_for(engine.sync_engine, "connect")
    def _on_connect(dbapi_conn, _record):  # noqa: ANN001
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


def make_engine(settings: Settings) -> AsyncEngine:
    engine = create_async_engine(settings.database_url, future=True)
    if engine.dialect.name == "sqlite":
        _enable_sqlite_fks(engine)
    return engine


def init_db(settings: Settings) -> None:
    global _engine, _session_factory
    if _engine is None:
        _engine = make_engine(settings)
        _session_factory = async_sessionmaker(_engine, expire_on_commit=False)


def get_engine() -> AsyncEngine:
    assert _engine is not None, "init_db() has not been called"
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    assert _session_factory is not None, "init_db() has not been called"
    return _session_factory
