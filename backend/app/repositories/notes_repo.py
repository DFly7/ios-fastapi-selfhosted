# Repository for the `notes` table.
# Pattern: accept a Supabase AsyncClient as the first argument so the caller controls
# the security context (user-scoped JWT client vs server-side service-role client).
# Each function maps 1-to-1 to a database operation; business logic lives in the service.

from uuid import UUID

from postgrest import CountMethod
from supabase import AsyncClient

from app.schemas.notes import NoteIn, NoteOut, NoteUpdate

_SELECT = "id, user_id, title, body, created_at, updated_at"


async def count_notes(client: AsyncClient, user_id: UUID) -> int:
    """Return the number of notes owned by *user_id* without fetching row data."""
    res = await (
        client.table("notes")
        .select("*", count=CountMethod.exact)
        .eq("user_id", str(user_id))
        .limit(0)
        .execute()
    )
    return res.count or 0


async def list_notes(client: AsyncClient, user_id: UUID) -> list[NoteOut]:
    res = await (
        client.table("notes")
        .select(_SELECT)
        .eq("user_id", str(user_id))
        .order("created_at", desc=True)
        .execute()
    )
    return [NoteOut.model_validate(row) for row in (res.data or [])]


async def get_note(client: AsyncClient, note_id: UUID, user_id: UUID) -> NoteOut | None:
    res = await (
        client.table("notes")
        .select(_SELECT)
        .eq("id", str(note_id))
        .eq("user_id", str(user_id))
        .limit(1)
        .execute()
    )
    rows = res.data or []
    return NoteOut.model_validate(rows[0]) if rows else None


async def create_note(client: AsyncClient, user_id: UUID, payload: NoteIn) -> NoteOut:
    res = await (
        client.table("notes")
        .insert({"user_id": str(user_id), "title": payload.title, "body": payload.body})
        .execute()
    )
    return NoteOut.model_validate(res.data[0])


async def update_note(
    client: AsyncClient, note_id: UUID, user_id: UUID, payload: NoteUpdate
) -> NoteOut | None:
    changes = payload.model_dump(exclude_none=True)
    if not changes:
        return await get_note(client, note_id, user_id)
    res = await (
        client.table("notes")
        .update(changes)
        .eq("id", str(note_id))
        .eq("user_id", str(user_id))
        .execute()
    )
    rows = res.data or []
    return NoteOut.model_validate(rows[0]) if rows else None


async def delete_note(client: AsyncClient, note_id: UUID, user_id: UUID) -> bool:
    res = await (
        client.table("notes").delete().eq("id", str(note_id)).eq("user_id", str(user_id)).execute()
    )
    return bool(res.data)
