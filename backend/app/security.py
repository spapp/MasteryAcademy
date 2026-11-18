"""Password hashing (scrypt), access tokens (JWT, short-lived), refresh tokens (opaque, stored hashed, rotated)."""
import base64
import hashlib
import hmac
import secrets
import time
import uuid

import jwt

from .config import get_settings

_N, _R, _P = 2 ** 14, 8, 1


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    return f"scrypt${_N}${_R}${_P}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, n, r, p, salt, digest = stored.split("$")
        got = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p), dklen=32)
        return hmac.compare_digest(got, base64.b64decode(digest))
    except Exception:
        return False


def new_refresh_token() -> tuple[str, str]:
    token = secrets.token_urlsafe(48)
    return token, hash_token(token)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def make_access_token(user_id: uuid.UUID, session_id: uuid.UUID) -> str:
    s = get_settings()
    now = int(time.time())
    return jwt.encode({"sub": str(user_id), "sid": str(session_id), "iat": now, "exp": now + s.access_ttl_seconds}, s.jwt_secret, algorithm="HS256")


def read_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None
