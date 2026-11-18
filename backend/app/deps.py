import time
import uuid
from collections import defaultdict, deque
from dataclasses import dataclass

from fastapi import Depends, Request
from sqlalchemy.orm import Session as Db

from . import models
from .db import get_db
from .errors import ApiError
from .security import read_access_token


@dataclass
class Principal:
    user: models.User
    session_id: uuid.UUID


def current_user(request: Request, db: Db = Depends(get_db)) -> Principal:
    header = request.headers.get("authorization", "")
    claims = read_access_token(header[7:]) if header.lower().startswith("bearer ") else None
    if not claims:
        raise ApiError(401, "UNAUTHENTICATED", "Sign in to continue.")
    session = db.get(models.Session, uuid.UUID(claims["sid"]))
    if session is None or session.revoked_at is not None:
        raise ApiError(401, "UNAUTHENTICATED", "This session has ended. Sign in again.")
    user = db.get(models.User, uuid.UUID(claims["sub"]))
    if user is None or user.deleted_at is not None:
        raise ApiError(401, "UNAUTHENTICATED", "Sign in to continue.")
    request.state.user_id = str(user.id)
    return Principal(user=user, session_id=session.id)


def app_key(request: Request):
    """Personal-app lock for the AI routes: the caller must send the server's APP_KEY in X-App-Key.
    With no APP_KEY set, a development server lets every caller in and a production server refuses."""
    import hmac

    from .config import get_settings
    settings = get_settings()
    if not settings.app_key:
        if settings.environment == "production":
            raise ApiError(503, "AI_DISABLED", "AI is switched off: the server has no APP_KEY.")
        return
    sent = request.headers.get("x-app-key", "")
    if not hmac.compare_digest(sent.encode(), settings.app_key.encode()):
        raise ApiError(401, "UNAUTHENTICATED", "The app key is missing or wrong. Set it in Profile, Server.")


# In-process sliding window. Enough for one API process; move to the gateway or Redis before running several
# (kb/00-core/07-open-decisions.md, D4).
_LIMITS = {"auth": (10, 60), "standard": (120, 60), "ai": (20, 60)}
_hits: dict[tuple[str, str], deque] = defaultdict(deque)


def rate_limit(tier: str):
    def dep(request: Request):
        if tier not in _LIMITS:
            return
        limit, window = _LIMITS[tier]
        who = request.client.host if request.client else "unknown"
        q = _hits[(tier, who)]
        now = time.monotonic()
        while q and now - q[0] > window:
            q.popleft()
        if len(q) >= limit:
            raise ApiError(429, "RATE_LIMITED", "Too many requests. Try again in a minute.")
        q.append(now)
    return dep


def reset_rate_limits():
    _hits.clear()
