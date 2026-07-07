"""Auth flow: invite gating, atomic redemption, refresh rotation + reuse
detection, account deletion."""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import select

from app.models import Invite, User
from app.util import utcnow


async def _apple_body(fake_apple, name: str, **extra) -> dict:
    suffix = uuid.uuid4().hex[:6]
    token = f"token-{name}-{suffix}"
    fake_apple.register(token, f"apple-{name}-{suffix}", email=f"{name}@example.com")
    body = {"identity_token": token, "device_id": str(uuid.uuid4()), "display_name": name}
    body.update(extra)
    return body


async def test_signup_without_invite_is_403(client, fake_apple):
    response = await client.post("/v1/auth/apple", json=await _apple_body(fake_apple, "noinvite"))
    assert response.status_code == 403
    assert response.json()["detail"] == "invite_required"


async def test_signup_with_invalid_invite_is_403(client, fake_apple):
    body = await _apple_body(fake_apple, "badcode", invite_code="SAIYAN-NOPE00")
    response = await client.post("/v1/auth/apple", json=body)
    assert response.status_code == 403


async def test_signup_with_expired_invite_is_403(client, fake_apple, make_invite):
    code = await make_invite(expires_in=timedelta(days=-1))
    body = await _apple_body(fake_apple, "late", invite_code=code)
    response = await client.post("/v1/auth/apple", json=body)
    assert response.status_code == 403
    assert response.json()["detail"] == "invite_required"


async def test_signup_success_burns_invite(client, fake_apple, make_invite, db_session):
    code = await make_invite(note="for Marcos")
    body = await _apple_body(fake_apple, "marcos", invite_code=code)
    response = await client.post("/v1/auth/apple", json=body)
    assert response.status_code == 200
    payload = response.json()
    assert payload["access_token"] and payload["refresh_token"]
    assert payload["user"]["display_name"] == "marcos"
    assert payload["user"]["email"] == "marcos@example.com"

    invite = await db_session.get(Invite, code)
    assert str(invite.redeemed_by) == payload["user"]["id"]
    assert invite.redeemed_at is not None


async def test_invalid_apple_token_is_401(client):
    response = await client.post(
        "/v1/auth/apple",
        json={"identity_token": "forged", "device_id": str(uuid.uuid4())},
    )
    assert response.status_code == 401


async def test_double_redeem_is_403_and_creates_no_user(client, fake_apple, make_invite, db_session):
    code = await make_invite()
    first = await client.post(
        "/v1/auth/apple", json=await _apple_body(fake_apple, "winner", invite_code=code)
    )
    assert first.status_code == 200

    body = await _apple_body(fake_apple, "loser", invite_code=code)
    second = await client.post("/v1/auth/apple", json=body)
    assert second.status_code == 403
    assert second.json()["detail"] == "invite_required"

    users = (await db_session.execute(select(User))).scalars().all()
    assert all(u.display_name != "loser" for u in users)


async def test_existing_user_logs_in_without_invite(client, fake_apple, make_invite):
    code = await make_invite()
    body = await _apple_body(fake_apple, "returning", invite_code=code)
    first = await client.post("/v1/auth/apple", json=body)
    assert first.status_code == 200

    body_again = {k: v for k, v in body.items() if k != "invite_code"}
    second = await client.post("/v1/auth/apple", json=body_again)
    assert second.status_code == 200
    assert second.json()["user"]["id"] == first.json()["user"]["id"]


async def test_refresh_rotates_and_detects_reuse(client, signup):
    creds = await signup("rotator")

    # Rotation: old refresh yields a new pair.
    r1 = await client.post(
        "/v1/auth/refresh",
        json={"device_id": creds["device_id"], "refresh_token": creds["refresh_token"]},
    )
    assert r1.status_code == 200
    rotated = r1.json()
    assert rotated["refresh_token"] != creds["refresh_token"]
    assert rotated["access_token"]

    # Reuse of the rotated (old) token: theft signal, device revoked.
    reuse = await client.post(
        "/v1/auth/refresh",
        json={"device_id": creds["device_id"], "refresh_token": creds["refresh_token"]},
    )
    assert reuse.status_code == 401
    assert reuse.json()["detail"] == "refresh_reuse_detected"

    # Even the latest legitimate token is now rejected — device must re-auth.
    after = await client.post(
        "/v1/auth/refresh",
        json={"device_id": creds["device_id"], "refresh_token": rotated["refresh_token"]},
    )
    assert after.status_code == 401
    assert after.json()["detail"] == "device_revoked"


async def test_refresh_unknown_device_is_401(client):
    response = await client.post(
        "/v1/auth/refresh", json={"device_id": str(uuid.uuid4()), "refresh_token": "whatever"}
    )
    assert response.status_code == 401


async def test_delete_me_removes_account_and_data(client, signup):
    creds = await signup("deleter")
    now = utcnow().isoformat()
    push = await client.post(
        "/v1/sync/push",
        headers=creds["headers"],
        json={
            "changes": {
                "workouts": [
                    {
                        "id": str(uuid.uuid4()),
                        "title": "Last Day",
                        "started_at": now,
                        "updated_at": now,
                    }
                ]
            }
        },
    )
    assert push.status_code == 200

    deleted = await client.delete("/v1/me", headers=creds["headers"])
    assert deleted.status_code == 204

    # Token now points at a nonexistent user.
    after = await client.get("/v1/sync/pull", headers=creds["headers"])
    assert after.status_code == 401
