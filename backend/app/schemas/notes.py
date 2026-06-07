from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class NoteIn(BaseModel):
    """POST /me/notes request body."""

    title: str = Field(..., min_length=1, max_length=255)
    body: str | None = None


class NoteUpdate(BaseModel):
    """PATCH /me/notes/{id} request body — all fields optional (partial update)."""

    title: str | None = Field(None, min_length=1, max_length=255)
    body: str | None = None


class NoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    title: str
    body: str | None
    created_at: datetime
    updated_at: datetime
