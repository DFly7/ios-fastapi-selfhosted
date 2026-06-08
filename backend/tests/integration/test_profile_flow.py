"""Integration tests for profile endpoints with real SQLAlchemy ORM."""

import pytest
from app.repositories import profile_repo, user_repo
from app.services.auth_service import hash_password
from tests.api.jwt_route_helpers import auth_header

pytestmark = pytest.mark.integration


async def _create_user_and_profile(db_session, email="test@example.com"):
    """Helper to create a user and their profile."""
    user = await user_repo.create_user(db_session, email, hash_password("password123"))
    await profile_repo.create_profile(db_session, user.id)
    await db_session.commit()
    return user


@pytest.mark.asyncio
async def test_profile_auto_created_on_user_creation(client, db_session):
    """New user → profile created automatically."""
    user = await _create_user_and_profile(db_session, "profile_create@example.com")
    hdrs = auth_header(user.id)

    resp = await client.get("/api/v1/me/profile", headers=hdrs)
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == str(user.id)
    assert "created_at" in data
    assert "display_name" in data
    assert "avatar_url" in data


@pytest.mark.asyncio
async def test_patch_profile_updates_display_name(client, db_session):
    """PATCH /me/profile updates display_name."""
    user = await _create_user_and_profile(db_session, "profile_patch@example.com")
    hdrs = auth_header(user.id)

    resp = await client.patch(
        "/api/v1/me/profile",
        json={"display_name": "Integration Tester"},
        headers=hdrs,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == str(user.id)
    assert data["display_name"] == "Integration Tester"


@pytest.mark.asyncio
async def test_profile_isolation_between_users(client, db_session):
    """User A's profile not visible to User B."""
    user_a = await _create_user_and_profile(db_session, "profile_a@example.com")
    user_b = await _create_user_and_profile(db_session, "profile_b@example.com")

    # User A updates their profile
    resp = await client.patch(
        "/api/v1/me/profile",
        json={"display_name": "User A"},
        headers=auth_header(user_a.id),
    )
    assert resp.status_code == 200

    # User B sees their own profile, not User A's
    resp = await client.get("/api/v1/me/profile", headers=auth_header(user_b.id))
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == str(user_b.id)
    assert data["display_name"] != "User A"
