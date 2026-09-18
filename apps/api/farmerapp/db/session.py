"""Async engine and session factory, plus the per-request tenant hook.

Row-level security (FA-003 / SEC-012) keys on the Postgres setting ``app.tenant_id``.
``set_tenant`` sets it transaction-locally (``set_config(..., is_local=true)``) so it
cannot leak across pooled connections. Until auth lands (FA-001) the request-scoped
tenant resolver is a stub returning ``None``.
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


def current_tenant_id(request: Request) -> uuid.UUID | None:
    """Stub: tenant comes from the verified JWT once FA-001/FA-002 land."""
    tenant: uuid.UUID | None = getattr(request.state, "tenant_id", None)
    return tenant


async def get_session(request: Request) -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: one transaction per request with the tenant bound."""
    factory = get_session_factory()
    async with factory() as session, session.begin():
        await set_tenant(session, current_tenant_id(request))
        yield session
