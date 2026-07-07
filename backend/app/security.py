"""Session JWTs, refresh tokens, invite codes, Fernet helpers."""

from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import timedelta, timezone

import jwt
from cryptography.fernet import Fernet

from .config import Settings
from .util import utcnow

ALGORITHM = "HS256"
CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


class TokenError(Exception):
    pass


def create_access_token(settings: Settings, user_id: uuid.UUID, device_id: uuid.UUID, is_admin: bool) -> str:
    now = utcnow().replace(tzinfo=timezone.utc)
    payload = {
        "sub": str(user_id),
        "dev": str(device_id),
        "adm": is_admin,
        "iat": now,
        "exp": now + timedelta(seconds=settings.access_ttl_sec),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def decode_access_token(settings: Settings, token: str) -> dict:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError as exc:
        raise TokenError(str(exc)) from exc


def create_state_token(settings: Settings, user_id: uuid.UUID, purpose: str, ttl_sec: int = 600) -> str:
    now = utcnow().replace(tzinfo=timezone.utc)
    payload = {
        "sub": str(user_id),
        "purpose": purpose,
        "iat": now,
        "exp": now + timedelta(seconds=ttl_sec),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def decode_state_token(settings: Settings, token: str, purpose: str) -> uuid.UUID:
    claims = decode_access_token(settings, token)
    if claims.get("purpose") != purpose:
        raise TokenError("wrong token purpose")
    return uuid.UUID(claims["sub"])


def new_refresh_token() -> str:
    """256-bit opaque refresh token, urlsafe."""
    return secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_invite_code() -> str:
    body = "".join(secrets.choice(CROCKFORD) for _ in range(6))
    return f"SAIYAN-{body}"


def new_friend_code() -> str:
    body = "".join(secrets.choice(CROCKFORD) for _ in range(8))
    return f"FUSION-{body}"


def fernet(settings: Settings) -> Fernet:
    return Fernet(settings.oura_token_key.encode())


def encrypt_token(settings: Settings, token: str) -> bytes:
    return fernet(settings).encrypt(token.encode())


def decrypt_token(settings: Settings, blob: bytes) -> str:
    return fernet(settings).decrypt(blob).decode()
