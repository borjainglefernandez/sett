"""Shared fixtures: temp-file SQLite database, app with injected fakes
(Apple verifier, Oura HTTP transport, digest model), and signup helpers.

httpx's ASGITransport does not run the FastAPI lifespan, so schema creation,
the sync counter, and the exercise seed happen here — mirroring what
AUTO_CREATE_SCHEMA / the initial Alembic migration do in real deployments.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

import httpx
import pytest
from sqlalchemy import event
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app import deps
from app.config import get_settings
from app.main import create_app
from app.models import Base, Invite
from app.seeding import seed_exercises
from app.seq import ensure_counter
from app.services.apple import AppleVerificationError
from app.services.digests import DigestResult
from app.util import utcnow

CANNED_DIGEST = (
    "## Sleep × Performance\nSolid.\n\n## Plateau Watch\nAdvancing.\n\n"
    "## Deload Advice\nNo deload needed.\n\n## Goal Check\nOn track."
)


class FakeAppleVerifier:
    def __init__(self) -> None:
        self.tokens: dict[str, dict] = {}

    def register(self, identity_token: str, sub: str, email: str | None = None) -> None:
        self.tokens[identity_token] = {"sub": sub, "email": email}

    async def verify(self, identity_token: str, nonce: str | None) -> dict:
        if identity_token not in self.tokens:
            raise AppleVerificationError("unknown identity token")
        return self.tokens[identity_token]


class OuraFake:
    """Mutable holder tests point at per-scenario handlers."""

    def __init__(self) -> None:
        self.handler = lambda request: httpx.Response(404)


class FakeDigestModel:
    def __init__(self) -> None:
        self.calls: list[str] = []

    async def complete(self, system: str, prompt: str, max_tokens: int = 1500) -> DigestResult:
        self.calls.append(prompt)
        return DigestResult(text=CANNED_DIGEST, input_tokens=5000, output_tokens=1000, model="fake-haiku")


@pytest.fixture
async def engine(tmp_path):
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path}/test.db")

    @event.listens_for(engine.sync_engine, "connect")
    def _fk_on(dbapi_conn, _record):  # noqa: ANN001
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def session_factory(engine):
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as session:
        await ensure_counter(session)
        await seed_exercises(session)
        await session.commit()
    return factory


@pytest.fixture
async def db_session(session_factory):
    async with session_factory() as session:
        yield session


@pytest.fixture
def fake_apple():
    return FakeAppleVerifier()


@pytest.fixture
def oura_fake():
    return OuraFake()


@pytest.fixture
async def oura_client(oura_fake):
    transport = httpx.MockTransport(lambda request: oura_fake.handler(request))
    client = httpx.AsyncClient(transport=transport)
    yield client
    await client.aclose()


@pytest.fixture
def digest_model():
    return FakeDigestModel()


@pytest.fixture
def app(session_factory, fake_apple, oura_client, digest_model):
    application = create_app(get_settings())

    async def override_session():
        async with session_factory() as session:
            yield session

    application.dependency_overrides[deps.get_session] = override_session
    application.dependency_overrides[deps.get_apple_verifier] = lambda: fake_apple
    application.dependency_overrides[deps.get_oura_http] = lambda: oura_client
    application.dependency_overrides[deps.get_digest_model] = lambda: digest_model
    return application


@pytest.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as http:
        yield http


@pytest.fixture
def make_invite(session_factory):
    async def _make(expires_in: timedelta = timedelta(days=30), note: str | None = None) -> str:
        code = f"SAIYAN-{uuid.uuid4().hex[:6].upper()}"
        async with session_factory() as session:
            session.add(Invite(code=code, note=note, expires_at=utcnow() + expires_in))
            await session.commit()
        return code

    return _make


@pytest.fixture
def signup(client, fake_apple, make_invite):
    """Full happy-path signup; returns tokens, ids, and auth headers."""

    async def _signup(name: str = "alice") -> dict:
        suffix = uuid.uuid4().hex[:6]
        identity_token = f"token-{name}-{suffix}"
        fake_apple.register(identity_token, f"apple-{name}-{suffix}", email=f"{name}@example.com")
        device_id = str(uuid.uuid4())
        response = await client.post(
            "/v1/auth/apple",
            json={
                "identity_token": identity_token,
                "device_id": device_id,
                "device_name": f"{name}'s iPhone",
                "display_name": name.capitalize(),
                "invite_code": await make_invite(),
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        return {
            "identity_token": identity_token,
            "device_id": device_id,
            "user_id": body["user"]["id"],
            "access_token": body["access_token"],
            "refresh_token": body["refresh_token"],
            "headers": {"Authorization": f"Bearer {body['access_token']}"},
        }

    return _signup
