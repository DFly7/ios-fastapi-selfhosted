from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Note
from app.exceptions import NotesLimitExceeded
from app.repositories import notes_repo
from app.schemas.notes import NoteIn, NoteUpdate

MAX_NOTES_PER_USER = 5


async def list_user_notes(db: AsyncSession, user_id: uuid.UUID) -> list[Note]:
    """Return all notes owned by *user_id*."""
    return await notes_repo.list_notes(db, user_id)


async def get_user_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> Note | None:
    """Return a single note by ID if it belongs to *user_id*."""
    return await notes_repo.get_note(db, note_id, user_id)


async def create_user_note(db: AsyncSession, user_id: uuid.UUID, data: NoteIn) -> Note:
    """Create a new note, enforcing the per-user limit."""
    current = await notes_repo.count_notes(db, user_id)
    if current >= MAX_NOTES_PER_USER:
        raise NotesLimitExceeded(MAX_NOTES_PER_USER)
    return await notes_repo.create_note(db, user_id, data)


async def update_user_note(
    db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID, data: NoteUpdate
) -> Note | None:
    """Update a note if it belongs to *user_id*."""
    return await notes_repo.update_note(db, note_id, user_id, data)


async def delete_user_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    """Delete a note if it belongs to *user_id*."""
    return await notes_repo.delete_note(db, note_id, user_id)
