"""SQL loaders: the live tables -> the fact records ``farmerapp.analytics.kpi`` computes on.

All reads run under the request's RLS tenant binding and additionally filter by
``tenant_id`` and the request ``Scope`` (SPEC 2.6). Aggregation that only sums happens in
SQL (``sales_aggregate``); anything with a SPEC 5.2 rule behind it (verified, conversion,
active, ageing) is computed by ``kpi`` on the loaded facts.

Sales are fulfilled orders (``handed_over`` / ``delivered``), dated by ``placed_at`` (else
``created_at``) in IST; cancelled and open orders are not sales.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import AsyncIterator, Iterable, Sequence
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    ColumnElement,
    Date,
    Numeric,
    and_,
    cast,
    distinct,
    func,
    literal,
    select,
    text,
    union,
)
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from farmerapp.analytics.filters import IST_SQL, Scope, ist_date
from farmerapp.analytics.kpi import VisitFact
from farmerapp.auth.models import RefreshToken
from farmerapp.catalog.models import Product, Sku
from farmerapp.farmers.models import Farmer
from farmerapp.khata.models import KhataEntry
from farmerapp.location.models import DutySession
from farmerapp.orders.models import FULFILLED_STATUSES, Order, OrderLine
from farmerapp.payments.models import RECEIVED_STATUSES, Payment
from farmerapp.stock.models import MovementKind, StockBatch, StockMovement
from farmerapp.visits.models import Visit
from farmerapp.visits.scoring import VERIFIED_MIN

FULFILLED = tuple(s.value for s in FULFILLED_STATUSES)


@contextlib.asynccontextmanager
async def hash_joins(session: AsyncSession) -> AsyncIterator[None]:
    """Run range aggregations without nested-loop joins (transaction-local planner setting).

    A dashboard aggregate joins every order in a range to its lines (tens of thousands of
    rows): a hash join is always the right plan. Without fresh statistics (a bulk load not
    yet analysed, a partition just filled) the planner estimates one row per side and picks a
    nested loop with a join *filter* -- quadratic, tens of seconds for 50 stores. Pinning the
    join method for these statements keeps the owner home inside its 3-second budget (WC-001)
    whatever the statistics; point lookups elsewhere are unaffected (reset on exit).
    """
    await session.execute(text("SET LOCAL enable_nestloop = off"))
    try:
        yield
    finally:
        await session.execute(text("SET LOCAL enable_nestloop = on"))


RECEIVED = tuple(s.value for s in RECEIVED_STATUSES)


def sold_at() -> ColumnElement[datetime]:
    return func.coalesce(Order.placed_at, Order.created_at)


def _order_filters(scope: Scope, start: datetime, end: datetime) -> list[ColumnElement[bool]]:
    at = sold_at()
    out: list[ColumnElement[bool]] = [
        Order.tenant_id == scope.tenant_id,
        Order.deleted_at.is_(None),
        Order.status.in_(FULFILLED),
        at >= start,
        at < end,
        *scope.store_column_filters(Order.store_id),
        *scope.crop_column_filters(Order.farmer_id),
    ]
    if scope.own_officer_id is not None:
        out.append(Order.placed_by == scope.own_officer_id)
    return out


def _avg_cost() -> Any:
    """The store's average batch cost of the line's SKU (lines sold without a batch)."""
    other = aliased(StockBatch)
    return (
        select(func.avg(other.cost_paise))
        .where(
            other.tenant_id == Order.tenant_id,
            other.store_id == Order.store_id,
            other.sku_id == OrderLine.sku_id,
        )
        .correlate(Order, OrderLine)
        .scalar_subquery()
    )


def sales_lines(scope: Scope, start: datetime, end: datetime) -> Any:
    """Subquery: one row per fulfilled order line in scope with net and cost (paise)."""
    return sales_lines_where(_order_filters(scope, start, end))


def tenant_sales_lines(tenant_id: uuid.UUID) -> Any:
    """Every fulfilled order line of the tenant (all time; farmer LTV)."""
    return sales_lines_where(
        [
            Order.tenant_id == tenant_id,
            Order.deleted_at.is_(None),
            Order.status.in_(FULFILLED),
        ]
    )


def sales_lines_where(where: Sequence[ColumnElement[bool]]) -> Any:
    """Order lines of the matching orders: net (after the order discount, pro rata) and cost.

    Deliberately no product / SKU join: the product attributes (own brand, category) are
    attached in Python from a tiny SKU map, which keeps the plan a simple order -> line ->
    batch walk even when the planner has no statistics yet.
    """
    subtotal = func.nullif(Order.subtotal_paise, 0)
    discount = cast(Order.discount_paise, Numeric) * OrderLine.line_total_paise / subtotal
    discount = func.coalesce(discount, 0)
    unit_cost = func.coalesce(cast(StockBatch.cost_paise, Numeric), _avg_cost(), 0)
    at = sold_at()
    return (
        select(
            Order.id.label("order_id"),
            Order.store_id.label("store_id"),
            Order.farmer_id.label("farmer_id"),
            Order.placed_by.label("placed_by"),
            at.label("sold_at"),
            ist_date(at).label("day"),
            cast(func.date_trunc("month", func.timezone(IST_SQL, at)), Date).label("month"),
            OrderLine.sku_id.label("sku_id"),
            OrderLine.line_total_paise.label("gross"),
            discount.label("discount"),
            (OrderLine.line_total_paise - discount).label("net"),
            (OrderLine.qty * unit_cost).label("cost"),
        )
        .join(OrderLine, and_(OrderLine.order_id == Order.id, OrderLine.deleted_at.is_(None)))
        .outerjoin(StockBatch, StockBatch.id == OrderLine.batch_id)
        .where(*where)
        .subquery("sales_lines")
    )


@dataclass(frozen=True)
class SalesRow:
    keys: dict[str, Any]
    gross_paise: int
    discount_paise: int
    net_paise: int
    cost_paise: int
    orders: int  # distinct orders; exact only when no product key (own_brand / category)

    @property
    def margin_paise(self) -> int:
        return self.net_paise - self.cost_paise


def _paise(value: Any) -> int:
    if value is None:
        return 0
    return int(Decimal(value).to_integral_value())


PRODUCT_KEYS = frozenset({"own_brand", "category"})


async def sku_attributes(
    session: AsyncSession, tenant_id: uuid.UUID
) -> dict[uuid.UUID, tuple[bool, str]]:
    """``sku_id -> (own_brand, category)`` for the tenant's catalogue."""
    rows = await session.execute(
        select(Sku.id, Product.own_brand, Product.category)
        .join(Product, Product.id == Sku.product_id)
        .where(Sku.tenant_id == tenant_id)
    )
    return {r[0]: (bool(r[1]), str(r[2])) for r in rows}


