"""Route-logic tests for the notes endpoints — no database, repo/service mocked.

Exercises the handler branching in `app/api/v1/notes.py` (list, create, get,
update, delete, and the notes-limit path) in the fast unit suite via dependency
overrides + monkeypatched repository/service functions.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.core.auth import verify_jwt
from app.db.session import get_db
from app.main import app
from app.schemas.notes import NoteOut
from app.services.notes_service import NotesLimitExceeded

USER_ID = uuid.uuid4()


def _fake_note(title: str = "Hello", body: str | None = "world") -> NoteOut:
    now = datetime.now(UTC)
    return NoteOut(
        id=uuid.uuid4(),
        user_id=USER_ID,
        title=title,
        body=body,
        created_at=now,
        updated_at=now,
    )


@pytest.fixture(autouse=True)
def _auth_and_db(monkeypatch: pytest.MonkeyPatch):
    """Authenticate as USER_ID, stub the DB, and disable rate limiting."""
    from app.core.rate_limit import limiter

    monkeypatch.setattr(limiter, "enabled", False, raising=False)

    async def _override_get_db():
        yield object()

    app.dependency_overrides[get_db] = _override_get_db
    app.dependency_overrides[verify_jwt] = lambda: {"payload": {"sub": str(USER_ID)}}
    yield
    app.dependency_overrides.clear()


def test_list_notes_returns_notes(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.repositories.notes_repo.list_notes",
        AsyncMock(return_value=[_fake_note("A"), _fake_note("B")]),
    )
    with TestClient(app) as client:
        r = client.get("/api/v1/me/notes")

    assert r.status_code == 200
    assert [n["title"] for n in r.json()] == ["A", "B"]


def test_create_note_returns_201(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.api.v1.notes.create_user_note", AsyncMock(return_value=_fake_note("New"))
    )
    with TestClient(app) as client:
        r = client.post("/api/v1/me/notes", json={"title": "New"})

    assert r.status_code == 201
    assert r.json()["title"] == "New"


def test_create_note_over_limit_returns_422(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.api.v1.notes.create_user_note",
        AsyncMock(side_effect=NotesLimitExceeded("note limit reached")),
    )
    with TestClient(app) as client:
        r = client.post("/api/v1/me/notes", json={"title": "New"})

    assert r.status_code == 422


def test_get_note_found(monkeypatch: pytest.MonkeyPatch) -> None:
    note = _fake_note("Found")
    monkeypatch.setattr("app.repositories.notes_repo.get_note", AsyncMock(return_value=note))
    with TestClient(app) as client:
        r = client.get(f"/api/v1/me/notes/{note.id}")

    assert r.status_code == 200
    assert r.json()["title"] == "Found"


def test_get_note_missing_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.repositories.notes_repo.get_note", AsyncMock(return_value=None))
    with TestClient(app) as client:
        r = client.get(f"/api/v1/me/notes/{uuid.uuid4()}")

    assert r.status_code == 404


def test_update_note_success(monkeypatch: pytest.MonkeyPatch) -> None:
    note = _fake_note("Updated")
    monkeypatch.setattr("app.api.v1.notes.update_user_note", AsyncMock(return_value=note))
    with TestClient(app) as client:
        r = client.patch(f"/api/v1/me/notes/{note.id}", json={"title": "Updated"})

    assert r.status_code == 200
    assert r.json()["title"] == "Updated"


def test_update_note_missing_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.api.v1.notes.update_user_note", AsyncMock(return_value=None))
    with TestClient(app) as client:
        r = client.patch(f"/api/v1/me/notes/{uuid.uuid4()}", json={"title": "x"})

    assert r.status_code == 404


def test_delete_note_success_returns_204(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.api.v1.notes.delete_user_note", AsyncMock(return_value=True))
    with TestClient(app) as client:
        r = client.delete(f"/api/v1/me/notes/{uuid.uuid4()}")

    assert r.status_code == 204


def test_delete_note_missing_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("app.api.v1.notes.delete_user_note", AsyncMock(return_value=False))
    with TestClient(app) as client:
        r = client.delete(f"/api/v1/me/notes/{uuid.uuid4()}")

    assert r.status_code == 404
