"""Unauthenticated health / version endpoints for uptime checks and the
client's "update required" gate."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sqlalchemy import text

from ..deps import SessionDep, SettingsDep

router = APIRouter(prefix="/v1", tags=["meta"])


@router.get("/health")
async def health(session: SessionDep) -> Any:
    try:
        await session.execute(text("SELECT 1"))
    except Exception:
        return JSONResponse(status_code=503, content={"status": "error", "db": "error"})
    return {"status": "ok", "db": "ok"}


@router.get("/version")
async def version(settings: SettingsDep) -> dict[str, Any]:
    return {"api": settings.api_version, "min_client_build": settings.min_client_build}
