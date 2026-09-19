"""``/v1/stores/{id}/reorder-levels`` — ST-004 reorder level per SKU per store.

Read by the stock roles of the store (``STOCK_ROLES``), set by the stock writers
(``STOCK_WRITE_ROLES``: owner, director, cluster head, store manager of the store). A SKU
without a row uses the tenant default (``stock_alerts.default_reorder_level``), echoed in the
response.
"""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import require_roles
from farmerapp.catalog.models import Sku
from farmerapp.stock.reorder import ReorderLevel
from farmerapp.stock.router import STOCK_ROLES, STOCK_WRITE_ROLES, visible_store
from farmerapp.tenants.settings import get_tenant_settings

router = APIRouter(tags=["stock"])


class ReorderLevelIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sku_id: uuid.UUID
    reorder_level: Decimal = Field(ge=0, max_digits=12, decimal_places=3)


class ReorderLevelsIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[ReorderLevelIn] = Field(min_length=1, max_length=1000)


class ReorderLevelOut(BaseModel):
    sku_id: uuid.UUID
    reorder_level: Decimal


class ReorderLevelsOut(BaseModel):
    store_id: uuid.UUID
    default_reorder_level: int = Field(description="Tenant default for SKUs without a row.")
    items: list[ReorderLevelOut]


async def _out(session: DbSession, actor: User, store_id: uuid.UUID) -> ReorderLevelsOut:
    rows = (
        await session.execute(
            select(ReorderLevel)
            .where(
                ReorderLevel.tenant_id == actor.tenant_id,
                ReorderLevel.store_id == store_id,
                ReorderLevel.deleted_at.is_(None),
            )
            .order_by(ReorderLevel.sku_id)
        )
    ).scalars()
    settings = await get_tenant_settings(session, actor.tenant_id)
    return ReorderLevelsOut(
        store_id=store_id,
        default_reorder_level=settings.stock_alerts.default_reorder_level,
        items=[ReorderLevelOut(sku_id=r.sku_id, reorder_level=r.reorder_level) for r in rows],
    )


@router.get(
    "/stores/{id}/reorder-levels",
    operation_id="listReorderLevels",
    summary="ST-004 reorder levels of a store's SKUs (plus the tenant default)",
    response_model=ReorderLevelsOut,
    responses=problem_responses((404, "not_found")),
)
async def list_reorder_levels(
    id: uuid.UUID, actor: Annotated[User, require_roles(*STOCK_ROLES)], session: DbSession
) -> ReorderLevelsOut:
    store = await visible_store(session, actor, id)
    return await _out(session, actor, store.id)


@router.put(
    "/stores/{id}/reorder-levels",
    operation_id="setReorderLevels",
    summary="Set reorder levels per SKU for a store (ST-004 low-stock alerts)",
    response_model=ReorderLevelsOut,
    responses=problem_responses((404, "not_found")),
)
async def set_reorder_levels(
    id: uuid.UUID,
    body: ReorderLevelsIn,
    actor: Annotated[User, require_roles(*STOCK_WRITE_ROLES)],
    session: DbSession,
) -> ReorderLevelsOut:
    store = await visible_store(session, actor, id)
    sku_ids = {item.sku_id for item in body.items}
    known = set(
        (
            await session.execute(
                select(Sku.id).where(
                    Sku.id.in_(sku_ids), Sku.tenant_id == actor.tenant_id, Sku.deleted_at.is_(None)
                )
            )
        ).scalars()
    )
    if known != sku_ids:
        raise NotFoundError("SKU not found.", extra={"sku_ids": sorted(map(str, sku_ids - known))})
    existing = {
        r.sku_id: r
        for r in (
            await session.execute(
                select(ReorderLevel).where(
                    ReorderLevel.tenant_id == actor.tenant_id,
                    ReorderLevel.store_id == store.id,
                    ReorderLevel.sku_id.in_(sku_ids),
                )
            )
        ).scalars()
    }
    for item in body.items:
        row = existing.get(item.sku_id)
        if row is None:
            row = ReorderLevel(
                tenant_id=actor.tenant_id, store_id=store.id, sku_id=item.sku_id, reorder_level=0
            )
            session.add(row)
            existing[item.sku_id] = row
        row.reorder_level = item.reorder_level
        row.deleted_at = None
    await session.flush()
    return await _out(session, actor, store.id)


__all__ = ["router"]
