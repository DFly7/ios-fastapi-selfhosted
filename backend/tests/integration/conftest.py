"""Integration fixtures: real PostgreSQL + AsyncClient wired to FastAPI."""

import os

# Must be set before app/settings import so JWT verification matches test tokens.
os.environ.setdefault("JWT_SECRET", "testsecretatleast32charslong1234")
os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test",
)

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.config import get_settings

get_settings.cache_clear()

from app.db.base import Base
from app.db.session import get_db
from app.main import app

# auth_service caches settings at import — reload after test env is fixed.
from app.services import auth_service

auth_service._settings = get_settings()

TEST_DB_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test"


@pytest_asyncio.fixture
async def test_engine():
    """Per-test engine (NullPool avoids asyncpg event-loop reuse issues)."""
    engine = create_async_engine(TEST_DB_URL, echo=False, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(test_engine):
    """Fresh session for direct ORM setup in tests."""
    session_factory = async_sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)
    async with session_factory() as session:
        yield session
        await session.rollback()


@pytest_asyncio.fixture
async def client(test_engine):
    """Async HTTP client; each request gets its own committed DB session."""

    session_factory = async_sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)

    async def override_get_db():
        async with session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()
