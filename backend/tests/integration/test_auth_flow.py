"""Integration tests for auth endpoints with real SQLAlchemy ORM."""

import pytest

pytestmark = pytest.mark.integration


@pytest.mark.asyncio
async def test_register_and_login(client):
    """Register a new user and verify credentials work for login."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "alice@example.com", "password": "Password123!"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data

    resp = await client.post(
        "/api/v1/auth/token",
        json={"email": "alice@example.com", "password": "Password123!"},
    )
    assert resp.status_code == 200

    resp = await client.post(
        "/api/v1/auth/token",
        json={"email": "alice@example.com", "password": "wrong"},
    )
    assert resp.status_code == 401

    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "alice@example.com", "password": "otherpass1"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
async def test_refresh_token_rotation(client):
    """Verify refresh token rotation and invalidation."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "bob@example.com", "password": "Password123!"},
    )
    refresh_token = resp.json()["refresh_token"]

    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    new_refresh = resp.json()["refresh_token"]
    assert new_refresh != refresh_token

    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_logout_invalidates_token(client):
    """Verify logout invalidates refresh token."""
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "carol@example.com", "password": "Password123!"},
    )
    refresh_token = resp.json()["refresh_token"]

    await client.post("/api/v1/auth/logout", json={"refresh_token": refresh_token})

    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 401
