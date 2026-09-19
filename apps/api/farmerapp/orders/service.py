"""Order capture and the store queue (FA-020, ST-005) — shared by REST and sync.

Placing (``place_order``)
-------------------------
1. **Who for, where**: a field officer orders for their own farmers (``channel = officer``),
   a farmer for themselves (``farmer_app``), store staff (store manager / accountant) for
   any farmer of the tenant at their own store (``pos``). The store is the request's
   ``store_id``, the caller's own store for store staff, else the farmer's **nearest store**
   (``nearest_store``: the village's store, else the closest store by distance).
2. **Prices** are recomputed from the price list (``catalog.pricing.prices_for``, MRP
   fallback) and the product's GST: ``line_total = qty x unit`` (half-up), ``tax`` per line,
   ``total = subtotal + tax``. A client ``unit_price_paise`` or ``expected_total_paise``
   that differs is a 409 ``amount_mismatch`` carrying the server's numbers (SEC-023 spirit:
   amounts are always recomputed server-side).
3. **Stock**: ``allocate_fefo`` locks the store's unexpired batches and splits each line
   over them, earliest expiry first; short lines are a 409 ``insufficient_stock`` with the
   available quantity per line.
4. **Credit** (``payment_mode = credit``): ``khata.credit.check_and_reserve_credit``; beyond
   the limit nothing but the approval request is written and the caller answers 402
   ``credit_limit_exceeded`` (``PlaceResult.blocked``).
5. The order is written ``placed`` then ``reserved`` (two ``order_status_event`` rows) with
   its lines and ``stock_reservation`` rows; the farmer's login and the placing officer get
   a notification. A **prepaid** order (``payment_mode`` UPI QR / payment link) holds the
   same reservations but waits in ``placed`` until its payment is captured:
   ``farmerapp.orders.payment_events`` then moves it to ``reserved`` (FA-021 ``PaymentCaptured``).

Label claims (DX-007): a line that carries ``label_claim_id`` (a recommendation) is checked
with ``catalog.recommendable.assert_sku_recommendable``; anything but a live, approved claim
of that SKU is 422 ``sku_not_recommendable`` — for REST, the ``order`` sync op and the POS.

Queue (``change_status``)
-------------------------
``TRANSITIONS`` in ``orders.models``; anything else is a 409 ``invalid_transition``.
``placed -> reserved`` reserves stock (orders from before FA-020), ``cancelled`` releases
the reservation and reverses a credit debit, ``handed_over`` / ``delivered`` turn the
reservation into ``sale`` movements and issue the order's GST invoice
(``invoices.service.issue_order_invoice``: the POS numbering / GST / PDF path, once per order).
Every change writes an append-only ``order_status_event`` and a ``notification`` (kind
``order_status``) for the farmer's user and the placing user, never for the actor.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ConflictError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import farmer_filters
from farmerapp.catalog.errors import SkuNotRecommendable
from farmerapp.catalog.models import Product, Sku
from farmerapp.catalog.pricing import prices_for, resolved_price
from farmerapp.catalog.recommendable import assert_sku_recommendable
from farmerapp.farmers.models import Farmer
from farmerapp.khata.credit import CreditDecision, check_and_reserve_credit
from farmerapp.khata.ledger import post_credit
from farmerapp.khata.models import EntryRef, EntryType, KhataEntry
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import (
    FULFILLED_STATUSES,
    TRANSITIONS,
    Order,
    OrderChannel,
    OrderLine,
    OrderStatus,
    OrderStatusEvent,
    can_transition,
    line_total_paise,
    tax_paise,
)
from farmerapp.orders.schemas import (
    OrderCreate,
    OrderDetailOut,
    OrderLineOut,
    OrderOut,
    OrderReservationOut,
    OrderStatusEventOut,
    OrderStatusIn,
)
from farmerapp.payments.models import PROVIDER_MODES, Payment, PaymentMode
from farmerapp.payments.schemas import PaymentOut
from farmerapp.stock.models import StockReservation
from farmerapp.stock.service import (
    LineDemand,
    active_reservations,
    allocate_fefo,
    consume_order,
    hold_allocations,
    release_order,
)
from farmerapp.tenants.models import Store, Village
from farmerapp.uploads.blobstore import BlobStore

NOTIFICATION_KIND = "order_status"
NOTIFICATION_TITLE_KEY = "order.status.title"


class AmountMismatchError(ConflictError):
    code = "amount_mismatch"


class InvalidTransitionError(ConflictError):
    code = "invalid_transition"


class OrderExistsError(ConflictError):
    code = "order_exists"


class InvalidOrderError(AppError):
    status = 422
    code = "invalid_order"


@dataclass(frozen=True)
class PlaceResult:
    """Either the placed order or the credit decision that blocked it (402)."""

    order: OrderDetailOut | None = None
    blocked: CreditDecision | None = None


# --------------------------------------------------------------------------- nearest store
@dataclass(frozen=True)
class NearestStore:
    store: Store
    distance_m: float | None
    source: str  # "village" | "nearest"


async def nearest_store(session: AsyncSession, farmer: Farmer) -> NearestStore:
    """The farmer's village store, else the tenant's closest store to the village."""
    village_point = (
        select(Village.location).where(Village.id == farmer.village_id).scalar_subquery()
    )
    distance = func.ST_Distance(Store.location, village_point)
    village_store = await session.scalar(
        select(Village.store_id).where(Village.id == farmer.village_id)
    )
    base = select(Store, distance).where(
        Store.tenant_id == farmer.tenant_id, Store.deleted_at.is_(None)
    )
    if village_store is not None:
        row = (await session.execute(base.where(Store.id == village_store))).first()
        if row is not None:
            return NearestStore(store=row[0], distance_m=_meters(row[1]), source="village")
    row = (await session.execute(base.order_by(distance, Store.code).limit(1))).first()
    if row is None:
        raise NotFoundError("The tenant has no store.")
    return NearestStore(store=row[0], distance_m=_meters(row[1]), source="nearest")


def _meters(value: Any) -> float | None:
    return None if value is None else round(float(value), 1)


# --------------------------------------------------------------------------- lookups
async def _tenant_store(session: AsyncSession, actor: User, store_id: uuid.UUID) -> Store:
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


async def _farmer_for(
    session: AsyncSession, actor: User, farmer_id: uuid.UUID | None
) -> tuple[Farmer, OrderChannel]:
    role = UserRole(actor.role)
    stmt = select(Farmer).where(Farmer.deleted_at.is_(None))
    if role == UserRole.FARMER:
        stmt = stmt.where(Farmer.tenant_id == actor.tenant_id, Farmer.user_id == actor.id)
        if farmer_id is not None:
            stmt = stmt.where(Farmer.id == farmer_id)
        channel = OrderChannel.FARMER_APP
    else:
        if farmer_id is None:
            raise InvalidOrderError("farmer_id is required.")
        stmt = stmt.where(Farmer.id == farmer_id)
        if role == UserRole.FIELD_OFFICER:
            stmt = stmt.where(*farmer_filters(actor))  # own farmers only
            channel = OrderChannel.OFFICER
        else:  # store staff serve any farmer of the tenant
            stmt = stmt.where(Farmer.tenant_id == actor.tenant_id)
            channel = OrderChannel.POS
    farmer = (await session.execute(stmt.order_by(Farmer.created_at).limit(1))).scalar()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    return farmer, channel


async def _store_for(
    session: AsyncSession, actor: User, farmer: Farmer, store_id: uuid.UUID | None
) -> Store:
    role = UserRole(actor.role)
    if role in (UserRole.STORE_MANAGER, UserRole.ACCOUNTANT) and actor.store_id is not None:
        if store_id is not None and store_id != actor.store_id:
            raise NotFoundError("Store not found.")
        return await _tenant_store(session, actor, actor.store_id)
    if role == UserRole.STORE_MANAGER:
        raise NotFoundError("Store not found.")  # a store manager without a store
    if store_id is not None:
        return await _tenant_store(session, actor, store_id)
    return (await nearest_store(session, farmer)).store


# --------------------------------------------------------------------------- pricing
@dataclass(frozen=True)
class PricedLine:
    index: int
    sku_id: uuid.UUID
    qty: Decimal
    unit_price_paise: int
    gst_rate_bp: int
    line_total_paise: int
    tax_paise: int
    label_claim_id: uuid.UUID | None


async def price_lines(
    session: AsyncSession, actor: User, store: Store, body: OrderCreate, today: date
) -> list[PricedLine]:
    sku_ids = sorted({line.sku_id for line in body.lines})
    rows = (
        await session.execute(
            select(Sku, Product.gst_rate_bp)
            .join(Product, Product.id == Sku.product_id)
            .where(
                Sku.id.in_(sku_ids),
                Sku.tenant_id == actor.tenant_id,
                Sku.deleted_at.is_(None),
                Sku.active.is_(True),
                Product.deleted_at.is_(None),
                Product.active.is_(True),
            )
        )
    ).all()
    skus = {sku.id: (sku, int(gst)) for sku, gst in rows}
    unknown = [
        {"loc": ["lines", i, "sku_id"], "msg": "Unknown or inactive SKU."}
        for i, line in enumerate(body.lines)
        if line.sku_id not in skus
    ]
    if unknown:
        raise InvalidOrderError("Unknown or inactive SKU.", extra={"errors": unknown})
    await assert_lines_recommendable(
        session,
        actor.tenant_id,
        [(line.sku_id, line.label_claim_id) for line in body.lines],
    )
    prices = await prices_for(session, sku_ids, store.id, today)
    priced: list[PricedLine] = []
    for i, line in enumerate(body.lines):
        sku, gst = skus[line.sku_id]
        unit = resolved_price(prices.get(sku.id), sku.mrp_paise)
        total = line_total_paise(line.qty, unit)
        priced.append(
            PricedLine(
                index=i,
                sku_id=sku.id,
                qty=line.qty,
                unit_price_paise=unit,
                gst_rate_bp=gst,
                line_total_paise=total,
                tax_paise=tax_paise(total, gst),
                label_claim_id=line.label_claim_id,
            )
        )
    return priced


async def assert_lines_recommendable(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    lines: list[tuple[uuid.UUID, uuid.UUID | None]],
) -> None:
    """DX-007 on every line that sets ``order_line.label_claim_id`` (a recommendation): the
    claim must be a live, approved claim of that SKU (``assert_sku_recommendable``).
    Raises 422 ``sku_not_recommendable`` listing the offending lines; nothing is written."""
    errors: list[dict[str, Any]] = []
    for i, (sku_id, claim_id) in enumerate(lines):
        if claim_id is None:
            continue
        try:
            await assert_sku_recommendable(
                session, tenant_id=tenant_id, sku_id=sku_id, label_claim_id=claim_id
            )
        except SkuNotRecommendable:
            errors.append(
                {
                    "loc": ["lines", i, "label_claim_id"],
                    "msg": "No approved label claim for this SKU (DX-007).",
                    "sku_id": str(sku_id),
                    "label_claim_id": str(claim_id),
                }
            )
    if errors:
        raise SkuNotRecommendable(
            "This SKU has no approved label claim for the crop and problem (DX-007).",
            extra={"errors": errors},
        )


def _check_client_amounts(body: OrderCreate, priced: list[PricedLine]) -> tuple[int, int, int]:
    subtotal = sum(p.line_total_paise for p in priced)
    tax = sum(p.tax_paise for p in priced)
    total = subtotal + tax
    errors: list[dict[str, Any]] = [
        {
            "loc": ["lines", p.index, "unit_price_paise"],
            "expected": p.unit_price_paise,
            "got": line.unit_price_paise,
        }
        for p, line in zip(priced, body.lines, strict=True)
        if line.unit_price_paise is not None and line.unit_price_paise != p.unit_price_paise
    ]
    if body.expected_total_paise is not None and body.expected_total_paise != total:
        errors.append(
            {"loc": ["expected_total_paise"], "expected": total, "got": body.expected_total_paise}
        )
    if errors:
        raise AmountMismatchError(
            "Prices changed: the server recomputed the order.",
            extra={
                "errors": errors,
                "subtotal_paise": subtotal,
                "tax_paise": tax,
                "total_paise": total,
                "unit_prices_paise": {str(p.sku_id): p.unit_price_paise for p in priced},
            },
        )
    return subtotal, tax, total


# --------------------------------------------------------------------------- events
async def _record_status(
    session: AsyncSession,
    actor_id: uuid.UUID | None,
    order: Order,
    farmer_user_id: uuid.UUID | None,
    *,
    from_status: str | None,
    to_status: OrderStatus,
    note: str | None,
    notify: bool = True,
) -> None:
    session.add(
        OrderStatusEvent(
            tenant_id=order.tenant_id,
            order_id=order.id,
            from_status=from_status,
            to_status=to_status.value,
            note=note,
            actor_id=actor_id,  # None = the system (a captured payment)
        )
    )
    if notify:
        recipients = {u for u in (farmer_user_id, order.placed_by) if u is not None}
        recipients.discard(actor_id)
        for user_id in sorted(recipients):
            session.add(
                Notification(
                    tenant_id=order.tenant_id,
                    user_id=user_id,
                    kind=NOTIFICATION_KIND,
                    title_key=NOTIFICATION_TITLE_KEY,
                    body_key=f"order.status.{to_status.value}",
                    data={
                        "order_id": str(order.id),
                        "store_id": str(order.store_id),
                        "status": to_status.value,
                    },
                )
            )
    await session.flush()


async def _farmer_user(session: AsyncSession, order: Order) -> uuid.UUID | None:
    if order.farmer_id is None:
        return None
    user_id: uuid.UUID | None = await session.scalar(
        select(Farmer.user_id).where(Farmer.id == order.farmer_id)
    )
    return user_id


# --------------------------------------------------------------------------- place
async def place_order(
    session: AsyncSession, actor: User, body: OrderCreate, *, today: date
) -> PlaceResult:
    farmer, channel = await _farmer_for(session, actor, body.farmer_id)
    store = await _store_for(session, actor, farmer, body.store_id)
    priced = await price_lines(session, actor, store, body, today)
    subtotal, tax, total = _check_client_amounts(body, priced)
    order_id = body.id or uuid.uuid4()
    if await session.get(Order, order_id) is not None:
        raise OrderExistsError("An order with this id already exists.")
    demands = [LineDemand(index=p.index, sku_id=p.sku_id, qty=p.qty) for p in priced]
    allocations = await allocate_fefo(session, store.id, demands, today)
    if body.payment_mode == PaymentMode.CREDIT and total > 0:
        decision = await check_and_reserve_credit(
            session,
            tenant_id=actor.tenant_id,
            farmer_id=farmer.id,
            store_id=store.id,
            amount_paise=total,
            order_id=order_id,
            actor=actor,
            approval_request_id=body.credit_approval_request_id,
        )
        if not decision.allowed:
            return PlaceResult(blocked=decision)
    now = datetime.now(UTC)
    order = Order(
        id=order_id,
        tenant_id=actor.tenant_id,
        farmer_id=farmer.id,
        store_id=store.id,
        channel=channel,
        status=OrderStatus.PLACED,
        fulfilment=body.fulfilment,
        subtotal_paise=subtotal,
        discount_paise=0,
        tax_paise=tax,
        total_paise=total,
        placed_by=actor.id,
        placed_at=now,
        notes=body.notes,
        client_order_id=body.id,
    )
    session.add(order)
    await session.flush()
    lines: list[OrderLine] = []
    for p, allocation in zip(priced, allocations, strict=True):
        line = OrderLine(
            tenant_id=actor.tenant_id,
            order_id=order.id,
            sku_id=p.sku_id,
            batch_id=allocation[0][0].id if allocation else None,
            qty=p.qty,
            unit_price_paise=p.unit_price_paise,
            gst_rate_bp=p.gst_rate_bp,
            line_total_paise=p.line_total_paise,
            label_claim_id=p.label_claim_id,
        )
        session.add(line)
        lines.append(line)
    await session.flush()
    await hold_allocations(
        session,
        tenant_id=actor.tenant_id,
        order_id=order.id,
        store_id=store.id,
        demands=[
            LineDemand(index=p.index, sku_id=p.sku_id, qty=p.qty, line_id=line.id)
            for p, line in zip(priced, lines, strict=True)
        ],
        allocations=allocations,
    )
    await _record_status(
        session,
        actor.id,
        order,
        farmer.user_id,
        from_status=None,
        to_status=OrderStatus.PLACED,
        note=body.notes,
        notify=False,
    )
    if body.payment_mode in PROVIDER_MODES:
        # Prepaid (UPI QR / link): stock is held, the order waits in ``placed`` until the
        # payment is captured (``farmerapp.orders.payment_events``).
        return PlaceResult(order=await order_detail(session, order))
    order.status = OrderStatus.RESERVED
    await _record_status(
        session,
        actor.id,
        order,
        farmer.user_id,
        from_status=OrderStatus.PLACED.value,
        to_status=OrderStatus.RESERVED,
        note=None,
    )
    return PlaceResult(order=await order_detail(session, order))


# --------------------------------------------------------------------------- detail
async def order_detail(session: AsyncSession, order: Order) -> OrderDetailOut:
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
    events = (
        (
            await session.execute(
                select(OrderStatusEvent)
                .where(OrderStatusEvent.order_id == order.id)
                .order_by(OrderStatusEvent.created_at, OrderStatusEvent.id)
            )
        )
        .scalars()
        .all()
    )
    reservations = (
        (
            await session.execute(
                select(StockReservation)
                .where(StockReservation.order_id == order.id)
                .order_by(StockReservation.created_at, StockReservation.id)
            )
        )
        .scalars()
        .all()
    )
    await session.refresh(order)
    return OrderDetailOut(
        **OrderOut.model_validate(order).model_dump(),
        lines=[OrderLineOut.model_validate(line) for line in lines],
        payments=[PaymentOut.model_validate(p) for p in payments],
        events=[OrderStatusEventOut.model_validate(e) for e in events],
        reservations=[OrderReservationOut.model_validate(r) for r in reservations],
    )


# --------------------------------------------------------------------------- status
async def _line_demands(session: AsyncSession, order: Order) -> list[LineDemand]:
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
    return [
        LineDemand(index=i, sku_id=line.sku_id, qty=line.qty, line_id=line.id)
        for i, line in enumerate(lines)
    ]


async def _reverse_credit(session: AsyncSession, actor: User, order: Order) -> None:
    """A cancelled credit order: credit back what was debited for it (net of reversals)."""
    if order.farmer_id is None:
        return
    signed = await session.scalar(
        select(
            func.coalesce(
                func.sum(
                    case(
                        (KhataEntry.type == EntryType.DEBIT.value, KhataEntry.amount_paise),
                        else_=-KhataEntry.amount_paise,
                    )
                ),
                0,
            )
        ).where(
            KhataEntry.farmer_id == order.farmer_id,
            KhataEntry.store_id == order.store_id,
            KhataEntry.ref_id == order.id,
            KhataEntry.ref_type.in_([EntryRef.ORDER.value, EntryRef.ADJUSTMENT.value]),
        )
    )
    owed = int(signed or 0)
    if owed > 0:
        await post_credit(
            session,
            tenant_id=order.tenant_id,
            farmer_id=order.farmer_id,
            store_id=order.store_id,
            amount_paise=owed,
            ref_type=EntryRef.ADJUSTMENT.value,
            ref_id=order.id,
            actor=actor,
            note="Order cancelled: credit sale reversed",
        )


async def reserve_placed_order(session: AsyncSession, order: Order, today: date) -> None:
    """``placed -> reserved`` stock: FEFO-reserve the lines unless the order already holds
    its reservations (a prepaid order reserved at placing)."""
    if await active_reservations(session, order.id):
        return
    demands = await _line_demands(session, order)
    allocations = await allocate_fefo(session, order.store_id, demands, today)
    await hold_allocations(
        session,
        tenant_id=order.tenant_id,
        order_id=order.id,
        store_id=order.store_id,
        demands=demands,
        allocations=allocations,
    )


async def advance_paid_order(
    session: AsyncSession, order: Order, *, today: date, note: str | None = None
) -> bool:
    """A fully paid order waiting in ``placed`` moves to ``reserved`` (ST-005 transition,
    by the system: ``actor_id`` NULL). Anything else is left alone. Returns whether it
    moved; the farmer's login and the placing user are notified."""
    if order.status != OrderStatus.PLACED:
        return False
    await reserve_placed_order(session, order, today)
    order.status = OrderStatus.RESERVED
    await session.flush()
    await _record_status(
        session,
        None,
        order,
        await _farmer_user(session, order),
        from_status=OrderStatus.PLACED.value,
        to_status=OrderStatus.RESERVED,
        note=note,
    )
    return True


