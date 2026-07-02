from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import verify_jwt
from app.db.session import get_db
from app.repositories import notes_repo
from app.schemas.notes import NoteIn, NoteOut, NoteUpdate
from app.services.notes_service import (
    NotesLimitExceeded,
    create_user_note,
    delete_user_note,
    update_user_note,
)

router = APIRouter(prefix="/me/notes", tags=["notes"])


def _user_id(auth: dict = Depends(verify_jwt)) -> uuid.UUID:
    """Extract and convert user_id from JWT payload."""
    return uuid.UUID(auth["payload"]["sub"])


@router.get("", response_model=list[NoteOut])
async def list_notes(
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    """Return all notes owned by the signed-in user, newest first."""
    return await notes_repo.list_notes(db, user_id)


@router.post("", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
async def create_note(
    body: NoteIn,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    """Create a new note. Returns 201 with the created resource."""
    try:
        return await create_user_note(db, user_id, body)
    except NotesLimitExceeded as e:
        raise HTTPException(status_code=422, detail=str(e)) from e


@router.get("/{note_id}", response_model=NoteOut)
async def get_note(
    note_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    """Return a single note by ID (must belong to the signed-in user)."""
    note = await notes_repo.get_note(db, note_id, user_id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.patch("/{note_id}", response_model=NoteOut)
async def update_note(
    note_id: uuid.UUID,
    body: NoteUpdate,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    """Partially update a note — only supplied fields are changed (PATCH semantics)."""
    note = await update_user_note(db, note_id, user_id, body)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(
    note_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    """Delete a note. Returns 204 No Content on success."""
    if not await delete_user_note(db, note_id, user_id):
        raise HTTPException(status_code=404, detail="Note not found")
