"""SQLAlchemy models.

Conventions:
- Client-generated UUID primary keys on all syncable tables.
- Weights are ALWAYS integer grams (`weight_g`, `target_weight_g`, `bodyweight_g`).
- Datetimes are stored naive UTC (portable across SQLite tests and Postgres prod).
- Every syncable table carries updated_at / deleted_at / sync_seq. `sync_seq` comes
  from ONE global monotonic counter (`sync_counter` row) assigned in the service
  layer (`app.seq.allocate_seq`) so the exact same code path works on SQLite and
  Postgres — no engine-specific triggers required.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    LargeBinary,
    SmallInteger,
    String,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from .util import utcnow

JSONVariant = JSON().with_variant(JSONB(), "postgresql")


class Base(DeclarativeBase):
    pass


class SyncMixin:
    """Columns shared by every syncable table."""

    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime)
    sync_seq: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0, index=True)


class SyncCounter(Base):
    """Single-row global monotonic counter backing sync_seq on all engines."""

    __tablename__ = "sync_counter"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    value: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)


# ============ identity ============


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    apple_sub: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    email: Mapped[str | None] = mapped_column(String)
    display_name: Mapped[str | None] = mapped_column(String)
    unit_pref: Mapped[str] = mapped_column(String, nullable=False, default="lb")
    is_admin: Mapped[bool] = mapped_column(nullable=False, default=False)
    # Intentionally no FK constraint (avoids users<->invites create cycle).
    invite_code: Mapped[str | None] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)


class Invite(Base):
    __tablename__ = "invites"

    code: Mapped[str] = mapped_column(String, primary_key=True)
    # Plain columns, no FK: invites are admin bookkeeping and must survive
    # account deletion without cascade gymnastics.
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    note: Mapped[str | None] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    redeemed_by: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    redeemed_at: Mapped[datetime | None] = mapped_column(DateTime)


class Device(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    name: Mapped[str | None] = mapped_column(String)
    refresh_token_hash: Mapped[str | None] = mapped_column(String)
    refresh_expires_at: Mapped[datetime | None] = mapped_column(DateTime)
    last_pull_seq: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)


# ============ sync data (client-pushed) ============


class Exercise(SyncMixin, Base):
    __tablename__ = "exercises"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    # NULL user_id = global seed catalog (67 rows, fixed UUIDs shared with the app bundle).
    user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    category: Mapped[str] = mapped_column(String, nullable=False)
    equipment: Mapped[str] = mapped_column(String, nullable=False)


class Routine(SyncMixin, Base):
    __tablename__ = "routines"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    days_of_week: Mapped[list[Any]] = mapped_column(JSONVariant, nullable=False, default=list)
    notes: Mapped[str | None] = mapped_column(String)


class RoutineExercise(SyncMixin, Base):
    __tablename__ = "routine_exercises"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    routine_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("routines.id"), nullable=False, index=True)
    exercise_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("exercises.id"), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    target_sets: Mapped[int | None] = mapped_column(Integer)
    target_reps: Mapped[int | None] = mapped_column(Integer)
    target_weight_g: Mapped[int | None] = mapped_column(Integer)


class Workout(SyncMixin, Base):
    __tablename__ = "workouts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    routine_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("routines.id"))
    title: Mapped[str] = mapped_column(String, nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime)
    active_sec: Mapped[int | None] = mapped_column(Integer)
    bodyweight_g: Mapped[int | None] = mapped_column(Integer)
    rating: Mapped[float | None] = mapped_column(Float)
    notes: Mapped[str | None] = mapped_column(String)


class WorkoutExercise(SyncMixin, Base):
    __tablename__ = "workout_exercises"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    workout_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("workouts.id"), nullable=False, index=True)
    exercise_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("exercises.id"), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(String)


class Sett(SyncMixin, Base):
    __tablename__ = "setts"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    workout_exercise_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("workout_exercises.id"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    weight_g: Mapped[int | None] = mapped_column(Integer)
    reps: Mapped[int | None] = mapped_column(Integer)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime)
    notes: Mapped[str | None] = mapped_column(String)


class PlannedSet(SyncMixin, Base):
    __tablename__ = "planned_sets"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False, index=True)
    routine_exercise_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("routine_exercises.id"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    target_weight_g: Mapped[int | None] = mapped_column(Integer)
    target_reps: Mapped[int | None] = mapped_column(Integer)


class Goal(SyncMixin, Base):
    __tablename__ = "goals"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String, nullable=False)
    exercise_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("exercises.id"))
    target_value: Mapped[float] = mapped_column(Float, nullable=False)
    period: Mapped[str | None] = mapped_column(String)
    starts_on: Mapped[date] = mapped_column(Date, nullable=False)
    ends_on: Mapped[date | None] = mapped_column(Date)


class BadgeEvent(SyncMixin, Base):
    __tablename__ = "badge_events"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    badge_kind: Mapped[str] = mapped_column(String, nullable=False)
    tier: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=1)
    earned_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    source_workout_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("workouts.id"))
    payload: Mapped[dict[str, Any]] = mapped_column(JSONVariant, nullable=False, default=dict)


# ============ server-owned (pulled via sync, never pushed) ============


class OuraConnection(Base):
    __tablename__ = "oura_connections"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), primary_key=True)
    kind: Mapped[str] = mapped_column(String, nullable=False)  # 'oauth' | 'pat'
    access_token_enc: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    refresh_token_enc: Mapped[bytes | None] = mapped_column(LargeBinary)
    token_expires_at: Mapped[datetime | None] = mapped_column(DateTime)
    scopes: Mapped[str | None] = mapped_column(String)
    status: Mapped[str] = mapped_column(String, nullable=False, default="active")
    last_pull_at: Mapped[datetime | None] = mapped_column(DateTime)
    last_error: Mapped[str | None] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)


class SleepDaily(SyncMixin, Base):
    __tablename__ = "sleep_daily"

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), primary_key=True)
    day: Mapped[date] = mapped_column(Date, primary_key=True)
    sleep_score: Mapped[int | None] = mapped_column(SmallInteger)
    readiness_score: Mapped[int | None] = mapped_column(SmallInteger)
    total_sleep_sec: Mapped[int | None] = mapped_column(Integer)
    deep_sec: Mapped[int | None] = mapped_column(Integer)
    rem_sec: Mapped[int | None] = mapped_column(Integer)
    light_sec: Mapped[int | None] = mapped_column(Integer)
    efficiency: Mapped[int | None] = mapped_column(SmallInteger)
    avg_hrv_ms: Mapped[float | None] = mapped_column(Float)
    lowest_hr: Mapped[int | None] = mapped_column(SmallInteger)
    bedtime_start: Mapped[datetime | None] = mapped_column(DateTime)
    bedtime_end: Mapped[datetime | None] = mapped_column(DateTime)
    raw: Mapped[dict[str, Any] | None] = mapped_column(JSONVariant)


class AIDigest(SyncMixin, Base):
    __tablename__ = "ai_digests"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String, nullable=False)  # 'weekly' | 'on_demand'
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    content_md: Mapped[str] = mapped_column(String, nullable=False)
    model: Mapped[str] = mapped_column(String, nullable=False)
    input_tokens: Mapped[int | None] = mapped_column(Integer)
    output_tokens: Mapped[int | None] = mapped_column(Integer)
    cost_usd: Mapped[float | None] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)


# ============ social ============


class Friendship(Base):
    __tablename__ = "friendships"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    friend_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("users.id"), index=True)
    code: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime)


class Gym(Base):
    __tablename__ = "gyms"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)


class GymLog(Base):
    """A 'chamber log': one training visit to a gym."""

    __tablename__ = "gym_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    gym_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("gyms.id"), nullable=False, index=True)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id"), nullable=False, index=True)
    workout_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    logged_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)
    note: Mapped[str | None] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utcnow)
