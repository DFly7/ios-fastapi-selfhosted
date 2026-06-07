"""Unit tests for /api/v1/me/notes (mocked Supabase via dependency_overrides)."""

import uuid
from unittest.mock import AsyncMock, MagicMock

from fastapi.testclient import TestClient
from tests.api.jwt_route_helpers import (
    FAKE_TOKEN,
    MOCK_AUTH_DATA,
    notes_auth_override,
)

from app.core.auth import get_authenticated_client
from app.main import app

_NOTE_ID = str(uuid.uuid4())
_NOTE_ROW = {
    "id": _NOTE_ID,
    "user_id": MOCK_AUTH_DATA["payload"]["sub"],
    "title": "Test note",
    "body": None,
    "created_at": "2026-01-01T00:00:00+00:00",
    "updated_at": "2026-01-01T00:00:00+00:00",
}


def _mock_execute(data) -> AsyncMock:
    """Return an AsyncMock for .execute() that resolves to a result with .data."""
    return AsyncMock(return_value=MagicMock(data=data))


def _mock_count_execute(count: int = 0) -> AsyncMock:
    """Return an AsyncMock for count_notes: empty data plus Supabase count metadata."""
    return AsyncMock(return_value=MagicMock(data=[], count=count))


def test_list_notes_requires_auth() -> None:
    """No Authorization header → 401."""
    with TestClient(app) as client:
        response = client.get("/api/v1/me/notes")
    assert response.status_code == 401


def test_create_note_requires_auth() -> None:
    """No Authorization header → 401."""
    with TestClient(app) as client:
        response = client.post("/api/v1/me/notes", json={"title": "hi"})
    assert response.status_code == 401


def test_list_notes_returns_empty_list() -> None:
    """GET /me/notes returns [] when no notes exist."""
    mock_supabase = MagicMock()
    (
        mock_supabase.table.return_value.select.return_value.eq.return_value.order.return_value
    ).execute = _mock_execute([])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.get(
                "/api/v1/me/notes",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 200
    assert response.json() == []


def test_list_notes_returns_existing_notes() -> None:
    """GET /me/notes returns a list of the user's notes."""
    mock_supabase = MagicMock()
    (
        mock_supabase.table.return_value.select.return_value.eq.return_value.order.return_value
    ).execute = _mock_execute([_NOTE_ROW])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.get(
                "/api/v1/me/notes",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["title"] == "Test note"
    assert data[0]["user_id"] == MOCK_AUTH_DATA["payload"]["sub"]


def test_create_note_returns_201() -> None:
    """POST /me/notes with valid body → 201 with created row."""
    mock_supabase = MagicMock()
    sel = mock_supabase.table.return_value.select.return_value
    sel.eq.return_value.limit.return_value.execute = _mock_count_execute(0)
    mock_supabase.table.return_value.insert.return_value.execute = _mock_execute([_NOTE_ROW])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.post(
                "/api/v1/me/notes",
                json={"title": "Test note"},
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 201
    assert response.json()["title"] == "Test note"
    assert response.json()["id"] == _NOTE_ID


def test_create_note_missing_title_returns_422() -> None:
    """POST /me/notes without title → 422 Unprocessable Entity."""
    mock_supabase = MagicMock()
    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.post(
                "/api/v1/me/notes",
                json={"body": "no title here"},
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 422


def test_get_single_note_returns_404_when_missing() -> None:
    """GET /me/notes/{id} for a non-existent note → 404."""
    mock_supabase = MagicMock()
    (
        mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value
    ).execute = _mock_execute([])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.get(
                f"/api/v1/me/notes/{_NOTE_ID}",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 404


def test_patch_note_returns_updated_note() -> None:
    """PATCH /me/notes/{id} with valid payload → 200 with updated note."""
    updated_row = {**_NOTE_ROW, "title": "Updated title"}
    mock_supabase = MagicMock()
    upd = mock_supabase.table.return_value.update.return_value
    upd.eq.return_value.eq.return_value.execute = _mock_execute([updated_row])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.patch(
                f"/api/v1/me/notes/{_NOTE_ID}",
                json={"title": "Updated title"},
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 200
    assert response.json()["title"] == "Updated title"


def test_delete_note_requires_auth() -> None:
    """No Authorization header → 401."""
    with TestClient(app) as client:
        response = client.delete(f"/api/v1/me/notes/{_NOTE_ID}")
    assert response.status_code == 401


def test_delete_note_returns_204() -> None:
    """DELETE /me/notes/{id} for an existing note → 204 No Content."""
    mock_supabase = MagicMock()
    q = mock_supabase.table.return_value.delete.return_value
    q.eq.return_value.eq.return_value.execute = _mock_execute([_NOTE_ROW])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.delete(
                f"/api/v1/me/notes/{_NOTE_ID}",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 204


def test_delete_note_returns_404_when_missing() -> None:
    """DELETE /me/notes/{id} for a non-existent note → 404."""
    mock_supabase = MagicMock()
    q = mock_supabase.table.return_value.delete.return_value
    q.eq.return_value.eq.return_value.execute = _mock_execute([])

    app.dependency_overrides[get_authenticated_client] = notes_auth_override(mock_supabase)
    try:
        with TestClient(app) as client:
            response = client.delete(
                f"/api/v1/me/notes/{_NOTE_ID}",
                headers={"Authorization": f"Bearer {FAKE_TOKEN}"},
            )
    finally:
        app.dependency_overrides.pop(get_authenticated_client, None)

    assert response.status_code == 404
