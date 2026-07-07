"""FastAPI app factory.

Production runs `uvicorn app.main:app`; the lifespan initializes the engine
and — when AUTO_CREATE_SCHEMA is enabled (dev/SQLite convenience; prod uses
Alembic) — creates tables, the sync counter, and the exercise seed catalog.

Tests build the app via `create_app()` and override the dependencies in
`app.deps` (session, Apple verifier, Oura HTTP, digest model); httpx's
ASGITransport does not run the lifespan, so tests own their schema setup.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from . import db
from .config import Settings, get_settings
from .models import Base
from .routers import analyze, auth, friends, gyms, meta, oura, sync
from .seeding import seed_exercises
from .seq import ensure_counter


async def create_schema_and_seed() -> None:
    engine = db.get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with db.get_session_factory()() as session:
        await ensure_counter(session)
        await seed_exercises(session)
        await session.commit()


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        db.init_db(settings)
        if settings.auto_create_schema:
            await create_schema_and_seed()
        yield

    application = FastAPI(title="sett API", version=settings.api_version, lifespan=lifespan)
    application.include_router(meta.router)
    application.include_router(auth.router)
    application.include_router(sync.router)
    application.include_router(oura.router)
    application.include_router(analyze.router)
    application.include_router(friends.router)
    application.include_router(gyms.router)
    return application


app = create_app()
