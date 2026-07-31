from __future__ import annotations

import asyncio
import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt

from app.core.config import get_settings

_settings = get_settings()


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode(), hashed.encode())


# Fixed dummy hash so login misses still pay a bcrypt verify (timing-oracle mitigation).
# Not a real password — only used when the email is unknown.
DUMMY_PASSWORD_HASH = hash_password("timing-oracle-dummy")


async def hash_password_async(plain: str) -> str:
    """Bcrypt hashing is CPU-bound and blocks for tens of ms — run off the event loop."""
    return await asyncio.to_thread(hash_password, plain)


async def verify_password_async(plain: str, hashed: str) -> bool:
    """Bcrypt verification is CPU-bound and blocks for tens of ms — run off the event loop."""
    return await asyncio.to_thread(verify_password, plain, hashed)


def _make_jwt(sub: str, expire_seconds: int, token_type: str) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "sub": sub,
            "aud": "authenticated",
            "type": token_type,
            "iat": now,
            "exp": now + timedelta(seconds=expire_seconds),
        },
        _settings.jwt_secret,
        algorithm="HS256",
    )


def create_access_token(user_id: uuid.UUID) -> str:
    return _make_jwt(str(user_id), _settings.jwt_access_token_expire_seconds, "access")


def create_refresh_token_value() -> str:
    return secrets.token_urlsafe(48)


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        _settings.jwt_secret,
        algorithms=["HS256"],
        audience="authenticated",
    )