async def sales_aggregate(
    session: AsyncSession, scope: Scope, start: datetime, end: datetime, keys: Sequence[str]
) -> list[SalesRow]:
    """Sums of the scoped sales grouped by ``keys``: columns of ``sales_lines`` (``day``,
    ``month``, ``store_id``, ``farmer_id``, ``placed_by``) and the product keys ``own_brand``
    / ``category``."""
    lines = sales_lines(scope, start, end)
    product_keys = [k for k in keys if k in PRODUCT_KEYS]
    sql_keys = [k for k in keys if k not in PRODUCT_KEYS]
    group = [lines.c[k] for k in sql_keys] + ([lines.c.sku_id] if product_keys else [])
    stmt = select(
        *group,
        func.sum(lines.c.gross),
        func.sum(lines.c.discount),
        func.sum(lines.c.net),
        func.sum(lines.c.cost),
        func.count(distinct(lines.c.order_id)),
    ).group_by(*group)
    async with hash_joins(session):
        rows = (await session.execute(stmt)).all()
    attrs = await sku_attributes(session, scope.tenant_id) if product_keys else {}
    totals: dict[tuple[Any, ...], list[Any]] = {}
    n = len(group)
    for r in rows:
        values = dict(zip(sql_keys, r[: len(sql_keys)], strict=True))
        if product_keys:
            own, category = attrs.get(r[len(sql_keys)], (False, "other"))
            values.update(own_brand=own, category=category)
        key = tuple(values[k] for k in keys)
        acc = totals.setdefault(key, [Decimal(0), Decimal(0), Decimal(0), Decimal(0), 0])
        for i in range(4):
            acc[i] += Decimal(r[n + i] or 0)
        acc[4] += int(r[n + 4] or 0)
    return [
        SalesRow(
            keys=dict(zip(keys, key, strict=True)),
            gross_paise=_paise(acc[0]),
            discount_paise=_paise(acc[1]),
            net_paise=_paise(acc[2]),
            cost_paise=_paise(acc[3]),
            orders=acc[4],
        )
        for key, acc in totals.items()
    ]


