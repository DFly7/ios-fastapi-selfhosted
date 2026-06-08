from __future__ import annotations

import uuid

from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Note
from app.schemas.notes import NoteIn, NoteUpdate


async def count_notes(db: AsyncSession, user_id: uuid.UUID) -> int:
    """Return the number of notes owned by *user_id* without fetching row data."""
    result = await db.execute(select(func.count()).where(Note.user_id == user_id))
    return result.scalar_one()


async def list_notes(db: AsyncSession, user_id: uuid.UUID) -> list[Note]:
    """Return all notes owned by *user_id*, ordered newest first."""
    result = await db.execute(
        select(Note).where(Note.user_id == user_id).order_by(Note.created_at.desc())
    )
    return list(result.scalars().all())


async def get_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> Note | None:
    """Return a single note by ID if it belongs to *user_id*."""
    result = await db.execute(
        select(Note).where(Note.id == note_id, Note.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def create_note(db: AsyncSession, user_id: uuid.UUID, data: NoteIn) -> Note:
    """Create and persist a new note."""
    note = Note(user_id=user_id, **data.model_dump())
    db.add(note)
    await db.commit()
    await db.refresh(note)
    return note


async def update_note(
    db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID, data: NoteUpdate
) -> Note | None:
    """Update a note if it belongs to *user_id*. Returns the updated note or None."""
    values = data.model_dump(exclude_unset=True)
    if values:
        await db.execute(
            update(Note).where(Note.id == note_id, Note.user_id == user_id).values(**values)
        )
        await db.commit()
    return await get_note(db, note_id, user_id)


async def delete_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    """Delete a note if it belongs to *user_id*. Returns True if a row was deleted."""
    result = await db.execute(
        delete(Note).where(Note.id == note_id, Note.user_id == user_id)
    )
    await db.commit()
    return result.rowcount > 0
