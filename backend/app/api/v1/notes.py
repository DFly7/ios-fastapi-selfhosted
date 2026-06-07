"""Notes CRUD router — demonstrates POST (201), GET, PATCH, DELETE (204) with auth.

Every endpoint requires a valid JWT (`get_authenticated_client`).
RLS on the `notes` table provides a second layer: even if a bug leaked the wrong
user_id into a query, Postgres would reject the row.
"""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auth import AuthenticatedClient, get_authenticated_client
from app.schemas.notes import NoteIn, NoteOut, NoteUpdate
from app.services import notes_service

router = APIRouter(prefix="/me/notes", tags=["notes"])


@router.get("", response_model=list[NoteOut])
async def list_notes(
    auth: AuthenticatedClient = Depends(get_authenticated_client),
) -> list[NoteOut]:
    """Return all notes owned by the signed-in user, newest first."""
    return await notes_service.list_user_notes(auth.client, auth.payload["sub"])


@router.post("", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
async def create_note(
    payload: NoteIn,
    auth: AuthenticatedClient = Depends(get_authenticated_client),
) -> NoteOut:
    """Create a new note. Returns 201 with the created resource."""
    return await notes_service.create_user_note(auth.client, auth.payload["sub"], payload)


@router.get("/{note_id}", response_model=NoteOut)
async def get_note(
    note_id: UUID,
    auth: AuthenticatedClient = Depends(get_authenticated_client),
) -> NoteOut:
    """Return a single note by ID (must belong to the signed-in user)."""
    note = await notes_service.get_user_note(auth.client, note_id, auth.payload["sub"])
    if not note:
        raise HTTPException(status_code=404, detail="Note not found.")
    return note


@router.patch("/{note_id}", response_model=NoteOut)
async def update_note(
    note_id: UUID,
    payload: NoteUpdate,
    auth: AuthenticatedClient = Depends(get_authenticated_client),
) -> NoteOut:
    """Partially update a note — only supplied fields are changed (PATCH semantics)."""
    note = await notes_service.update_user_note(auth.client, note_id, auth.payload["sub"], payload)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found.")
    return note


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(
    note_id: UUID,
    auth: AuthenticatedClient = Depends(get_authenticated_client),
) -> None:
    """Delete a note. Returns 204 No Content on success."""
    deleted = await notes_service.delete_user_note(auth.client, note_id, auth.payload["sub"])
    if not deleted:
        raise HTTPException(status_code=404, detail="Note not found.")
