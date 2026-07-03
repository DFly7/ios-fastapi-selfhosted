"""Route-logic tests for the auth endpoints — no database, repositories mocked.

These exercise the handler branching in `app/api/v1/auth.py` (register, login,
refresh, logout, /me) that the integration suite otherwise covers only against a
live Postgres. By overriding `get_db` / `verify_jwt` and monkeypatching the
repository functions, they run in the fast unit suite — so `make backend-test`
(and CI) actually guards these flows instead of leaving them a false-green gate.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.core.auth import verify_jwt
from app.db.session import get_db
from app.main import app


class _FakeUser:
    def __init__(
        self,
        *,
        uid: uuid.UUID | None = None,
        email: str = "user@example.com",
        is_active: bool = True,
    ):
        self.id = uid or uuid.uuid4()
        self.email = email
        self.hashed_password = "not-verified-directly"
        self.is_active = is_active


class _FakeRefreshToken:
    def __init__(self, *, user_id: uuid.UUID, expires_at: datetime):
        self.user_id = user_id
        self.expires_at = expires_at


@pytest.fixture(autouse=True)
def _no_db_no_rate_limits(monkeypatch: pytest.MonkeyPatch):
    """Stub the DB dependency and disable rate limiting for every test here."""
    from app.core.rate_limit import limiter

    monkeypatch.setattr(limiter, "enabled", False, raising=False)

    async def _override_get_db():
        yield object()

    app.dependency_overrides[get_db] = _override_get_db
    yield
    app.dependency_overrides.clear()


# ── register ──────────────────────────────────────────────────────────────────


def test_register_returns_201_with_tokens(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.repositories.user_repo.get_by_email", AsyncMock(return_value=None))
    monkeypatch.setattr(
        "app.repositories.user_repo.create_user", AsyncMock(return_value=_FakeUser())
    )
    monkeypatch.setattr(
        "app.repositories.profile_repo.create_profile", AsyncMock(return_value=None)
    )
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.create_refresh_token", AsyncMock(return_value=None)
    )

    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/register", json={"email": "new@example.com", "password": "password123"}
        )

    assert r.status_code == 201
    body = r.json()
    assert body["access_token"]
    assert body["refresh_token"]


def test_register_duplicate_email_returns_409(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.user_repo.get_by_email", AsyncMock(return_value=_FakeUser())
    )

    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/register", json={"email": "dupe@example.com", "password": "password123"}
        )

    assert r.status_code == 409


# ── login (POST /auth/token) ──────────────────────────────────────────────────


def test_login_success_returns_tokens(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.user_repo.get_by_email", AsyncMock(return_value=_FakeUser())
    )
    monkeypatch.setattr("app.api.v1.auth.verify_password", lambda pw, hashed: True)
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.create_refresh_token", AsyncMock(return_value=None)
    )

    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/token", json={"email": "user@example.com", "password": "password123"}
        )

    assert r.status_code == 200
    assert r.json()["access_token"]


def test_login_unknown_email_returns_401(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.repositories.user_repo.get_by_email", AsyncMock(return_value=None))

    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/token", json={"email": "nobody@example.com", "password": "password123"}
        )

    assert r.status_code == 401


def test_login_wrong_password_returns_401(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.user_repo.get_by_email", AsyncMock(return_value=_FakeUser())
    )
    monkeypatch.setattr("app.api.v1.auth.verify_password", lambda pw, hashed: False)

    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/token", json={"email": "user@example.com", "password": "wrong"}
        )

    assert r.status_code == 401


def test_login_disabled_account_returns_403(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.user_repo.get_by_email",
        AsyncMock(return_value=_FakeUser(is_active=False)),
    )
    monkeypatch.setattr("app.api.v1.auth.verify_password", lambda pw, hashed: True)

    with TestClient(app) as client:
        r = client.post(
            "/api/v1/auth/token", json={"email": "user@example.com", "password": "password123"}
        )

    assert r.status_code == 403


# ── refresh ───────────────────────────────────────────────────────────────────


def test_refresh_rotates_and_returns_new_tokens(monkeypatch: pytest.MonkeyPatch) -> None:
    stored = _FakeRefreshToken(
        user_id=uuid.uuid4(), expires_at=datetime.now(UTC) + timedelta(days=1)
    )
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.get_by_hash", AsyncMock(return_value=stored)
    )
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.delete_by_hash", AsyncMock(return_value=None)
    )
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.create_refresh_token", AsyncMock(return_value=None)
    )

    with TestClient(app) as client:
        r = client.post("/api/v1/auth/refresh", json={"refresh_token": "whatever"})

    assert r.status_code == 200
    assert r.json()["refresh_token"]


def test_refresh_unknown_token_returns_401(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.get_by_hash", AsyncMock(return_value=None)
    )

    with TestClient(app) as client:
        r = client.post("/api/v1/auth/refresh", json={"refresh_token": "nope"})

    assert r.status_code == 401


def test_refresh_expired_token_returns_401(monkeypatch: pytest.MonkeyPatch) -> None:
    stored = _FakeRefreshToken(
        user_id=uuid.uuid4(), expires_at=datetime.now(UTC) - timedelta(days=1)
    )
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.get_by_hash", AsyncMock(return_value=stored)
    )

    with TestClient(app) as client:
        r = client.post("/api/v1/auth/refresh", json={"refresh_token": "old"})

    assert r.status_code == 401


# ── logout ────────────────────────────────────────────────────────────────────


def test_logout_returns_204(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.refresh_token_repo.delete_by_hash", AsyncMock(return_value=None)
    )

    with TestClient(app) as client:
        r = client.post("/api/v1/auth/logout", json={"refresh_token": "bye"})

    assert r.status_code == 204


# ── /me ───────────────────────────────────────────────────────────────────────


def test_me_returns_current_user(monkeypatch: pytest.MonkeyPatch) -> None:
    uid = uuid.uuid4()
    app.dependency_overrides[verify_jwt] = lambda: {"payload": {"sub": str(uid)}}
    monkeypatch.setattr(
        "app.repositories.user_repo.get_by_id",
        AsyncMock(return_value=_FakeUser(uid=uid, email="me@example.com")),
    )

    with TestClient(app) as client:
        r = client.get("/api/v1/auth/me")

    assert r.status_code == 200
    assert r.json()["email"] == "me@example.com"


def test_me_unknown_user_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    uid = uuid.uuid4()
    app.dependency_overrides[verify_jwt] = lambda: {"payload": {"sub": str(uid)}}
    monkeypatch.setattr("app.repositories.user_repo.get_by_id", AsyncMock(return_value=None))

    with TestClient(app) as client:
        r = client.get("/api/v1/auth/me")

    assert r.status_code == 404
