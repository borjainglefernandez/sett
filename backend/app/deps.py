"""FastAPI dependencies. Every external effect (DB session, Apple JWKS, Oura
HTTP, Anthropic) flows through one of these so tests can override them."""

from __future__ import annotations

import uuid
from typing import Annotated, AsyncIterator

import httpx
from fastapi import Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from . import db
from .config import Settings, get_settings
from .models import Device, User
from .security import TokenError, decode_access_token
from .services.apple import AppleVerifier, RemoteAppleVerifier
from .services.digests import AnthropicDigestModel, DigestModel


def settings_dep() -> Settings:
    return get_settings()


SettingsDep = Annotated[Settings, Depends(settings_dep)]


async def get_session() -> AsyncIterator[AsyncSession]:
    async with db.get_session_factory()() as session:
        yield session


SessionDep = Annotated[AsyncSession, Depends(get_session)]

_apple_verifier: AppleVerifier | None = None
_oura_client: httpx.AsyncClient | None = None
_digest_model: DigestModel | None = None


def get_apple_verifier(settings: SettingsDep) -> AppleVerifier:
    global _apple_verifier
    if _apple_verifier is None:
        _apple_verifier = RemoteAppleVerifier(settings)
    return _apple_verifier


async def get_oura_http() -> httpx.AsyncClient:
    """HTTP client used for Oura token exchange / API calls. Tests override."""
    global _oura_client
    if _oura_client is None:
        _oura_client = httpx.AsyncClient(timeout=15)
    return _oura_client


def get_digest_model(settings: SettingsDep) -> DigestModel:
    global _digest_model
    if _digest_model is None:
        _digest_model = AnthropicDigestModel(settings)
    return _digest_model


class AuthContext:
    def __init__(self, user: User, device_id: uuid.UUID, is_admin: bool) -> None:
        self.user = user
        self.device_id = device_id
        self.is_admin = is_admin


async def get_auth(request: Request, settings: SettingsDep, session: SessionDep) -> AuthContext:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        claims = decode_access_token(settings, header.removeprefix("Bearer "))
        user_id = uuid.UUID(claims["sub"])
        device_id = uuid.UUID(claims["dev"])
    except (TokenError, KeyError, ValueError):
        raise HTTPException(status_code=401, detail="invalid token")
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="unknown user")
    # Revoked / logged-out device: the access token must stop working immediately, not
    # linger up to an hour until it expires. A live session always has a
    # refresh_token_hash (login sets it, logout/revoke clears it or deletes the device).
    device = await session.get(Device, device_id)
    if device is None or device.refresh_token_hash is None or device.user_id != user_id:
        raise HTTPException(status_code=401, detail="device revoked")
    # Admin is authoritative from the DB, never just the token's `adm` claim (which a
    # stale or — absent the secret guard — forged token could carry).
    return AuthContext(user=user, device_id=device_id, is_admin=user.is_admin)


AuthDep = Annotated[AuthContext, Depends(get_auth)]


async def require_admin(auth: AuthDep) -> AuthContext:
    if not auth.is_admin:
        raise HTTPException(status_code=403, detail="admin required")
    return auth
