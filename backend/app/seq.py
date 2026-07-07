"""Global monotonic sync_seq allocation.

One counter row (`sync_counter.id = 1`) is bumped with an atomic
`UPDATE ... RETURNING` — row-locked on Postgres, serialized by the single
writer on SQLite — so the same code path yields a strictly increasing global
sequence on both engines. This replaces the Postgres-only trigger approach in
the design doc (documented deviation; behavior is identical).
"""

from __future__ import annotations

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .models import SyncCounter

COUNTER_ID = 1


async def ensure_counter(session: AsyncSession) -> None:
    existing = await session.get(SyncCounter, COUNTER_ID)
    if existing is None:
        session.add(SyncCounter(id=COUNTER_ID, value=0))
        await session.flush()


async def allocate_seq(session: AsyncSession, count: int = 1) -> list[int]:
    """Atomically reserve `count` consecutive sequence numbers, returning them."""
    result = await session.execute(
        update(SyncCounter)
        .where(SyncCounter.id == COUNTER_ID)
        .values(value=SyncCounter.value + count)
        .returning(SyncCounter.value)
    )
    last = result.scalar_one()
    return list(range(last - count + 1, last + 1))


async def next_seq(session: AsyncSession) -> int:
    return (await allocate_seq(session, 1))[0]


async def current_seq(session: AsyncSession) -> int:
    result = await session.execute(select(SyncCounter.value).where(SyncCounter.id == COUNTER_ID))
    value = result.scalar_one_or_none()
    return value or 0
