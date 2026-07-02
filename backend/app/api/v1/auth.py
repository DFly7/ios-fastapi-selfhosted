from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import structlog
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import verify_jwt
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.db.session import get_db
from app.repositories import profile_repo, refresh_token_repo, user_repo
from app.schemas.auth import LoginRequest, RefreshRequest, RegisterRequest, TokenResponse, UserOut
from app.services.auth_service import (
    create_access_token,
    create_refresh_token_value,
    hash_password,
    hash_refresh_token,
    verify_password,
)

logger = structlog.get_logger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])
_settings = get_settings()


def _make_token_response(db: AsyncSession, user_id: uuid.UUID):
    access = create_access_token(user_id)
    raw_refresh = create_refresh_token_value()
    rt_hash = hash_refresh_token(raw_refresh)
    expires_at = datetime.now(UTC) + timedelta(seconds=_settings.jwt_refresh_token_expire_seconds)
    return TokenResponse(access_token=access, refresh_token=raw_refresh), rt_hash, expires_at


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
async def register(request: Request, body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    existing = await user_repo.get_by_email(db, body.email)
    if existing:
        raise HTTPException(status_code=409, detail="Email already registered")

    hashed = hash_password(body.password)
    user = await user_repo.create_user(db, body.email, hashed)
    await profile_repo.create_profile(db, user.id, display_name=body.display_name)

    token_resp, rt_hash, expires_at = _make_token_response(db, user.id)
    await refresh_token_repo.create_refresh_token(db, user.id, rt_hash, expires_at)
    logger.info("user_registered", user_id=str(user.id))
    return token_resp


@router.post("/token", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login(request: Request, body: LoginRequest, db: AsyncSession = Depends(get_db)):
    user = await user_repo.get_by_email(db, body.email)
    if not user or not verify_password(body.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")

    token_resp, rt_hash, expires_at = _make_token_response(db, user.id)
    await refresh_token_repo.create_refresh_token(db, user.id, rt_hash, expires_at)
    logger.info("user_logged_in", user_id=str(user.id))
    return token_resp


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("5/minute")
async def refresh(request: Request, body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    rt_hash = hash_refresh_token(body.refresh_token)
    stored = await refresh_token_repo.get_by_hash(db, rt_hash)
    if not stored or stored.expires_at.replace(tzinfo=UTC) < datetime.now(UTC):
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    await refresh_token_repo.delete_by_hash(db, rt_hash)
    token_resp, new_hash, expires_at = _make_token_response(db, stored.user_id)
    await refresh_token_repo.create_refresh_token(db, stored.user_id, new_hash, expires_at)
    return token_resp


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    rt_hash = hash_refresh_token(body.refresh_token)
    await refresh_token_repo.delete_by_hash(db, rt_hash)


@router.get("/me", response_model=UserOut)
async def me(auth: dict = Depends(verify_jwt), db: AsyncSession = Depends(get_db)):
    user_id = uuid.UUID(auth["payload"]["sub"])
    user = await user_repo.get_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserOut(id=str(user.id), email=user.email)
