"""The request-scoped session dependency binds ``app.tenant_id`` for RLS."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
from fastapi import Request
from sqlalchemy import text

from farmerapp.db import session as session_mod


def _request(tenant_id: uuid.UUID | None) -> Request:
    request = Request({"type": "http", "method": "GET", "path": "/", "headers": []})
    if tenant_id is not None:
        request.state.tenant_id = tenant_id
    return request


@pytest.fixture
async def fresh_engine(migrated_database: str) -> AsyncIterator[None]:
    session_mod.get_engine.cache_clear()
    session_mod.get_session_factory.cache_clear()
    yield
    await session_mod.get_engine().dispose()
    session_mod.get_engine.cache_clear()
    session_mod.get_session_factory.cache_clear()


async def test_get_session_binds_tenant(fresh_engine: None) -> None:
    tenant_id = uuid.uuid4()
    gen = session_mod.get_session(_request(tenant_id))
    session = await anext(gen)
    bound = await session.scalar(text("SELECT current_setting('app.tenant_id', true)"))
    assert bound == str(tenant_id)
    await session.rollback()
    with pytest.raises(StopAsyncIteration):
        await anext(gen)


async def test_get_session_without_tenant(fresh_engine: None) -> None:
    assert session_mod.current_tenant_id(_request(None)) is None
    gen = session_mod.get_session(_request(None))
    session = await anext(gen)
    bound = await session.scalar(text("SELECT current_setting('app.tenant_id', true)"))
    assert bound in (None, "")
    await session.rollback()
    with pytest.raises(StopAsyncIteration):
        await anext(gen)
