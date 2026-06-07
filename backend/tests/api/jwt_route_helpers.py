"""Shared JWT mock data and dependency overrides for API route tests."""

from unittest.mock import MagicMock

from app.core.auth import AuthenticatedClient

FAKE_USER_ID = "00000000-0000-0000-0000-000000000001"
FAKE_TOKEN = "mock.jwt.token"

MOCK_AUTH_DATA = {
    "token": FAKE_TOKEN,
    "payload": {
        "sub": FAKE_USER_ID,
        "email": "test@example.com",
        "aud": "authenticated",
        "role": "authenticated",
    },
}


def override_verify_jwt() -> dict:
    return MOCK_AUTH_DATA


def notes_auth_override(mock_supabase: MagicMock):
    async def _override() -> AuthenticatedClient:
        return AuthenticatedClient.model_construct(
            client=mock_supabase, payload=MOCK_AUTH_DATA["payload"]
        )

    return _override
