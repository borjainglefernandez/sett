"""Oura connection endpoints. All outbound HTTP goes through the injected
`get_oura_http` client so tests run against a fake transport."""

from __future__ import annotations

from typing import Annotated, Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.responses import RedirectResponse
from pydantic import BaseModel

from ..deps import AuthDep, SessionDep, SettingsDep, get_oura_http
from ..models import OuraConnection
from ..security import TokenError, create_state_token, decode_state_token
from ..services.oura import OuraError, build_authorize_url, exchange_code, store_connection, validate_pat
from ..util import iso

router = APIRouter(prefix="/v1/oura", tags=["oura"])

OuraHttpDep = Annotated[httpx.AsyncClient, Depends(get_oura_http)]

STATE_PURPOSE = "oura_oauth"


class PatBody(BaseModel):
    token: str


@router.get("/connect")
async def connect(auth: AuthDep, settings: SettingsDep) -> dict[str, Any]:
    state = create_state_token(settings, auth.user.id, purpose=STATE_PURPOSE)
    return {"authorize_url": build_authorize_url(settings, state)}


@router.get("/callback")
async def callback(
    code: str, state: str, session: SessionDep, settings: SettingsDep, client: OuraHttpDep
) -> RedirectResponse:
    try:
        user_id = decode_state_token(settings, state, purpose=STATE_PURPOSE)
    except TokenError as exc:
        raise HTTPException(status_code=401, detail="invalid state") from exc
    try:
        tokens = await exchange_code(client, settings, code)
    except OuraError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    existing = await session.get(OuraConnection, user_id)
    store_connection(
        session,
        settings,
        existing,
        user_id,
        kind="oauth",
        access_token=tokens["access_token"],
        refresh_token=tokens.get("refresh_token"),
        expires_in_sec=tokens.get("expires_in"),
        scopes=tokens.get("scope"),
    )
    await session.commit()
    return RedirectResponse(url=settings.oura_deeplink, status_code=302)


@router.post("/pat")
async def set_pat(
    body: PatBody, auth: AuthDep, session: SessionDep, settings: SettingsDep, client: OuraHttpDep
) -> dict[str, Any]:
    if not await validate_pat(client, settings, body.token):
        raise HTTPException(status_code=400, detail="invalid personal access token")
    existing = await session.get(OuraConnection, auth.user.id)
    store_connection(
        session,
        settings,
        existing,
        auth.user.id,
        kind="pat",
        access_token=body.token,
        refresh_token=None,
        expires_in_sec=None,
        scopes=None,
    )
    await session.commit()
    return {"connected": True, "kind": "pat"}


@router.get("/status")
async def status(auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    conn = await session.get(OuraConnection, auth.user.id)
    if conn is None:
        return {"connected": False, "kind": None, "last_pull_at": None, "status": None}
    return {
        "connected": True,
        "kind": conn.kind,
        "last_pull_at": iso(conn.last_pull_at),
        "status": conn.status,
    }


@router.delete("", status_code=204)
async def disconnect(auth: AuthDep, session: SessionDep) -> Response:
    """Disconnect and delete tokens; sleep_daily history is kept."""
    conn = await session.get(OuraConnection, auth.user.id)
    if conn is not None:
        await session.delete(conn)
        await session.commit()
    return Response(status_code=204)
