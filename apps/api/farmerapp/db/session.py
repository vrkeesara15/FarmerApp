"""Async engine and session factory, plus the per-request tenant binding.

Row-level security (FA-003 / SEC-012) keys on the Postgres setting ``app.tenant_id``; every
policy compares the row's tenant with ``app_current_tenant()`` (NULL when unset, so an
unbound session sees nothing). ``set_tenant`` binds it **transaction-locally**
(``set_config(..., is_local => true)``): it ends with the transaction, so a pooled connection
never carries a tenant into the next request (proved in ``tests/rls/test_session.py``).

Tenant resolution: ``farmerapp.auth.deps.get_current_user`` verifies the bearer token, calls
``set_tenant`` with the token's tenant and only then loads the user, so a token whose tenant
claim does not match the user finds nobody (401). Login (``/v1/auth/*``) runs before a tenant
is known and resolves it through the ``SECURITY DEFINER`` lookups (``farmerapp.db.rls``).

Jobs and the worker bind explicitly: ``tenant_scope(session, tenant_id)`` for a block, or
``job_session(tenant_id)`` for a whole transaction. There is no bypass switch: cross-tenant
work is done per tenant, or by the migrate role (``MIGRATION_DATABASE_URL``).
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import AsyncIterator
from functools import lru_cache

from fastapi import Request
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from farmerapp.settings import get_settings

_SET_TENANT = text("SELECT set_config('app.tenant_id', :tid, true)")
_GET_TENANT = text("SELECT current_setting('app.tenant_id', true)")


@lru_cache(maxsize=1)
def get_engine() -> AsyncEngine:
    settings = get_settings()
    return create_async_engine(
        settings.database_url,
        echo=settings.db_echo,
        pool_size=settings.db_pool_size,
        max_overflow=settings.db_max_overflow,
        pool_pre_ping=True,
    )


@lru_cache(maxsize=1)
def get_session_factory() -> async_sessionmaker[AsyncSession]:
    from farmerapp.db.audit import install_audit_listener  # FA-006 (import cycle otherwise)

    install_audit_listener()
    return async_sessionmaker(get_engine(), expire_on_commit=False)


async def set_tenant(session: AsyncSession, tenant_id: uuid.UUID | None) -> None:
    """Bind ``app.tenant_id`` for the current transaction (no-op when ``None``).

    Must be called inside an open transaction (``SET LOCAL`` semantics via ``set_config``).
    """
    if tenant_id is None:
        return
    await session.execute(_SET_TENANT, {"tid": str(tenant_id)})
    # SEC-026: the tenant's data key is loaded (or created) once per process, so PII fields
    # of this tenant encrypt / decrypt synchronously for the rest of the work.
    from farmerapp.pii.keys import ensure_tenant_key

    await ensure_tenant_key(session, tenant_id)


async def clear_tenant(session: AsyncSession) -> None:
    """Unbind the tenant for the rest of the transaction (the session then sees no rows)."""
    await session.execute(_SET_TENANT, {"tid": ""})


async def bound_tenant(session: AsyncSession) -> uuid.UUID | None:
    """The tenant currently bound on the session's transaction, if any."""
    value = await session.scalar(_GET_TENANT)
    return uuid.UUID(value) if value else None


@contextlib.asynccontextmanager
async def tenant_scope(session: AsyncSession, tenant_id: uuid.UUID) -> AsyncIterator[None]:
    """Bind ``tenant_id`` for the block and restore the previous binding afterwards.

    For jobs, the worker and tests that touch several tenants in one transaction.
    """
    previous: str | None = await session.scalar(_GET_TENANT)
    await set_tenant(session, tenant_id)
    try:
        yield
    finally:
        if session.is_active:
            await session.execute(_SET_TENANT, {"tid": previous or ""})


@contextlib.asynccontextmanager
async def job_session(tenant_id: uuid.UUID | None = None) -> AsyncIterator[AsyncSession]:
    """One transaction for a job/worker step, bound to ``tenant_id`` when given."""
    factory = get_session_factory()
    async with factory() as session, session.begin():
        await set_tenant(session, tenant_id)
        yield session


def current_tenant_id(request: Request) -> uuid.UUID | None:
    """Tenant bound so far on this request (set by ``get_current_user``)."""
    tenant: uuid.UUID | None = getattr(request.state, "tenant_id", None)
    return tenant


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: one transaction per request with the tenant bound."""
    factory = get_session_factory()
    async with factory() as session, session.begin():
        await set_tenant(session, current_tenant_id(request))
        yield session
