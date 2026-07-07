"""Gyms ('chambers'): community upsert, visit logs, and nearby search with
distance / rating / day-pass aggregation."""

from __future__ import annotations

import uuid

# Madrid city centre; Getafe is ~13 km south, Barcelona ~505 km away.
MADRID = (40.4168, -3.7038)
GETAFE = (40.3083, -3.7327)
BARCELONA = (41.3874, 2.1686)


async def upsert(client, headers, name: str, lat: float, lon: float) -> str:
    gym_id = str(uuid.uuid4())
    response = await client.post(
        "/v1/gyms", headers=headers, json={"id": gym_id, "name": name, "lat": lat, "lon": lon}
    )
    assert response.status_code == 200, response.text
    assert response.json()["created"] is True
    return gym_id


async def test_upsert_gym_create_then_update(client, signup):
    creds = await signup("owner")
    gym_id = str(uuid.uuid4())
    body = {"id": gym_id, "name": "Kame House", "lat": MADRID[0], "lon": MADRID[1]}

    created = await client.post("/v1/gyms", headers=creds["headers"], json=body)
    assert created.status_code == 200
    assert created.json()["created"] is True

    updated = await client.post(
        "/v1/gyms", headers=creds["headers"], json={**body, "name": "Kame House 2"}
    )
    assert updated.json()["created"] is False
    assert updated.json()["name"] == "Kame House 2"


async def test_log_visit_and_unknown_gym_404(client, signup):
    creds = await signup("visitor")
    gym_id = await upsert(client, creds["headers"], "Capsule Gym", *MADRID)

    log = await client.post(
        f"/v1/gyms/{gym_id}/log",
        headers=creds["headers"],
        json={"rating": 4.5, "day_pass_price": 12.0, "note": "good dumbbells"},
    )
    assert log.status_code == 201
    assert log.json()["gym_id"] == gym_id

    missing = await client.post(
        f"/v1/gyms/{uuid.uuid4()}/log", headers=creds["headers"], json={"rating": 3.0}
    )
    assert missing.status_code == 404


async def test_nearby_filters_radius_sorts_and_aggregates(client, signup):
    creds = await signup("traveler")
    headers = creds["headers"]
    madrid_gym = await upsert(client, headers, "Madrid Iron", *MADRID)
    getafe_gym = await upsert(client, headers, "Getafe Grava", *GETAFE)
    await upsert(client, headers, "BCN Muscle", *BARCELONA)  # outside 30 km

    for rating, price in ((4.0, 10.0), (5.0, 20.0), (None, 30.0)):
        response = await client.post(
            f"/v1/gyms/{madrid_gym}/log",
            headers=headers,
            json={"rating": rating, "day_pass_price": price},
        )
        assert response.status_code == 201

    nearby = await client.get(
        f"/v1/gyms/nearby?lat={MADRID[0]}&lon={MADRID[1]}", headers=headers
    )
    assert nearby.status_code == 200
    gyms = nearby.json()["gyms"]
    assert [g["name"] for g in gyms] == ["Madrid Iron", "Getafe Grava"]  # sorted by distance

    madrid = gyms[0]
    assert madrid["id"] == madrid_gym
    assert madrid["distance_km"] < 0.1
    assert madrid["log_count"] == 3
    assert madrid["avg_rating"] == 4.5
    assert madrid["median_day_pass_price"] == 20.0

    getafe = next(g for g in gyms if g["id"] == getafe_gym)
    assert 10 < getafe["distance_km"] < 30
    assert getafe["log_count"] == 0
    assert getafe["avg_rating"] is None and getafe["median_day_pass_price"] is None


async def test_gym_validation(client, signup):
    creds = await signup("fatfinger")
    bad_lat = await client.post(
        "/v1/gyms",
        headers=creds["headers"],
        json={"id": str(uuid.uuid4()), "name": "Nope", "lat": 123.0, "lon": 0.0},
    )
    assert bad_lat.status_code == 422
    gym_id = await upsert(client, creds["headers"], "Fine Gym", *MADRID)
    bad_rating = await client.post(
        f"/v1/gyms/{gym_id}/log", headers=creds["headers"], json={"rating": 6.0}
    )
    assert bad_rating.status_code == 422


async def test_gyms_require_auth(client):
    assert (await client.get("/v1/gyms/nearby?lat=0&lon=0")).status_code == 401
    assert (
        await client.post(
            "/v1/gyms", json={"id": str(uuid.uuid4()), "name": "X", "lat": 0, "lon": 0}
        )
    ).status_code == 401
