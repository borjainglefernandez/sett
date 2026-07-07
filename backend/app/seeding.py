"""Exercise catalog seeding.

Reads app/seed/ExerciseSeed.json — a byte-identical copy of
SettCore/Sources/SettCore/Seed/ExerciseSeed.json in the iOS app. The two files
MUST stay identical: the fixed UUIDs are how client and server agree on
exercise identity. If the catalog changes, update both copies together.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import Exercise
from .seq import ensure_counter, next_seq

SEED_PATH = Path(__file__).parent / "seed" / "ExerciseSeed.json"

# Fixed timestamp so seeding is deterministic and idempotent across deploys.
SEED_UPDATED_AT = datetime(2020, 1, 1, 0, 0, 0)


def load_seed_catalog() -> list[dict[str, str]]:
    with SEED_PATH.open() as fh:
        return json.load(fh)


async def seed_exercises(session: AsyncSession) -> int:
    """Insert missing global catalog rows (user_id NULL). Returns rows inserted."""
    await ensure_counter(session)
    existing = set(
        (await session.execute(select(Exercise.id).where(Exercise.user_id.is_(None)))).scalars()
    )
    inserted = 0
    for entry in load_seed_catalog():
        eid = uuid.UUID(entry["id"])
        if eid in existing:
            continue
        session.add(
            Exercise(
                id=eid,
                user_id=None,
                name=entry["name"],
                category=entry["muscle"].capitalize(),
                equipment=entry["equipment"].capitalize(),
                updated_at=SEED_UPDATED_AT,
                deleted_at=None,
                sync_seq=await next_seq(session),
            )
        )
        inserted += 1
    await session.flush()
    return inserted
