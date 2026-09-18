"""``GET /v1/stores/{id}/stock`` — batches with on-hand quantities (ST-003, ST-004).

Store internals follow ``STORE_VISIBILITY``: owner / director / tenant admin / auditor /
accountant see every store, a cluster head their cluster, a store manager their own store;
a store outside the caller's scope is a 404. ``on_hand`` is the sum of the movement ledger
per batch (the truth), ``qty`` the cache kept with it.
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
from farmerapp.stock.ledger import stock_on_hand_by_batch
from farmerapp.stock.models import StockBatch
from farmerapp.stock.schemas import StockBatchOut, StockPage
from farmerapp.tenants.models import Store

router = APIRouter(prefix="/stores", tags=["stock"])

STOCK_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
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


@router.get(
    "/{id}/stock",
    operation_id="listStoreStock",
    summary="Stock batches of a store with on-hand quantity and days to expiry",
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
    return StockPage(
        items=[
            StockBatchOut.from_row(b, on_hand=on_hand.get(b.id, b.qty * 0), today=today)
            for b in items
        ],
        next_cursor=next_cursor,
    )


__all__ = ["STOCK_ROLES", "router", "visible_store"]
