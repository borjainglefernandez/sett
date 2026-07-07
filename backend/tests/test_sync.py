"""Cursor sync: push/pull round trip, LWW conflict handling, tombstones,
idempotency, pagination, ownership guards, server-owned rows, and the batch cap."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from app.models import AIDigest, SleepDaily
from app.seeding import load_seed_catalog
from app.seq import next_seq
from app.util import utcnow

CATALOG_SIZE = len(load_seed_catalog())
GLOBAL_EXERCISE_ID = load_seed_catalog()[0]["id"]


def full_batch(at: str) -> dict:
    ids = {name: str(uuid.uuid4()) for name in ("ex", "rt", "rex", "wo", "wex", "st", "goal", "badge")}
    changes = {
        "exercises": [
            {
                "id": ids["ex"],
                "name": "Zercher Squat",
                "category": "Legs",
                "equipment": "Barbell",
                "updated_at": at,
            }
        ],
        "routines": [
            {"id": ids["rt"], "name": "Leg Day", "days_of_week": [1, 4], "updated_at": at}
        ],
        "routine_exercises": [
            {
                "id": ids["rex"],
                "routine_id": ids["rt"],
                "exercise_id": ids["ex"],
                "position": 0,
                "target_sets": 3,
                "target_reps": 8,
                "target_weight_g": 80000,
                "updated_at": at,
            }
        ],
        "workouts": [
            {
                "id": ids["wo"],
                "routine_id": ids["rt"],
                "title": "Leg Day",
                "started_at": at,
                "bodyweight_g": 82500,
                "updated_at": at,
            }
        ],
        "workout_exercises": [
            {
                "id": ids["wex"],
                "workout_id": ids["wo"],
                "exercise_id": ids["ex"],
                "position": 0,
                "updated_at": at,
            }
        ],
        "setts": [
            {
                "id": ids["st"],
                "workout_exercise_id": ids["wex"],
                "position": 0,
                "weight_g": 80000,
                "reps": 8,
                "completed_at": at,
                "updated_at": at,
            }
        ],
        "goals": [
            {
                "id": ids["goal"],
                "kind": "workouts_per_week",
                "target_value": 4,
                "period": "week",
                "starts_on": date.today().isoformat(),
                "updated_at": at,
            }
        ],
        "badge_events": [
            {
                "id": ids["badge"],
                "badge_kind": "first_blood",
                "tier": 1,
                "earned_at": at,
                "source_workout_id": ids["wo"],
                "payload": {"note": "first workout"},
                "updated_at": at,
            }
        ],
    }
    return {"ids": ids, "changes": changes}


async def test_push_pull_round_trip(client, signup):
    creds = await signup("syncer")
    at = utcnow().isoformat()
    batch = full_batch(at)

    push = await client.post(
        "/v1/sync/push",
        headers=creds["headers"],
        json={"device_id": creds["device_id"], "changes": batch["changes"]},
    )
    assert push.status_code == 200, push.text
    body = push.json()
    assert body["applied"] == 8
    assert body["skipped"] == []
    assert body["server_seq"] >= CATALOG_SIZE + 8

    pull = await client.get("/v1/sync/pull?since=0&limit=1000", headers=creds["headers"])
    assert pull.status_code == 200
    changes = pull.json()["changes"]
    # Global catalog + the custom exercise.
    assert len(changes["exercises"]) == CATALOG_SIZE + 1
    assert any(e["id"] == batch["ids"]["ex"] for e in changes["exercises"])
    sett = changes["setts"][0]
    assert sett["weight_g"] == 80000 and sett["reps"] == 8
    assert changes["badge_events"][0]["payload"] == {"note": "first workout"}
    assert pull.json()["has_more"] is False
    assert pull.json()["next_cursor"] == body["server_seq"]


async def test_repush_is_idempotent(client, signup):
    creds = await signup("idem")
    at = utcnow().isoformat()
    batch = full_batch(at)

    first = await client.post("/v1/sync/push", headers=creds["headers"], json={"changes": batch["changes"]})
    assert first.status_code == 200
    cursor = first.json()["server_seq"]

    second = await client.post("/v1/sync/push", headers=creds["headers"], json={"changes": batch["changes"]})
    assert second.status_code == 200
    assert second.json()["applied"] == 8
    assert second.json()["skipped"] == []
    assert second.json()["server_seq"] == cursor  # no new sequence numbers burned

    pull = await client.get(f"/v1/sync/pull?since={cursor}", headers=creds["headers"])
    assert pull.json()["changes"] == {}
    assert pull.json()["next_cursor"] == cursor


async def test_lww_stale_update_is_skipped(client, signup):
    creds = await signup("lww")
    t0 = utcnow()
    workout_id = str(uuid.uuid4())

    def workout(title: str, at) -> dict:
        return {
            "changes": {
                "workouts": [
                    {
                        "id": workout_id,
                        "title": title,
                        "started_at": t0.isoformat(),
                        "updated_at": at.isoformat(),
                    }
                ]
            }
        }

    fresh = await client.post("/v1/sync/push", headers=creds["headers"], json=workout("Current", t0))
    assert fresh.json()["applied"] == 1

    stale = await client.post(
        "/v1/sync/push", headers=creds["headers"], json=workout("Old news", t0 - timedelta(minutes=5))
    )
    assert stale.json()["applied"] == 0
    assert stale.json()["skipped"] == [{"table": "workouts", "id": workout_id, "reason": "stale"}]

    newer = await client.post(
        "/v1/sync/push", headers=creds["headers"], json=workout("Rewritten", t0 + timedelta(minutes=5))
    )
    assert newer.json()["applied"] == 1

    pull = await client.get("/v1/sync/pull", headers=creds["headers"])
    titles = [w["title"] for w in pull.json()["changes"]["workouts"]]
    assert titles == ["Rewritten"]


async def test_tombstone_flows_through_pull(client, signup):
    creds = await signup("tomb")
    t0 = utcnow()
    workout_id = str(uuid.uuid4())
    base = {"id": workout_id, "title": "Doomed", "started_at": t0.isoformat()}

    await client.post(
        "/v1/sync/push",
        headers=creds["headers"],
        json={"changes": {"workouts": [{**base, "updated_at": t0.isoformat()}]}},
    )
    first_cursor = (await client.get("/v1/sync/pull", headers=creds["headers"])).json()["next_cursor"]

    t1 = t0 + timedelta(minutes=1)
    await client.post(
        "/v1/sync/push",
        headers=creds["headers"],
        json={
            "changes": {
                "workouts": [{**base, "updated_at": t1.isoformat(), "deleted_at": t1.isoformat()}]
            }
        },
    )

    pull = await client.get(f"/v1/sync/pull?since={first_cursor}", headers=creds["headers"])
    workouts = pull.json()["changes"]["workouts"]
    assert len(workouts) == 1
    assert workouts[0]["id"] == workout_id
    assert workouts[0]["deleted_at"] is not None


async def test_pull_pagination_walks_all_records(client, signup):
    creds = await signup("pager")
    at = utcnow().isoformat()
    goals = [
        {
            "id": str(uuid.uuid4()),
            "kind": "workouts_per_week",
            "target_value": n,
            "starts_on": date.today().isoformat(),
            "updated_at": at,
        }
        for n in range(10)
    ]
    await client.post("/v1/sync/push", headers=creds["headers"], json={"changes": {"goals": goals}})

    seen = 0
    cursor = 0
    pages = 0
    while True:
        pull = await client.get(f"/v1/sync/pull?since={cursor}&limit=20", headers=creds["headers"])
        payload = pull.json()
        page_count = sum(len(rows) for rows in payload["changes"].values())
        assert page_count <= 20
        seen += page_count
        assert payload["next_cursor"] >= cursor
        cursor = payload["next_cursor"]
        pages += 1
        if not payload["has_more"]:
            break
    assert seen == CATALOG_SIZE + 10
    assert pages >= 4


async def test_push_cap_is_413(client, signup):
    creds = await signup("bulk")
    at = utcnow().isoformat()
    goals = [
        {
            "id": str(uuid.uuid4()),
            "kind": "workouts_per_week",
            "target_value": 1,
            "starts_on": date.today().isoformat(),
            "updated_at": at,
        }
        for _ in range(1001)
    ]
    response = await client.post(
        "/v1/sync/push", headers=creds["headers"], json={"changes": {"goals": goals}}
    )
    assert response.status_code == 413


async def test_cannot_touch_other_users_rows_or_global_catalog(client, signup):
    alice = await signup("alice")
    bob = await signup("bob")
    at = utcnow().isoformat()
    workout_id = str(uuid.uuid4())

    await client.post(
        "/v1/sync/push",
        headers=alice["headers"],
        json={
            "changes": {
                "workouts": [{"id": workout_id, "title": "Alice's", "started_at": at, "updated_at": at}]
            }
        },
    )

    later = (utcnow() + timedelta(minutes=1)).isoformat()
    attack = await client.post(
        "/v1/sync/push",
        headers=bob["headers"],
        json={
            "changes": {
                "workouts": [
                    {"id": workout_id, "title": "Bob's now", "started_at": at, "updated_at": later}
                ],
                "exercises": [
                    {
                        "id": GLOBAL_EXERCISE_ID,
                        "name": "Vandalized",
                        "category": "Legs",
                        "equipment": "Barbell",
                        "updated_at": later,
                    }
                ],
            }
        },
    )
    body = attack.json()
    assert body["applied"] == 0
    reasons = {(s["table"], s["reason"]) for s in body["skipped"]}
    assert reasons == {("workouts", "forbidden"), ("exercises", "readonly")}

    pull = await client.get("/v1/sync/pull", headers=alice["headers"])
    assert pull.json()["changes"]["workouts"][0]["title"] == "Alice's"


async def test_server_owned_rows_flow_through_pull(client, signup, db_session):
    creds = await signup("sleepy")
    user_id = uuid.UUID(creds["user_id"])

    db_session.add(
        SleepDaily(
            user_id=user_id,
            day=date.today(),
            sleep_score=88,
            readiness_score=90,
            total_sleep_sec=28000,
            updated_at=utcnow(),
            sync_seq=await next_seq(db_session),
        )
    )
    db_session.add(
        AIDigest(
            user_id=user_id,
            kind="weekly",
            period_start=date.today() - timedelta(weeks=4),
            period_end=date.today(),
            content_md="## Sleep × Performance\nfine",
            model="fake",
            updated_at=utcnow(),
            sync_seq=await next_seq(db_session),
        )
    )
    await db_session.commit()

    pull = await client.get("/v1/sync/pull", headers=creds["headers"])
    changes = pull.json()["changes"]
    assert changes["sleep_daily"][0]["sleep_score"] == 88
    assert changes["ai_digests"][0]["kind"] == "weekly"


async def test_pull_requires_auth(client):
    assert (await client.get("/v1/sync/pull")).status_code == 401
