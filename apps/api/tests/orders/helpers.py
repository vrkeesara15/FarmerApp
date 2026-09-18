"""Shared helpers for the FA-020 / ST-003 / ST-005 / ST-007 / FA-022 write-path tests."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.stock.models import StockBatch, StockMovement
from farmerapp.tenants.models import Store
from tests.authz.conftest import Bearer, SeededTenant, World


def today() -> date:
    return datetime.now(UTC).date()


def demo_farmer(tenant: SeededTenant) -> Farmer:
    """The farmer with an app login (registered by the role officer, lives in the store
    manager's store's village)."""
    return next(f for f in tenant.farmers if f.user_id is not None)


def user(tenant: SeededTenant, role: str | UserRole) -> User:
    return tenant.user(role)


async def receive(
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    *,
    qty: str | int = 10,
    batch_no: str | None = None,
    expiry: date | None = None,
    sku_id: uuid.UUID | None = None,
    store_id: uuid.UUID | None = None,
    cost_paise: int = 1000,
    actor: User | None = None,
) -> dict[str, Any]:
    """Goods receipt of one batch (default: the fixture SKU at the store manager's store,
    expiring in 300 days) — returns the batch state."""
    store = store_id or world.a.store_id
    resp = await client.post(
        f"/v1/stores/{store}/stock/receipts",
        json={
            "reference": "GRN-TEST",
            "lines": [
                {
                    "sku_id": str(sku_id or world.a.sku_id),
                    "batch_no": batch_no or f"T-{uuid.uuid4().hex[:8]}",
                    "expiry": (expiry or today() + timedelta(days=300)).isoformat(),
                    "qty": str(qty),
                    "cost_paise": cost_paise,
                }
            ],
        },
        headers=bearer(actor or world.a.user(UserRole.STORE_MANAGER)),
    )
    assert resp.status_code == 201, resp.text
    batch: dict[str, Any] = resp.json()["batches"][0]
    return batch


async def available(
    db_session: AsyncSession, world: World, sku_id: uuid.UUID | None, store_id: uuid.UUID | None
) -> Decimal:
    """Unexpired, unreserved stock of the SKU at the store (what FEFO can take)."""
    from farmerapp.stock.ledger import reserved_by_batch

    async with tenant_scope(db_session, world.a.tenant.id):
        batches = (
            (
                await db_session.execute(
                    select(StockBatch).where(
                        StockBatch.store_id == store_id,
                        StockBatch.sku_id == sku_id,
                        StockBatch.qty > 0,
                    )
                )
            )
            .scalars()
            .all()
        )
        live = [b for b in batches if b.expiry is None or b.expiry >= today()]
        held = await reserved_by_batch(db_session, [b.id for b in live])
    return sum((b.qty - held.get(b.id, Decimal(0)) for b in live), Decimal(0))


async def ledger_by_batch(
    db_session: AsyncSession, batch_ids: list[uuid.UUID]
) -> dict[uuid.UUID, Decimal]:
    rows = await db_session.execute(
        select(StockMovement.batch_id, func.sum(StockMovement.qty))
        .where(StockMovement.batch_id.in_(batch_ids))
        .group_by(StockMovement.batch_id)
    )
    return {b: Decimal(q) for b, q in rows}


async def assert_cache_matches_ledger(
    db_session: AsyncSession, store_ids: Sequence[uuid.UUID | None]
) -> None:
    """ST-003: for every batch of the stores, cached qty == sum of its movements >= 0."""
    batches = (
        (
            await db_session.execute(
                select(StockBatch).where(StockBatch.store_id.in_([s for s in store_ids if s]))
            )
        )
        .scalars()
        .all()
    )
    ledger = await ledger_by_batch(db_session, [b.id for b in batches])
    for b in batches:
        await db_session.refresh(b)
        assert b.qty >= 0, b.batch_no
        assert b.qty == ledger.get(b.id, Decimal(0)), (b.batch_no, b.qty, ledger.get(b.id))


async def other_store(db_session: AsyncSession, world: World, *, same_cluster: bool) -> Store:
    head = world.a.user(UserRole.CLUSTER_HEAD)
    async with tenant_scope(db_session, world.a.tenant.id):
        stores = (await db_session.execute(select(Store).order_by(Store.code))).scalars().all()
    return next(
        s
        for s in stores
        if s.id != world.a.store_id and (s.cluster_id == head.cluster_id) is same_cluster
    )


def order_body(world: World, farmer: Farmer | None = None, **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "farmer_id": str((farmer or demo_farmer(world.a)).id),
        "fulfilment": "pickup",
        "lines": [{"sku_id": str(world.a.sku_id), "qty": "2"}],
    }
    body.update(overrides)
    return body


async def place(
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    *,
    actor: User | None = None,
    expect: int = 201,
    **overrides: Any,
) -> dict[str, Any]:
    resp = await client.post(
        "/v1/orders",
        json=order_body(world, **overrides),
        headers=bearer(actor or world.a.user(UserRole.FIELD_OFFICER)),
    )
    assert resp.status_code == expect, resp.text
    out: dict[str, Any] = resp.json()
    return out