async def purchases(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    farmer_ids: Iterable[uuid.UUID],
    start: datetime,
    end: datetime,
) -> list[tuple[uuid.UUID, datetime]]:
    """``(farmer_id, sold_at)`` of the farmers' fulfilled orders at any store (conversion)."""
    ids = list(set(farmer_ids))
    if not ids:
        return []
    at = sold_at()
    rows = await session.execute(
        select(Order.farmer_id, at).where(
            Order.tenant_id == tenant_id,
            Order.deleted_at.is_(None),
            Order.status.in_(FULFILLED),
            Order.farmer_id.in_(ids),
            at >= start,
            at < end,
        )
    )
    return [(r[0], r[1]) for r in rows]


# --------------------------------------------------------------------------- visits
def visit_filters(scope: Scope, start: datetime, end: datetime) -> list[ColumnElement[bool]]:
    return [
        Visit.tenant_id == scope.tenant_id,
        Visit.deleted_at.is_(None),
        Visit.checkin_at >= start,
        Visit.checkin_at < end,
        *scope.officer_column_filters(Visit.officer_id),
        *scope.crop_column_filters(Visit.farmer_id),
    ]


async def visits(
    session: AsyncSession, scope: Scope, start: datetime, end: datetime
) -> list[VisitFact]:
    rows = await session.execute(
        select(
            Visit.officer_id,
            Visit.farmer_id,
            Visit.checkin_at,
            Visit.checkout_at,
            Visit.score,
            Visit.confirmed_at,
            Visit.id,
        ).where(*visit_filters(scope, start, end))
    )
    return [VisitFact(*r) for r in rows]


@dataclass(frozen=True)
class DutyFact:
    officer_id: uuid.UUID
    start_at: datetime
    end_at: datetime | None
    km: Decimal | None
    day: date


async def duty_sessions(
    session: AsyncSession, scope: Scope, start: datetime, end: datetime
) -> list[DutyFact]:
    rows = await session.execute(
        select(
            DutySession.officer_id,
            DutySession.start_at,
            DutySession.end_at,
            DutySession.km,
            ist_date(DutySession.start_at),
        ).where(
            DutySession.tenant_id == scope.tenant_id,
            DutySession.deleted_at.is_(None),
            DutySession.start_at >= start,
            DutySession.start_at < end,
            *scope.officer_column_filters(DutySession.officer_id),
        )
    )
    return [DutyFact(*r) for r in rows]


async def registrations(
    session: AsyncSession, scope: Scope, start: datetime, end: datetime
) -> dict[uuid.UUID, int]:
    """New farmers per registering officer in the window (scorecard "new registrations")."""
    rows = await session.execute(
        select(Farmer.registered_by, func.count())
        .where(
            Farmer.tenant_id == scope.tenant_id,
            Farmer.deleted_at.is_(None),
            Farmer.registered_by.is_not(None),
            Farmer.created_at >= start,
            Farmer.created_at < end,
            *scope.officer_column_filters(Farmer.registered_by),
            *scope.crop_column_filters(Farmer.id),
        )
        .group_by(Farmer.registered_by)
    )
    return {r[0]: int(r[1]) for r in rows}


async def collections(
    session: AsyncSession, scope: Scope, start: datetime, end: datetime
) -> dict[uuid.UUID, int]:
    """Money received per collecting officer (paise; paid, reconciled or cash in hand)."""
    at = func.coalesce(Payment.paid_at, Payment.created_at)
    rows = await session.execute(
        select(Payment.collected_by, func.sum(Payment.amount_paise))
        .where(
            Payment.tenant_id == scope.tenant_id,
            Payment.deleted_at.is_(None),
            Payment.collected_by.is_not(None),
            Payment.status.in_(RECEIVED),
            at >= start,
            at < end,
            *scope.officer_column_filters(Payment.collected_by),
        )
        .group_by(Payment.collected_by)
    )
    return {r[0]: int(r[1] or 0) for r in rows}


