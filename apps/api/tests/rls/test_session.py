"""The tenant binding is transaction-local: pooled connections never carry it over."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
from fastapi import Request
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from farmerapp.db import session as session_mod
from farmerapp.db.session import clear_tenant, set_tenant, tenant_scope

SETTING = text("SELECT current_setting('app.tenant_id', true)")


def _request(tenant_id: uuid.UUID | None) -> Request:
    request = Request({"type": "http", "method": "GET", "path": "/", "headers": []})
    if tenant_id is not None:
        request.state.tenant_id = tenant_id
    return request


@pytest.fixture
async def single_connection_factory(
    migrated_database: str,
) -> AsyncIterator[async_sessionmaker[AsyncSession]]:
    """A pool of exactly one connection so consecutive sessions provably reuse it."""
    engine = create_async_engine(migrated_database, pool_size=1, max_overflow=0)
    try:
        yield async_sessionmaker(engine, expire_on_commit=False)
    finally:
        await engine.dispose()


async def test_tenant_does_not_leak_across_pooled_sessions(
    single_connection_factory: async_sessionmaker[AsyncSession],
) -> None:
    tenant_a = uuid.uuid4()
    async with single_connection_factory() as session, session.begin():
        await set_tenant(session, tenant_a)
        assert await session.scalar(SETTING) == str(tenant_a)
        pid_a = await session.scalar(text("SELECT pg_backend_pid()"))
    # committed: the connection went back to the pool
    async with single_connection_factory() as session, session.begin():
        assert await session.scalar(text("SELECT pg_backend_pid()")) == pid_a  # same connection
        assert (await session.scalar(SETTING)) in (None, "")
        await set_tenant(session, uuid.uuid4())
        await session.rollback()
    async with single_connection_factory() as session, session.begin():
        assert (await session.scalar(SETTING)) in (None, "")


async def test_get_session_dependency_resets_between_requests(
    single_connection_factory: async_sessionmaker[AsyncSession], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(session_mod, "get_session_factory", lambda: single_connection_factory)
    tenant_a = uuid.uuid4()

    async def run(request: Request) -> str | None:
        gen = session_mod.get_session(request)
        session = await anext(gen)
        value: str | None = await session.scalar(SETTING)
        await session.commit()
        with pytest.raises(StopAsyncIteration):
            await anext(gen)
        return value

    assert await run(_request(tenant_a)) == str(tenant_a)
    assert await run(_request(None)) in (None, "")
    assert await run(_request(tenant_a)) == str(tenant_a)


async def test_tenant_scope_restores_previous_binding(db_session: AsyncSession) -> None:
    outer, inner = uuid.uuid4(), uuid.uuid4()
    await clear_tenant(db_session)
    async with tenant_scope(db_session, outer):
        assert await db_session.scalar(SETTING) == str(outer)
        async with tenant_scope(db_session, inner):
            assert await db_session.scalar(SETTING) == str(inner)
        assert await db_session.scalar(SETTING) == str(outer)
    assert (await db_session.scalar(SETTING)) in (None, "")


async def test_tenant_scope_restores_after_an_error(db_session: AsyncSession) -> None:
    outer, inner = uuid.uuid4(), uuid.uuid4()
    await set_tenant(db_session, outer)
    with pytest.raises(RuntimeError):
        async with tenant_scope(db_session, inner):
            raise RuntimeError("boom")
    assert await db_session.scalar(SETTING) == str(outer)
