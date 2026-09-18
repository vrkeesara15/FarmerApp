"""Order routes (FA-020, ST-005, FM-010).

* ``GET /v1/orders``, ``GET /v1/orders/{id}`` — list and detail (lines, payments, status
  history, reservations).
* ``POST /v1/orders`` — FA-020 capture: a field officer for their own farmers, store staff
  (store manager / accountant) at their own store, a farmer for themselves; prices and
  totals recomputed server-side, FEFO stock reservation, ST-007 credit gate (402
  ``credit_limit_exceeded``).
* ``POST /v1/orders/{id}/status`` — ST-005 queue transitions (store roles, own store).
* ``GET /v1/stores/{id}/order-queue`` — the store's queue (S05), open orders by default.
* ``GET /v1/stores/nearest?farmer_id=`` — where an order for the farmer goes (village
  store, else nearest by distance) with availability of the requested SKUs.

Scope (``farmerapp.auth.scope.order_filters``): owner / director / tenant admin / auditor /
accountant see the tenant, a cluster head the orders of their cluster's stores, a store
manager their store's queue, a field officer the orders they placed, a farmer their own.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Query, Request
from fastapi.responses import JSONResponse
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_response, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import farmer_filters, order_filters
from farmerapp.farmers.models import Farmer
from farmerapp.khata.credit import CreditLimitExceededError, decision_extra
from farmerapp.orders import service
from farmerapp.orders.models import OPEN_STATUSES, Order, OrderChannel, OrderLine, OrderStatus
from farmerapp.orders.schemas import (
    NearestStoreOut,
    OrderCreate,
    OrderDetailOut,
    OrderLineOut,
    OrderOut,
    OrderPage,
    OrderQueueItemOut,
    OrderQueuePage,
    OrderStatusIn,
    SkuAvailabilityOut,
    StoreBriefOut,
)
from farmerapp.stock.ledger import reserved_by_sku, stock_on_hand_by_sku
from farmerapp.stock.router import STOCK_ROLES, visible_store

router = APIRouter(tags=["orders"])

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
#: FA-020: who places orders (officer for own farmers, store staff, farmer for self).
PLACE_ROLES = (Role.FIELD_OFFICER, Role.STORE_MANAGER, Role.ACCOUNTANT, Role.FARMER)
#: ST-005: who moves orders through the queue (store scope).
QUEUE_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.ACCOUNTANT,
)
NEAREST_ROLES = (*PLACE_ROLES, Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN, Role.CLUSTER_HEAD)


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
    "/orders",
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


@router.post(
    "/orders",
    operation_id="placeOrder",
    summary="Place an order for a farmer: server prices, FEFO reservation, credit gate",
    status_code=201,
    response_model=OrderDetailOut,
    responses=problem_responses(
        (402, "credit_limit_exceeded"),
        (404, "not_found"),
        (409, "insufficient_stock"),
        (409, "amount_mismatch"),
        (409, "order_exists"),
        (422, "invalid_order"),
        (422, "validation_error"),
    ),
)
async def place_order(
    body: OrderCreate,
    request: Request,
    actor: Annotated[User, require_roles(*PLACE_ROLES)],
    session: DbSession,
    services: Services,
) -> OrderDetailOut | JSONResponse:
    result = await service.place_order(session, actor, body, today=services.clock.now().date())
    if result.blocked is not None:
        # Returned, not raised: the approval request must commit with this transaction.
        return problem_response(
            request,
            status=CreditLimitExceededError.status,
            code=CreditLimitExceededError.code,
            detail="This credit sale is beyond the farmer's limit; a cluster head must approve it.",
            extra=decision_extra(result.blocked),
        )
    if result.order is None:  # pragma: no cover - place_order returns one or the other
        raise RuntimeError("place_order returned neither an order nor a block")
    return result.order


@router.get(
    "/orders/{id}",
    operation_id="getOrder",
    summary="One order with its lines, payments, status history and reservations",
    response_model=OrderDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_order(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ORDER_ROLES)],
    session: DbSession,
) -> OrderDetailOut:
    order = await visible_order(session, actor, id)
    return await service.order_detail(session, order)


@router.post(
    "/orders/{id}/status",
    operation_id="changeOrderStatus",
    summary="Move an order through the store queue (ST-005)",
    response_model=OrderDetailOut,
    responses=problem_responses(
        (404, "not_found"), (409, "invalid_transition"), (409, "insufficient_stock")
    ),
)
async def change_order_status(
    id: uuid.UUID,
    body: OrderStatusIn,
    actor: Annotated[User, require_roles(*QUEUE_ROLES)],
    session: DbSession,
    services: Services,
) -> OrderDetailOut:
    order = await visible_order(session, actor, id)
    return await service.change_status(
        session, actor, order, body, today=services.clock.now().date()
    )


@router.get(
    "/stores/{id}/order-queue",
    operation_id="getStoreOrderQueue",
    summary="The store's order queue with lines, oldest first (ST-005, S05)",
    response_model=OrderQueuePage,
    responses=problem_responses((400, "invalid_cursor"), (404, "not_found")),
)
async def store_order_queue(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*STOCK_ROLES)],
    session: DbSession,
    page: Page,
    status: Annotated[
        list[OrderStatus] | None, Query(description="Default: the open statuses.")
    ] = None,
) -> OrderQueuePage:
    store = await visible_store(session, actor, id)
    wanted = [s.value for s in (status or sorted(OPEN_STATUSES))]
    stmt = select(Order).where(
        Order.store_id == store.id, Order.deleted_at.is_(None), Order.status.in_(wanted)
    )
    after = page.after(Order.created_at, Order.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Order.created_at, Order.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    lines: dict[uuid.UUID, list[OrderLineOut]] = {}
    if items:
        for line in (
            await session.execute(
                select(OrderLine)
                .where(
                    OrderLine.order_id.in_([o.id for o in items]),
                    OrderLine.deleted_at.is_(None),
                )
                .order_by(OrderLine.created_at, OrderLine.id)
            )
        ).scalars():
            lines.setdefault(line.order_id, []).append(OrderLineOut.model_validate(line))
    return OrderQueuePage(
        items=[
            OrderQueueItemOut(**OrderOut.model_validate(o).model_dump(), lines=lines.get(o.id, []))
            for o in items
        ],
        next_cursor=next_cursor,
    )


@router.get(
    "/stores/nearest",
    operation_id="getNearestStore",
    summary="The store an order for this farmer goes to, with SKU availability (FA-020)",
    response_model=NearestStoreOut,
    responses=problem_responses(
        (404, "not_found"), (422, "invalid_order"), (422, "validation_error")
    ),
)
async def get_nearest_store(
    actor: Annotated[User, require_roles(*NEAREST_ROLES)],
    session: DbSession,
    farmer_id: Annotated[
        uuid.UUID | None, Query(description="Required except for a farmer (self).")
    ] = None,
    sku_id: Annotated[list[uuid.UUID] | None, Query(max_length=50)] = None,
) -> NearestStoreOut:
    stmt = select(Farmer).where(Farmer.deleted_at.is_(None), *farmer_filters(actor))
    if farmer_id is not None:
        stmt = stmt.where(Farmer.id == farmer_id)
    elif UserRole(actor.role) != UserRole.FARMER:
        raise service.InvalidOrderError("farmer_id is required.")
    farmer = (await session.execute(stmt.order_by(Farmer.created_at).limit(1))).scalar()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    nearest = await service.nearest_store(session, farmer)
    stock: list[SkuAvailabilityOut] = []
    if sku_id:
        on_hand = await stock_on_hand_by_sku(session, nearest.store.id, sku_id)
        reserved = await reserved_by_sku(session, nearest.store.id, sku_id)
        zero = Decimal("0.000")
        for sid in dict.fromkeys(sku_id):
            have, held = on_hand.get(sid, zero), reserved.get(sid, zero)
            stock.append(
                SkuAvailabilityOut(sku_id=sid, on_hand=have, reserved=held, available=have - held)
            )
    return NearestStoreOut(
        farmer_id=farmer.id,
        store=StoreBriefOut.model_validate(nearest.store),
        distance_m=nearest.distance_m,
        source=nearest.source,
        stock=stock,
    )


__all__ = ["NEAREST_ROLES", "ORDER_ROLES", "PLACE_ROLES", "QUEUE_ROLES", "router", "visible_order"]
