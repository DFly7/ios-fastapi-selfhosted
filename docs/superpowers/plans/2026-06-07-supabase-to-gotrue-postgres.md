# Supabase → Self-Hosted FastAPI Auth + PostgreSQL Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all Supabase dependencies with a self-contained FastAPI backend that owns auth (JWT issued directly) + PostgreSQL for data — the smallest possible footprint for a Raspberry Pi, with no GoTrue, no nginx proxy, and no Supabase SDK on iOS.

**Architecture:** FastAPI issues HS256 JWTs from its own `/auth/register` and `/auth/token` endpoints. PostgreSQL stores users, profiles, notes. Alembic manages migrations. iOS `AuthService.swift` is rewritten to call FastAPI directly via URLSession — same public interface (`isAuthenticated`, `userId`, `accessToken`, `signIn`, `signOut`, `register`), so no other Swift files change. Single Docker Compose: `db` + `backend` + `adminer` (lightweight DB UI). No nginx, no GoTrue, no Supabase SDK dependency anywhere.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2 (async), asyncpg, Alembic, PyJWT (HS256), Passlib (bcrypt), PostgreSQL 17, Adminer, Docker Compose, Swift + URLSession + Keychain (replaces Supabase Swift SDK for auth), Fastlane, GitHub Actions.

---

## File Map

### Deleted
- `supabase/` — entire directory
- `.github/workflows/supabase-migrations.yml`
- `backend/docker-compose.yml`

### Created
- `docker-compose.yml` — Postgres + backend + adminer
- `.env.example` — root-level env vars
- `backend/app/db/__init__.py`
- `backend/app/db/base.py` — SQLAlchemy DeclarativeBase
- `backend/app/db/models.py` — User, Profile, Note, Waitlist ORM models
- `backend/app/db/session.py` — async engine, `get_db` dependency
- `backend/app/api/v1/auth.py` — `/auth/register`, `/auth/token`, `/auth/refresh`, `/auth/me`
- `backend/app/repositories/user_repo.py` — user CRUD
- `backend/app/repositories/profile_repo.py` — profile CRUD
- `backend/app/services/auth_service.py` — password hashing, JWT issuance, token verification
- `backend/alembic.ini`
- `backend/alembic/env.py`
- `backend/alembic/versions/001_initial_schema.py`
- `backend/alembic/versions/002_add_is_pro.py`
- `ios/StarterApp/StarterApp/Services/AuthService.swift` — full rewrite (same public interface)
- `ios/StarterApp/StarterApp/Services/KeychainTokenStore.swift` — JWT + refresh token Keychain storage

### Modified
- `backend/pyproject.toml` — remove supabase/postgrest, add sqlalchemy/asyncpg/alembic/passlib
- `backend/.env.example` — replace SUPABASE_* with DATABASE_URL, JWT_SECRET
- `backend/app/core/config.py` — new settings fields
- `backend/app/core/auth.py` — HS256 verify_jwt, remove JWKS/supabase-py
- `backend/app/main.py` — lifespan: dispose SQLAlchemy engine
- `backend/app/api/v1/router.py` — include auth router, swap deps to get_db + verify_jwt
- `backend/app/api/v1/notes.py` — use AsyncSession dependency
- `backend/app/api/v1/webhooks.py` — RevenueCat uses SQLAlchemy (remove service-role pattern)
- `backend/app/repositories/notes_repo.py` — full SQLAlchemy rewrite
- `backend/app/services/notes_service.py` — AsyncSession instead of AsyncClient
- `backend/tests/conftest.py` — SQLAlchemy fixtures
- `backend/tests/integration/conftest.py` — Postgres-only test setup
- `backend/tests/integration/test_profile_flow.py` — rewrite for SQLAlchemy
- `backend/tests/integration/test_notes_flow.py` — rewrite for SQLAlchemy
- `backend/tests/api/jwt_route_helpers.py` — HS256 token generation
- `ios/StarterApp/StarterApp/StarterAppApp.swift` — remove SupabaseClient init
- `ios/StarterApp/Config.example.xcconfig` — remove SUPABASE_URL/SUPABASE_ANON_KEY
- `Makefile` — remove supabase targets, simplify dev stack
- `.github/workflows/backend-integration.yml` — postgres service, no supabase start
- `README.md` — update stack and quick-start

---

## Task 1: Delete Supabase artefacts and create Docker Compose

**Files:**
- Delete: `supabase/`, `.github/workflows/supabase-migrations.yml`, `backend/docker-compose.yml`
- Create: `docker-compose.yml`, `.env.example`

- [ ] **Step 1: Delete Supabase artefacts**

```bash
rm -rf supabase/
rm -f .github/workflows/supabase-migrations.yml
rm -f backend/docker-compose.yml
```

- [ ] **Step 2: Create `.env.example` at repo root**

```dotenv
# ── Auth ─────────────────────────────────────────────────────────────────────
# Generate: openssl rand -hex 32
JWT_SECRET=change-me-generate-with-openssl-rand-hex-32

# Access token lifetime in seconds (default 3600 = 1 hour)
JWT_ACCESS_TOKEN_EXPIRE_SECONDS=3600

# Refresh token lifetime in seconds (default 2592000 = 30 days)
JWT_REFRESH_TOKEN_EXPIRE_SECONDS=2592000

# ── Database ──────────────────────────────────────────────────────────────────
POSTGRES_PASSWORD=postgres

# ── Backend ───────────────────────────────────────────────────────────────────
APP_NAME=Starter API
ENVIRONMENT=development
ALLOWED_ORIGINS=*

# Optional
SENTRY_DSN=
REVENUECAT_WEBHOOK_SECRET=
RESEND_API_KEY=
```

- [ ] **Step 3: Create `docker-compose.yml`**

