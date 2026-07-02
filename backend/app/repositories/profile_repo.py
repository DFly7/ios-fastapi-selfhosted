from __future__ import annotations

import uuid

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Profile
from app.schemas.profile import ProfileUpdate


async def get_profile(db: AsyncSession, user_id: uuid.UUID) -> Profile | None:
    result = await db.execute(select(Profile).where(Profile.id == user_id))
    return result.scalar_one_or_none()


async def create_profile(
    db: AsyncSession, user_id: uuid.UUID, display_name: str | None = None
) -> Profile:
    profile = Profile(id=user_id, display_name=display_name)
    db.add(profile)
    await db.flush()
    return profile


async def update_profile(
    db: AsyncSession, user_id: uuid.UUID, data: ProfileUpdate
) -> Profile | None:
    values = data.model_dump(exclude_unset=True, exclude={"is_pro"})
    if values:
        await db.execute(update(Profile).where(Profile.id == user_id).values(**values))
        await db.flush()
    return await get_profile(db, user_id)


async def set_pro_status(db: AsyncSession, user_id: uuid.UUID, *, is_pro: bool) -> None:
    await db.execute(update(Profile).where(Profile.id == user_id).values(is_pro=is_pro))
    await db.flush()
