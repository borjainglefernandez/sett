"""Gyms ('chambers'): community upsert, per-visit chamber logs, and nearby
search with haversine distance plus rating / day-pass-price aggregation."""

from __future__ import annotations

import math
import statistics
import uuid
from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select

from ..deps import AuthDep, SessionDep
from ..models import Gym, GymLog
from ..util import iso, to_naive_utc, utcnow

router = APIRouter(prefix="/v1/gyms", tags=["gyms"])

NEARBY_RADIUS_KM = 30.0
EARTH_RADIUS_KM = 6371.0


class GymBody(BaseModel):
    id: uuid.UUID
    name: str = Field(min_length=1)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class GymLogBody(BaseModel):
    workout_id: uuid.UUID | None = None
    logged_at: datetime | None = None
    rating: float | None = Field(default=None, ge=0, le=5)
    day_pass_price: float | None = Field(default=None, ge=0)
    note: str | None = None


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


@router.post("")
async def upsert_gym(body: GymBody, auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    gym = await session.get(Gym, body.id)
    created = gym is None
    if gym is None:
        gym = Gym(id=body.id, name=body.name, lat=body.lat, lon=body.lon, created_by=auth.user.id)
        session.add(gym)
    else:
        # Only the creator may rename/relocate a community gym — otherwise any
        # authenticated user could move or rename anyone's gym.
        if gym.created_by != auth.user.id:
            raise HTTPException(status_code=403, detail="not the gym's creator")
        gym.name = body.name
        gym.lat = body.lat
        gym.lon = body.lon
    gym.updated_at = utcnow()
    await session.commit()
    return {
        "id": str(gym.id),
        "name": gym.name,
        "lat": gym.lat,
        "lon": gym.lon,
        "created": created,
    }


@router.post("/{gym_id}/log", status_code=201)
async def log_visit(gym_id: uuid.UUID, body: GymLogBody, auth: AuthDep, session: SessionDep) -> dict[str, Any]:
    gym = await session.get(Gym, gym_id)
    if gym is None:
        raise HTTPException(status_code=404, detail="unknown gym")
    log = GymLog(
        id=uuid.uuid4(),
        gym_id=gym_id,
        user_id=auth.user.id,
        workout_id=body.workout_id,
        logged_at=to_naive_utc(body.logged_at) or utcnow(),
        rating=body.rating,
        day_pass_price=body.day_pass_price,
        note=body.note,
    )
    session.add(log)
    await session.commit()
    return {"id": str(log.id), "gym_id": str(gym_id), "logged_at": iso(log.logged_at)}


@router.get("/nearby")
async def nearby(
    auth: AuthDep,
    session: SessionDep,
    lat: float = Query(ge=-90, le=90),
    lon: float = Query(ge=-180, le=180),
) -> dict[str, Any]:
    gyms = (await session.execute(select(Gym))).scalars().all()
    within = [
        (gym, haversine_km(lat, lon, gym.lat, gym.lon))
        for gym in gyms
        if haversine_km(lat, lon, gym.lat, gym.lon) <= NEARBY_RADIUS_KM
    ]
    gym_ids = [gym.id for gym, _ in within]
    logs_by_gym: dict[uuid.UUID, list[GymLog]] = {}
    if gym_ids:
        logs = (
            (await session.execute(select(GymLog).where(GymLog.gym_id.in_(gym_ids)))).scalars().all()
        )
        for log in logs:
            logs_by_gym.setdefault(log.gym_id, []).append(log)

    results: list[dict[str, Any]] = []
    for gym, distance in sorted(within, key=lambda pair: pair[1]):
        logs = logs_by_gym.get(gym.id, [])
        ratings = [log.rating for log in logs if log.rating is not None]
        prices = [log.day_pass_price for log in logs if log.day_pass_price is not None]
        results.append(
            {
                "id": str(gym.id),
                "name": gym.name,
                "lat": gym.lat,
                "lon": gym.lon,
                "distance_km": round(distance, 2),
                "log_count": len(logs),
                "avg_rating": round(sum(ratings) / len(ratings), 2) if ratings else None,
                "median_day_pass_price": round(statistics.median(prices), 2) if prices else None,
            }
        )
    return {"gyms": results}
