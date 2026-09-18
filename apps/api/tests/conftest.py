"""Test fixtures.

* Points at the compose database (``make db``). Two roles, mirroring production (SEC-011):
  the **app** role (``DATABASE_URL``: DML only, subject to RLS) is what every test session and
  the app under test use; the **migrate** role (``MIGRATION_DATABASE_URL``: owner, DDL) only
  creates the test database, runs ``alembic upgrade head`` and serves ``migrate_engine`` for
  setup/verification. ``TEST_DATABASE_URL`` / ``TEST_MIGRATION_DATABASE_URL`` override.
* Every test runs inside a transaction that is rolled back. Rows are written under a tenant
  scope (``farmerapp.db.session.tenant_scope``) because the app role cannot write a row whose
  tenant is not the bound one (FA-003).
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import AsyncIterator, Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine

from farmerapp.api.app import create_app
from farmerapp.db.session import get_session
from farmerapp.settings import get_settings

API_ROOT = Path(__file__).resolve().parents[1]
TEST_DB_NAME = "farmerapp_test"


def _with_test_db(url: str) -> str:
    return make_url(url).set(database=TEST_DB_NAME).render_as_string(hide_password=False)


def _test_database_urls() -> tuple[str, str]:
    """(app URL, migrate URL) for the test database.

    Explicit ``TEST_*`` variables win; otherwise the configured URLs with the database name
    replaced by ``farmerapp_test``.
    """
    settings = get_settings()
    app_url = os.environ.get("TEST_DATABASE_URL") or _with_test_db(settings.database_url)
    migrate_url = os.environ.get("TEST_MIGRATION_DATABASE_URL") or _with_test_db(
        settings.migration_database_url or settings.database_url
    )
    return app_url, migrate_url


TEST_DATABASE_URL, TEST_MIGRATION_DATABASE_URL = _test_database_urls()


async def _ensure_database(url: str) -> None:
    target = make_url(url)
    dbname = target.database
    assert dbname, "TEST_MIGRATION_DATABASE_URL must name a database"
    maintenance = create_async_engine(
        target.set(database="postgres"), isolation_level="AUTOCOMMIT", poolclass=None
    )
    try:
        async with maintenance.connect() as conn:
            exists = await conn.scalar(
                text("SELECT 1 FROM pg_database WHERE datname = :n"), {"n": dbname}
            )
            if not exists:
                await conn.execute(text(f'CREATE DATABASE "{dbname}"'))
    finally:
        await maintenance.dispose()


@pytest.fixture(scope="session", autouse=True)
def _env() -> Iterator[None]:
    os.environ["DATABASE_URL"] = TEST_DATABASE_URL
    os.environ["MIGRATION_DATABASE_URL"] = TEST_MIGRATION_DATABASE_URL
    os.environ["APP_ENV"] = "test"
    os.environ["LOG_JSON"] = "false"
    os.environ["OTP_PROVIDER"] = "fake"
    os.environ["OTP_DEV_CODE"] = ""  # never accept the dev code in tests unless a test opts in
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture(scope="session", autouse=True)
def migrated_database(_env: None) -> str:
    """Create the test DB if needed and migrate to head as the migrate role.

    Returns the *app* URL every test session connects with.
    """
    asyncio.run(_ensure_database(TEST_MIGRATION_DATABASE_URL))
    cfg = Config(str(API_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(API_ROOT / "alembic"))
    cfg.set_main_option("sqlalchemy.url", TEST_MIGRATION_DATABASE_URL)
    command.upgrade(cfg, "head")
    return TEST_DATABASE_URL


@pytest.fixture
async def migrate_engine(migrated_database: str) -> AsyncIterator[AsyncEngine]:
    """Owner/DDL connection (``farmerapp_migrate`` member) for setup and catalogue checks."""
    engine = create_async_engine(TEST_MIGRATION_DATABASE_URL)
    try:
        yield engine
    finally:
        await engine.dispose()


@pytest.fixture
async def db_session(migrated_database: str) -> AsyncIterator[AsyncSession]:
    """An app-role session inside an outer transaction that is always rolled back."""
    engine = create_async_engine(migrated_database)
    async with engine.connect() as conn:
        trans = await conn.begin()
        session = AsyncSession(
            bind=conn, expire_on_commit=False, join_transaction_mode="create_savepoint"
        )
        try:
            yield session
        finally:
            await session.close()
            await trans.rollback()
    await engine.dispose()


@pytest.fixture
def app(db_session: AsyncSession) -> FastAPI:
    application = create_app()

    async def _override() -> AsyncIterator[AsyncSession]:
        yield db_session

    application.dependency_overrides[get_session] = _override
    return application


@pytest.fixture
async def client(app: FastAPI) -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
