"""Oura: connect URL, OAuth callback (fake transport), PAT flow, status,
disconnect, and the sleep pull -> sync pipe."""

from __future__ import annotations

import json
import uuid
from datetime import date, timedelta
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

from app.config import get_settings
from app.models import OuraConnection, SleepDaily
from app.security import create_state_token, decrypt_token, encrypt_token
from app.services.oura import OuraError, pull_sleep
from app.util import utcnow

TOKEN_RESPONSE = {
    "access_token": "oura-access-1",
    "refresh_token": "oura-refresh-1",
    "expires_in": 86400,
    "scope": "daily heartrate personal",
}


def oura_api_handler(request: httpx.Request) -> httpx.Response:
    """Fake Oura API used across tests: token exchange + the three v2 endpoints."""
    path = request.url.path
    if path == "/oauth/token":
        form = parse_qs(request.content.decode())
        if form.get("grant_type") == ["authorization_code"] and form.get("code") == ["good-code"]:
            return httpx.Response(200, json=TOKEN_RESPONSE)
        return httpx.Response(400, json={"error": "invalid_grant"})
    if path == "/v2/usercollection/personal_info":
        auth = request.headers.get("Authorization", "")
        return httpx.Response(200 if auth == "Bearer valid-pat" else 401, json={})
    day = date.today().isoformat()
    if path == "/v2/usercollection/daily_sleep":
        return httpx.Response(200, json={"data": [{"day": day, "score": 85}]})
    if path == "/v2/usercollection/sleep":
        return httpx.Response(
            200,
            json={
                "data": [
                    {
                        "day": day,
                        "total_sleep_duration": 27000,
                        "deep_sleep_duration": 6000,
                        "rem_sleep_duration": 5400,
                        "light_sleep_duration": 15600,
                        "efficiency": 92,
                        "average_hrv": 46.5,
                        "lowest_heart_rate": 47,
                        "bedtime_start": "2026-07-06T23:30:00+02:00",
                        "bedtime_end": "2026-07-07T07:00:00+02:00",
                    }
                ]
            },
        )
    if path == "/v2/usercollection/daily_readiness":
        return httpx.Response(200, json={"data": [{"day": day, "score": 78}]})
    return httpx.Response(404)


async def test_connect_returns_authorize_url_with_state(client, signup):
    creds = await signup("connector")
    response = await client.get("/v1/oura/connect", headers=creds["headers"])
    assert response.status_code == 200
    url = urlparse(response.json()["authorize_url"])
    assert url.hostname == "cloud.ouraring.com"
    query = parse_qs(url.query)
    assert query["response_type"] == ["code"]
    assert query["state"][0]  # short-lived JWT binding the user


async def test_oauth_callback_stores_encrypted_tokens_and_redirects(
    client, signup, oura_fake, db_session
):
    creds = await signup("oauthy")
    oura_fake.handler = oura_api_handler
    settings = get_settings()
    state = create_state_token(settings, uuid.UUID(creds["user_id"]), purpose="oura_oauth")

    response = await client.get(f"/v1/oura/callback?code=good-code&state={state}")
    assert response.status_code == 302
    assert response.headers["location"] == settings.oura_deeplink

    conn = await db_session.get(OuraConnection, uuid.UUID(creds["user_id"]))
    assert conn is not None and conn.kind == "oauth" and conn.status == "active"
    # Tokens are Fernet-encrypted at rest, not plaintext.
    assert conn.access_token_enc != b"oura-access-1"
    assert decrypt_token(settings, conn.access_token_enc) == "oura-access-1"
    assert decrypt_token(settings, conn.refresh_token_enc) == "oura-refresh-1"
    assert conn.token_expires_at is not None

    status = await client.get("/v1/oura/status", headers=creds["headers"])
    assert status.json() == {
        "connected": True,
        "kind": "oauth",
        "last_pull_at": None,
        "status": "active",
    }


async def test_oauth_callback_with_bad_state_is_401(client, oura_fake):
    oura_fake.handler = oura_api_handler
    response = await client.get("/v1/oura/callback?code=good-code&state=forged")
    assert response.status_code == 401


