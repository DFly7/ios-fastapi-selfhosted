"""Tests for GET /healthz.

Matches the test_health.py entry in tests/api/README.md.
"""

from fastapi.testclient import TestClient

from app.main import app


def test_healthz_returns_200() -> None:
    """GET /healthz → 200 with {"status": "ok"}."""
    with TestClient(app) as client:
        response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_healthz_does_not_require_auth() -> None:
    """Health check must be reachable without an Authorization header."""
    with TestClient(app) as client:
        response = client.get("/healthz")
    assert response.status_code != 401
