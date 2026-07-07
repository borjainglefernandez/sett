"""Oura API v2 integration: OAuth exchange, PAT validation, daily sleep pull.

All HTTP goes through an injected httpx-compatible client so tests never touch
the network. Tokens are Fernet-encrypted at rest (OURA_TOKEN_KEY)."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from urllib.parse import urlencode

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import Settings
from ..models import OuraConnection, SleepDaily
from ..security import decrypt_token, encrypt_token
from ..seq import next_seq
from ..util import to_naive_utc, utcnow


class OuraError(Exception):
    pass


def build_authorize_url(settings: Settings, state: str) -> str:
    query = urlencode(
        {
            "client_id": settings.oura_client_id,
            "redirect_uri": settings.oura_redirect_uri,
            "response_type": "code",
            "scope": "daily heartrate personal",
            "state": state,
        }
    )
    return f"{settings.oura_authorize_url}?{query}"


async def exchange_code(client: httpx.AsyncClient, settings: Settings, code: str) -> dict:
    response = await client.post(
        settings.oura_token_url,
        data={
            "grant_type": "authorization_code",
            "code": code,
            "client_id": settings.oura_client_id,
            "client_secret": settings.oura_client_secret,
            "redirect_uri": settings.oura_redirect_uri,
        },
    )
    if response.status_code != 200:
        raise OuraError(f"token exchange failed: {response.status_code}")
    return response.json()


async def refresh_access_token(client: httpx.AsyncClient, settings: Settings, refresh_token: str) -> dict:
    response = await client.post(
        settings.oura_token_url,
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": settings.oura_client_id,
            "client_secret": settings.oura_client_secret,
        },
    )
    if response.status_code != 200:
        raise OuraError(f"token refresh failed: {response.status_code}")
    return response.json()


async def validate_pat(client: httpx.AsyncClient, settings: Settings, token: str) -> bool:
    response = await client.get(
        f"{settings.oura_api_base}/v2/usercollection/personal_info",
        headers={"Authorization": f"Bearer {token}"},
    )
    return response.status_code == 200


def store_connection(
    session: AsyncSession,
    settings: Settings,
    existing: OuraConnection | None,
    user_id: uuid.UUID,
    kind: str,
    access_token: str,
    refresh_token: str | None,
    expires_in_sec: int | None,
    scopes: str | None,
) -> OuraConnection:
    expires_at = utcnow() + timedelta(seconds=expires_in_sec) if expires_in_sec else None
    if existing is None:
        existing = OuraConnection(
            user_id=user_id,
            kind=kind,
            access_token_enc=encrypt_token(settings, access_token),
        )
        session.add(existing)
    existing.kind = kind
    existing.access_token_enc = encrypt_token(settings, access_token)
    existing.refresh_token_enc = encrypt_token(settings, refresh_token) if refresh_token else None
    existing.token_expires_at = expires_at
    existing.scopes = scopes
    existing.status = "active"
    existing.last_error = None
    return existing


async def ensure_fresh_token(
    session: AsyncSession, settings: Settings, client: httpx.AsyncClient, conn: OuraConnection
) -> str:
    """Return a usable access token, proactively refreshing OAuth tokens that
    expire within the hour. Single-use refresh tokens are replaced atomically."""
    access_token = decrypt_token(settings, conn.access_token_enc)
    if conn.kind != "oauth" or conn.refresh_token_enc is None:
        return access_token
    if conn.token_expires_at is None or conn.token_expires_at > utcnow() + timedelta(hours=1):
        return access_token
    tokens = await refresh_access_token(client, settings, decrypt_token(settings, conn.refresh_token_enc))
    store_connection(
        session,
        settings,
        conn,
        conn.user_id,
        kind="oauth",
        access_token=tokens["access_token"],
        refresh_token=tokens.get("refresh_token"),
        expires_in_sec=tokens.get("expires_in"),
        scopes=conn.scopes,
    )
    return tokens["access_token"]


async def _get_json(client: httpx.AsyncClient, settings: Settings, path: str, token: str, params: dict):
    response = await client.get(
        f"{settings.oura_api_base}{path}",
        headers={"Authorization": f"Bearer {token}"},
        params=params,
    )
    if response.status_code != 200:
        raise OuraError(f"GET {path} -> {response.status_code}")
    return response.json()


async def pull_sleep(
    session: AsyncSession,
    settings: Settings,
    client: httpx.AsyncClient,
    conn: OuraConnection,
    days: int = 7,
) -> int:
    """Fetch a trailing window of daily_sleep / sleep / daily_readiness and
    upsert into sleep_daily. Idempotent — re-fetch is safe. Caller commits."""
    token = await ensure_fresh_token(session, settings, client, conn)
    end = utcnow().date()
    start = end - timedelta(days=days)
    params = {"start_date": start.isoformat(), "end_date": end.isoformat()}

    try:
        daily_sleep = await _get_json(client, settings, "/v2/usercollection/daily_sleep", token, params)
        sleep_periods = await _get_json(client, settings, "/v2/usercollection/sleep", token, params)
        readiness = await _get_json(client, settings, "/v2/usercollection/daily_readiness", token, params)
    except OuraError as exc:
        conn.status = "error"
        conn.last_error = str(exc)
        raise

    by_day: dict[date, dict] = {}

    for item in daily_sleep.get("data", []):
        day = date.fromisoformat(item["day"])
        by_day.setdefault(day, {})["sleep_score"] = item.get("score")
        by_day[day].setdefault("raw", {})["daily_sleep"] = item

    for item in sleep_periods.get("data", []):
        day = date.fromisoformat(item["day"])
        entry = by_day.setdefault(day, {})
        # Keep the longest sleep period per day.
        if item.get("total_sleep_duration", 0) >= entry.get("total_sleep_sec", -1):
            entry.update(
                total_sleep_sec=item.get("total_sleep_duration"),
                deep_sec=item.get("deep_sleep_duration"),
                rem_sec=item.get("rem_sleep_duration"),
                light_sec=item.get("light_sleep_duration"),
                efficiency=item.get("efficiency"),
                avg_hrv_ms=item.get("average_hrv"),
                lowest_hr=item.get("lowest_heart_rate"),
                bedtime_start=_parse_dt(item.get("bedtime_start")),
                bedtime_end=_parse_dt(item.get("bedtime_end")),
            )
            entry.setdefault("raw", {})["sleep"] = item

    for item in readiness.get("data", []):
        day = date.fromisoformat(item["day"])
        by_day.setdefault(day, {})["readiness_score"] = item.get("score")
        by_day[day].setdefault("raw", {})["daily_readiness"] = item

    upserted = 0
    for day, fields in sorted(by_day.items()):
        row = await session.get(SleepDaily, (conn.user_id, day))
        if row is None:
            row = SleepDaily(user_id=conn.user_id, day=day, updated_at=utcnow())
            session.add(row)
        for key, value in fields.items():
            setattr(row, key, value)
        row.updated_at = utcnow()
        row.deleted_at = None
        row.sync_seq = await next_seq(session)
        upserted += 1

    conn.status = "active"
    conn.last_pull_at = utcnow()
    conn.last_error = None
    await session.flush()
    return upserted


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    return to_naive_utc(datetime.fromisoformat(value))
