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
