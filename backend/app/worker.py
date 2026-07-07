"""Scheduled worker (`python -m app.worker`): APScheduler in-process cron.

Jobs:
- Daily Oura sleep pull at 09:30 UTC + retry sweep at 15:30 UTC (7-day
  trailing window; upsert makes late ring syncs self-healing).
- Weekly AI digest, Monday 06:00 Europe/Madrid.
- Nightly Postgres backup at 03:15 UTC: pg_dump | gzip -> S3 via boto3.
  Guarded by env — runs only when BACKUP_S3_BUCKET is set and DATABASE_URL
  is Postgres.

Each job optionally pings a healthchecks.io URL (HC_PING_OURA /
HC_PING_DIGEST / HC_PING_BACKUP) as a dead-man's switch.
"""

from __future__ import annotations

import asyncio
import gzip
import logging
import os
import subprocess
from datetime import datetime, timezone

import httpx
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from . import db
from .config import Settings, get_settings
from .models import OuraConnection, User
from .services.digests import AnthropicDigestModel, run_weekly_digests
from .services.oura import pull_sleep

log = logging.getLogger("sett.worker")


async def _ping(env_key: str) -> None:
    url = os.environ.get(env_key)
    if not url:
        return
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            await client.get(url)
    except httpx.HTTPError:  # dead-man ping must never break the job
        log.warning("healthcheck ping failed for %s", env_key)


async def pull_oura_all(settings: Settings) -> int:
    """Pull the trailing sleep window for every active Oura connection."""
    pulled = 0
    async with db.get_session_factory()() as session:
        connections = (
            (await session.execute(select(OuraConnection).where(OuraConnection.status != "revoked")))
            .scalars()
            .all()
        )
        async with httpx.AsyncClient(timeout=30) as client:
            for conn in connections:
                try:
                    pulled += await pull_sleep(session, settings, client, conn)
                except Exception:
                    log.exception("oura pull failed for user %s", conn.user_id)
                await session.commit()
    await _ping("HC_PING_OURA")
    return pulled


async def weekly_digest_job(settings: Settings) -> int:
    model = AnthropicDigestModel(settings)
    async with db.get_session_factory()() as session:
        written = await run_weekly_digests(session, settings, model)
        await session.commit()
    await _ping("HC_PING_DIGEST")
    log.info("weekly digests written: %d", written)
    return written


def _pg_dump_gzip(database_url: str) -> bytes:
    """Run pg_dump against the sync DSN and gzip the output."""
    dsn = database_url.replace("+asyncpg", "")
    dump = subprocess.run(
        ["pg_dump", "--no-owner", "--dbname", dsn],
        check=True,
        capture_output=True,
    )
    return gzip.compress(dump.stdout)


async def nightly_backup(settings: Settings) -> str | None:
    if not settings.backup_s3_bucket:
        log.info("backup skipped: BACKUP_S3_BUCKET not set")
        return None
    if not settings.database_url.startswith("postgresql"):
        log.info("backup skipped: DATABASE_URL is not Postgres")
        return None

    def _run() -> str:
        import boto3  # optional dependency: pip install '.[backup]'

        blob = _pg_dump_gzip(settings.database_url)
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        key = f"{settings.backup_s3_prefix}/sett-{stamp}.sql.gz"
        boto3.client("s3").put_object(Bucket=settings.backup_s3_bucket, Key=key, Body=blob)
        return key

    key = await asyncio.to_thread(_run)
    await _ping("HC_PING_BACKUP")
    log.info("backup uploaded: s3://%s/%s", settings.backup_s3_bucket, key)
    return key


def build_scheduler(settings: Settings) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone="UTC")
    scheduler.add_job(
        pull_oura_all, CronTrigger(hour=9, minute=30, timezone="UTC"), args=[settings], id="oura_am"
    )
    scheduler.add_job(
        pull_oura_all, CronTrigger(hour=15, minute=30, timezone="UTC"), args=[settings], id="oura_pm"
    )
    scheduler.add_job(
        weekly_digest_job,
        CronTrigger(day_of_week="mon", hour=6, minute=0, timezone="Europe/Madrid"),
        args=[settings],
        id="weekly_digest",
    )
    scheduler.add_job(
        nightly_backup, CronTrigger(hour=3, minute=15, timezone="UTC"), args=[settings], id="backup"
    )
    return scheduler


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    settings = get_settings()
    db.init_db(settings)
    scheduler = build_scheduler(settings)
    scheduler.start()
    log.info("worker started; jobs: %s", [job.id for job in scheduler.get_jobs()])
    await asyncio.Event().wait()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
