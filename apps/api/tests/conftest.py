"""Test fixtures.

* Points at the compose database (``make db``). Two roles, mirroring production (SEC-011):
  the **app** role (``DATABASE_URL``: DML only, subject to RLS) is what every test session and
  the app under test use; the **migrate** role (``MIGRATION_DATABASE_URL``: owner, DDL) only
  creates the test database, runs ``alembic upgrade head`` and serves ``migrate_engine`` for
  setup/verification. ``TEST_DATABASE_URL`` / ``TEST_MIGRATION_DATABASE_URL`` override.
* Every test runs inside a transaction that is rolled back. Rows are written under a tenant
  scope (``farmerapp.db.session.tenant_scope``) because the app role cannot write a row whose
  tenant is not the bound one (FA-003).
* One event loop and one app-role engine for the whole session (``pyproject.toml``
  ``asyncio_default_*_loop_scope = "session"``): a pooled asyncpg connection is reused across
  tests, so the per-connection warm-up (PostGIS type introspection, statement caches; ~0.3 s)
  is paid once instead of once per test.
* Parallel runs (pytest-xdist, ``make check-api``): every worker gets its own database,
  ``<test db>_<checkout key>_gw0``, ``…_gw1``, …, created with ``CREATE DATABASE … TEMPLATE``
  from ``<test db>_<checkout key>_template``. The first worker to need the template builds it
  (create + ``alembic upgrade head`` as the migrate role) under a Postgres advisory lock; the
  template is rebuilt from scratch whenever the migration files change (fingerprint in the
  database comment). The checkout key (a hash of this checkout's path) keeps two worktrees on
  different branches from sharing, or dropping, each other's databases. A serial run (no
  ``-n``) keeps using ``farmerapp_test`` exactly as before.
"""

from __future__ import annotations

import asyncio
import hashlib
import os
import shutil
import tempfile
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
from sqlalchemy.pool import NullPool

from farmerapp.api.app import create_app
from farmerapp.db.rls import APP_ROLE
from farmerapp.db.session import get_session
from farmerapp.settings import get_settings

API_ROOT = Path(__file__).resolve().parents[1]
TEST_DB_NAME = "farmerapp_test"
# Set by pytest-xdist in each worker process before conftest is imported ("gw0", "gw1", ...);
# absent in a serial run.
XDIST_WORKER = os.environ.get("PYTEST_XDIST_WORKER", "")
CHECKOUT_KEY = hashlib.sha256(str(API_ROOT).encode()).hexdigest()[:6]


def _with_db(url: str, dbname: str) -> str:
    return make_url(url).set(database=dbname).render_as_string(hide_password=False)


def _test_database_urls() -> tuple[str, str]:
    """(app URL, migrate URL) for the base test database.

    Explicit ``TEST_*`` variables win; otherwise the configured URLs with the database name
    replaced by ``farmerapp_test``.
    """
    settings = get_settings()
    app_url = os.environ.get("TEST_DATABASE_URL") or _with_db(settings.database_url, TEST_DB_NAME)
    migrate_url = os.environ.get("TEST_MIGRATION_DATABASE_URL") or _with_db(
        settings.migration_database_url or settings.database_url, TEST_DB_NAME
    )
    return app_url, migrate_url


BASE_DATABASE_URL, BASE_MIGRATION_DATABASE_URL = _test_database_urls()


def _derived_name(suffix: str) -> str:
    base = make_url(BASE_MIGRATION_DATABASE_URL).database or TEST_DB_NAME
    return f"{base}_{CHECKOUT_KEY}_{suffix}"


WORKER_DB_NAME: str | None = None
TEMPLATE_DB_NAME: str | None = None
if XDIST_WORKER:
    WORKER_DB_NAME = worker_db = _derived_name(XDIST_WORKER)
    TEMPLATE_DB_NAME = _derived_name("template")
    TEST_DATABASE_URL = _with_db(BASE_DATABASE_URL, worker_db)
    TEST_MIGRATION_DATABASE_URL = _with_db(BASE_MIGRATION_DATABASE_URL, worker_db)
