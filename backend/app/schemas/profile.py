from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ProfileOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    display_name: str | None
    avatar_url: str | None
    created_at: datetime
    is_pro: bool = False


class ProfileUpdate(BaseModel):
    """PATCH /me/profile request body — all fields optional (partial update)."""

    display_name: str | None = Field(None, max_length=100)
    avatar_url: str | None = Field(None, max_length=2048)