```yaml
services:

  db:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 10

  backend:
    build:
      context: ./backend
      target: production
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql+asyncpg://postgres:${POSTGRES_PASSWORD:-postgres}@db:5432/postgres
      JWT_SECRET: ${JWT_SECRET}
      JWT_ACCESS_TOKEN_EXPIRE_SECONDS: ${JWT_ACCESS_TOKEN_EXPIRE_SECONDS:-3600}
      JWT_REFRESH_TOKEN_EXPIRE_SECONDS: ${JWT_REFRESH_TOKEN_EXPIRE_SECONDS:-2592000}
      APP_NAME: ${APP_NAME:-Starter API}
      ENVIRONMENT: ${ENVIRONMENT:-production}
      ALLOWED_ORIGINS: ${ALLOWED_ORIGINS:-*}
      SENTRY_DSN: ${SENTRY_DSN:-}
      REVENUECAT_WEBHOOK_SECRET: ${REVENUECAT_WEBHOOK_SECRET:-}
      RESEND_API_KEY: ${RESEND_API_KEY:-}
    ports:
      - "8000:8000"

  adminer:
    image: adminer:latest
    restart: unless-stopped
    depends_on:
      - db
    ports:
      - "8080:8080"

volumes:
  postgres_data:
```

Adminer is a lightweight (~500KB) DB admin UI — open `http://localhost:8080`, login with System=PostgreSQL, Server=db, User=postgres, Password=postgres.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml .env.example .github/workflows/
git rm -r supabase/ backend/docker-compose.yml
git commit -m "chore: replace Supabase with self-contained FastAPI + Postgres docker-compose"
```

---

## Task 2: Update Python dependencies

**Files:**
- Modify: `backend/pyproject.toml`

- [ ] **Step 1: Update `[project.dependencies]` in `backend/pyproject.toml`**

Remove:
```
supabase>=2.24.0
postgrest>=2.24.0
```

Add:
```
sqlalchemy[asyncio]>=2.0.36
asyncpg>=0.30.0
alembic>=1.14.0
passlib[bcrypt]>=1.7.4
```

`PyJWT`, `cryptography`, and `httpx` entries stay.

- [ ] **Step 2: Install**

```bash
cd backend && uv sync
```

Expected: resolves without supabase/postgrest errors.

- [ ] **Step 3: Commit**

```bash
git add backend/pyproject.toml backend/uv.lock
git commit -m "chore: swap supabase-py for sqlalchemy + asyncpg + alembic + passlib"
```

---

## Task 3: SQLAlchemy models and session

**Files:**
- Create: `backend/app/db/__init__.py`, `backend/app/db/base.py`, `backend/app/db/models.py`, `backend/app/db/session.py`

- [ ] **Step 1: Create `backend/app/db/__init__.py`**

```python
```
(empty)

- [ ] **Step 2: Create `backend/app/db/base.py`**

```python
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
```

- [ ] **Step 3: Create `backend/app/db/models.py`**

```python
from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class User(Base):
    """Auth identity — email + hashed password. One-to-one with Profile."""

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true", nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class Profile(Base):
    """User-facing profile data."""

    __tablename__ = "profiles"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    display_name: Mapped[str | None] = mapped_column(String(255))
    avatar_url: Mapped[str | None] = mapped_column(Text)
    is_pro: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class Note(Base):
    __tablename__ = "notes"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class RefreshToken(Base):
    """Stored refresh tokens — deleted on logout or rotation."""

    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class Waitlist(Base):
    __tablename__ = "waitlist"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    phone: Mapped[str | None] = mapped_column(String(50))
    ip_address: Mapped[str | None] = mapped_column(String(45))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
```

- [ ] **Step 4: Create `backend/app/db/session.py`**

```python
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

_settings = get_settings()

