"""Sign in with Apple, invite-gated signup, rotating refresh tokens, account deletion.

Invite redemption is a single atomic UPDATE ... RETURNING inside the
user-creation transaction: zero rows means no user is created and the request
fails 403 — one code, one account, no other registration path.

Refresh tokens are opaque, per-device, stored hashed, and rotated on every
use. Presenting a token that does not match the stored hash is treated as a
theft signal: the device is revoked and must re-run Sign in with Apple.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from sqlalchemy import delete, or_, select, update

from ..config import Settings
from ..deps import AuthDep, SessionDep, SettingsDep, get_apple_verifier
from ..models import (
    AIDigest,
    BadgeEvent,
    Device,
    Exercise,
    Friendship,
    Goal,
    GymLog,
    Invite,
    OuraConnection,
    PlannedSet,
    Routine,
    RoutineExercise,
    Sett,
    SleepDaily,
    User,
    Workout,
    WorkoutExercise,
)
from ..security import create_access_token, hash_token, new_refresh_token
from ..services.apple import AppleVerificationError, AppleVerifier
from ..util import iso, utcnow

router = APIRouter(prefix="/v1", tags=["auth"])

VerifierDep = Annotated[AppleVerifier, Depends(get_apple_verifier)]


class AppleAuthBody(BaseModel):
    identity_token: str
    device_id: uuid.UUID
    nonce: str | None = None
    device_name: str | None = None
    invite_code: str | None = None
    # Apple only supplies these on the FIRST authorization; client forwards them.
    email: str | None = None
    display_name: str | None = None


class RefreshBody(BaseModel):
    device_id: uuid.UUID
    refresh_token: str


def _user_payload(user: User) -> dict[str, Any]:
    return {
        "id": str(user.id),
        "email": user.email,
        "display_name": user.display_name,
        "unit_pref": user.unit_pref,
        "is_admin": user.is_admin,
        "created_at": iso(user.created_at),
    }


async def _issue_tokens(
    session: SessionDep, settings: Settings, user: User, body: AppleAuthBody
) -> dict[str, Any]:
    device = await session.get(Device, body.device_id)
    if device is None:
        device = Device(id=body.device_id, user_id=user.id)
        session.add(device)
    device.user_id = user.id
    if body.device_name:
        device.name = body.device_name
    refresh_token = new_refresh_token()
    device.refresh_token_hash = hash_token(refresh_token)
    device.refresh_expires_at = utcnow() + timedelta(days=settings.refresh_ttl_days)
    device.last_seen_at = utcnow()
    await session.flush()
    return {
        "access_token": create_access_token(settings, user.id, device.id, user.is_admin),
        "refresh_token": refresh_token,
        "user": _user_payload(user),
    }


@router.post("/auth/apple")
async def auth_apple(
    body: AppleAuthBody, session: SessionDep, settings: SettingsDep, verifier: VerifierDep
) -> dict[str, Any]:
    try:
        claims = await verifier.verify(body.identity_token, body.nonce)
    except AppleVerificationError as exc:
        raise HTTPException(status_code=401, detail=f"apple verification failed: {exc}") from exc
    apple_sub = claims.get("sub")
    if not apple_sub:
        raise HTTPException(status_code=401, detail="apple token missing sub")

    user = (
        await session.execute(select(User).where(User.apple_sub == apple_sub))
    ).scalar_one_or_none()
    if user is None:
        # New account: burn an invite atomically or refuse to create anything.
        new_user_id = uuid.uuid4()
        redeemed = None
        if body.invite_code:
            redeemed = (
                await session.execute(
                    update(Invite)
                    .where(
                        Invite.code == body.invite_code,
                        Invite.redeemed_by.is_(None),
                        Invite.expires_at > utcnow(),
                    )
                    .values(redeemed_by=new_user_id, redeemed_at=utcnow())
                    .returning(Invite.code)
                )
            ).scalar_one_or_none()
        if redeemed is None:
            await session.rollback()
            raise HTTPException(status_code=403, detail="invite_required")
        user = User(
            id=new_user_id,
            apple_sub=apple_sub,
            email=body.email or claims.get("email"),
            display_name=body.display_name,
            invite_code=redeemed,
        )
        session.add(user)
        await session.flush()

    result = await _issue_tokens(session, settings, user, body)
    await session.commit()
    return result


@router.post("/auth/refresh")
async def auth_refresh(body: RefreshBody, session: SessionDep, settings: SettingsDep) -> dict[str, Any]:
    device = await session.get(Device, body.device_id)
    if device is None:
        raise HTTPException(status_code=401, detail="unknown device")
    if device.refresh_token_hash is None:
        raise HTTPException(status_code=401, detail="device_revoked")
    if device.refresh_expires_at is None or device.refresh_expires_at < utcnow():
        raise HTTPException(status_code=401, detail="refresh_expired")
    if hash_token(body.refresh_token) != device.refresh_token_hash:
        # Reuse of a rotated token: theft signal — revoke the device outright.
        device.refresh_token_hash = None
        device.refresh_expires_at = None
        await session.commit()
        raise HTTPException(status_code=401, detail="refresh_reuse_detected")

    user = await session.get(User, device.user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="unknown user")
    refresh_token = new_refresh_token()
    device.refresh_token_hash = hash_token(refresh_token)
    device.refresh_expires_at = utcnow() + timedelta(days=settings.refresh_ttl_days)
    device.last_seen_at = utcnow()
    await session.commit()
    return {
        "access_token": create_access_token(settings, user.id, device.id, user.is_admin),
        "refresh_token": refresh_token,
    }


@router.delete("/me", status_code=204)
async def delete_me(auth: AuthDep, session: SessionDep) -> Response:
    """Hard-delete the account and every row it owns (App-Store compliance)."""
    uid = auth.user.id
    # Children before parents (no DB-level cascades configured).
    await session.execute(delete(Sett).where(Sett.user_id == uid))
    await session.execute(delete(PlannedSet).where(PlannedSet.user_id == uid))
    await session.execute(delete(WorkoutExercise).where(WorkoutExercise.user_id == uid))
    await session.execute(delete(BadgeEvent).where(BadgeEvent.user_id == uid))
    await session.execute(delete(Workout).where(Workout.user_id == uid))
    await session.execute(delete(RoutineExercise).where(RoutineExercise.user_id == uid))
    await session.execute(delete(Routine).where(Routine.user_id == uid))
    await session.execute(delete(Goal).where(Goal.user_id == uid))
    await session.execute(delete(Exercise).where(Exercise.user_id == uid))
    await session.execute(delete(SleepDaily).where(SleepDaily.user_id == uid))
    await session.execute(delete(AIDigest).where(AIDigest.user_id == uid))
    await session.execute(delete(OuraConnection).where(OuraConnection.user_id == uid))
    await session.execute(delete(GymLog).where(GymLog.user_id == uid))
    await session.execute(
        delete(Friendship).where(or_(Friendship.user_id == uid, Friendship.friend_id == uid))
    )
    await session.execute(delete(Device).where(Device.user_id == uid))
    await session.execute(delete(User).where(User.id == uid))
    await session.commit()
    return Response(status_code=204)
