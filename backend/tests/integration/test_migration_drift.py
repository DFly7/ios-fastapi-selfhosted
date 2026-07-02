"""Integration test: Alembic migrations must match SQLAlchemy metadata (no drift).

This guard catches the "green suite, broken prod" scenario where a model change
is added without a corresponding Alembic migration: create_all() would silently
apply the change in tests while production Alembic runs never see it.

Strategy
--------
1. Drop all tables on the test database via ``Base.metadata.drop_all``, then
   delete the alembic_version row so Alembic treats it as a fresh database.
2. Run ``alembic upgrade head`` in a subprocess (keeps Alembic's async env.py
   off pytest's event loop).
3. Open a fresh async engine, inspect the live DB, and use
   ``alembic.autogenerate.compare_metadata`` to diff it against ``Base.metadata``.
4. Assert the diff is empty — any entry means a model was changed without a
   matching migration.
"""

from __future__ import annotations

import os
import subprocess
import sys

import pytest
import pytest_asyncio
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

from app.db.base import Base

pytestmark = pytest.mark.integration

TEST_DB_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/postgres_test"


@pytest_asyncio.fixture
async def clean_migrated_db():
    """Drop all tables and re-apply all Alembic migrations from scratch.

    Uses drop_all (not alembic downgrade) so it works even when the DB was
    previously populated by create_all (the existing integration test pattern).
    The alembic_version table is also dropped so Alembic sees a clean slate.
    """
    engine = create_async_engine(TEST_DB_URL, echo=False, poolclass=NullPool)

    # 1. Drop everything so we start from a known-clean state.
    async with engine.begin() as conn:
        # Drop alembic_version if it exists (create_all doesn't create it)
        await conn.execute(text("DROP TABLE IF EXISTS alembic_version"))
        await conn.run_sync(Base.metadata.drop_all)

    await engine.dispose()

    # 2. Run migrations in a subprocess to keep Alembic's asyncio loop separate
    #    from pytest-asyncio's loop.
    backend_dir = os.path.realpath(
        os.path.join(os.path.dirname(__file__), "..", "..")
    )
    env = {
        **os.environ,
        "DATABASE_URL": TEST_DB_URL,
        "JWT_SECRET": os.environ.get("JWT_SECRET", "testsecretatleast32charslong1234"),
    }
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=backend_dir,
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"alembic upgrade head failed:\n{result.stdout}\n{result.stderr}"
        )

    yield  # test runs here

    # Teardown: drop user tables but KEEP alembic_version at head.
    # This matters because the Makefile runs `alembic upgrade head` before each
    # test suite invocation: if alembic_version is absent, Alembic tries to run
    # all migrations from scratch and collides with tables left by create_all.
    # By leaving alembic_version=head, the next `alembic upgrade head` is a no-op.
    # The other integration fixtures (test_engine) manage their own tables via
    # drop_all + create_all, so they are not affected by this choice.
    engine2 = create_async_engine(TEST_DB_URL, echo=False, poolclass=NullPool)
    async with engine2.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine2.dispose()


@pytest.mark.asyncio
async def test_migrations_match_metadata(clean_migrated_db):
    """After running all migrations, the live schema must equal Base.metadata.

    A non-empty diff means a model was added/changed without a matching migration.
    """
    engine = create_async_engine(TEST_DB_URL, echo=False, poolclass=NullPool)

    try:
        async with engine.connect() as conn:
            diff = await conn.run_sync(_compare_metadata_sync)
    finally:
        await engine.dispose()

    # Filter out known benign false positives on this schema.
    # Alembic autogenerate sometimes reports server_default representation
    # differences for Boolean columns (e.g. "true" vs. True) — these are
    # harmless dialect rendering differences and do not indicate real drift.
    real_diffs = [
        d for d in diff
        if not _is_benign_server_default_diff(d)
    ]

    assert real_diffs == [], (
        f"Migration drift detected — {len(real_diffs)} difference(s) between "
        f"Alembic-migrated schema and Base.metadata.\n"
        f"Run 'alembic revision --autogenerate -m <description>' to generate a migration.\n"
        f"Diff:\n" + "\n".join(str(d) for d in real_diffs)
    )


def _compare_metadata_sync(sync_conn):
    """Called via conn.run_sync(); receives a sync Connection."""
    migration_ctx = MigrationContext.configure(sync_conn)
    return compare_metadata(migration_ctx, Base.metadata)


def _is_benign_server_default_diff(diff) -> bool:
    """Return True only for the specific known-benign server_default diffs.

    Alembic autogenerate reports a ``modify_server_default`` diff for Boolean
    columns whose migrations store the raw SQL string (``'true'`` / ``'false'``)
    while SQLAlchemy metadata renders the dialect-native Python bool.  These are
    harmless representation differences, not real schema drift.

    Known benign pairs (table, column):
      - users.is_active  — server_default='true'  (migration 001)
      - profiles.is_pro  — server_default='false' (migration 002)

    Any other ``modify_server_default`` diff (e.g. on a newly added column) must
    NOT be silenced here — it must surface as a real test failure.

    Alembic diff tuple layout for modify_server_default:
      (directive, schema, table_name, column_name, existing_type, ...)
    """
    # Known-benign (table, column) pairs for Boolean server_default string diffs.
    _BENIGN_BOOL_DEFAULTS: set[tuple[str, str]] = {
        ("users", "is_active"),
        ("profiles", "is_pro"),
    }
    try:
        if diff[0] == "modify_server_default":
            table_name = diff[2]
            column_name = diff[3]
            return (table_name, column_name) in _BENIGN_BOOL_DEFAULTS
    except (IndexError, TypeError):
        pass
    return False