# --------------------------------------------------------------------------- activity
async def activity(
    session: AsyncSession, scope: Scope, start: datetime, end: datetime
) -> list[tuple[uuid.UUID, date]]:
    """Distinct ``(farmer_id, IST day)`` with a purchase, a verified visit or an app session
    (a refresh token issued to the farmer's own login) -- the "active farmer" events -- of the
    live farmers in scope.

    The events are read tenant-wide and narrowed with the scoped farmer id set in Python: a
    ``farmer_id IN (subquery)`` over tens of thousands of events is at the mercy of the
    planner's estimates, a set lookup is not.
    """
    at = sold_at()
    bought = select(Order.farmer_id.label("farmer_id"), ist_date(at).label("day")).where(
        Order.tenant_id == scope.tenant_id,
        Order.deleted_at.is_(None),
        Order.status.in_(FULFILLED),
        Order.farmer_id.is_not(None),
        at >= start,
        at < end,
    )
    visited = select(Visit.farmer_id, ist_date(Visit.checkin_at)).where(
        Visit.tenant_id == scope.tenant_id,
        Visit.deleted_at.is_(None),
        Visit.score >= VERIFIED_MIN,
        Visit.checkin_at >= start,
        Visit.checkin_at < end,
    )
    sessions = (
        select(Farmer.id, ist_date(RefreshToken.created_at))
        .join(RefreshToken, RefreshToken.user_id == Farmer.user_id)
        .where(
            Farmer.tenant_id == scope.tenant_id,
            RefreshToken.tenant_id == scope.tenant_id,
            RefreshToken.created_at >= start,
            RefreshToken.created_at < end,
        )
    )
    allowed = set((await session.execute(scope.farmer_ids())).scalars())
    rows: Any = await session.execute(union(bought, visited, sessions))
    return [(r[0], r[1]) for r in rows if r[0] in allowed]


# --------------------------------------------------------------------------- khata / stock
async def khata_entries(session: AsyncSession, scope: Scope, until: datetime) -> list[KhataEntry]:
    stmt = select(KhataEntry).where(
        KhataEntry.tenant_id == scope.tenant_id,
        KhataEntry.created_at < until,
        *scope.store_column_filters(KhataEntry.store_id),
    )
    if scope.own_officer_id is not None or scope.crop_id is not None:
        stmt = stmt.where(KhataEntry.farmer_id.in_(scope.farmer_ids()))
    return list((await session.execute(stmt)).scalars().all())


async def stock_value_by_store(
    session: AsyncSession, tenant_id: uuid.UUID, store_ids: Iterable[uuid.UUID] | None
) -> dict[uuid.UUID, int]:
    """Current stock at cost per store (``stock_batch.qty`` x ``cost_paise``)."""
    stmt = (
        select(StockBatch.store_id, func.sum(StockBatch.qty * StockBatch.cost_paise))
        .where(StockBatch.tenant_id == tenant_id, StockBatch.deleted_at.is_(None))
        .group_by(StockBatch.store_id)
    )
    if store_ids is not None:
        stmt = stmt.where(StockBatch.store_id.in_(list(store_ids)))
    return {r[0]: _paise(r[1]) for r in await session.execute(stmt)}


async def write_offs(
    session: AsyncSession, tenant_id: uuid.UUID, store_id: uuid.UUID, start: datetime, end: datetime
) -> list[tuple[date, int]]:
    """``(IST day, paise at cost)`` of damage write-offs at a store in the window."""
    unit = func.coalesce(StockBatch.cost_paise, literal(0))
    rows = await session.execute(
        select(
            ist_date(StockMovement.created_at),
            func.sum(-StockMovement.qty * unit),
        )
        .outerjoin(StockBatch, StockBatch.id == StockMovement.batch_id)
        .where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.store_id == store_id,
            StockMovement.kind == MovementKind.DAMAGE.value,
            StockMovement.created_at >= start,
            StockMovement.created_at < end,
        )
        .group_by(ist_date(StockMovement.created_at))
    )
    return [(r[0], _paise(r[1])) for r in rows]


__all__ = [
    "FULFILLED",
    "DutyFact",
    "SalesRow",
    "activity",
    "collections",
    "duty_sessions",
    "hash_joins",
    "khata_entries",
    "purchases",
    "registrations",
    "sales_aggregate",
    "sales_lines",
    "sales_lines_where",
    "sku_attributes",
    "sold_at",
    "stock_value_by_store",
    "tenant_sales_lines",
    "visit_filters",
    "visits",
    "write_offs",
]