async def test_oauth_callback_failed_exchange_is_502(client, signup, oura_fake):
    creds = await signup("badcode")
    oura_fake.handler = oura_api_handler
    state = create_state_token(get_settings(), uuid.UUID(creds["user_id"]), purpose="oura_oauth")
    response = await client.get(f"/v1/oura/callback?code=bad-code&state={state}")
    assert response.status_code == 502


async def test_pat_flow_validates_then_stores(client, signup, oura_fake, db_session):
    creds = await signup("patty")
    oura_fake.handler = oura_api_handler

    bad = await client.post("/v1/oura/pat", headers=creds["headers"], json={"token": "wrong-pat"})
    assert bad.status_code == 400

    good = await client.post("/v1/oura/pat", headers=creds["headers"], json={"token": "valid-pat"})
    assert good.status_code == 200
    assert good.json() == {"connected": True, "kind": "pat"}

    conn = await db_session.get(OuraConnection, uuid.UUID(creds["user_id"]))
    assert conn.kind == "pat" and conn.refresh_token_enc is None
    assert decrypt_token(get_settings(), conn.access_token_enc) == "valid-pat"


async def test_disconnect_deletes_connection_but_keeps_sleep_history(
    client, signup, oura_fake, db_session
):
    creds = await signup("quitter")
    user_id = uuid.UUID(creds["user_id"])
    oura_fake.handler = oura_api_handler
    await client.post("/v1/oura/pat", headers=creds["headers"], json={"token": "valid-pat"})
    db_session.add(
        SleepDaily(user_id=user_id, day=date.today(), sleep_score=70, updated_at=utcnow(), sync_seq=0)
    )
    await db_session.commit()

    response = await client.delete("/v1/oura", headers=creds["headers"])
    assert response.status_code == 204

    status = await client.get("/v1/oura/status", headers=creds["headers"])
    assert status.json()["connected"] is False
    db_session.expire_all()
    assert await db_session.get(SleepDaily, (user_id, date.today())) is not None


async def test_status_disconnected_by_default(client, signup):
    creds = await signup("lonely")
    response = await client.get("/v1/oura/status", headers=creds["headers"])
    assert response.json() == {"connected": False, "kind": None, "last_pull_at": None, "status": None}


async def test_pull_sleep_upserts_and_flows_through_sync(
    client, signup, oura_fake, oura_client, db_session
):
    creds = await signup("dreamer")
    user_id = uuid.UUID(creds["user_id"])
    oura_fake.handler = oura_api_handler
    settings = get_settings()
    conn = OuraConnection(
        user_id=user_id, kind="pat", access_token_enc=encrypt_token(settings, "valid-pat")
    )
    db_session.add(conn)
    await db_session.flush()

    upserted = await pull_sleep(db_session, settings, oura_client, conn)
    assert upserted == 1
    # Re-pull is a safe idempotent upsert, not a duplicate insert.
    assert await pull_sleep(db_session, settings, oura_client, conn) == 1
    assert conn.status == "active" and conn.last_pull_at is not None
    await db_session.commit()

    pull = await client.get("/v1/sync/pull", headers=creds["headers"])
    rows = pull.json()["changes"]["sleep_daily"]
    assert len(rows) == 1
    row = rows[0]
    assert row["sleep_score"] == 85
    assert row["readiness_score"] == 78
    assert row["total_sleep_sec"] == 27000
    assert row["avg_hrv_ms"] == 46.5
    # Bedtimes normalized to UTC.
    assert row["bedtime_start"] == "2026-07-06T21:30:00+00:00"


async def test_pull_sleep_api_error_marks_connection_errored(signup, oura_fake, oura_client, db_session):
    creds = await signup("ringless")
    settings = get_settings()
    oura_fake.handler = lambda request: httpx.Response(401, json={"detail": "revoked"})
    conn = OuraConnection(
        user_id=uuid.UUID(creds["user_id"]),
        kind="pat",
        access_token_enc=encrypt_token(settings, "valid-pat"),
    )
    db_session.add(conn)
    await db_session.flush()

    with pytest.raises(OuraError):
        await pull_sleep(db_session, settings, oura_client, conn)
    assert conn.status == "error"
    assert conn.last_error


async def test_oura_endpoints_require_auth(client):
    assert (await client.get("/v1/oura/connect")).status_code == 401
    assert (await client.post("/v1/oura/pat", json={"token": "x"})).status_code == 401
    assert (await client.get("/v1/oura/status")).status_code == 401
