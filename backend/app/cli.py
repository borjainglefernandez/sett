"""Admin CLI (`python -m app.cli`): typer commands run inside the api container.

    docker compose exec sett-api python -m app.cli create-invite --note "for Marcos"
    docker compose exec sett-api python -m app.cli run-digest --user marcos@example.com
    docker compose exec sett-api python -m app.cli pull-oura
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import timedelta
from typing import Any, Coroutine

import typer
from sqlalchemy import select

from . import db
from .config import get_settings
from .models import Invite, User
from .security import new_invite_code
from .services.digests import AnthropicDigestModel, generate_digest
from .util import utcnow

cli = typer.Typer(help="sett backend admin commands", no_args_is_help=True)


def _run(coro: Coroutine[Any, Any, Any]) -> Any:
    return asyncio.run(coro)


async def _find_user(session, needle: str) -> User | None:
    try:
        return await session.get(User, uuid.UUID(needle))
    except ValueError:
        pass
    result = await session.execute(
        select(User).where((User.email == needle) | (User.apple_sub == needle))
    )
    return result.scalar_one_or_none()


@cli.command("create-invite")
def create_invite(
    note: str = typer.Option(None, "--note", help='Who this is for, e.g. "for Marcos"'),
    days: int = typer.Option(30, "--days", help="Days until the code expires"),
) -> None:
    """Mint a one-shot invite code."""

    async def go() -> str:
        settings = get_settings()
        db.init_db(settings)
        async with db.get_session_factory()() as session:
            code = new_invite_code()
            session.add(Invite(code=code, note=note, expires_at=utcnow() + timedelta(days=days)))
            await session.commit()
            return code

    code = _run(go())
    typer.echo(code)


@cli.command("run-digest")
def run_digest(
    user: str = typer.Option(..., "--user", help="User id, email, or apple_sub"),
    focus: str = typer.Option(None, "--focus", help="Optional focus for the digest"),
) -> None:
    """Generate an on-demand digest for one user (bypasses rate limits)."""

    async def go() -> str:
        settings = get_settings()
        db.init_db(settings)
        async with db.get_session_factory()() as session:
            target = await _find_user(session, user)
            if target is None:
                raise typer.BadParameter(f"no user matching {user!r}")
            model = AnthropicDigestModel(settings)
            digest = await generate_digest(session, settings, model, target, kind="on_demand", focus=focus)
            await session.commit()
            return digest.content_md

    typer.echo(_run(go()))


@cli.command("pull-oura")
def pull_oura() -> None:
    """Run the daily Oura sleep pull for all active connections now."""

    async def go() -> int:
        from .worker import pull_oura_all

        settings = get_settings()
        db.init_db(settings)
        return await pull_oura_all(settings)

    typer.echo(f"upserted {_run(go())} sleep_daily rows")


if __name__ == "__main__":
    cli()
