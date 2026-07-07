"""AI digest pipeline: compact context assembly + Claude call + persistence.

The model client is injected behind the `DigestModel` protocol so tests run
with a fake returning canned markdown and fixed token counts.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Protocol

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import Settings
from ..models import AIDigest, BadgeEvent, Goal, Sett, SleepDaily, User, Workout, WorkoutExercise, Exercise
from ..seq import next_seq
from ..util import utcnow

SYSTEM_PROMPT = """You are sett's training analyst — a terse, Saiyan-flavored strength coach.
You receive compact JSON rollups of a lifter's recent training, goals, badges and sleep.
Respond in markdown with EXACTLY these four sections, in this order:

## Sleep × Performance
Correlate previous-night sleep/readiness with training output. If no sleep data, say so in one line.

## Plateau Watch
Flag exercises with <= 0 net progress over 3+ weeks. Name them. If none, say training is advancing.

## Deload Advice
Only recommend a deload if a plateau coincides with declining readiness or HRV; otherwise one line: no deload needed.

## Goal Check
Progress against each active goal, one line each.

Rules: terse, concrete numbers, no medical claims, no fluff, never invent data not in the input."""


@dataclass
class DigestResult:
    text: str
    input_tokens: int
    output_tokens: int
    model: str


class DigestModel(Protocol):
    async def complete(self, system: str, prompt: str, max_tokens: int = 1500) -> DigestResult: ...


class AnthropicDigestModel:
    """Production implementation over the official anthropic SDK."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client = None

    def _get_client(self):
        if self._client is None:
            import anthropic

            self._client = anthropic.AsyncAnthropic(api_key=self._settings.anthropic_api_key)
        return self._client

    async def complete(self, system: str, prompt: str, max_tokens: int = 1500) -> DigestResult:
        client = self._get_client()
        message = await client.messages.create(
            model=self._settings.digest_model,
            max_tokens=max_tokens,
            # Weekly runs call back-to-back per user: cache the system prompt once.
            system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": prompt}],
        )
        text = "".join(block.text for block in message.content if block.type == "text")
        return DigestResult(
            text=text,
            input_tokens=message.usage.input_tokens,
            output_tokens=message.usage.output_tokens,
            model=self._settings.digest_model,
        )


def compute_cost_usd(settings: Settings, input_tokens: int, output_tokens: int) -> float:
    cost = (
        input_tokens * settings.digest_input_usd_per_mtok
        + output_tokens * settings.digest_output_usd_per_mtok
    ) / 1_000_000
    return round(cost, 5)


