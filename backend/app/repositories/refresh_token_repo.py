from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import RefreshToken


async def create_refresh_token(
    db: AsyncSession, user_id: uuid.UUID, token_hash: str, expires_at: datetime
) -> RefreshToken:
    rt = RefreshToken(user_id=user_id, token_hash=token_hash, expires_at=expires_at)
    db.add(rt)
    await db.flush()
    await db.refresh(rt)
    return rt


async def get_by_hash(db: AsyncSession, token_hash: str) -> RefreshToken | None:
    result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    return result.scalar_one_or_none()


async def delete_by_hash(db: AsyncSession, token_hash: str) -> None:
    await db.execute(delete(RefreshToken).where(RefreshToken.token_hash == token_hash))


async def delete_expired(db: AsyncSession) -> None:
    await db.execute(delete(RefreshToken).where(RefreshToken.expires_at < datetime.now(UTC)))
