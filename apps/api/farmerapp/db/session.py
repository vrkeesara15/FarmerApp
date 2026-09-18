"""Async engine and session factory, plus the per-request tenant hook.

Row-level security (FA-003 / SEC-012) keys on the Postgres setting ``app.tenant_id``.
``set_tenant`` sets it transaction-locally (``set_config(..., is_local=true)``) so it
cannot leak across pooled connections.

Tenant resolution: ``farmerapp.auth.deps.get_current_user`` verifies the bearer token,
stores ``request.state.tenant_id`` / ``request.state.user`` and calls ``set_tenant`` on the
request session. Requests without a token (login, health) run with no tenant bound.

``set_bypass_rls`` sets ``app.bypass_rls = 'on'`` for the transaction. It is reserved for the
auth module: login-by-phone happens before the tenant is known, so the user lookup must
cross tenants. FA-003 will make the RLS policies honour it
(``USING (tenant_id = current_setting('app.tenant_id')::uuid OR
current_setting('app.bypass_rls', true) = 'on')``).
"""

from __future__ import annotations

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
    return async_sessionmaker(get_engine(), expire_on_commit=False)


async def set_tenant(session: AsyncSession, tenant_id: uuid.UUID | None) -> None:
    """Bind ``app.tenant_id`` for the current transaction (no-op when ``None``).

    Must be called inside an open transaction; ``SET LOCAL`` semantics via ``set_config``.
    """
    if tenant_id is None:
        return
    await session.execute(
        text("SELECT set_config('app.tenant_id', :tid, true)"), {"tid": str(tenant_id)}
    )


async def set_bypass_rls(session: AsyncSession) -> None:
    """Auth-module only: allow cross-tenant reads for the current transaction (see module doc)."""
    await session.execute(text("SELECT set_config('app.bypass_rls', 'on', true)"))


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
