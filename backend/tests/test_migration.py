"""The initial Alembic migration must build the full schema and seed the
frozen exercise catalog — the prod counterpart of AUTO_CREATE_SCHEMA."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from alembic import command
from alembic.config import Config

from app.models import Base

BACKEND_DIR = Path(__file__).resolve().parents[1]


def test_initial_migration_creates_schema_and_seed(tmp_path):
    db_path = tmp_path / "migrated.db"
    config = Config(str(BACKEND_DIR / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    config.set_main_option("sqlalchemy.url", f"sqlite+aiosqlite:///{db_path}")

    command.upgrade(config, "head")

    conn = sqlite3.connect(db_path)
    try:
        tables = {
            row[0]
            for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        # Every model table exists (identical metadata by construction).
        assert set(Base.metadata.tables) <= tables

        catalog_rows = conn.execute(
            "SELECT COUNT(*) FROM exercises WHERE user_id IS NULL"
        ).fetchone()[0]
        assert catalog_rows == 81
        # Counter primed past the catalog's sequence numbers.
        assert conn.execute("SELECT value FROM sync_counter WHERE id=1").fetchone()[0] == 81
        assert conn.execute("SELECT version_num FROM alembic_version").fetchone()[0] == "0001_initial"
    finally:
        conn.close()
