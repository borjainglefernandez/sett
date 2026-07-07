"""Friends: short-code invites and privacy-filtered snapshots.

A snapshot NEVER contains set, weight, or bodyweight data — only display
name, badge count, last workout date, workouts this week, and streak weeks.
"""

from __future__ import annotations

import uuid
from datetime import date, timedelta
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, or_, select

from ..deps import AuthDep, SessionDep
from ..models import BadgeEvent, Friendship, User, Workout
from ..security import new_friend_code
from ..util import utcnow

router = APIRouter(prefix="/v1/friends", tags=["friends"])


class AcceptBody(BaseModel):
    code: str


def streak_weeks(workout_days: set[date], today: date) -> int:
    """Consecutive ISO weeks with >= 1 workout day; the completed weeks before
    the current week form the base, and the in-progress week extends but never
    breaks the streak."""
    if not workout_days:
        return 0
    weeks = {d - timedelta(days=d.weekday()) for d in workout_days}
    this_week = today - timedelta(days=today.weekday())
    streak = 0
    week = this_week - timedelta(weeks=1)
    while week in weeks:
        streak += 1
        week -= timedelta(weeks=1)
    if this_week in weeks:
        streak += 1
    return streak


async def _snapshot(session: SessionDep, user: User) -> dict[str, Any]:
    badge_count = (
        await session.execute(
            select(func.count(BadgeEvent.id)).where(
                BadgeEvent.user_id == user.id, BadgeEvent.deleted_at.is_(None)
            )
        )
    ).scalar_one()
    started_ats = (
        (
            await session.execute(
                select(Workout.started_at).where(
                    Workout.user_id == user.id, Workout.deleted_at.is_(None)
                )
            )
        )
        .scalars()
        .all()
    )
    today = utcnow().date()
    week_start = today - timedelta(days=today.weekday())
    workout_days = {dt.date() for dt in started_ats}
    return {
        "user_id": str(user.id),
        "display_name": user.display_name,
        "badge_count": int(badge_count),
        "last_workout_date": max(workout_days).isoformat() if workout_days else None,
        "workouts_this_week": sum(1 for dt in started_ats if dt.date() >= week_start),
        "streak_weeks": streak_weeks(workout_days, today),
    }


@router.post("/invite")
async def create_invite(auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    code = new_friend_code()
    session.add(Friendship(id=uuid.uuid4(), user_id=auth.user.id, code=code, status="pending"))
    await session.commit()
    return {"code": code}


@router.post("/accept")
async def accept(body: AcceptBody, auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    friendship = (
        await session.execute(
            select(Friendship).where(Friendship.code == body.code, Friendship.status == "pending")
        )
    ).scalar_one_or_none()
    if friendship is None:
        raise HTTPException(status_code=404, detail="invalid_code")
    if friendship.user_id == auth.user.id:
        raise HTTPException(status_code=400, detail="own_code")
    friendship.friend_id = auth.user.id
    friendship.status = "accepted"
    friendship.accepted_at = utcnow()
    other = await session.get(User, friendship.user_id)
    snapshot = await _snapshot(session, other) if other else None
    await session.commit()
    return {"ok": True, "friend": snapshot}


@router.get("")
async def list_friends(auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    friendships = (
        (
            await session.execute(
                select(Friendship).where(
                    Friendship.status == "accepted",
                    or_(Friendship.user_id == auth.user.id, Friendship.friend_id == auth.user.id),
                )
            )
        )
        .scalars()
        .all()
    )
    snapshots: list[dict[str, Any]] = []
    seen: set[uuid.UUID] = set()
    for friendship in friendships:
        other_id = friendship.friend_id if friendship.user_id == auth.user.id else friendship.user_id
        if other_id is None or other_id in seen:
            continue
        seen.add(other_id)
        other = await session.get(User, other_id)
        if other is not None:
            snapshots.append(await _snapshot(session, other))
    return {"friends": snapshots}
