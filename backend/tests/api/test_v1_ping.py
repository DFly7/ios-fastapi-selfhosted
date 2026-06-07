"""Tests for GET /api/v1/ping.

Matches the test_v1_ping.py entry in tests/api/README.md.
"""

from fastapi.testclient import TestClient

from app.main import app


def test_ping_returns_200() -> None:
    """GET /api/v1/ping → 200 with {"ok": true}."""
    with TestClient(app) as client:
        response = client.get("/api/v1/ping")
    assert response.status_code == 200
    assert response.json() == {"ok": True}


def test_ping_does_not_require_auth() -> None:
    """Ping must be reachable without an Authorization header (useful for uptime monitors)."""
    with TestClient(app) as client:
        response = client.get("/api/v1/ping")
    assert response.status_code != 401
