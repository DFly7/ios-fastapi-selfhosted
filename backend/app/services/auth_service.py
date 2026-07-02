from __future__ import annotations

import hashlib
import secrets
import uuid
import warnings
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt
from passlib.context import CryptContext

from app.core.config import get_settings

# Suppress passlib's bcrypt version detection error on Python 3.12
# bcrypt module doesn't expose __about__.__version__, but passlib still works
warnings.filterwarnings("ignore", ".*error reading bcrypt version.*", append=True)

_settings = get_settings()

# Initialize CryptContext; passlib's bcrypt detection on Python 3.12 fails
# because bcrypt doesn't expose __about__.__version__, but bcrypt still works.
# We work around this by catching the error and suppressing the AttributeError.
# However, passlib can still raise ValueError during hash() if it tries wrap bug detection.
# Since bcrypt is known to work, we can safely disable that check.
_pwd_context: CryptContext | None
try:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        _pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
        # Test that it works by hashing a short string
        _ = _pwd_context.hash("test")
except (AttributeError, ValueError):
    # Fallback to using bcrypt directly if CryptContext fails
    _pwd_context = None


def hash_password(plain: str) -> str:
    if _pwd_context is not None:
        return str(_pwd_context.hash(plain))
    # Fallback: use bcrypt directly
    return bcrypt.hashpw(plain.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    if _pwd_context is not None:
        return bool(_pwd_context.verify(plain, hashed))
    # Fallback: use bcrypt directly
    return bcrypt.checkpw(plain.encode(), hashed.encode())


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
