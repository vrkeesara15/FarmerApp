"""Async Alembic environment.

URL comes from ``sqlalchemy.url`` (tests) or ``MIGRATION_DATABASE_URL``: migrations run as the
owner/DDL role, never as the runtime app role (SEC-011).
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import Connection, pool
from sqlalchemy.ext.asyncio import async_engine_from_config

import farmerapp.db.models  # noqa: F401  (registers models on Base.metadata)
from farmerapp.db.base import Base
from farmerapp.settings import get_settings

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

if not config.get_main_option("sqlalchemy.url"):
    config.set_main_option("sqlalchemy.url", get_settings().migration_database_url)

target_metadata = Base.metadata

# Tables owned by extensions (PostGIS) that autogenerate / `alembic check` must ignore.
EXTENSION_TABLES = {"spatial_ref_sys"}


def include_object(obj: object, name: str | None, type_: str, *_: object) -> bool:
    return not (type_ == "table" and name in EXTENSION_TABLES)


def run_migrations_offline() -> None:
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        include_object=include_object,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
        include_object=include_object,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
