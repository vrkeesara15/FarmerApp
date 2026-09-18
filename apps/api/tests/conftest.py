"""Test fixtures.

* Points at the compose database (``make db``). ``TEST_DATABASE_URL`` overrides.
* Creates the test database if missing via the maintenance DB, runs ``alembic upgrade head``
  once per session, and wraps every test in a transaction that is rolled back.
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
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from farmerapp.api.app import create_app
from farmerapp.db.session import get_session
from farmerapp.settings import get_settings

API_ROOT = Path(__file__).resolve().parents[1]
TEST_DB_NAME = "farmerapp_test"


def _test_database_url() -> str:
    """``TEST_DATABASE_URL`` if set, else ``DATABASE_URL`` (env or .env) with the test db name."""
    explicit = os.environ.get("TEST_DATABASE_URL")
    if explicit:
        return explicit
    base = make_url(get_settings().database_url)
    return base.set(database=TEST_DB_NAME).render_as_string(hide_password=False)


TEST_DATABASE_URL = _test_database_url()


async def _ensure_database(url: str) -> None:
    target = make_url(url)
    dbname = target.database
    assert dbname, "TEST_DATABASE_URL must name a database"
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
    os.environ["APP_ENV"] = "test"
    os.environ["LOG_JSON"] = "false"
    os.environ["OTP_PROVIDER"] = "fake"
    os.environ["OTP_DEV_CODE"] = ""  # never accept the dev code in tests unless a test opts in
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture(scope="session", autouse=True)
def migrated_database(_env: None) -> str:
    """Create the test DB if needed and migrate to head (sync: runs outside the test loop)."""
    asyncio.run(_ensure_database(TEST_DATABASE_URL))
    cfg = Config(str(API_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(API_ROOT / "alembic"))
    cfg.set_main_option("sqlalchemy.url", TEST_DATABASE_URL)
    command.upgrade(cfg, "head")
    return TEST_DATABASE_URL


@pytest.fixture
async def db_session(migrated_database: str) -> AsyncIterator[AsyncSession]:
    """A session inside an outer transaction that is always rolled back."""
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
