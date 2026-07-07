"""Meta endpoints, worker schedule wiring, CLI registration, and the weekly
digest job body."""

from __future__ import annotations

import uuid
from datetime import timedelta

from app.cli import cli
from app.config import get_settings
from app.services.digests import run_weekly_digests
from app.util import utcnow
from app.worker import build_scheduler


async def test_health_and_version_need_no_auth(client):
    health = await client.get("/v1/health")
    assert health.status_code == 200
    assert health.json() == {"status": "ok", "db": "ok"}

    version = await client.get("/v1/version")
    assert version.status_code == 200
    body = version.json()
    assert body["api"] == get_settings().api_version
    assert isinstance(body["min_client_build"], int)


def test_worker_schedules_all_jobs():
    scheduler = build_scheduler(get_settings())
    jobs = {job.id: str(job.trigger) for job in scheduler.get_jobs()}
    assert set(jobs) == {"oura_am", "oura_pm", "weekly_digest", "backup"}
    assert "hour='9'" in jobs["oura_am"] and "minute='30'" in jobs["oura_am"]
    assert "hour='15'" in jobs["oura_pm"]
    assert "day_of_week='mon'" in jobs["weekly_digest"] and "hour='6'" in jobs["weekly_digest"]
    assert "hour='3'" in jobs["backup"] and "minute='15'" in jobs["backup"]


def test_cli_registers_admin_commands():
    names = {command.name for command in cli.registered_commands}
    assert {"create-invite", "run-digest", "pull-oura"} <= names


async def test_weekly_digest_job_targets_active_lifters(client, signup, db_session, digest_model):
    """Only users with >= 2 workouts in the trailing 4 weeks get a weekly digest."""
    active = await signup("active")
    await signup("idle")  # zero workouts: no digest

    for offset_days in (1, 3):
        at = (utcnow() - timedelta(days=offset_days)).isoformat()
        push = await client.post(
            "/v1/sync/push",
            headers=active["headers"],
            json={
                "changes": {
                    "workouts": [
                        {
                            "id": str(uuid.uuid4()),
                            "title": f"Session -{offset_days}d",
                            "started_at": at,
                            "updated_at": at,
                        }
                    ]
                }
            },
        )
        assert push.status_code == 200

    written = await run_weekly_digests(db_session, get_settings(), digest_model)
    await db_session.commit()
    assert written == 1

    pull = await client.get("/v1/sync/pull", headers=active["headers"])
    digests = pull.json()["changes"]["ai_digests"]
    assert len(digests) == 1 and digests[0]["kind"] == "weekly"