async def change_status(
    session: AsyncSession,
    actor: User,
    order: Order,
    body: OrderStatusIn,
    *,
    today: date,
    blobs: BlobStore,
    now: datetime,
) -> OrderDetailOut:
    current = order.status
    target = body.status
    if not can_transition(current, target):
        raise InvalidTransitionError(
            f"An order cannot move from {current} to {target.value}.",
            extra={
                "from": current,
                "to": target.value,
                "allowed": sorted(s.value for s in TRANSITIONS[OrderStatus(current)]),
            },
        )
    if target == OrderStatus.RESERVED:
        await reserve_placed_order(session, order, today)
    elif target == OrderStatus.CANCELLED:
        await release_order(session, order.id)
        await _reverse_credit(session, actor, order)
    elif target in (OrderStatus.HANDED_OVER, OrderStatus.DELIVERED):
        await consume_order(
            session,
            tenant_id=order.tenant_id,
            order_id=order.id,
            store_id=order.store_id,
            demands=await _line_demands(session, order),
            actor_id=actor.id,
            today=today,
        )
    order.status = target
    await session.flush()
    if target in FULFILLED_STATUSES:
        # ST-001 / FA-020: the sale is complete -> its GST invoice (idempotent per order).
        from farmerapp.invoices.service import issue_order_invoice

        await issue_order_invoice(session, actor, order, blobs=blobs, now=now)
    await _record_status(
        session,
        actor.id,
        order,
        await _farmer_user(session, order),
        from_status=current,
        to_status=target,
        note=body.note,
    )
    return await order_detail(session, order)


__all__ = [
    "NOTIFICATION_KIND",
    "AmountMismatchError",
    "InvalidOrderError",
    "InvalidTransitionError",
    "NearestStore",
    "OrderExistsError",
    "PlaceResult",
    "PricedLine",
    "advance_paid_order",
    "assert_lines_recommendable",
    "change_status",
    "nearest_store",
    "order_detail",
    "place_order",
    "price_lines",
    "reserve_placed_order",
]
