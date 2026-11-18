import uuid
from datetime import timedelta, timezone

from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as Db

from .. import models
from ..config import get_settings
from ..db import get_db
from ..deps import Principal, current_user, rate_limit
from ..errors import ApiError
from ..schemas import RefreshBody, RegisterBody, SessionBody, user_out
from ..security import hash_password, hash_token, make_access_token, new_refresh_token, verify_password

router = APIRouter()
# Verified against when the email is unknown, so both paths cost the same time.
_DUMMY_HASH = hash_password("not-a-real-password")


def _aware(dt):
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _open_session(db: Db, user: models.User, device_name: str | None) -> dict:
    s = get_settings()
    token, token_hash = new_refresh_token()
    session = models.Session(user_id=user.id, device_name=device_name or "", refresh_hash=token_hash,
                             expires_at=models.now() + timedelta(days=s.refresh_ttl_days))
    db.add(session)
    db.flush()
    return {"accessToken": make_access_token(user.id, session.id), "refreshToken": token, "expiresIn": s.access_ttl_seconds}


@router.post("/auth/users", status_code=201, dependencies=[Depends(rate_limit("auth"))])
def registerUser(body: RegisterBody, db: Db = Depends(get_db)):
    email = body.email.lower()
    if db.scalar(select(models.User).where(models.User.email == email)):
        raise ApiError(409, "CONFLICT", "An account with this email already exists.")
    user = models.User(email=email, display_name=body.displayName.strip(), password_hash=hash_password(body.password))
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        raise ApiError(409, "CONFLICT", "An account with this email already exists.")
    return {"data": {"user": user_out(user), "tokens": _open_session(db, user, None)}}


@router.post("/auth/sessions", status_code=201, dependencies=[Depends(rate_limit("auth"))])
def createSession(body: SessionBody, db: Db = Depends(get_db)):
    user = db.scalar(select(models.User).where(models.User.email == body.email.lower(), models.User.deleted_at.is_(None)))
    ok = verify_password(body.password, user.password_hash if user else _DUMMY_HASH)
    if not user or not ok:
        raise ApiError(401, "INVALID_CREDENTIALS", "Email or password is incorrect.")
    return {"data": {"user": user_out(user), "tokens": _open_session(db, user, body.deviceName)}}


@router.post("/auth/sessions/refresh", dependencies=[Depends(rate_limit("auth"))])
def refreshSession(body: RefreshBody, db: Db = Depends(get_db)):
    h = hash_token(body.refreshToken)
    session = db.scalar(select(models.Session).where(models.Session.refresh_hash == h))
    if session is None:
        # A token that was already rotated away is being replayed: end that session.
        reused = db.scalar(select(models.Session).where(models.Session.prev_refresh_hash == h))
        if reused is not None and reused.revoked_at is None:
            reused.revoked_at = models.now()
            db.commit()
            raise ApiError(401, "TOKEN_REUSED", "This session was ended for safety. Sign in again.")
        raise ApiError(401, "UNAUTHENTICATED", "Sign in again.")
    if session.revoked_at is not None or _aware(session.expires_at) < models.now():
        raise ApiError(401, "UNAUTHENTICATED", "Sign in again.")
    s = get_settings()
    token, token_hash = new_refresh_token()
    session.prev_refresh_hash, session.refresh_hash = session.refresh_hash, token_hash
    session.expires_at = models.now() + timedelta(days=s.refresh_ttl_days)
    return {"data": {"accessToken": make_access_token(session.user_id, session.id), "refreshToken": token, "expiresIn": s.access_ttl_seconds}}


@router.delete("/auth/sessions/current", status_code=204)
def deleteSession(p: Principal = Depends(current_user), db: Db = Depends(get_db)):
    session = db.get(models.Session, p.session_id)
    session.revoked_at = models.now()
    return Response(status_code=204)


@router.get("/me", dependencies=[Depends(rate_limit("standard"))])
def getMe(p: Principal = Depends(current_user)):
    return {"data": user_out(p.user)}


@router.delete("/me", status_code=204)
def deleteMe(p: Principal = Depends(current_user), db: Db = Depends(get_db)):
    uid: uuid.UUID = p.user.id
    db.execute(delete(models.ProgressRecord).where(models.ProgressRecord.user_id == uid))
    db.execute(delete(models.SyncCounter).where(models.SyncCounter.user_id == uid))
    db.execute(delete(models.Session).where(models.Session.user_id == uid))
    db.delete(p.user)
    return Response(status_code=204)
