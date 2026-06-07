# Service layer for notes.
# Pattern: one file per use-case / aggregate.
# Services orchestrate one or more repositories and contain business logic.
# Keep repository calls here so routers stay thin (validate input → call service → return schema).
#
# Add further business rules here rather than in the router or repo, for example:
#   - strip / sanitise note content before persistence
#   - fan out to a notification or search-index service after a write

from uuid import UUID

from supabase import AsyncClient

from app.exceptions import NotesLimitExceeded
from app.repositories import notes_repo
from app.schemas.notes import NoteIn, NoteOut, NoteUpdate

MAX_NOTES_PER_USER = 5


async def list_user_notes(client: AsyncClient, user_id: UUID) -> list[NoteOut]:
    return await notes_repo.list_notes(client, user_id)


async def get_user_note(client: AsyncClient, note_id: UUID, user_id: UUID) -> NoteOut | None:
    return await notes_repo.get_note(client, note_id, user_id)


async def create_user_note(client: AsyncClient, user_id: UUID, payload: NoteIn) -> NoteOut:
    current = await notes_repo.count_notes(client, user_id)
    if current >= MAX_NOTES_PER_USER:
        raise NotesLimitExceeded(MAX_NOTES_PER_USER)
    return await notes_repo.create_note(client, user_id, payload)


async def update_user_note(
    client: AsyncClient, note_id: UUID, user_id: UUID, payload: NoteUpdate
) -> NoteOut | None:
    return await notes_repo.update_note(client, note_id, user_id, payload)


async def delete_user_note(client: AsyncClient, note_id: UUID, user_id: UUID) -> bool:
    return await notes_repo.delete_note(client, note_id, user_id)
