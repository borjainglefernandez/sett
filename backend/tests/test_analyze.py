"""On-demand digests: happy path, 3/day rate limit (429 + Retry-After),
monthly spend circuit breaker, sync pull delivery, and /v1/digests reads."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from app.config import get_settings
from app.models import AIDigest
from app.seq import next_seq
from app.util import utcnow

from conftest import CANNED_DIGEST


async def test_analyze_returns_digest_and_records_cost(client, signup, digest_model, db_session):
    creds = await signup("analyzed")
    response = await client.post(
        "/v1/analyze", headers=creds["headers"], json={"focus": "squat plateau"}
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["kind"] == "on_demand"
    assert body["content_md"] == CANNED_DIGEST
    for section in ("## Sleep × Performance", "## Plateau Watch", "## Deload Advice", "## Goal Check"):
        assert section in body["content_md"]
    assert body["model"] == "fake-haiku"
    # The user's focus string reaches the model prompt.
    assert "squat plateau" in digest_model.calls[-1]

    digest = await db_session.get(AIDigest, uuid.UUID(body["id"]))
    # fake model: 5000 in @ $1/M + 1000 out @ $5/M = $0.01
    assert digest.cost_usd == 0.01
    assert digest.input_tokens == 5000 and digest.output_tokens == 1000
    assert digest.sync_seq > 0


async def test_analyze_rate_limit_is_3_per_day_with_retry_after(client, signup):
    creds = await signup("greedy")
    settings = get_settings()
    for _ in range(settings.analyze_daily_limit):
        ok = await client.post("/v1/analyze", headers=creds["headers"], json={})
        assert ok.status_code == 200

    limited = await client.post("/v1/analyze", headers=creds["headers"], json={})
    assert limited.status_code == 429
    assert limited.json()["detail"] == "rate_limited"
    retry_after = int(limited.headers["Retry-After"])
    assert 0 < retry_after <= 24 * 3600 + 1


async def test_analyze_rate_limit_window_rolls(client, signup, db_session):
    """Digests older than 24h do not count against the limit."""
    creds = await signup("patient")
    settings = get_settings()
    user_id = uuid.UUID(creds["user_id"])
    old = utcnow() - timedelta(hours=25)
    for _ in range(settings.analyze_daily_limit):
        db_session.add(
            AIDigest(
                user_id=user_id,
                kind="on_demand",
                period_start=date.today() - timedelta(weeks=4),
                period_end=date.today(),
                content_md="old",
                model="fake",
                cost_usd=0.01,
                created_at=old,
                updated_at=old,
                sync_seq=await next_seq(db_session),
            )
        )
    await db_session.commit()

    response = await client.post("/v1/analyze", headers=creds["headers"], json={})
    assert response.status_code == 200


async def test_monthly_spend_circuit_breaker(client, signup, db_session):
    creds = await signup("spender")
    user_id = uuid.UUID(creds["user_id"])
    # A weekly digest doesn't hit the 24h on-demand counter but does count as spend.
    db_session.add(
        AIDigest(
            user_id=user_id,
            kind="weekly",
            period_start=date.today() - timedelta(weeks=4),
            period_end=date.today(),
            content_md="pricey",
            model="fake",
            cost_usd=get_settings().monthly_budget_usd,
            created_at=utcnow(),
            updated_at=utcnow(),
            sync_seq=await next_seq(db_session),
        )
    )
    await db_session.commit()

    response = await client.post("/v1/analyze", headers=creds["headers"], json={})
    assert response.status_code == 429
    assert response.json()["detail"] == "budget_exhausted"
    assert int(response.headers["Retry-After"]) > 0


async def test_circuit_breaker_is_per_user(client, signup, db_session):
    """One user maxing their budget must not disable analysis for others."""
    broke = await signup("broke")
    db_session.add(
        AIDigest(
            user_id=uuid.UUID(broke["user_id"]),
            kind="weekly",
            period_start=date.today() - timedelta(weeks=4),
            period_end=date.today(),
            content_md="pricey",
            model="fake",
            cost_usd=99.0,
            created_at=utcnow(),
            updated_at=utcnow(),
            sync_seq=await next_seq(db_session),
        )
    )
    await db_session.commit()
    solvent = await signup("solvent")

    assert (await client.post("/v1/analyze", headers=broke["headers"], json={})).status_code == 429
    assert (await client.post("/v1/analyze", headers=solvent["headers"], json={})).status_code == 200


async def test_digest_flows_through_sync_pull_and_digest_list(client, signup):
    creds = await signup("reader")
    created = await client.post("/v1/analyze", headers=creds["headers"], json={})
    digest_id = created.json()["id"]

    pull = await client.get("/v1/sync/pull", headers=creds["headers"])
    digests = pull.json()["changes"]["ai_digests"]
    assert [d["id"] for d in digests] == [digest_id]
    assert digests[0]["content_md"] == CANNED_DIGEST

    listed = await client.get("/v1/digests?limit=5", headers=creds["headers"])
    assert [d["id"] for d in listed.json()["digests"]] == [digest_id]


async def test_analyze_requires_auth(client):
    assert (await client.post("/v1/analyze", json={})).status_code == 401
    assert (await client.get("/v1/digests")).status_code == 401
