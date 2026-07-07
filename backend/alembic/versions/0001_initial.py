"""Initial schema + exercise catalog seed.

Revision ID: 0001_initial
Revises: None

The schema is created from `app.models.Base.metadata` so this migration is
guaranteed to match the models by construction (a deliberate solo-dev
tradeoff over hand-written op.create_table calls; future revisions should
use normal Alembic operations). Runs on Postgres and SQLite alike — tests
exercise it against sqlite+aiosqlite.

Seeds:
- sync_counter row (id=1) primed past the catalog sequence numbers.
- The 67-exercise global catalog (user_id NULL) with the FROZEN UUIDs from
  app/seed/ExerciseSeed.json — byte-identical to the iOS app bundle copy.
"""

from __future__ import annotations

import uuid

import sqlalchemy as sa
from alembic import op

from app.models import Base, Exercise, SyncCounter
from app.seeding import SEED_UPDATED_AT, load_seed_catalog

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    Base.metadata.create_all(bind)

    catalog = load_seed_catalog()
    bind.execute(sa.insert(SyncCounter.__table__).values(id=1, value=len(catalog)))
    rows = [
        {
            "id": uuid.UUID(entry["id"]),
            "user_id": None,
            "name": entry["name"],
            "category": entry["muscle"].capitalize(),
            "equipment": entry["equipment"].capitalize(),
            "updated_at": SEED_UPDATED_AT,
            "deleted_at": None,
            "sync_seq": index + 1,
        }
        for index, entry in enumerate(catalog)
    ]
    bind.execute(sa.insert(Exercise.__table__), rows)


def downgrade() -> None:
    Base.metadata.drop_all(op.get_bind())
