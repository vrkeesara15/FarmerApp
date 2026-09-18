"""Gapless invoice numbering under concurrency (ST-001, GST rule 46).

Two real transactions on two connections (not the rolled-back test transaction): the
second waits on the counter row lock until the first ends, so numbers are unique and a
rolled-back sale gives its number back. The tenant and store are committed by the migrate
role for the duration of the test and removed afterwards.
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from farmerapp.db.session import set_tenant
from farmerapp.invoices.numbering import next_seq

FY = "2026-27"


@pytest.fixture
async def committed_store(
    migrate_engine: AsyncEngine,
) -> AsyncIterator[tuple[uuid.UUID, uuid.UUID]]:
    tenant_id, store_id = uuid.uuid4(), uuid.uuid4()
    async with migrate_engine.begin() as conn:
        await conn.execute(
            text("INSERT INTO tenant (id, tenant_id, name) VALUES (:t, :t, 'Numbering test')"),
            {"t": tenant_id},
        )
        await conn.execute(
            text(
                "INSERT INTO store (id, tenant_id, code, name, district, location) VALUES "
                "(:s, :t, 'NUM', 'Numbering', 'Warangal', "
                "ST_GeogFromText('SRID=4326;POINT(79.5 18.0)'))"
            ),
            {"s": store_id, "t": tenant_id},
        )
    try:
        yield tenant_id, store_id
    finally:
        async with migrate_engine.begin() as conn:
            await conn.execute(
                text("DELETE FROM invoice_counter WHERE tenant_id = :t"), {"t": tenant_id}
            )
            await conn.execute(text("DELETE FROM store WHERE id = :s"), {"s": store_id})
            await conn.execute(text("DELETE FROM tenant WHERE id = :t"), {"t": tenant_id})


async def _take(
    engine: AsyncEngine,
    tenant_id: uuid.UUID,
    store_id: uuid.UUID,
    *,
    hold: asyncio.Event | None = None,
    taken: asyncio.Event | None = None,
    commit: bool = True,
) -> int:
    async with AsyncSession(engine) as session, session.begin():
        await set_tenant(session, tenant_id)
        seq = await next_seq(session, tenant_id=tenant_id, store_id=store_id, fy=FY)
        if taken is not None:
            taken.set()
        if hold is not None:
            await hold.wait()
        if not commit:
            await session.rollback()
        return seq


async def test_two_sessions_get_consecutive_numbers(
    app_engine: AsyncEngine, committed_store: tuple[uuid.UUID, uuid.UUID]
) -> None:
    tenant_id, store_id = committed_store
    release, first_taken = asyncio.Event(), asyncio.Event()
    first = asyncio.create_task(
        _take(app_engine, tenant_id, store_id, hold=release, taken=first_taken)
    )
    await first_taken.wait()
    second = asyncio.create_task(_take(app_engine, tenant_id, store_id))
    await asyncio.sleep(0.3)
    assert not second.done(), "the second sale must wait for the counter row lock"
    release.set()
    assert sorted([await first, await second]) == [1, 2]
    assert await _take(app_engine, tenant_id, store_id) == 3


async def test_rolled_back_sale_gives_its_number_back(
    app_engine: AsyncEngine, committed_store: tuple[uuid.UUID, uuid.UUID]
) -> None:
    tenant_id, store_id = committed_store
    release, first_taken = asyncio.Event(), asyncio.Event()
    doomed = asyncio.create_task(
        _take(app_engine, tenant_id, store_id, hold=release, taken=first_taken, commit=False)
    )
    await first_taken.wait()
    waiting = asyncio.create_task(_take(app_engine, tenant_id, store_id))
    await asyncio.sleep(0.2)
    release.set()
    assert await doomed == 1
    assert await waiting == 1  # no gap: the rolled-back number is reused
    assert await _take(app_engine, tenant_id, store_id) == 2
