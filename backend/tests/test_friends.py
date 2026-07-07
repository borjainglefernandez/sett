"""Friends: code invite/accept lifecycle and the privacy contract — a friend
snapshot NEVER exposes sets, weights, or bodyweight."""

from __future__ import annotations

import json
import uuid
from datetime import date, timedelta

from app.routers.friends import streak_weeks
from app.util import utcnow

SNAPSHOT_FIELDS = {
    "user_id",
    "display_name",
    "badge_count",
    "last_workout_date",
    "workouts_this_week",
    "streak_weeks",
}


async def push_workout(client, creds, started_at, with_weights: bool = True) -> None:
    at = started_at.isoformat()
    ids = {k: str(uuid.uuid4()) for k in ("wo", "wex", "st", "badge")}
    changes = {
        "workouts": [
            {
                "id": ids["wo"],
                "title": "Secret Session",
                "started_at": at,
                "bodyweight_g": 82000,
                "updated_at": at,
            }
        ],
        "badge_events": [
            {
                "id": ids["badge"],
                "badge_kind": "pr",
                "tier": 2,
                "earned_at": at,
                "payload": {"weight_g": 140000},
                "updated_at": at,
            }
        ],
    }
    if with_weights:
        changes["workout_exercises"] = [
            {
                "id": ids["wex"],
                "workout_id": ids["wo"],
                "exercise_id": "10F5CCD9-606A-5B6B-8A4D-38C0EE9D694E",  # seed catalog row
                "position": 0,
                "updated_at": at,
            }
        ]
        changes["setts"] = [
            {
                "id": ids["st"],
                "workout_exercise_id": ids["wex"],
                "position": 0,
                "weight_g": 140000,
                "reps": 5,
                "completed_at": at,
                "updated_at": at,
            }
        ]
    response = await client.post(
        "/v1/sync/push", headers=creds["headers"], json={"changes": changes}
    )
    assert response.status_code == 200 and response.json()["skipped"] == []


async def test_invite_accept_and_list_both_directions(client, signup):
    alice = await signup("alice")
    bob = await signup("bob")

    invite = await client.post("/v1/friends/invite", headers=alice["headers"])
    assert invite.status_code == 200
    code = invite.json()["code"]
    assert code.startswith("FUSION-")

    accept = await client.post("/v1/friends/accept", headers=bob["headers"], json={"code": code})
    assert accept.status_code == 200
    assert accept.json()["friend"]["user_id"] == alice["user_id"]
    assert accept.json()["friend"]["display_name"] == "Alice"

    alices_view = (await client.get("/v1/friends", headers=alice["headers"])).json()["friends"]
    bobs_view = (await client.get("/v1/friends", headers=bob["headers"])).json()["friends"]
    assert [f["user_id"] for f in alices_view] == [bob["user_id"]]
    assert [f["user_id"] for f in bobs_view] == [alice["user_id"]]


async def test_accept_invalid_own_or_used_code(client, signup):
    alice = await signup("alice")
    bob = await signup("bob")
    carol = await signup("carol")

    missing = await client.post(
        "/v1/friends/accept", headers=bob["headers"], json={"code": "FUSION-NOPE0000"}
    )
    assert missing.status_code == 404

    code = (await client.post("/v1/friends/invite", headers=alice["headers"])).json()["code"]
    own = await client.post("/v1/friends/accept", headers=alice["headers"], json={"code": code})
    assert own.status_code == 400

    assert (
        await client.post("/v1/friends/accept", headers=bob["headers"], json={"code": code})
    ).status_code == 200
    # A code is single-use: once accepted it is no longer pending.
    reused = await client.post("/v1/friends/accept", headers=carol["headers"], json={"code": code})
    assert reused.status_code == 404


async def test_snapshot_privacy_no_training_data_leaks(client, signup):
    alice = await signup("alice")
    bob = await signup("bob")
    await push_workout(client, alice, utcnow())

    code = (await client.post("/v1/friends/invite", headers=alice["headers"])).json()["code"]
    await client.post("/v1/friends/accept", headers=bob["headers"], json={"code": code})

    friends = (await client.get("/v1/friends", headers=bob["headers"])).json()["friends"]
    assert len(friends) == 1
    snapshot = friends[0]
    # Exactly the whitelisted fields — nothing else.
    assert set(snapshot.keys()) == SNAPSHOT_FIELDS
    assert snapshot["badge_count"] == 1
    assert snapshot["workouts_this_week"] >= 1
    assert snapshot["last_workout_date"] == utcnow().date().isoformat()
    assert snapshot["streak_weeks"] >= 1
    # Belt and braces: no weight/set/bodyweight values anywhere in the payload.
    dumped = json.dumps(snapshot)
    for forbidden in ("weight", "sett", "reps", "82000", "140000", "Secret Session"):
        assert forbidden not in dumped


async def test_streak_weeks_counts_consecutive_weeks():
    today = date(2026, 7, 8)  # a Wednesday
    monday = today - timedelta(days=today.weekday())

    assert streak_weeks(set(), today) == 0
    # Three consecutive completed weeks (a Wednesday each), nothing this week yet.
    days = {monday - timedelta(weeks=w) + timedelta(days=2) for w in (1, 2, 3)}
    assert streak_weeks(days, today) == 3
    # Training this week extends it.
    assert streak_weeks(days | {today}, today) == 4
    # A gap two weeks back resets the base streak.
    gappy = {monday - timedelta(weeks=1) + timedelta(days=2), monday - timedelta(weeks=3) + timedelta(days=2)}
    assert streak_weeks(gappy, today) == 1


async def test_friends_require_auth(client):
    assert (await client.get("/v1/friends")).status_code == 401
    assert (await client.post("/v1/friends/invite")).status_code == 401
    assert (await client.post("/v1/friends/accept", json={"code": "X"})).status_code == 401
