"""Small shared helpers: UTC-naive datetime discipline and JSON-safe encoding.

All datetimes are stored in the database as *naive UTC* (works identically on
SQLite and Postgres `timestamp`). Anything crossing the API boundary is
converted with `to_naive_utc` on the way in and `iso` (ISO-8601 with +00:00
offset) on the way out.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timezone
from typing import Any


def utcnow() -> datetime:
    """Current time as naive UTC."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def to_naive_utc(dt: datetime | None) -> datetime | None:
    """Normalize any datetime (aware or naive) to naive UTC."""
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def iso(dt: datetime | None) -> str | None:
    """Naive-UTC datetime -> ISO-8601 string with explicit UTC offset."""
    if dt is None:
        return None
    return dt.replace(tzinfo=timezone.utc).isoformat()


def encode_value(value: Any) -> Any:
    """JSON-safe encoding for sync payload values."""
    if isinstance(value, datetime):
        return iso(value)
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, uuid.UUID):
        return str(value)
    return value