else:
    TEST_DATABASE_URL, TEST_MIGRATION_DATABASE_URL = (
        BASE_DATABASE_URL,
        BASE_MIGRATION_DATABASE_URL,
    )


def _maintenance_engine(url: str) -> AsyncEngine:
    """AUTOCOMMIT owner connection to the ``postgres`` database (CREATE / DROP DATABASE)."""
    return create_async_engine(
        make_url(url).set(database="postgres"), isolation_level="AUTOCOMMIT", poolclass=NullPool
    )


async def _ensure_database(url: str) -> None:
    target = make_url(url)
    dbname = target.database
    assert dbname, "TEST_MIGRATION_DATABASE_URL must name a database"
    maintenance = _maintenance_engine(url)
    try:
        async with maintenance.connect() as conn:
            exists = await conn.scalar(
                text("SELECT 1 FROM pg_database WHERE datname = :n"), {"n": dbname}
            )
            if not exists:
                await conn.execute(text(f'CREATE DATABASE "{dbname}"'))
    finally:
        await maintenance.dispose()


def _alembic_upgrade(url: str) -> None:
    cfg = Config(str(API_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(API_ROOT / "alembic"))
    cfg.set_main_option("sqlalchemy.url", url)
    command.upgrade(cfg, "head")


def _migrations_fingerprint() -> str:
    """Changes whenever a migration (or the Alembic env) changes: the template is rebuilt."""
    digest = hashlib.sha256()
    for path in sorted((API_ROOT / "alembic").rglob("*.py")):
        digest.update(path.relative_to(API_ROOT).as_posix().encode())
        digest.update(path.read_bytes())
    return f"farmerapp-test-template {digest.hexdigest()[:16]}"


# pg_advisory_lock key (any constant; locks are scoped to the ``postgres`` database the
# maintenance connection uses, so this serialises the workers of every checkout).
_TEMPLATE_LOCK_KEY = 0x0FA2_7E57


async def _create_worker_database(migrate_url: str) -> None:
    """Build the template once (under a lock), then clone it into this worker's database."""
    assert WORKER_DB_NAME and TEMPLATE_DB_NAME
    template, worker = TEMPLATE_DB_NAME, WORKER_DB_NAME
    fingerprint = _migrations_fingerprint()
    maintenance = _maintenance_engine(migrate_url)
    try:
        async with maintenance.connect() as conn:
            await conn.execute(text("SELECT pg_advisory_lock(:k)"), {"k": _TEMPLATE_LOCK_KEY})
            try:
                current = await conn.scalar(
                    text(
                        "SELECT shobj_description(oid, 'pg_database') FROM pg_database "
                        "WHERE datname = :n"
                    ),
                    {"n": template},
                )
                if current != fingerprint:
                    await conn.execute(text(f'DROP DATABASE IF EXISTS "{template}" WITH (FORCE)'))
                    await conn.execute(text(f'CREATE DATABASE "{template}"'))
                    # alembic runs its own event loop (asyncio.run): do it off this loop.
                    await asyncio.to_thread(_alembic_upgrade, _with_db(migrate_url, template))
                    await conn.execute(
                        text(f"COMMENT ON DATABASE \"{template}\" IS '{fingerprint}'")
                    )
                await conn.execute(text(f'DROP DATABASE IF EXISTS "{worker}" WITH (FORCE)'))
                await conn.execute(text(f'CREATE DATABASE "{worker}" TEMPLATE "{template}"'))
                # Database-level ACLs are not copied from a template (migration 0003 grants the
                # app role CONNECT on "its" database, SEC-011): re-apply it to the clone.
                await conn.execute(text(f'GRANT CONNECT ON DATABASE "{worker}" TO {APP_ROLE}'))
            finally:
                await conn.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": _TEMPLATE_LOCK_KEY})
    finally:
        await maintenance.dispose()


async def _drop_worker_database(migrate_url: str) -> None:
    assert WORKER_DB_NAME
    maintenance = _maintenance_engine(migrate_url)
    try:
        async with maintenance.connect() as conn:
            await conn.execute(text(f'DROP DATABASE IF EXISTS "{WORKER_DB_NAME}" WITH (FORCE)'))
    finally:
        await maintenance.dispose()


@pytest.fixture(scope="session", autouse=True)
def _env() -> Iterator[None]:
    os.environ["DATABASE_URL"] = TEST_DATABASE_URL
    os.environ["MIGRATION_DATABASE_URL"] = TEST_MIGRATION_DATABASE_URL
    os.environ["APP_ENV"] = "test"
    os.environ["LOG_JSON"] = "false"
    os.environ["OTP_PROVIDER"] = "fake"
    os.environ["PAYMENT_PROVIDER"] = "fake"  # FA-021: never call a payment provider from tests
    os.environ["PAYMENT_WEBHOOK_DELIVERY"] = "inline"
    os.environ["OTP_DEV_CODE"] = ""  # never accept the dev code in tests unless a test opts in
    os.environ["BLOB_STORE"] = "local"  # NF-003: uploads land in a temp directory
    os.environ["BLOB_LOCAL_DIR"] = tempfile.mkdtemp(prefix="farmerapp-blobs-")
    get_settings.cache_clear()
    yield
    shutil.rmtree(os.environ["BLOB_LOCAL_DIR"], ignore_errors=True)
    get_settings.cache_clear()


@pytest.fixture(scope="session", autouse=True)
def migrated_database(_env: None) -> Iterator[str]:
    """Serial: create the test DB if needed and migrate to head as the migrate role.
    xdist worker: a fresh per-worker clone of the migrated template (dropped at the end).

    Yields the *app* URL every test session connects with.
    """
    if WORKER_DB_NAME is None:
        asyncio.run(_ensure_database(TEST_MIGRATION_DATABASE_URL))
        _alembic_upgrade(TEST_MIGRATION_DATABASE_URL)
        yield TEST_DATABASE_URL
        return
    asyncio.run(_create_worker_database(TEST_MIGRATION_DATABASE_URL))
    yield TEST_DATABASE_URL
    asyncio.run(_drop_worker_database(TEST_MIGRATION_DATABASE_URL))


@pytest.fixture
async def migrate_engine(migrated_database: str) -> AsyncIterator[AsyncEngine]:
    """Owner/DDL connection (``farmerapp_migrate`` member) for setup and catalogue checks."""
    engine = create_async_engine(TEST_MIGRATION_DATABASE_URL)
    try:
        yield engine
    finally:
        await engine.dispose()


@pytest.fixture(scope="session")
async def app_engine(migrated_database: str) -> AsyncIterator[AsyncEngine]:
    """The app-role engine shared by every test (connections are reused, see module doc).

    ``pool_pre_ping=True`` as in production (``farmerapp.db.session.get_engine``): the pool
    outlives any single test, so a pooled connection can be dead by the time a test checks it
    out — the Postgres container was recreated or restarted underneath the run (another
    checkout's ``make db`` recreating the shared ``farmerapp-db-1``, Docker Desktop
    restarting the emulated amd64 image). Without the ping the next test failed in setup with
    asyncpg "connection is closed"; with it the checkout detects the dead connection,
    invalidates the pool and reconnects. This only happens at checkout, before a test runs a
    statement: a connection that dies *during* a test still fails that test."""
    engine = create_async_engine(
        migrated_database,
        pool_size=2,
        max_overflow=2,
        pool_pre_ping=True,
        # asyncpg waits forever on a half-open socket (a pooled connection whose backend
        # vanished without a FIN, e.g. across a Docker Desktop network reset): bound connect
        # and every statement, the pre-ping included, so such a test fails instead of hanging.
        connect_args={"timeout": 30, "command_timeout": 120},
    )
    try:
        yield engine
    finally:
        await engine.dispose()


@pytest.fixture
async def db_session(app_engine: AsyncEngine) -> AsyncIterator[AsyncSession]:
    """An app-role session inside an outer transaction that is always rolled back."""
    async with app_engine.connect() as conn:
        trans = await conn.begin()
        session = AsyncSession(
            bind=conn, expire_on_commit=False, join_transaction_mode="create_savepoint"
        )
        try:
            yield session
        finally:
            await session.close()
            await trans.rollback()


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
