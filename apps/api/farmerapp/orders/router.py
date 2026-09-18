"""``/v1/orders`` — the order list and detail (FA-020, ST-005, FM-010).

Scope (``farmerapp.auth.scope.order_filters``): owner / director / tenant admin / auditor /
accountant see the tenant, a cluster head the orders of their cluster's stores, a store
manager their store's queue, a field officer the orders they placed, a farmer their own.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import order_filters
from farmerapp.orders.models import Order, OrderChannel, OrderLine, OrderStatus
from farmerapp.orders.schemas import OrderDetailOut, OrderLineOut, OrderOut, OrderPage
from farmerapp.payments.models import Payment
from farmerapp.payments.schemas import PaymentOut

router = APIRouter(prefix="/orders", tags=["orders"])

ORDER_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.FARMER,
)


async def visible_order(session: DbSession, actor: User, order_id: uuid.UUID) -> Order:
    """The order if it exists and is within the actor's scope; else 404."""
    order = (
        await session.execute(
            select(Order).where(
                Order.id == order_id, Order.deleted_at.is_(None), *order_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if order is None:
        raise NotFoundError("Order not found.")
    return order


@router.get(
    "",
    operation_id="listOrders",
    summary="Orders visible to the caller, oldest first",
    response_model=OrderPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_orders(
    actor: Annotated[User, require_roles(*ORDER_ROLES)],
    session: DbSession,
    page: Page,
    store_id: Annotated[uuid.UUID | None, Query()] = None,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
    status: Annotated[OrderStatus | None, Query()] = None,
    channel: Annotated[OrderChannel | None, Query()] = None,
    placed_from: Annotated[datetime | None, Query(alias="from")] = None,
    placed_to: Annotated[datetime | None, Query(alias="to")] = None,
) -> OrderPage:
    stmt = select(Order).where(Order.deleted_at.is_(None), *order_filters(actor))
    if store_id is not None:
        stmt = stmt.where(Order.store_id == store_id)
    if farmer_id is not None:
        stmt = stmt.where(Order.farmer_id == farmer_id)
    if status is not None:
        stmt = stmt.where(Order.status == status.value)
    if channel is not None:
        stmt = stmt.where(Order.channel == channel.value)
    if placed_from is not None:
        stmt = stmt.where(Order.created_at >= placed_from)
    if placed_to is not None:
        stmt = stmt.where(Order.created_at <= placed_to)
    after = page.after(Order.created_at, Order.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Order.created_at, Order.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return OrderPage(items=[OrderOut.model_validate(o) for o in items], next_cursor=next_cursor)


@router.get(
    "/{id}",
    operation_id="getOrder",
    summary="One order with its lines and payments",
    response_model=OrderDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_order(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ORDER_ROLES)],
    session: DbSession,
) -> OrderDetailOut:
    order = await visible_order(session, actor, id)
    lines = (
        (
            await session.execute(
                select(OrderLine)
                .where(OrderLine.order_id == order.id, OrderLine.deleted_at.is_(None))
                .order_by(OrderLine.created_at, OrderLine.id)
            )
        )
        .scalars()
        .all()
    )
    payments = (
        (
            await session.execute(
                select(Payment)
                .where(Payment.order_id == order.id, Payment.deleted_at.is_(None))
                .order_by(Payment.created_at, Payment.id)
            )
        )
        .scalars()
        .all()
    )
    return OrderDetailOut(
        **OrderOut.model_validate(order).model_dump(),
        lines=[OrderLineOut.model_validate(line) for line in lines],
        payments=[PaymentOut.model_validate(p) for p in payments],
    )


__all__ = ["ORDER_ROLES", "router", "visible_order"]