async def build_context(session: AsyncSession, user: User, period_start: date, period_end: date) -> str:
    """Compact JSON context (target <= ~6K tokens): weekly per-exercise rollups,
    goal progress inputs, sleep weekly averages + per-workout pairing table,
    recent badges. Never raw sets."""
    rollup_start = period_end - timedelta(weeks=8)

    rows = (
        await session.execute(
            select(
                Exercise.name,
                Workout.started_at,
                Sett.weight_g,
                Sett.reps,
            )
            .join(WorkoutExercise, WorkoutExercise.id == Sett.workout_exercise_id)
            .join(Workout, Workout.id == WorkoutExercise.workout_id)
            .join(Exercise, Exercise.id == WorkoutExercise.exercise_id)
            .where(
                Workout.user_id == user.id,
                Workout.deleted_at.is_(None),
                WorkoutExercise.deleted_at.is_(None),
                Sett.deleted_at.is_(None),
                Workout.started_at >= rollup_start,
            )
        )
    ).all()

    weekly: dict[tuple[str, str], dict] = {}
    for name, started_at, weight_g, reps in rows:
        week = started_at.date() - timedelta(days=started_at.date().weekday())
        key = (name, week.isoformat())
        agg = weekly.setdefault(key, {"sets": 0, "reps": 0, "top_weight_g": 0, "volume_g": 0})
        agg["sets"] += 1
        agg["reps"] += reps or 0
        agg["top_weight_g"] = max(agg["top_weight_g"], weight_g or 0)
        agg["volume_g"] += (weight_g or 0) * (reps or 0)

    exercise_rollups: dict[str, list[dict]] = {}
    for (name, week), agg in sorted(weekly.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        exercise_rollups.setdefault(name, []).append({"week": week, **agg})
    for series in exercise_rollups.values():
        prev = None
        for entry in series:
            entry["volume_delta_g"] = entry["volume_g"] - prev if prev is not None else 0
            prev = entry["volume_g"]

    workouts = (
        (
            await session.execute(
                select(Workout)
                .where(
                    Workout.user_id == user.id,
                    Workout.deleted_at.is_(None),
                    Workout.started_at >= rollup_start,
                )
                .order_by(Workout.started_at)
            )
        )
        .scalars()
        .all()
    )

    sleep_rows = (
        (
            await session.execute(
                select(SleepDaily).where(
                    SleepDaily.user_id == user.id,
                    SleepDaily.deleted_at.is_(None),
                    SleepDaily.day >= rollup_start,
                )
            )
        )
        .scalars()
        .all()
    )
    sleep_by_day = {row.day: row for row in sleep_rows}

    pairing = []
    for workout in workouts:
        night = sleep_by_day.get(workout.started_at.date())
        pairing.append(
            {
                "workout_date": workout.started_at.date().isoformat(),
                "prev_night_sleep_score": night.sleep_score if night else None,
                "prev_night_hrv_ms": night.avg_hrv_ms if night else None,
                "prev_night_readiness": night.readiness_score if night else None,
            }
        )

    goals = (
        (
            await session.execute(
                select(Goal).where(Goal.user_id == user.id, Goal.deleted_at.is_(None))
            )
        )
        .scalars()
        .all()
    )

    badges = (
        (
            await session.execute(
                select(BadgeEvent)
                .where(
                    BadgeEvent.user_id == user.id,
                    BadgeEvent.deleted_at.is_(None),
                    BadgeEvent.earned_at >= rollup_start,
                )
                .order_by(BadgeEvent.earned_at.desc())
                .limit(10)
            )
        )
        .scalars()
        .all()
    )

    context = {
        "period": {"start": period_start.isoformat(), "end": period_end.isoformat()},
        "unit_pref": user.unit_pref,
        "weekly_exercise_rollups": exercise_rollups,
        "workouts_per_week": _workouts_per_week(workouts),
        "sleep_workout_pairing": pairing,
        "goals": [
            {
                "kind": g.kind,
                "target_value": g.target_value,
                "period": g.period,
                "starts_on": g.starts_on.isoformat(),
            }
            for g in goals
        ],
        "recent_badges": [{"kind": b.badge_kind, "tier": b.tier} for b in badges],
    }
    return json.dumps(context, separators=(",", ":"))


def _workouts_per_week(workouts) -> dict[str, int]:
    counts: dict[str, int] = {}
    for workout in workouts:
        week = workout.started_at.date() - timedelta(days=workout.started_at.date().weekday())
        counts[week.isoformat()] = counts.get(week.isoformat(), 0) + 1
    return counts


async def generate_digest(
    session: AsyncSession,
    settings: Settings,
    model: DigestModel,
    user: User,
    kind: str,
    focus: str | None = None,
) -> AIDigest:
    """Assemble context, call the model, persist an ai_digests row (sync_seq
    assigned so devices pick it up on next pull). Caller commits."""
    period_end = utcnow().date()
    period_start = period_end - timedelta(weeks=4)
    context = await build_context(session, user, period_start, period_end)
    prompt = f"Training data:\n{context}"
    if focus:
        prompt += f"\n\nThe lifter asked to focus on: {focus}"

    result = await model.complete(SYSTEM_PROMPT, prompt)
    digest = AIDigest(
        id=uuid.uuid4(),
        user_id=user.id,
        kind=kind,
        period_start=period_start,
        period_end=period_end,
        content_md=result.text,
        model=result.model,
        input_tokens=result.input_tokens,
        output_tokens=result.output_tokens,
        cost_usd=compute_cost_usd(settings, result.input_tokens, result.output_tokens),
        created_at=utcnow(),
        updated_at=utcnow(),
        deleted_at=None,
        sync_seq=await next_seq(session),
    )
    session.add(digest)
    await session.flush()
    return digest


async def on_demand_count_last_24h(session: AsyncSession, user_id: uuid.UUID):
    """Returns (count, oldest_created_at) for on-demand digests in the last 24h."""
    since = utcnow() - timedelta(hours=24)
    rows = (
        (
            await session.execute(
                select(AIDigest.created_at).where(
                    AIDigest.user_id == user_id,
                    AIDigest.kind == "on_demand",
                    AIDigest.created_at > since,
                )
            )
        )
        .scalars()
        .all()
    )
    return len(rows), (min(rows) if rows else None)


async def month_spend_usd(session: AsyncSession, user_id: uuid.UUID) -> float:
    month_start = utcnow().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    total = (
        await session.execute(
            select(func.coalesce(func.sum(AIDigest.cost_usd), 0.0)).where(
                AIDigest.user_id == user_id,
                AIDigest.created_at >= month_start,
            )
        )
    ).scalar_one()
    return float(total)


async def run_weekly_digests(session: AsyncSession, settings: Settings, model: DigestModel) -> int:
    """Weekly job body: digest every user with >= 2 workouts in the trailing 4
    weeks. Returns number of digests written. Caller commits."""
    window_start = utcnow() - timedelta(weeks=4)
    user_ids = (
        (
            await session.execute(
                select(Workout.user_id)
                .where(Workout.deleted_at.is_(None), Workout.started_at >= window_start)
                .group_by(Workout.user_id)
                .having(func.count(Workout.id) >= 2)
            )
        )
        .scalars()
        .all()
    )
    written = 0
    for user_id in user_ids:
        user = await session.get(User, user_id)
        if user is None:
            continue
        await generate_digest(session, settings, model, user, kind="weekly")
        written += 1
    return written
