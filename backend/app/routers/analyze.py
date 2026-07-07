"""On-demand AI digests + digest reads.

Guardrails per the design doc: 3 on-demand digests per user per rolling 24h
(429 + Retry-After) and a per-user monthly spend circuit breaker — once
SUM(cost_usd) reaches the monthly budget, on-demand analysis is disabled
until the month ends.
"""

from __future__ import annotations

import calendar
from datetime import timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select

from ..deps import AuthDep, SessionDep, SettingsDep, get_digest_model
from ..models import AIDigest
from ..services.digests import DigestModel, generate_digest, month_spend_usd, on_demand_count_last_24h
from ..util import iso, utcnow

router = APIRouter(prefix="/v1", tags=["digests"])

DigestModelDep = Annotated[DigestModel, Depends(get_digest_model)]


class AnalyzeBody(BaseModel):
    focus: str | None = None


def _digest_payload(digest: AIDigest) -> dict[str, Any]:
    return {
        "id": str(digest.id),
        "kind": digest.kind,
        "period_start": digest.period_start.isoformat(),
        "period_end": digest.period_end.isoformat(),
        "content_md": digest.content_md,
        "model": digest.model,
        "created_at": iso(digest.created_at),
    }


def _seconds_until_month_end() -> int:
    now = utcnow()
    last_day = calendar.monthrange(now.year, now.month)[1]
    month_end = now.replace(day=last_day, hour=23, minute=59, second=59, microsecond=0)
    return max(1, int((month_end - now).total_seconds()) + 1)


@router.post("/analyze")
async def analyze(
    body: AnalyzeBody,
    auth: AuthDep,
    session: SessionDep,
    settings: SettingsDep,
    model: DigestModelDep,
) -> dict[str, Any]:
    count, oldest = await on_demand_count_last_24h(session, auth.user.id)
    if count >= settings.analyze_daily_limit:
        retry_at = (oldest or utcnow()) + timedelta(hours=24)
        retry_sec = max(1, int((retry_at - utcnow()).total_seconds()) + 1)
        raise HTTPException(
            status_code=429,
            detail="rate_limited",
            headers={"Retry-After": str(retry_sec)},
        )
    if await month_spend_usd(session, auth.user.id) >= settings.monthly_budget_usd:
        raise HTTPException(
            status_code=429,
            detail="budget_exhausted",
            headers={"Retry-After": str(_seconds_until_month_end())},
        )

    digest = await generate_digest(session, settings, model, auth.user, kind="on_demand", focus=body.focus)
    await session.commit()
    return _digest_payload(digest)


@router.get("/digests")
async def list_digests(
    auth: AuthDep, session: SessionDep, limit: int = Query(10, ge=1, le=50)
) -> dict[str, Any]:
    digests = (
        (
            await session.execute(
                select(AIDigest)
                .where(AIDigest.user_id == auth.user.id, AIDigest.deleted_at.is_(None))
                .order_by(AIDigest.created_at.desc())
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    return {"digests": [_digest_payload(d) for d in digests]}
