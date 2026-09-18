"""Stock routes (ST-003, ST-004).

* ``GET /v1/stores/{id}/stock`` — batches with on-hand (ledger sum), reserved and available
  quantities.
* ``POST /v1/stores/{id}/stock/receipts`` — goods receipt.
* ``POST /v1/stock/transfers`` — transfer between two stores (atomic out + in).
* ``POST /v1/stores/{id}/stock/write-offs`` — damage / expiry write-off with a photo.
* ``POST /v1/stores/{id}/stock/adjustments`` — stock count correction (store manager only,
  audited).

Store internals follow ``STORE_VISIBILITY``: owner / director / tenant admin / auditor /
accountant see every store, a cluster head their cluster, a store manager their own store;
a store outside the caller's scope is a 404. Writes need a store role that runs stock
(``STOCK_WRITE_ROLES``); the destination of a transfer may be any store of the tenant.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import visible_store_filters
from farmerapp.stock import service
from farmerapp.stock.ledger import reserved_by_batch, stock_on_hand_by_batch
from farmerapp.stock.models import StockBatch
from farmerapp.stock.schemas import (
    AdjustmentIn,
    ReceiptIn,
    StockBatchOut,
    StockPage,
    StockWriteOut,
    TransferIn,
    WriteOffIn,
)
from farmerapp.tenants.models import Store

router = APIRouter(tags=["stock"])

STOCK_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
)
#: Who receives, transfers and writes off stock (auditor / accountant / tenant admin read).
STOCK_WRITE_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD, Role.STORE_MANAGER)

_WRITE_PROBLEMS = (
    (404, "not_found"),
    (409, "negative_stock"),
    (409, "batch_mismatch"),
    (422, "invalid_stock_request"),
    (422, "validation_error"),
)


async def visible_store(session: DbSession, actor: User, store_id: uuid.UUID) -> Store:
    """The store if it exists and is within the actor's scope; else 404."""
    store = (
        await session.execute(
            select(Store).where(
                Store.id == store_id, Store.deleted_at.is_(None), *visible_store_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if store is None:
        raise NotFoundError("Store not found.")
    return store


async def tenant_store(session: DbSession, actor: User, store_id: uuid.UUID) -> Store:
    """Any live store of the actor's tenant (transfer destination); else 404."""
    store = (
        await session.execute(
            select(Store).where(
                Store.id == store_id,
                Store.tenant_id == actor.tenant_id,
                Store.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if store is None:
        raise NotFoundError("Store not found.")
    return store


@router.get(
    "/stores/{id}/stock",
    operation_id="listStoreStock",
    summary="Stock batches of a store with on-hand, reserved and available quantity",
    response_model=StockPage,
    responses=problem_responses((400, "invalid_cursor"), (404, "not_found")),
)
async def list_store_stock(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*STOCK_ROLES)],
    session: DbSession,
    services: Services,
    page: Page,
    sku_id: Annotated[uuid.UUID | None, Query()] = None,
    expiring_within_days: Annotated[
        int | None, Query(ge=0, description="Only batches expiring within N days (ST-004).")
    ] = None,
    include_empty: Annotated[bool, Query(description="Include batches with zero stock.")] = False,
) -> StockPage:
    store = await visible_store(session, actor, id)
    today = services.clock.now().date()
    stmt = select(StockBatch).where(
        StockBatch.store_id == store.id, StockBatch.deleted_at.is_(None)
    )
    if sku_id is not None:
        stmt = stmt.where(StockBatch.sku_id == sku_id)
    if expiring_within_days is not None:
        stmt = stmt.where(
            StockBatch.expiry.is_not(None),
            StockBatch.expiry <= today + timedelta(days=expiring_within_days),
        )
    if not include_empty:
        stmt = stmt.where(StockBatch.qty > 0)
    after = page.after(StockBatch.created_at, StockBatch.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(StockBatch.created_at, StockBatch.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    on_hand = await stock_on_hand_by_batch(session, store.id)
    reserved = await reserved_by_batch(session, [b.id for b in items])
    return StockPage(
        items=[
            StockBatchOut.from_row(
                b,
                on_hand=on_hand.get(b.id, b.qty * 0),
                today=today,
                reserved=reserved.get(b.id, b.qty * 0),
            )
            for b in items
        ],
        next_cursor=next_cursor,
    )


@router.post(
    "/stores/{id}/stock/receipts",
    operation_id="receiveStock",
    summary="Goods receipt: receipt movements into new or existing batches (ST-003)",
    status_code=201,
    response_model=StockWriteOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
async def receive_stock(
    id: uuid.UUID,
    body: ReceiptIn,
    actor: Annotated[User, require_roles(*STOCK_WRITE_ROLES)],
    session: DbSession,
) -> StockWriteOut:
    store = await visible_store(session, actor, id)
    return await service.receive(session, actor, store, body)


@router.post(
    "/stock/transfers",
    operation_id="transferStock",
    summary="Transfer batches between stores: transfer_out + transfer_in atomically (ST-003)",
    status_code=201,
    response_model=StockWriteOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
async def transfer_stock(
    body: TransferIn,
    actor: Annotated[User, require_roles(*STOCK_WRITE_ROLES)],
    session: DbSession,
) -> StockWriteOut:
    source = await visible_store(session, actor, body.from_store_id)
    target = await tenant_store(session, actor, body.to_store_id)
    return await service.transfer(session, actor, source, target, body)


@router.post(
    "/stores/{id}/stock/write-offs",
    operation_id="writeOffStock",
    summary="Damage / expiry write-off with reason and optional photo (ST-003)",
    status_code=201,
    response_model=StockWriteOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
async def write_off_stock(
    id: uuid.UUID,
    body: WriteOffIn,
    actor: Annotated[User, require_roles(*STOCK_WRITE_ROLES)],
    session: DbSession,
) -> StockWriteOut:
    store = await visible_store(session, actor, id)
    return await service.write_off(session, actor, store, body)


@router.post(
    "/stores/{id}/stock/adjustments",
    operation_id="adjustStock",
    summary="Stock count correction to the counted quantity (store manager, audited)",
    status_code=201,
    response_model=StockWriteOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
async def adjust_stock(
    id: uuid.UUID,
    body: AdjustmentIn,
    actor: Annotated[User, require_roles(Role.STORE_MANAGER)],
    session: DbSession,
) -> StockWriteOut:
    store = await visible_store(session, actor, id)
    return await service.adjust(session, actor, store, body)


__all__ = ["STOCK_ROLES", "STOCK_WRITE_ROLES", "router", "tenant_store", "visible_store"]
