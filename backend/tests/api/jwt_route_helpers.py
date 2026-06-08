"""Shared JWT mock data for API route tests."""

import time
import uuid

import jwt

TEST_JWT_SECRET = "testsecretatleast32charslong1234"


def make_test_token(user_id: uuid.UUID | None = None, expired: bool = False) -> str:
    """Generate a test JWT token with HS256."""
    uid = str(user_id or uuid.uuid4())
    exp = int(time.time()) + (-10 if expired else 3600)
    return jwt.encode(
        {
            "sub": uid,
            "aud": "authenticated",
            "type": "access",
            "email": f"{uid[:8]}@test.example",
            "exp": exp,
        },
        TEST_JWT_SECRET,
        algorithm="HS256",
    )


def auth_header(user_id: uuid.UUID | None = None) -> dict[str, str]:
    """Return Authorization header dict with a test JWT token."""
    return {"Authorization": f"Bearer {make_test_token(user_id)}"}
