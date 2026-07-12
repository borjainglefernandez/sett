"""Catalog drift guard: the backend's exercise seed must stay byte-identical
to the copy shipped inside the iOS app bundle — the frozen UUIDs are how
client and server agree on exercise identity."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

import pytest

from app.seeding import SEED_PATH, load_seed_catalog

REPO_ROOT = Path(__file__).resolve().parents[2]
IOS_SEED_PATH = REPO_ROOT / "SettCore" / "Sources" / "SettCore" / "Seed" / "ExerciseSeed.json"


def test_seed_is_byte_identical_to_ios_bundle_copy():
    if not IOS_SEED_PATH.exists():
        pytest.skip("SettCore checkout not present (backend-only context)")
    assert SEED_PATH.read_bytes() == IOS_SEED_PATH.read_bytes(), (
        "app/seed/ExerciseSeed.json has drifted from "
        "SettCore/Sources/SettCore/Seed/ExerciseSeed.json — update both together"
    )


def test_seed_catalog_shape():
    catalog = load_seed_catalog()
    assert len(catalog) == 81
    ids = [entry["id"] for entry in catalog]
    assert len(set(ids)) == len(ids), "duplicate exercise UUIDs in seed"
    for entry in catalog:
        uuid.UUID(entry["id"])  # valid, frozen UUIDs
        assert entry["name"]
        assert entry["muscle"]
        assert entry["equipment"]


async def test_seeding_is_idempotent(db_session):
    from app.seeding import seed_exercises

    # conftest already seeded; a second run must insert nothing.
    assert await seed_exercises(db_session) == 0
