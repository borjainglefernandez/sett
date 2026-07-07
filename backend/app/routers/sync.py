"""Cursor sync: POST /v1/sync/push and GET /v1/sync/pull.

Push applies client changes in FK-safe order inside one transaction with
last-write-wins on the client-set `updated_at` (strictly older incoming rows
are skipped and reported; identical timestamps are idempotent no-ops). Pull
returns per-table changes with `sync_seq > since` across ALL syncable tables —
including tombstones and the server-owned sleep_daily / ai_digests — ordered
by the global sequence, paginated by `limit`.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import Date, DateTime, Uuid, inspect as sa_inspect, or_, select
from sqlalchemy.exc import IntegrityError

from ..deps import AuthDep, SessionDep
from ..models import (
    AIDigest,
    BadgeEvent,
    Device,
    Exercise,
    Goal,
    PlannedSet,
    Routine,
    RoutineExercise,
    Sett,
    SleepDaily,
    Workout,
    WorkoutExercise,
)
from ..seq import current_seq, next_seq
from ..util import encode_value, to_naive_utc, utcnow

router = APIRouter(prefix="/v1/sync", tags=["sync"])

MAX_PUSH_RECORDS = 1000

# FK-safe apply order: parents before children.
PUSH_TABLES: list[tuple[str, type]] = [
    ("exercises", Exercise),
    ("routines", Routine),
    ("routine_exercises", RoutineExercise),
    ("planned_sets", PlannedSet),
    ("workouts", Workout),
    ("workout_exercises", WorkoutExercise),
    ("setts", Sett),
    ("goals", Goal),
    ("badge_events", BadgeEvent),
]

# Everything a client pulls: pushed tables + server-owned rows (same pipe).
PULL_TABLES: list[tuple[str, type]] = PUSH_TABLES + [
    ("sleep_daily", SleepDaily),
    ("ai_digests", AIDigest),
]


class PushBody(BaseModel):
    device_id: uuid.UUID | None = None
    changes: dict[str, list[dict[str, Any]]] = Field(default_factory=dict)


def coerce_record(model: type, payload: dict[str, Any]) -> dict[str, Any]:
    """Convert a JSON record into column-typed values, keyed by mapped attribute.
    Unknown keys are dropped; absent keys stay absent (partial rows allowed)."""
    out: dict[str, Any] = {}
    for column in sa_inspect(model).columns:
        key = column.key
        if key not in payload:
            continue
        value = payload[key]
        if value is None:
            out[key] = None
        elif isinstance(column.type, Uuid):
            out[key] = uuid.UUID(str(value))
        elif isinstance(column.type, Date) and not isinstance(column.type, DateTime):
            out[key] = value if isinstance(value, date) else date.fromisoformat(value)
        elif isinstance(column.type, DateTime):
            parsed = value if isinstance(value, datetime) else datetime.fromisoformat(value)
            out[key] = to_naive_utc(parsed)
        else:
            out[key] = value
    return out


def serialize_row(model: type, obj: Any) -> dict[str, Any]:
    return {c.key: encode_value(getattr(obj, c.key)) for c in sa_inspect(model).columns}


@router.post("/push")
async def push(body: PushBody, auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    total = sum(len(records) for records in body.changes.values())
    if total > MAX_PUSH_RECORDS:
        raise HTTPException(status_code=413, detail=f"batch too large (max {MAX_PUSH_RECORDS} records)")

    applied = 0
    skipped: list[dict[str, Any]] = []

    try:
        applied = await _apply_changes(body, auth, session, skipped)
        await session.flush()
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(status_code=409, detail="constraint violation (push parents first)") from exc
    server_seq = await current_seq(session)
    await session.commit()
    return {"applied": applied, "skipped": skipped, "server_seq": server_seq}


async def _apply_changes(
    body: PushBody, auth: AuthDep, session: SessionDep, skipped: list[dict[str, Any]]
) -> int:
    applied = 0
    for table_name, model in PUSH_TABLES:
        for payload in body.changes.get(table_name, []):
            try:
                data = coerce_record(model, payload)
            except (ValueError, TypeError):
                skipped.append({"table": table_name, "id": payload.get("id"), "reason": "malformed"})
                continue
            record_id = data.get("id")
            if record_id is None or data.get("updated_at") is None:
                skipped.append({"table": table_name, "id": payload.get("id"), "reason": "malformed"})
                continue
            data["user_id"] = auth.user.id
            data.pop("sync_seq", None)

            existing = await session.get(model, record_id)
            if existing is not None:
                if table_name == "exercises" and existing.user_id is None:
                    skipped.append({"table": table_name, "id": str(record_id), "reason": "readonly"})
                    continue
                if existing.user_id != auth.user.id:
                    skipped.append({"table": table_name, "id": str(record_id), "reason": "forbidden"})
                    continue
                if data["updated_at"] < existing.updated_at:
                    skipped.append({"table": table_name, "id": str(record_id), "reason": "stale"})
                    continue
                if data["updated_at"] == existing.updated_at:
                    applied += 1  # idempotent re-push: no-op, no new sync_seq
                    continue
                for key, value in data.items():
                    if key != "id":
                        setattr(existing, key, value)
                existing.sync_seq = await next_seq(session)
            else:
                obj = model(**data)
                obj.sync_seq = await next_seq(session)
                session.add(obj)
            applied += 1

    if body.device_id is not None:
        device = await session.get(Device, body.device_id)
        if device is not None and device.user_id == auth.user.id:
            device.last_seen_at = utcnow()
    return applied


@router.get("/pull")
async def pull(
    auth: AuthDep,
    session: SessionDep,
    since: int = Query(0, ge=0),
    limit: int = Query(500, ge=1, le=1000),
    device_id: uuid.UUID | None = None,
) -> dict[str, Any]:
    collected: list[tuple[int, str, dict[str, Any]]] = []
    for table_name, model in PULL_TABLES:
        owner = model.user_id == auth.user.id
        if model is Exercise:
            owner = or_(owner, Exercise.user_id.is_(None))  # global catalog syncs to everyone
        rows = (
            (
                await session.execute(
                    select(model)
                    .where(owner, model.sync_seq > since)
                    .order_by(model.sync_seq)
                    .limit(limit + 1)
                )
            )
            .scalars()
            .all()
        )
        for row in rows:
            collected.append((row.sync_seq, table_name, serialize_row(model, row)))

    collected.sort(key=lambda item: item[0])
    page = collected[:limit]
    has_more = len(collected) > limit

    changes: dict[str, list[dict[str, Any]]] = {}
    for _seq, table_name, record in page:
        changes.setdefault(table_name, []).append(record)
    next_cursor = page[-1][0] if page else since

    if device_id is not None:
        device = await session.get(Device, device_id)
        if device is not None and device.user_id == auth.user.id:
            device.last_pull_seq = max(device.last_pull_seq, next_cursor)
            device.last_seen_at = utcnow()
            await session.commit()

    return {"changes": changes, "next_cursor": next_cursor, "has_more": has_more}
