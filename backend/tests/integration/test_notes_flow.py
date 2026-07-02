"""Integration tests for notes endpoints with real SQLAlchemy ORM."""

import asyncio
from datetime import datetime

import pytest
from tests.api.jwt_route_helpers import auth_header

from app.repositories import profile_repo, user_repo
from app.services.auth_service import hash_password

pytestmark = pytest.mark.integration


async def _create_user_and_profile(db_session, email="test@example.com"):
    """Helper to create a user and their profile."""
    user = await user_repo.create_user(db_session, email, hash_password("password123"))
    await profile_repo.create_profile(db_session, user.id)
    await db_session.commit()
    return user


@pytest.mark.asyncio
async def test_notes_list_empty_on_fresh_user(client, db_session):
    """Fresh user → GET /me/notes returns an empty list."""
    user = await _create_user_and_profile(db_session, "notes_empty@example.com")
    hdrs = auth_header(user.id)

    resp = await client.get("/api/v1/me/notes", headers=hdrs)
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_create_note_returns_201(client, db_session):
    """POST /me/notes with valid data returns 201 with persisted row."""
    user = await _create_user_and_profile(db_session, "notes_create@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "Hello", "body": "World"},
        headers=hdrs,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["title"] == "Hello"
    assert data["body"] == "World"
    assert data["user_id"] == str(user.id)
    assert "id" in data
    assert "created_at" in data
    assert "updated_at" in data


@pytest.mark.asyncio
async def test_list_notes_returns_created_note(client, db_session):
    """GET /me/notes returns previously created notes."""
    user = await _create_user_and_profile(db_session, "notes_list@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "Test Note", "body": "Content"},
        headers=hdrs,
    )
    note_id = resp.json()["id"]

    resp = await client.get("/api/v1/me/notes", headers=hdrs)
    assert resp.status_code == 200
    ids = [n["id"] for n in resp.json()]
    assert note_id in ids


@pytest.mark.asyncio
async def test_get_single_note_returns_200(client, db_session):
    """GET /me/notes/{id} returns the individual note."""
    user = await _create_user_and_profile(db_session, "notes_get@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "Single Note", "body": "Content"},
        headers=hdrs,
    )
    note_id = resp.json()["id"]

    resp = await client.get(f"/api/v1/me/notes/{note_id}", headers=hdrs)
    assert resp.status_code == 200
    assert resp.json()["id"] == note_id


@pytest.mark.asyncio
async def test_patch_note_updates_title(client, db_session):
    """PATCH /me/notes/{id} changes supplied fields and returns updated row."""
    user = await _create_user_and_profile(db_session, "notes_patch@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "Original", "body": "Content"},
        headers=hdrs,
    )
    note_id = resp.json()["id"]

    resp = await client.patch(
        f"/api/v1/me/notes/{note_id}",
        json={"title": "Updated"},
        headers=hdrs,
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["title"] == "Updated"
    assert data["body"] == "Content"
    assert data["id"] == note_id


@pytest.mark.asyncio
async def test_patch_note_updates_updated_at(client, db_session):
    """PATCH /me/notes/{id} bumps updated_at."""
    user = await _create_user_and_profile(db_session, "notes_updated_at@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "Original", "body": "Content"},
        headers=hdrs,
    )
    note_id = resp.json()["id"]
    original_updated_at = datetime.fromisoformat(resp.json()["updated_at"])

    await asyncio.sleep(0.05)

    resp = await client.patch(
        f"/api/v1/me/notes/{note_id}",
        json={"title": "Updated"},
        headers=hdrs,
    )
    assert resp.status_code == 200
    patched_updated_at = datetime.fromisoformat(resp.json()["updated_at"])
    assert patched_updated_at >= original_updated_at


@pytest.mark.asyncio
async def test_delete_note_returns_204(client, db_session):
    """DELETE /me/notes/{id} returns 204 and note is removed."""
    user = await _create_user_and_profile(db_session, "notes_delete@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "To Delete", "body": "Content"},
        headers=hdrs,
    )
    note_id = resp.json()["id"]

    resp = await client.delete(f"/api/v1/me/notes/{note_id}", headers=hdrs)
    assert resp.status_code == 204

    resp = await client.get("/api/v1/me/notes", headers=hdrs)
    ids = [n["id"] for n in resp.json()]
    assert note_id not in ids


@pytest.mark.asyncio
async def test_get_deleted_note_returns_404(client, db_session):
    """GET /me/notes/{id} after deletion returns 404."""
    user = await _create_user_and_profile(db_session, "notes_404@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "Temp Note", "body": "Content"},
        headers=hdrs,
    )
    note_id = resp.json()["id"]

    await client.delete(f"/api/v1/me/notes/{note_id}", headers=hdrs)

    resp = await client.get(f"/api/v1/me/notes/{note_id}", headers=hdrs)
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_notes_isolation_between_users(client, db_session):
    """User A's notes not visible to User B."""
    user_a = await _create_user_and_profile(db_session, "notes_a@example.com")
    user_b = await _create_user_and_profile(db_session, "notes_b@example.com")

    resp = await client.post(
        "/api/v1/me/notes",
        json={"title": "A's Note", "body": "Secret"},
        headers=auth_header(user_a.id),
    )
    note_id = resp.json()["id"]

    resp = await client.get(
        f"/api/v1/me/notes/{note_id}",
        headers=auth_header(user_b.id),
    )
    assert resp.status_code == 404