engine = create_async_engine(
    str(_settings.database_url),
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
```

- [ ] **Step 5: Commit**

```bash
git add backend/app/db/
git commit -m "feat: add SQLAlchemy models (User, Profile, Note, RefreshToken, Waitlist) and session"
```

---

## Task 4: Alembic setup and migrations

**Files:**
- Create: `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/versions/001_initial_schema.py`, `backend/alembic/versions/002_add_is_pro.py`

- [ ] **Step 1: Initialise Alembic**

```bash
cd backend && uv run alembic init alembic
```

- [ ] **Step 2: Update `backend/alembic.ini` — set default URL**

Find and replace:
```
sqlalchemy.url = driver://user:pass@localhost/dbname
```
With:
```
sqlalchemy.url = postgresql+asyncpg://postgres:postgres@localhost:5432/postgres
```

- [ ] **Step 3: Replace `backend/alembic/env.py`**

```python
import asyncio
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app.db.base import Base
from app.db import models  # noqa: F401

config = context.config
if config.config_file_name:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _db_url() -> str:
    return os.environ.get("DATABASE_URL") or config.get_main_option("sqlalchemy.url", "")


def run_migrations_offline() -> None:
    context.configure(
        url=_db_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    engine = create_async_engine(_db_url())
    async with engine.begin() as conn:
        await conn.run_sync(
            lambda sync_conn: context.configure(
                connection=sync_conn,
                target_metadata=target_metadata,
            )
        )
        await conn.run_sync(lambda c: context.run_migrations())
    await engine.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

- [ ] **Step 4: Create `backend/alembic/versions/001_initial_schema.py`**

```python
"""Initial schema: users, profiles, notes, refresh_tokens, waitlist

Revision ID: 001
Revises:
Create Date: 2026-06-07
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), unique=True, nullable=False),
        sa.Column("hashed_password", sa.String(255), nullable=False),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("users_email_idx", "users", ["email"])

    op.create_table(
        "profiles",
        sa.Column("id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("display_name", sa.String(255), nullable=True),
        sa.Column("avatar_url", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        "notes",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("body", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("notes_user_id_idx", "notes", ["user_id"])

    op.create_table(
        "refresh_tokens",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.String(64), unique=True, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("refresh_tokens_user_id_idx", "refresh_tokens", ["user_id"])

    op.create_table(
        "waitlist",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(255), unique=True, nullable=False),
        sa.Column("phone", sa.String(50), nullable=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("waitlist")
    op.drop_index("refresh_tokens_user_id_idx", "refresh_tokens")
    op.drop_table("refresh_tokens")
    op.drop_index("notes_user_id_idx", "notes")
    op.drop_table("notes")
    op.drop_table("profiles")
    op.drop_index("users_email_idx", "users")
    op.drop_table("users")
```

- [ ] **Step 5: Create `backend/alembic/versions/002_add_is_pro.py`**

```python
"""Add is_pro to profiles

Revision ID: 002
Revises: 001
Create Date: 2026-06-07
"""

from alembic import op
import sqlalchemy as sa

revision = "002"
down_revision = "001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column("is_pro", sa.Boolean, nullable=False, server_default="false"),
    )


def downgrade() -> None:
    op.drop_column("profiles", "is_pro")
```

- [ ] **Step 6: Verify migrations**

```bash
cd backend
docker run -d --name pg-test -e POSTGRES_PASSWORD=postgres -p 5433:5432 postgres:17-alpine
sleep 3
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5433/postgres uv run alembic upgrade head
```

Expected:
```
INFO  [alembic.runtime.migration] Running upgrade  -> 001, Initial schema ...
INFO  [alembic.runtime.migration] Running upgrade 001 -> 002, Add is_pro ...
```

```bash
docker rm -f pg-test
```

- [ ] **Step 7: Commit**

```bash
git add backend/alembic.ini backend/alembic/
git commit -m "feat: Alembic migrations — users, profiles, notes, refresh_tokens, waitlist"
```

---

## Task 5: Update config.py

**Files:**
- Modify: `backend/app/core/config.py`, `backend/.env.example`

- [ ] **Step 1: Update `backend/app/core/config.py`**

Remove these fields from `Settings`:
```python
supabase_url: AnyUrl | None = None
supabase_public_anon_key: str | None = None
supabase_service_role_key: str | None = None
```

Add:
```python
database_url: AnyUrl = Field(..., description="asyncpg DSN")
jwt_secret: str = Field(..., description="HS256 signing secret — min 32 chars")
jwt_access_token_expire_seconds: int = 3600
jwt_refresh_token_expire_seconds: int = 2_592_000  # 30 days
```

- [ ] **Step 2: Update `backend/.env.example`**

Replace:
```dotenv
SUPABASE_URL=http://host.docker.internal:54321
SUPABASE_PUBLIC_ANON_KEY=your-anon-key-here
```

With:
```dotenv
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres
JWT_SECRET=change-me-generate-with-openssl-rand-hex-32
JWT_ACCESS_TOKEN_EXPIRE_SECONDS=3600
JWT_REFRESH_TOKEN_EXPIRE_SECONDS=2592000
```

- [ ] **Step 3: Smoke-test config loads**

```bash
cd backend
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres \
JWT_SECRET=testsecretatleast32charslong1234 \
uv run python -c "from app.core.config import get_settings; print(get_settings().jwt_secret)"
```

Expected: `testsecretatleast32charslong1234`

- [ ] **Step 4: Commit**

```bash
git add backend/app/core/config.py backend/.env.example
git commit -m "feat: replace Supabase config with database_url + jwt_secret settings"
```

---

## Task 6: Auth service (password hashing + JWT issuance)

**Files:**
- Create: `backend/app/services/auth_service.py`
- Modify: `backend/app/core/auth.py`

- [ ] **Step 1: Create `backend/app/services/auth_service.py`**

```python
from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from passlib.context import CryptContext

from app.core.config import get_settings

_settings = get_settings()
_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plain: str) -> str:
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd_context.verify(plain, hashed)


def _make_jwt(sub: str, expire_seconds: int, token_type: str) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {
            "sub": sub,
            "aud": "authenticated",
            "type": token_type,
            "iat": now,
            "exp": now + timedelta(seconds=expire_seconds),
        },
        _settings.jwt_secret,
        algorithm="HS256",
    )


def create_access_token(user_id: uuid.UUID) -> str:
    return _make_jwt(str(user_id), _settings.jwt_access_token_expire_seconds, "access")


def create_refresh_token_value() -> str:
    """Returns a raw random token (stored hashed in DB)."""
    return secrets.token_urlsafe(48)


def hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        _settings.jwt_secret,
        algorithms=["HS256"],
        audience="authenticated",
    )
```

- [ ] **Step 2: Rewrite `backend/app/core/auth.py`**

```python
from typing import Any

import jwt
import structlog
from fastapi import Depends, HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.services.auth_service import decode_access_token

logger = structlog.get_logger(__name__)

http_bearer = HTTPBearer(auto_error=False, scheme_name="BearerAuth", bearerFormat="JWT")


async def verify_jwt(
    credentials: HTTPAuthorizationCredentials | None = Security(http_bearer),
) -> dict[str, Any]:
    if not credentials:
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    try:
        payload = decode_access_token(credentials.credentials)
        if payload.get("type") != "access":
            raise HTTPException(status_code=401, detail="Not an access token")
        return {"token": credentials.credentials, "payload": payload}
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired") from None
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}") from e
```

- [ ] **Step 3: Write failing tests**

Create `backend/tests/unit/test_auth_service.py`:

```python
import pytest
from app.services.auth_service import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token_value,
    hash_refresh_token,
    decode_access_token,
)
import uuid


def test_password_round_trip():
    hashed = hash_password("secret123")
    assert verify_password("secret123", hashed)
    assert not verify_password("wrong", hashed)


def test_access_token_decode():
    uid = uuid.uuid4()
    token = create_access_token(uid)
    payload = decode_access_token(token)
    assert payload["sub"] == str(uid)
    assert payload["type"] == "access"


def test_refresh_token_hash_is_deterministic():
    raw = create_refresh_token_value()
    assert hash_refresh_token(raw) == hash_refresh_token(raw)


def test_refresh_token_hash_differs_from_raw():
    raw = create_refresh_token_value()
    assert hash_refresh_token(raw) != raw
```

- [ ] **Step 4: Suppress passlib/bcrypt deprecation warning on Python 3.12**

`passlib` emits a `DeprecationWarning` on Python 3.12 because it introspects `bcrypt`'s internal version attribute that was removed in `bcrypt>=4.0`. Silence it at the module level in `auth_service.py` — add these two lines directly above the `CryptContext` instantiation:

```python
import warnings
warnings.filterwarnings("ignore", ".*error reading bcrypt version.*", append=True)

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
```

Also pin `bcrypt>=4.0.1` in `backend/pyproject.toml` (the version that removed the attribute but works correctly with passlib when the warning is suppressed):

```toml
bcrypt>=4.0.1
```

Run `uv sync` after adding the pin.

- [ ] **Step 5: Run tests**

```bash
cd backend
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost/postgres \
JWT_SECRET=testsecretatleast32charslong1234 \
uv run pytest tests/unit/test_auth_service.py -v 2>&1 | grep -v DeprecationWarning
```

Expected: 4 PASS, no deprecation noise in output.

- [ ] **Step 6: Commit**

```bash
git add backend/app/services/auth_service.py backend/app/core/auth.py backend/tests/unit/test_auth_service.py backend/pyproject.toml
git commit -m "feat: auth service (bcrypt hashing, HS256 JWT issuance), suppress passlib Python 3.12 warning"
```

---

## Task 7: User and profile repositories

**Files:**
- Create: `backend/app/repositories/user_repo.py`, `backend/app/repositories/profile_repo.py`

- [ ] **Step 1: Create `backend/app/repositories/user_repo.py`**

```python
from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import User


async def get_by_email(db: AsyncSession, email: str) -> User | None:
    result = await db.execute(select(User).where(User.email == email.lower()))
    return result.scalar_one_or_none()


async def get_by_id(db: AsyncSession, user_id: uuid.UUID) -> User | None:
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


async def create_user(db: AsyncSession, email: str, hashed_password: str) -> User:
    user = User(email=email.lower(), hashed_password=hashed_password)
    db.add(user)
    await db.flush()  # get user.id without committing
    return user
```

- [ ] **Step 2: Create `backend/app/repositories/profile_repo.py`**

```python
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
        await db.commit()
    return await get_profile(db, user_id)


async def set_pro_status(db: AsyncSession, user_id: uuid.UUID, *, is_pro: bool) -> None:
    await db.execute(update(Profile).where(Profile.id == user_id).values(is_pro=is_pro))
    await db.commit()
```

- [ ] **Step 3: Create `backend/app/repositories/refresh_token_repo.py`**

```python
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
    await db.commit()
    await db.refresh(rt)
    return rt


async def get_by_hash(db: AsyncSession, token_hash: str) -> RefreshToken | None:
    result = await db.execute(
        select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    )
    return result.scalar_one_or_none()


async def delete_by_hash(db: AsyncSession, token_hash: str) -> None:
    await db.execute(delete(RefreshToken).where(RefreshToken.token_hash == token_hash))
    await db.commit()


async def delete_expired(db: AsyncSession) -> None:
    await db.execute(
        delete(RefreshToken).where(RefreshToken.expires_at < datetime.now(UTC))
    )
    await db.commit()
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/repositories/
git commit -m "feat: user, profile, and refresh_token repositories"
```

---

## Task 8: Auth API endpoints

**Files:**
- Create: `backend/app/api/v1/auth.py`
- Modify: `backend/app/api/v1/router.py`

- [ ] **Step 1: Create `backend/app/api/v1/auth.py`**

```python
from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import verify_jwt
from app.core.config import get_settings
from app.db.session import get_db
from app.repositories import profile_repo, refresh_token_repo, user_repo
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


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


def _make_token_response(db: AsyncSession, user_id: uuid.UUID):
    """Returns (TokenResponse, raw_refresh, hash, expires_at) — caller must persist."""
    access = create_access_token(user_id)
    raw_refresh = create_refresh_token_value()
    rt_hash = hash_refresh_token(raw_refresh)
    expires_at = datetime.now(UTC) + timedelta(
        seconds=_settings.jwt_refresh_token_expire_seconds
    )
    return TokenResponse(access_token=access, refresh_token=raw_refresh), rt_hash, expires_at


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    existing = await user_repo.get_by_email(db, body.email)
    if existing:
        raise HTTPException(status_code=409, detail="Email already registered")

    hashed = hash_password(body.password)
    user = await user_repo.create_user(db, body.email, hashed)
    await profile_repo.create_profile(db, user.id, display_name=body.display_name)
    await db.commit()

    token_resp, rt_hash, expires_at = _make_token_response(db, user.id)
    await refresh_token_repo.create_refresh_token(db, user.id, rt_hash, expires_at)
    logger.info("user_registered", user_id=str(user.id))
    return token_resp


@router.post("/token", response_model=TokenResponse)
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
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
async def refresh(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    rt_hash = hash_refresh_token(body.refresh_token)
    stored = await refresh_token_repo.get_by_hash(db, rt_hash)
    if not stored or stored.expires_at.replace(tzinfo=UTC) < datetime.now(UTC):
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    await refresh_token_repo.delete_by_hash(db, rt_hash)  # rotate
    token_resp, new_hash, expires_at = _make_token_response(db, stored.user_id)
    await refresh_token_repo.create_refresh_token(db, stored.user_id, new_hash, expires_at)
    return token_resp


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    rt_hash = hash_refresh_token(body.refresh_token)
    await refresh_token_repo.delete_by_hash(db, rt_hash)


@router.get("/me")
async def me(auth: dict = Depends(verify_jwt), db: AsyncSession = Depends(get_db)):
    user_id = uuid.UUID(auth["payload"]["sub"])
    user = await user_repo.get_by_id(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {"id": str(user.id), "email": user.email}
```

- [ ] **Step 2: Include auth router in `backend/app/api/v1/router.py`**

At the top of `router.py`, add:
```python
from app.api.v1 import auth as auth_router
```

In the router setup section, add:
```python
router.include_router(auth_router.router)
```

- [ ] **Step 3: Write integration tests for auth endpoints**

Create `backend/tests/integration/test_auth_flow.py`:

```python
import pytest


@pytest.mark.asyncio
@pytest.mark.integration
async def test_register_and_login(client):
    # Register
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "alice@example.com", "password": "Password123!"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data

    # Login
    resp = await client.post(
        "/api/v1/auth/token",
        json={"email": "alice@example.com", "password": "Password123!"},
    )
    assert resp.status_code == 200

    # Wrong password
    resp = await client.post(
        "/api/v1/auth/token",
        json={"email": "alice@example.com", "password": "wrong"},
    )
    assert resp.status_code == 401

    # Duplicate email
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "alice@example.com", "password": "other"},
    )
    assert resp.status_code == 409


@pytest.mark.asyncio
@pytest.mark.integration
async def test_refresh_token_rotation(client):
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "bob@example.com", "password": "Password123!"},
    )
    refresh_token = resp.json()["refresh_token"]

    # Refresh
    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    new_refresh = resp.json()["refresh_token"]
    assert new_refresh != refresh_token

    # Old refresh token is invalid
    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 401


@pytest.mark.asyncio
@pytest.mark.integration
async def test_logout_invalidates_token(client):
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "carol@example.com", "password": "Password123!"},
    )
    refresh_token = resp.json()["refresh_token"]

    await client.post("/api/v1/auth/logout", json={"refresh_token": refresh_token})

    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 401
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/api/v1/auth.py backend/app/api/v1/router.py backend/tests/integration/test_auth_flow.py
git commit -m "feat: auth endpoints — register, login, refresh, logout, /me"
```

---

## Task 9: Rewrite notes repository and service

**Files:**
- Modify: `backend/app/repositories/notes_repo.py`, `backend/app/services/notes_service.py`

- [ ] **Step 1: Rewrite `backend/app/repositories/notes_repo.py`**

```python
from __future__ import annotations

import uuid

from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Note
from app.schemas.notes import NoteIn, NoteUpdate


async def count_notes(db: AsyncSession, user_id: uuid.UUID) -> int:
    result = await db.execute(select(func.count()).where(Note.user_id == user_id))
    return result.scalar_one()


async def list_notes(db: AsyncSession, user_id: uuid.UUID) -> list[Note]:
    result = await db.execute(
        select(Note).where(Note.user_id == user_id).order_by(Note.created_at.desc())
    )
    return list(result.scalars().all())


async def get_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> Note | None:
    result = await db.execute(
        select(Note).where(Note.id == note_id, Note.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def create_note(db: AsyncSession, user_id: uuid.UUID, data: NoteIn) -> Note:
    note = Note(user_id=user_id, **data.model_dump())
    db.add(note)
    await db.commit()
    await db.refresh(note)
    return note


async def update_note(
    db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID, data: NoteUpdate
) -> Note | None:
    values = data.model_dump(exclude_unset=True)
    if values:
        await db.execute(
            update(Note).where(Note.id == note_id, Note.user_id == user_id).values(**values)
        )
        await db.commit()
    return await get_note(db, note_id, user_id)


async def delete_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    result = await db.execute(
        delete(Note).where(Note.id == note_id, Note.user_id == user_id)
    )
    await db.commit()
    return result.rowcount > 0
```

- [ ] **Step 2: Rewrite `backend/app/services/notes_service.py`**

```python
from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Note
from app.repositories import notes_repo
from app.schemas.notes import NoteIn

MAX_NOTES_PER_USER = 5


class NotesLimitExceeded(Exception):
    pass


async def list_user_notes(db: AsyncSession, user_id: uuid.UUID) -> list[Note]:
    return await notes_repo.list_notes(db, user_id)


async def get_user_note(db: AsyncSession, note_id: uuid.UUID, user_id: uuid.UUID) -> Note | None:
    return await notes_repo.get_note(db, note_id, user_id)


async def create_user_note(db: AsyncSession, user_id: uuid.UUID, data: NoteIn) -> Note:
    count = await notes_repo.count_notes(db, user_id)
    if count >= MAX_NOTES_PER_USER:
        raise NotesLimitExceeded(f"Maximum {MAX_NOTES_PER_USER} notes per user")
    return await notes_repo.create_note(db, user_id, data)
```

- [ ] **Step 3: Update `backend/app/api/v1/notes.py`** — swap `get_authenticated_client` for `get_db` + `verify_jwt`

```python
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import verify_jwt
from app.db.session import get_db
from app.repositories import notes_repo
from app.schemas.notes import NoteIn, NoteOut, NoteUpdate
from app.services.notes_service import NotesLimitExceeded, create_user_note

router = APIRouter(prefix="/me/notes", tags=["notes"])


def _user_id(auth: dict = Depends(verify_jwt)) -> uuid.UUID:
    return uuid.UUID(auth["payload"]["sub"])


@router.get("", response_model=list[NoteOut])
async def list_notes(
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    return await notes_repo.list_notes(db, user_id)


@router.post("", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
async def create_note(
    body: NoteIn,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    try:
        return await create_user_note(db, user_id, body)
    except NotesLimitExceeded as e:
        raise HTTPException(status_code=422, detail=str(e))


@router.get("/{note_id}", response_model=NoteOut)
async def get_note(
    note_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
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
    note = await notes_repo.update_note(db, note_id, user_id, body)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.delete("/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_note(
    note_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user_id: uuid.UUID = Depends(_user_id),
):
    if not await notes_repo.delete_note(db, note_id, user_id):
        raise HTTPException(status_code=404, detail="Note not found")
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/repositories/notes_repo.py backend/app/services/notes_service.py backend/app/api/v1/notes.py
git commit -m "feat: rewrite notes repo/service/routes with SQLAlchemy"
```

---

## Task 10: Update router.py profile endpoints and main.py

**Files:**
- Modify: `backend/app/api/v1/router.py`, `backend/app/api/v1/webhooks.py`, `backend/app/main.py`

- [ ] **Step 1: Update profile routes in `backend/app/api/v1/router.py`**

Replace the Supabase-dependent profile GET/PATCH with:

```python
import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.auth import verify_jwt
from app.db.session import get_db
from app.repositories import profile_repo
from app.schemas.profile import ProfileOut, ProfileUpdate

# In the existing router, replace /me/profile handlers:

@router.get("/me/profile", response_model=ProfileOut)
async def get_profile(
    auth: dict = Depends(verify_jwt),
    db: AsyncSession = Depends(get_db),
):
    user_id = uuid.UUID(auth["payload"]["sub"])
    profile = await profile_repo.get_profile(db, user_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@router.patch("/me/profile", response_model=ProfileOut)
async def patch_profile(
    body: ProfileUpdate,
    auth: dict = Depends(verify_jwt),
    db: AsyncSession = Depends(get_db),
):
    user_id = uuid.UUID(auth["payload"]["sub"])
    updated = await profile_repo.update_profile(db, user_id, body)
    if not updated:
        raise HTTPException(status_code=404, detail="Profile not found")
    return updated
```

- [ ] **Step 2: Update RevenueCat webhook in `backend/app/api/v1/webhooks.py`**

Replace the Supabase service-role pattern. Find the block that creates a supabase client and calls `.table("profiles").update(...)` and replace with:

```python
# Add to imports at top of webhooks.py:
from app.db.session import get_db
from app.repositories import profile_repo
from sqlalchemy.ext.asyncio import AsyncSession

# In the RevenueCat webhook handler, add db dependency and replace the update:
# Old: supabase service-role client update
# New:
await profile_repo.set_pro_status(db, uuid.UUID(app_user_id), is_pro=is_pro)
```

Add `db: AsyncSession = Depends(get_db)` to the endpoint signature and remove all supabase client creation code.

- [ ] **Step 3: Update `backend/app/main.py` lifespan**

Remove import of `close_jwk_http_client`. Replace lifespan with:

```python
from contextlib import asynccontextmanager
from app.db.session import engine

@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await engine.dispose()
```

- [ ] **Step 4: Commit**

```bash
git add backend/app/api/v1/router.py backend/app/api/v1/webhooks.py backend/app/main.py
git commit -m "feat: update profile routes and RevenueCat webhook to SQLAlchemy, fix lifespan"
```

---

## Task 11: Rewrite iOS AuthService (remove Supabase SDK)

**Files:**
- Create: `ios/StarterApp/StarterApp/Services/KeychainTokenStore.swift`
- Modify: `ios/StarterApp/StarterApp/Services/AuthService.swift`
- Modify: `ios/StarterApp/StarterApp/StarterAppApp.swift`
- Modify: `ios/StarterApp/Config.example.xcconfig`

- [ ] **Step 1: Create `ios/StarterApp/StarterApp/Services/KeychainTokenStore.swift`**

```swift
import Foundation
import Security

enum KeychainTokenStore {
    private static let accessKey = "dev.starter.accessToken"
    private static let refreshKey = "dev.starter.refreshToken"

    static func save(accessToken: String, refreshToken: String) {
        set(key: accessKey, value: accessToken)
        set(key: refreshKey, value: refreshToken)
    }

    static func loadAccessToken() -> String? { get(key: accessKey) }
    static func loadRefreshToken() -> String? { get(key: refreshKey) }

    static func clear() {
        delete(key: accessKey)
        delete(key: refreshKey)
    }

    private static func set(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        let attrs = query.merging([kSecValueData as String: data]) { $1 }
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 2: Rewrite `ios/StarterApp/StarterApp/Services/AuthService.swift`**

This replaces the Supabase SDK entirely. Same public interface — no other files need changing.

```swift
import Foundation
import Observation
import OSLog
import PostHog

@Observable
@MainActor
final class AuthService {
    private(set) var isAuthenticated = false
    private(set) var userId: UUID?
    private(set) var userEmail: String?
    var isLoading = false
    var errorMessage: String?
    var infoMessage: String?
    private(set) var isCheckingInitialSession = true
    private(set) var accessToken: String?

    private let backendURL: URL

    init(backendURL: URL) {
        self.backendURL = backendURL
        Task { await restoreSession() }
    }

    // MARK: – Session restore

    private func restoreSession() async {
        defer { isCheckingInitialSession = false }
        guard let refresh = KeychainTokenStore.loadRefreshToken() else {
            clearSessionState()
            return
        }
        await performRefresh(refreshToken: refresh)
    }

    // MARK: – Public API

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        do {
            let resp: TokenResponse = try await post(
                path: "/api/v1/auth/token",
                body: ["email": email, "password": password]
            )
            applyTokens(resp)
            AppLog.auth.info("Signed in")
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func register(email: String, password: String) async {
        isLoading = true; errorMessage = nil; infoMessage = nil
        defer { isLoading = false }
        do {
            let resp: TokenResponse = try await post(
                path: "/api/v1/auth/register",
                body: ["email": email, "password": password]
            )
            applyTokens(resp)
            AppLog.auth.info("Registered")
        } catch {
            errorMessage = friendlyMessage(error)
        }
    }

    func signOut() {
        Task {
            if let refresh = KeychainTokenStore.loadRefreshToken() {
                try? await post(path: "/api/v1/auth/logout", body: ["refresh_token": refresh]) as EmptyResponse
            }
            withAnimation { clearSessionState() }
        }
    }

    // MARK: – Internal

    private func performRefresh(refreshToken: String) async {
        do {
            let resp: TokenResponse = try await post(
                path: "/api/v1/auth/refresh",
                body: ["refresh_token": refreshToken]
            )
            applyTokens(resp)
        } catch {
            AppLog.auth.error("Token refresh failed: \(error.localizedDescription, privacy: .public)")
            withAnimation { clearSessionState() }
        }
    }

    private func applyTokens(_ resp: TokenResponse) {
        KeychainTokenStore.save(accessToken: resp.accessToken, refreshToken: resp.refreshToken)
        accessToken = resp.accessToken
        if let payload = decodeJWTPayload(resp.accessToken) {
            userId = UUID(uuidString: payload["sub"] as? String ?? "")
            userEmail = payload["email"] as? String
        }
        isAuthenticated = true
        if APIConfig.isPostHogConfigured, let uid = userId {
            var props: [String: Any] = [:]
            if let email = userEmail { props["email"] = email }
            PostHogSDK.shared.identify(uid.uuidString, userProperties: props)
        }
    }

    private func clearSessionState() {
        KeychainTokenStore.clear()
        accessToken = nil
        isAuthenticated = false
        userId = nil
        userEmail = nil
        if APIConfig.isPostHogConfigured { PostHogSDK.shared.reset() }
    }

    // MARK: – HTTP helpers

    private func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.detail
            throw AuthError.server(http.statusCode, msg ?? "Unknown error")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let authErr = error as? AuthError {
            switch authErr {
            case .server(409, _): return "An account with this email already exists."
            case .server(401, _): return "Incorrect email or password."
            case .server(403, _): return "Account disabled."
            case .server: return "Something went wrong. Please try again."
            case .network: return "No internet connection. Please check your network."
            }
        }
        if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet {
            return "No internet connection. Please check your network."
        }
        return "Something went wrong. Please try again."
    }

    // MARK: – Preview helpers

    fileprivate func applyPreviewAuthenticated(userId: UUID = UUID(), email: String = "preview@example.com") {
        isAuthenticated = true; self.userId = userId; userEmail = email
    }
}

// MARK: – Supporting types

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct APIErrorBody: Decodable { let detail: String }
private struct EmptyResponse: Decodable {}

private enum AuthError: Error {
    case server(Int, String)
    case network
}

// MARK: – Previews

extension AuthService {
    @MainActor static var previewSignedOut: AuthService {
        AuthService(backendURL: URL(string: "http://localhost:8000")!)
    }

    @MainActor static var previewAuthenticated: AuthService {
        let svc = AuthService(backendURL: URL(string: "http://localhost:8000")!)
        svc.applyPreviewAuthenticated()
        return svc
    }
}
```

- [ ] **Step 3: Update `ios/StarterApp/StarterApp/StarterAppApp.swift`**

Remove the `SupabaseClient` initialisation. Replace the `AuthService` init call:

```swift
// OLD:
AuthService(supabaseURL: URL(string: APIConfig.supabaseURL)!, supabaseAnonKey: APIConfig.supabaseAnonKey)

// NEW:
AuthService(backendURL: URL(string: APIConfig.backendURL)!)
```

Remove any `import Supabase` from this file.

- [ ] **Step 4: Update `ios/StarterApp/Config.example.xcconfig`**

Remove:
```
SUPABASE_URL = https://yourproject.supabase.co
SUPABASE_ANON_KEY = your-anon-key
```

Add (if not already present):
```
# Backend base URL — points to your Pi or localhost in dev
BACKEND_URL = http://localhost:8000
```

- [ ] **Step 5: Remove the Supabase Swift SDK from Tuist `Package.swift`**

In `ios/StarterApp/Tuist/Package.swift`, remove:
```swift
.package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
```

And from the target dependencies, remove:
```swift
.product(name: "Supabase", package: "supabase-swift"),
.product(name: "Auth", package: "supabase-swift"),
```

- [ ] **Step 6: Commit**

```bash
git add ios/StarterApp/StarterApp/Services/ ios/StarterApp/StarterApp/StarterAppApp.swift ios/StarterApp/Config.example.xcconfig ios/StarterApp/Tuist/
git commit -m "feat: rewrite iOS AuthService to call FastAPI directly, remove Supabase Swift SDK"
```

---

## Task 12: Update tests, CI, and Makefile

**Files:**
- Modify: `backend/tests/api/jwt_route_helpers.py`, `backend/tests/integration/conftest.py`, `backend/tests/integration/test_profile_flow.py`, `backend/tests/integration/test_notes_flow.py`
- Modify: `.github/workflows/backend-integration.yml`, `.github/workflows/backend-ci.yml`
- Modify: `Makefile`

- [ ] **Step 1: Update `backend/tests/api/jwt_route_helpers.py`**

```python
import time
import uuid
import jwt

TEST_JWT_SECRET = "testsecretatleast32charslong1234"


def make_test_token(user_id: uuid.UUID | None = None, expired: bool = False) -> str:
    uid = str(user_id or uuid.uuid4())
    exp = int(time.time()) + (-10 if expired else 3600)
    return jwt.encode(
        {"sub": uid, "aud": "authenticated", "type": "access",
         "email": f"{uid[:8]}@test.example", "exp": exp},
        TEST_JWT_SECRET,
        algorithm="HS256",
    )


def auth_header(user_id: uuid.UUID | None = None) -> dict[str, str]:
    return {"Authorization": f"Bearer {make_test_token(user_id)}"}
```

- [ ] **Step 2: Update `backend/tests/integration/conftest.py`**

```python
import pytest_asyncio
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.main import app
from app.db.session import get_db
from app.db.base import Base
from app.db import models  # noqa: F401

TEST_DB_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test"


@pytest_asyncio.fixture(scope="session")
async def test_engine():
    engine = create_async_engine(TEST_DB_URL)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(test_engine):
    Session = async_sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)
    async with Session() as session:
        yield session
        await session.rollback()


@pytest_asyncio.fixture
async def client(db_session):
    app.dependency_overrides[get_db] = lambda: db_session
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()
```

- [ ] **Step 3: Update `backend/tests/integration/test_notes_flow.py`**

```python
import uuid
import pytest
from tests.api.jwt_route_helpers import auth_header
from app.repositories import profile_repo, user_repo
from app.services.auth_service import hash_password


async def _create_user_and_profile(db_session, email="test@example.com"):
    user = await user_repo.create_user(db_session, email, hash_password("pw"))
    await profile_repo.create_profile(db_session, user.id)
    await db_session.commit()
    return user


@pytest.mark.asyncio
@pytest.mark.integration
async def test_notes_crud(client, db_session):
    user = await _create_user_and_profile(db_session, "notes_crud@example.com")
    hdrs = auth_header(user.id)

    resp = await client.post("/api/v1/me/notes", json={"title": "Hello", "body": "World"}, headers=hdrs)
    assert resp.status_code == 201
    note_id = resp.json()["id"]

    resp = await client.get("/api/v1/me/notes", headers=hdrs)
    assert len(resp.json()) == 1

    resp = await client.patch(f"/api/v1/me/notes/{note_id}", json={"title": "Updated"}, headers=hdrs)
    assert resp.status_code == 200
    assert resp.json()["title"] == "Updated"

    resp = await client.delete(f"/api/v1/me/notes/{note_id}", headers=hdrs)
    assert resp.status_code == 204

    resp = await client.get(f"/api/v1/me/notes/{note_id}", headers=hdrs)
    assert resp.status_code == 404


@pytest.mark.asyncio
@pytest.mark.integration
async def test_notes_isolation(client, db_session):
    user_a = await _create_user_and_profile(db_session, "a_isolation@example.com")
    user_b = await _create_user_and_profile(db_session, "b_isolation@example.com")

    resp = await client.post(
        "/api/v1/me/notes", json={"title": "A note", "body": ""}, headers=auth_header(user_a.id)
    )
    note_id = resp.json()["id"]

    resp = await client.get(f"/api/v1/me/notes/{note_id}", headers=auth_header(user_b.id))
    assert resp.status_code == 404
```

- [ ] **Step 4: Update `backend-integration.yml`**

```yaml
name: Backend Integration Tests

on:
  push:
    branches: [main]
    paths: ["backend/**"]
  pull_request:
    paths: ["backend/**"]

jobs:
  integration:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: postgres_test
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4
      - run: uv sync
        working-directory: backend
      - name: Run migrations
        working-directory: backend
        env:
          DATABASE_URL: postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test
        run: uv run alembic upgrade head
      - name: Run integration tests
        working-directory: backend
        env:
          DATABASE_URL: postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test
          JWT_SECRET: testsecretatleast32charslong1234
        run: uv run pytest tests/integration/ -m integration -v
```

- [ ] **Step 5: Update `Makefile`**

Replace supabase targets:

```makefile
dev: ## Start Postgres + backend + Adminer
	docker compose up --build -d
	@echo "  API:     http://localhost:8000"
	@echo "  Adminer: http://localhost:8080  (server=db, user=postgres)"

dev-logs:
	docker compose logs -f

stop:
	docker compose down

db-migrate: ## Run Alembic migrations inside the running backend container
	docker compose exec backend uv run alembic upgrade head

db-shell:
	docker compose exec db psql -U postgres postgres

backend-test:
	cd backend && uv run pytest tests/unit/ -v --cov=app --cov-report=term-missing

backend-integration-test:
	cd backend && uv run pytest tests/integration/ -m integration -v
```

- [ ] **Step 6: Commit**

```bash
git add backend/tests/ .github/workflows/ Makefile
git commit -m "test/ci: rewrite tests for SQLAlchemy + HS256, replace supabase-start with postgres service"
```

---

## Task 13: Update README and docs

**Files:**
- Modify: `README.md`, `docs/` (any Supabase-specific content)

- [ ] **Step 1: Update `README.md` stack table**

```markdown
## Stack

| Layer | Technology |
|---|---|
| Auth | FastAPI (built-in — bcrypt + HS256 JWT) |
| Database | PostgreSQL 17 |
| ORM | SQLAlchemy 2 (async) + Alembic |
| Backend | FastAPI + Python 3.12 |
| iOS | Swift + URLSession + Keychain |
| DB Admin | Adminer (http://localhost:8080) |
| Deployment | Docker Compose (Raspberry Pi ready) |
```

- [ ] **Step 2: Update quick-start**

```markdown
## Quick Start

### Prerequisites
- Docker + Docker Compose
- Xcode 16+
- [mise](https://mise.jdx.dev/)

### Local dev

```bash
cp .env.example .env
# Set JWT_SECRET in .env to output of: openssl rand -hex 32

make dev          # starts Postgres + backend + Adminer
make db-migrate   # runs Alembic migrations

# API:     http://localhost:8000/api/v1/
# Adminer: http://localhost:8080 (server=db, user=postgres, pass=postgres)
```

Register your first user:
```bash
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"yourpassword"}'
```

In iOS: set `BACKEND_URL = http://localhost:8000` in `Config-Debug.xcconfig`.
```

- [ ] **Step 3: Grep and update docs/**

```bash
grep -rl "supabase" docs/ --include="*.md"
```

For each file, replace `supabase db push` → `make db-migrate`, remove Supabase dashboard references, update auth setup section to describe the `/auth/register` + `/auth/token` endpoints.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/
git commit -m "docs: update README and docs for self-hosted FastAPI auth stack"
```

---

## Task 14: End-to-end smoke test

- [ ] **Step 1: Set up `.env`**

```bash
cp .env.example .env
JWT_SECRET=$(openssl rand -hex 32)
sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/$JWT_SECRET/" .env
```

- [ ] **Step 2: Start stack**

```bash
make dev
```

Expected: `db`, `backend`, `adminer` all healthy.

- [ ] **Step 3: Run migrations**

```bash
make db-migrate
```

Expected:
```
Running upgrade  -> 001, Initial schema ...
Running upgrade 001 -> 002, Add is_pro ...
```

- [ ] **Step 4: Register a user**

```bash
curl -s -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Password123!"}' | jq .
```

Expected: `{"access_token":"...","refresh_token":"...","token_type":"bearer"}`

- [ ] **Step 5: Access a protected endpoint**

```bash
TOKEN=<paste access_token>
curl -s http://localhost:8000/api/v1/me/profile \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Expected: `{"id":"...","display_name":null,"is_pro":false,...}`

- [ ] **Step 6: Create a note**

```bash
curl -s -X POST http://localhost:8000/api/v1/me/notes \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"First note","body":"It works!"}' | jq .
```

Expected: 201 with note object.

- [ ] **Step 7: Refresh token**

```bash
REFRESH=<paste refresh_token>
curl -s -X POST http://localhost:8000/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH\"}" | jq .access_token
```

Expected: new access token string.

- [ ] **Step 8: Run unit tests**

```bash
cd backend
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/postgres \
JWT_SECRET=$(grep JWT_SECRET ../.env | cut -d= -f2) \
uv run pytest tests/unit/ -v
```

Expected: all PASS.

- [ ] **Step 9: Final commit**

```bash
git add .
git commit -m "chore: migration complete — self-contained FastAPI auth + Postgres template"
```

---

## Verification Checklist

- [ ] `make dev` brings up 3 containers: `db`, `backend`, `adminer`
- [ ] `make db-migrate` runs both Alembic migrations with no errors
- [ ] `POST /api/v1/auth/register` creates user + profile, returns tokens
- [ ] `POST /api/v1/auth/token` (login) works, wrong password returns 401
- [ ] `POST /api/v1/auth/refresh` rotates refresh token
- [ ] `POST /api/v1/auth/logout` invalidates refresh token
- [ ] `GET /api/v1/me/profile` returns profile, 401 without token
- [ ] Notes CRUD works end-to-end (create, list, update, delete)
- [ ] User A cannot access User B's notes (isolation test passes)
- [ ] RevenueCat webhook updates `is_pro` via SQLAlchemy
- [ ] Adminer accessible at `http://localhost:8080`
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] iOS `AuthService.swift` has no `import Supabase` or `import Auth`
- [ ] `supabase/` directory is gone
- [ ] No `supabase-py` or `postgrest` in `pyproject.toml`
- [ ] No `supabase start` anywhere in CI or Makefile
