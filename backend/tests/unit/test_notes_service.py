"""Unit tests for app.services.notes_service.

Demonstrates the service-layer testing pattern from tests/unit/README.md:
each test patches the repository layer so the service is tested in total
isolation — no HTTP server, no real Supabase client.

Pattern: patch `app.services.notes_service.notes_repo` (the module reference
inside the service) so calls to notes_repo.* are intercepted by AsyncMock,
matching the async repo interface.
"""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID

import pytest

from app.schemas.notes import NoteIn, NoteOut, NoteUpdate
from app.services import notes_service

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

USER_ID = UUID("00000000-0000-0000-0000-000000000001")
NOTE_ID = UUID("00000000-0000-0000-0000-000000000002")
_NOW = datetime(2026, 1, 1, tzinfo=UTC)

_SAMPLE_NOTE = NoteOut(
    id=NOTE_ID,
    user_id=USER_ID,
    title="Sample note",
    body="Hello",
    created_at=_NOW,
    updated_at=_NOW,
)


@pytest.fixture
def mock_client() -> MagicMock:
    return MagicMock()


# ---------------------------------------------------------------------------
# list_user_notes
# ---------------------------------------------------------------------------


class TestListUserNotes:
    async def test_delegates_to_repo_with_correct_args(self, mock_client: MagicMock) -> None:
        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.list_notes = AsyncMock(return_value=[_SAMPLE_NOTE])

            result = await notes_service.list_user_notes(mock_client, USER_ID)

            mock_repo.list_notes.assert_called_once_with(mock_client, USER_ID)
            assert result == [_SAMPLE_NOTE]

    async def test_returns_empty_list_when_repo_returns_none_data(
        self, mock_client: MagicMock
    ) -> None:
        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.list_notes = AsyncMock(return_value=[])

            result = await notes_service.list_user_notes(mock_client, USER_ID)

            assert result == []


# ---------------------------------------------------------------------------
# get_user_note
# ---------------------------------------------------------------------------


class TestGetUserNote:
    async def test_returns_note_when_found(self, mock_client: MagicMock) -> None:
        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.get_note = AsyncMock(return_value=_SAMPLE_NOTE)

            result = await notes_service.get_user_note(mock_client, NOTE_ID, USER_ID)

            mock_repo.get_note.assert_called_once_with(mock_client, NOTE_ID, USER_ID)
            assert result == _SAMPLE_NOTE

    async def test_returns_none_when_not_found(self, mock_client: MagicMock) -> None:
        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.get_note = AsyncMock(return_value=None)

            result = await notes_service.get_user_note(mock_client, NOTE_ID, USER_ID)

            assert result is None


# ---------------------------------------------------------------------------
# create_user_note
# ---------------------------------------------------------------------------


class TestCreateUserNote:
    async def test_delegates_to_repo_and_returns_created_note(self, mock_client: MagicMock) -> None:
        payload = NoteIn(title="New note", body=None)

        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.count_notes = AsyncMock(return_value=0)
            mock_repo.create_note = AsyncMock(return_value=_SAMPLE_NOTE)

            result = await notes_service.create_user_note(mock_client, USER_ID, payload)

            mock_repo.create_note.assert_called_once_with(mock_client, USER_ID, payload)
            assert result == _SAMPLE_NOTE

    async def test_payload_title_and_body_are_forwarded(self, mock_client: MagicMock) -> None:
        payload = NoteIn(title="Title", body="Body text")

        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.count_notes = AsyncMock(return_value=0)
            mock_repo.create_note = AsyncMock(return_value=_SAMPLE_NOTE)
            await notes_service.create_user_note(mock_client, USER_ID, payload)

            _, _, forwarded_payload = mock_repo.create_note.call_args[0]
            assert forwarded_payload.title == "Title"
            assert forwarded_payload.body == "Body text"


# ---------------------------------------------------------------------------
# update_user_note
# ---------------------------------------------------------------------------


class TestUpdateUserNote:
    async def test_delegates_to_repo_and_returns_updated_note(self, mock_client: MagicMock) -> None:
        payload = NoteUpdate(title="Updated")

        with patch("app.services.notes_service.notes_repo") as mock_repo:
            updated = NoteOut(**{**_SAMPLE_NOTE.model_dump(), "title": "Updated"})
            mock_repo.update_note = AsyncMock(return_value=updated)

            result = await notes_service.update_user_note(mock_client, NOTE_ID, USER_ID, payload)

            mock_repo.update_note.assert_called_once_with(mock_client, NOTE_ID, USER_ID, payload)
            assert result is not None
            assert result.title == "Updated"

    async def test_returns_none_when_note_not_found(self, mock_client: MagicMock) -> None:
        payload = NoteUpdate(title="Ghost")

        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.update_note = AsyncMock(return_value=None)

            result = await notes_service.update_user_note(mock_client, NOTE_ID, USER_ID, payload)

            assert result is None


# ---------------------------------------------------------------------------
# delete_user_note
# ---------------------------------------------------------------------------


class TestDeleteUserNote:
    async def test_returns_true_when_note_deleted(self, mock_client: MagicMock) -> None:
        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.delete_note = AsyncMock(return_value=True)

            result = await notes_service.delete_user_note(mock_client, NOTE_ID, USER_ID)

            mock_repo.delete_note.assert_called_once_with(mock_client, NOTE_ID, USER_ID)
            assert result is True

    async def test_returns_false_when_note_not_found(self, mock_client: MagicMock) -> None:
        with patch("app.services.notes_service.notes_repo") as mock_repo:
            mock_repo.delete_note = AsyncMock(return_value=False)

            result = await notes_service.delete_user_note(mock_client, NOTE_ID, USER_ID)

            assert result is False
