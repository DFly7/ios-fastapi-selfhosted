"""Tests for JWT-protected routes.

Uses FastAPI's dependency_overrides to bypass real JWKS verification so these
tests run without a live Supabase instance. Replace the mock payload with whatever
claims your route handlers actually read (sub, email, role, etc.).
"""

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient
from tests.api.jwt_route_helpers import (
    FAKE_TOKEN,
    FAKE_USER_ID,
    MOCK_AUTH_DATA,
    override_verify_jwt,
)

from app.core.auth import AuthenticatedClient, get_authenticated_client, verify_jwt
from app.main import app

# ---------------------------------------------------------------------------
# Tests — /api/v1/secure-test
# ---------------------------------------------------------------------------


def test_secure_test_requires_auth() -> None:
    """No Authorization header → 401."""
    with TestClient(app) as client:
        response = client.get("/api/v1/secure-test")
    assert response.status_code == 401


def test_secure_test_with_valid_jwt() -> None:
    """Valid (mocked) JWT → 200 with user_id from token payload."""
    app.dependency_overrides[verify_jwt] = override_verify_jwt
    try:
        with TestClient(app) as client:
            response = client.get(
                "/api/v1/secure-test",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(verify_jwt, None)

    assert response.status_code == 200
    body = response.json()
    assert body["user_id"] == FAKE_USER_ID
    assert body["message"] == "Token valid"


# ---------------------------------------------------------------------------
# Tests — /api/v1/me/profile
# ---------------------------------------------------------------------------


def test_get_profile_requires_auth() -> None:
    """No Authorization header → 401."""
    with TestClient(app) as client:
        response = client.get("/api/v1/me/profile")
    assert response.status_code == 401


def test_get_profile_not_found_when_no_row(monkeypatch: pytest.MonkeyPatch) -> None:
    """Profile route returns 404 when PostgREST returns no rows.

    We override get_authenticated_client so no real Supabase client is created,
    then mock the table query chain to return an empty data list.
    """
    mock_supabase = MagicMock()
    chain = mock_supabase.table.return_value.select.return_value
    chain = chain.eq.return_value.limit.return_value
    chain.execute = AsyncMock(return_value=MagicMock(data=[]))

    async def _override_authenticated_client() -> AuthenticatedClient:
        return AuthenticatedClient.model_construct(
            client=mock_supabase,
            payload=MOCK_AUTH_DATA["payload"],
        )

    app.dependency_overrides[get_authenticated_client] = _override_authenticated_client
    try:
        with TestClient(app) as client:
            response = client.get(
                "/api/v1/me/profile",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Tests — PATCH /api/v1/me/profile
# ---------------------------------------------------------------------------

_PROFILE_ROW = {
    "id": FAKE_USER_ID,
    "display_name": "Alice",
    "avatar_url": None,
    "created_at": "2026-01-01T00:00:00+00:00",
}


def _make_profile_client(rows: list[dict]) -> MagicMock:
    """Mock Supabase client whose .table(...).update(...).eq(...).execute() returns rows."""
    mock = MagicMock()
    mock.table.return_value.update.return_value.eq.return_value.execute = AsyncMock(
        return_value=MagicMock(data=rows)
    )
    return mock


def test_patch_profile_requires_auth() -> None:
    """No Authorization header → 401."""
    with TestClient(app) as client:
        response = client.patch("/api/v1/me/profile", json={"display_name": "Alice"})
    assert response.status_code == 401


def test_patch_profile_empty_body_returns_422() -> None:
    """Empty JSON body (no fields to update) → 422."""
    mock_supabase = MagicMock()

    async def _override() -> AuthenticatedClient:
        return AuthenticatedClient.model_construct(
            client=mock_supabase, payload=MOCK_AUTH_DATA["payload"]
        )

    app.dependency_overrides[get_authenticated_client] = _override
    try:
        with TestClient(app) as client:
            response = client.patch(
                "/api/v1/me/profile",
                json={},
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 422


def test_patch_profile_updates_display_name() -> None:
    """Valid PATCH with display_name → 200 and updated row returned."""
    mock_supabase = _make_profile_client([_PROFILE_ROW])

    async def _override() -> AuthenticatedClient:
        return AuthenticatedClient.model_construct(
            client=mock_supabase, payload=MOCK_AUTH_DATA["payload"]
        )

    app.dependency_overrides[get_authenticated_client] = _override
    try:
        with TestClient(app) as client:
            response = client.patch(
                "/api/v1/me/profile",
                json={"display_name": "Alice"},
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 200
    assert response.json()["display_name"] == "Alice"
    assert response.json()["id"] == FAKE_USER_ID


def test_patch_profile_returns_404_when_row_missing() -> None:
    """PATCH on a missing profile row → 404."""
    mock_supabase = _make_profile_client([])

    async def _override() -> AuthenticatedClient:
        return AuthenticatedClient.model_construct(
            client=mock_supabase, payload=MOCK_AUTH_DATA["payload"]
        )

    app.dependency_overrides[get_authenticated_client] = _override
    try:
        with TestClient(app) as client:
            response = client.patch(
                "/api/v1/me/profile",
                json={"display_name": "Ghost"},
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 404
