"""Tests for auth endpoint request validation (no database required)."""

from fastapi.testclient import TestClient

from app.main import app


def test_register_rejects_password_over_72_chars() -> None:
    """POST /api/v1/auth/register with a 73-byte password must return 422.

    bcrypt silently truncates (or raises) beyond 72 bytes. The Pydantic
    schema enforces max_length=72 so the server rejects the request before
    any hashing takes place.
    """
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": "test@example.com",
                "password": "a" * 73,
            },
        )
    assert response.status_code == 422


def test_register_rejects_password_too_short() -> None:
    """POST /api/v1/auth/register with a 7-byte password must return 422."""
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": "test@example.com",
                "password": "short",
            },
        )
    assert response.status_code == 422


def test_register_accepts_password_at_max_length() -> None:
    """POST /api/v1/auth/register with exactly 72-byte password passes schema validation.

    The request will fail further (DB not connected in unit suite) but must not
    return 422 — a 4xx/5xx other than 422 confirms schema validation passed.
    """
    with TestClient(app) as client:
        response = client.post(
            "/api/v1/auth/register",
            json={
                "email": "test@example.com",
                "password": "a" * 72,
            },
        )
    assert response.status_code != 422
