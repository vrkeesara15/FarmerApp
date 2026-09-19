"""WC-013 export resources: every list view that has a list endpoint, with the same filters
and the same role scoping, plus NF-013 consent records and the ST-008 accounting files.

Each ``Resource`` names the roles that may export it (the list endpoint's roles; farmers
never export), its filter model (the list endpoint's query parameters as a JSON object,
``from`` / ``to`` included), its columns (the list endpoint's read model, nested values as
JSON) and an async row source that streams the scoped query in chunks
(``session.stream_scalars`` with ``yield_per``).
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator, Awaitable, Callable, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import ColumnElement, Select, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.audit.router import AuditFilters
from farmerapp.audit.schemas import AuditLogOut
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import (
    farmer_filters,
    order_filters,
    payment_filters,
    visible_store_filters,
    visit_filters,
)
from farmerapp.db.models import AuditLog
from farmerapp.farmers.models import ConsentRecord, ConsentSubject, Farmer
from farmerapp.farmers.schemas import FarmerOut
from farmerapp.flags import service as flag_service
from farmerapp.flags.models import UNRESOLVED, Flag
from farmerapp.flags.schemas import FlagOut
from farmerapp.orders.models import Order
from farmerapp.orders.schemas import OrderOut
from farmerapp.payments.models import Payment
from farmerapp.payments.schemas import PaymentOut
from farmerapp.stock.models import StockBatch
from farmerapp.tenants.models import Store
from farmerapp.visits.models import Visit
from farmerapp.visits.schemas import VisitOut

R = UserRole
YIELD_PER = 500
MAX_ROWS = 100_000
TENANT_ADMINS = frozenset({R.OWNER, R.DIRECTOR, R.TENANT_ADMIN, R.AUDITOR})


class _Filters(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class FarmerFilters(_Filters):
    village_id: uuid.UUID | None = None
    registered_by: uuid.UUID | None = None


class OrderFilters(_Filters):
    store_id: uuid.UUID | None = None
    farmer_id: uuid.UUID | None = None
    status: str | None = None
    channel: str | None = None
    from_: datetime | None = Field(default=None, alias="from")
    to: datetime | None = None


class PaymentFilters(_Filters):
    store_id: uuid.UUID | None = None
    farmer_id: uuid.UUID | None = None
    order_id: uuid.UUID | None = None
    mode: str | None = None
    status: str | None = None
    from_: datetime | None = Field(default=None, alias="from")
    to: datetime | None = None


class VisitFilters(_Filters):
    officer_id: uuid.UUID | None = None
    farmer_id: uuid.UUID | None = None
    status: str | None = None
    from_: datetime | None = Field(default=None, alias="from")
    to: datetime | None = None


class FlagFilters(_Filters):
    status: list[str] = Field(default_factory=list)
    severity: list[str] = Field(default_factory=list)
    rule_id: str | None = Field(default=None, max_length=16)
    subject_type: str | None = None
    owner: Literal["me"] | None = None
    overdue: bool | None = None


class StockFilters(_Filters):
    store_id: uuid.UUID | None = None
    sku_id: uuid.UUID | None = None
    expiring_within_days: int | None = Field(default=None, ge=0)
    include_empty: bool = False


class AuditExportFilters(_Filters):
    entity: str | None = Field(default=None, max_length=64)
    entity_id: uuid.UUID | None = None
    actor_id: uuid.UUID | None = None
    actor_role: str | None = Field(default=None, max_length=32)
    action: str | None = Field(default=None, max_length=64)
    from_: datetime | None = Field(default=None, alias="from")
    to: datetime | None = None
    q: str | None = Field(default=None, max_length=36, pattern=r"^[0-9A-Fa-f-]+$")


class ConsentFilters(_Filters):
    purpose: Literal["data", "marketing"] | None = None
    farmer_id: uuid.UUID | None = None
    from_: datetime | None = Field(default=None, alias="from")
    to: datetime | None = None


class AccountingFilters(_Filters):
    store_id: uuid.UUID
    day: date = Field(alias="date", description="IST business day (YYYY-MM-DD).")


RowSource = Callable[[AsyncSession, User, Any, datetime], AsyncIterator[Sequence[Any]]]


@dataclass(frozen=True)
class Resource:
    name: str
    roles: frozenset[UserRole]
    filters: type[_Filters]
    columns: tuple[str, ...]
    rows: RowSource
    formats: frozenset[str] = frozenset({"csv", "xlsx"})
    #: For formats that are a document rather than a table (Tally XML).
    render: dict[
        str, Callable[[AsyncSession, User, Any, datetime], Awaitable[tuple[bytes, int]]]
    ] = field(default_factory=dict)
    description: str = ""


def _columns(model: type[BaseModel], drop: Sequence[str] = ()) -> tuple[str, ...]:
    return tuple(name for name in model.model_fields if name not in drop)


async def _stream(
    session: AsyncSession,
    stmt: Select[Any],
    to_row: Callable[[Any], Sequence[Any]],
) -> AsyncIterator[Sequence[Any]]:
    result = await session.stream_scalars(
        stmt.limit(MAX_ROWS).execution_options(yield_per=YIELD_PER)
    )
    async for obj in result:
        yield to_row(obj)


def _pick(out: BaseModel, columns: Sequence[str]) -> list[Any]:
    data = out.model_dump(mode="json")
    return [data.get(c) for c in columns]


# --------------------------------------------------------------------------- farmers
FARMER_COLUMNS = _columns(FarmerOut, drop=("tenant_id", "deleted_at"))


def _farmer_rows(
    session: AsyncSession, actor: User, f: FarmerFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    stmt = select(Farmer).where(Farmer.deleted_at.is_(None), *farmer_filters(actor))
    if f.village_id is not None:
        stmt = stmt.where(Farmer.village_id == f.village_id)
    if f.registered_by is not None:
        stmt = stmt.where(Farmer.registered_by == f.registered_by)
    redact = UserRole(actor.role) == R.AGRONOMIST
    return _stream(
        session,
        stmt.order_by(Farmer.created_at, Farmer.id),
        lambda row: _pick(FarmerOut.from_row(row, redact_pii=redact), FARMER_COLUMNS),
    )


# --------------------------------------------------------------------------- orders
ORDER_COLUMNS = _columns(OrderOut, drop=("tenant_id",))


def _order_rows(
    session: AsyncSession, actor: User, f: OrderFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    stmt = select(Order).where(Order.deleted_at.is_(None), *order_filters(actor))
    if f.store_id is not None:
        stmt = stmt.where(Order.store_id == f.store_id)
    if f.farmer_id is not None:
        stmt = stmt.where(Order.farmer_id == f.farmer_id)
    if f.status is not None:
        stmt = stmt.where(Order.status == f.status)
    if f.channel is not None:
        stmt = stmt.where(Order.channel == f.channel)
    if f.from_ is not None:
        stmt = stmt.where(Order.created_at >= f.from_)
    if f.to is not None:
        stmt = stmt.where(Order.created_at <= f.to)
    return _stream(
        session,
        stmt.order_by(Order.created_at, Order.id),
        lambda row: _pick(OrderOut.model_validate(row), ORDER_COLUMNS),
    )


# --------------------------------------------------------------------------- payments
PAYMENT_COLUMNS = _columns(PaymentOut, drop=("tenant_id",))


def _payment_rows(
    session: AsyncSession, actor: User, f: PaymentFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    stmt = select(Payment).where(Payment.deleted_at.is_(None), *payment_filters(actor))
    for column, value in (
        (Payment.store_id, f.store_id),
        (Payment.farmer_id, f.farmer_id),
        (Payment.order_id, f.order_id),
        (Payment.mode, f.mode),
        (Payment.status, f.status),
    ):
        if value is not None:
            stmt = stmt.where(column == value)
    if f.from_ is not None:
        stmt = stmt.where(Payment.created_at >= f.from_)
    if f.to is not None:
        stmt = stmt.where(Payment.created_at <= f.to)
    return _stream(
        session,
        stmt.order_by(Payment.created_at, Payment.id),
        lambda row: _pick(PaymentOut.model_validate(row), PAYMENT_COLUMNS),
    )


# --------------------------------------------------------------------------- visits
VISIT_COLUMNS = _columns(VisitOut, drop=("tenant_id",))


def _visit_rows(
    session: AsyncSession, actor: User, f: VisitFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    stmt = select(Visit).where(Visit.deleted_at.is_(None), *visit_filters(actor))
    if f.officer_id is not None:
        stmt = stmt.where(Visit.officer_id == f.officer_id)
    if f.farmer_id is not None:
        stmt = stmt.where(Visit.farmer_id == f.farmer_id)
    if f.status is not None:
        stmt = stmt.where(Visit.status == f.status)
    if f.from_ is not None:
        stmt = stmt.where(Visit.checkin_at >= f.from_)
    if f.to is not None:
        stmt = stmt.where(Visit.checkin_at < f.to)
    return _stream(
        session,
        stmt.order_by(Visit.created_at, Visit.id),
        lambda row: _pick(VisitOut.from_row(row), VISIT_COLUMNS),
    )


# --------------------------------------------------------------------------- flags
FLAG_COLUMNS = _columns(FlagOut)


def _flag_rows(
    session: AsyncSession, actor: User, f: FlagFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    filters: list[ColumnElement[bool]] = [
        Flag.deleted_at.is_(None),
        *flag_service.flag_filters(actor),
    ]
    if f.status:
        filters.append(Flag.status.in_(f.status))
    if f.severity:
        filters.append(Flag.severity.in_(f.severity))
    if f.rule_id:
        filters.append(Flag.rule_id == f.rule_id)
    if f.subject_type is not None:
        filters.append(Flag.subject_type == f.subject_type)
    if f.owner == "me":
        filters.append(or_(Flag.owner_id == actor.id, flag_service.watched_by(actor.id)))
    if f.overdue is not None:
        late = Flag.status.in_([s.value for s in UNRESOLVED]) & (Flag.sla_due_at < now)
        filters.append(late if f.overdue else ~late)
    stmt = select(Flag).where(*filters).order_by(Flag.created_at.desc(), Flag.id.desc())
    return _stream(session, stmt, lambda row: _pick(FlagOut.from_row(row, now=now), FLAG_COLUMNS))


# --------------------------------------------------------------------------- stock
STOCK_COLUMNS = (
    "id",
    "store_id",
    "store_code",
    "sku_id",
    "batch_no",
    "expiry",
    "on_hand",
    "cost_paise",
    "received_at",
)


def _stock_rows(
    session: AsyncSession, actor: User, f: StockFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    stores = select(Store.id).where(Store.deleted_at.is_(None), *visible_store_filters(actor))
    stmt = (
        select(StockBatch, Store.code)
        .join(Store, Store.id == StockBatch.store_id)
        .where(StockBatch.deleted_at.is_(None), StockBatch.store_id.in_(stores))
    )
    if f.store_id is not None:
        stmt = stmt.where(StockBatch.store_id == f.store_id)
    if f.sku_id is not None:
        stmt = stmt.where(StockBatch.sku_id == f.sku_id)
    if f.expiring_within_days is not None:
        stmt = stmt.where(
            StockBatch.expiry.is_not(None),
            StockBatch.expiry <= now.date() + timedelta(days=f.expiring_within_days),
        )
    if not f.include_empty:
        stmt = stmt.where(StockBatch.qty > 0)

    async def rows() -> AsyncIterator[Sequence[Any]]:
        result = await session.stream(
            stmt.order_by(Store.code, StockBatch.created_at, StockBatch.id)
            .limit(MAX_ROWS)
            .execution_options(yield_per=YIELD_PER)
        )
        async for batch, code in result.tuples():
            yield [
                str(batch.id),
                str(batch.store_id),
                code,
                str(batch.sku_id),
                batch.batch_no,
                batch.expiry.isoformat() if batch.expiry else None,
                batch.qty,
                batch.cost_paise,
                batch.received_at.isoformat(),
            ]

    return rows()


# --------------------------------------------------------------------------- audit logs
AUDIT_COLUMNS = _columns(AuditLogOut, drop=("tenant_id",))


def _audit_rows(
    session: AsyncSession, actor: User, f: AuditExportFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    filters = AuditFilters(
        f.entity, f.entity_id, f.actor_id, f.actor_role, f.action, f.from_, f.to, f.q
    )
    stmt = filters.apply(select(AuditLog), actor.tenant_id).order_by(
        AuditLog.created_at.desc(), AuditLog.id.desc()
    )
    return _stream(session, stmt, lambda row: _pick(AuditLogOut.from_row(row), AUDIT_COLUMNS))


# --------------------------------------------------------------------------- consent (NF-013)
CONSENT_COLUMNS = (
    "id",
    "created_at",
    "subject_type",
    "subject_id",
    "farmer_name",
    "purpose",
    "version",
    "language",
    "channel",
    "granted_at",
    "withdrawn_at",
    "recorded_by",
)


def _consent_rows(
    session: AsyncSession, actor: User, f: ConsentFilters, now: datetime
) -> AsyncIterator[Sequence[Any]]:
    stmt = (
        select(ConsentRecord, Farmer.name)
        .outerjoin(
            Farmer,
            (Farmer.id == ConsentRecord.subject_id)
            & (ConsentRecord.subject_type == ConsentSubject.FARMER.value),
        )
        .where(ConsentRecord.tenant_id == actor.tenant_id)
    )
    if f.purpose is not None:
        stmt = stmt.where(ConsentRecord.purpose == f.purpose)
    if f.farmer_id is not None:
        stmt = stmt.where(ConsentRecord.subject_id == f.farmer_id)
    if f.from_ is not None:
        stmt = stmt.where(ConsentRecord.created_at >= f.from_)
    if f.to is not None:
        stmt = stmt.where(ConsentRecord.created_at <= f.to)

    async def rows() -> AsyncIterator[Sequence[Any]]:
        result = await session.stream(
            stmt.order_by(ConsentRecord.created_at, ConsentRecord.id)
            .limit(MAX_ROWS)
            .execution_options(yield_per=YIELD_PER)
        )
        async for record, name in result.tuples():
            yield [
                str(record.id),
                record.created_at.isoformat(),
                record.subject_type,
                str(record.subject_id),
                name,
                record.purpose,
                record.version,
                record.language,
                record.channel,
                record.granted_at.isoformat() if record.granted_at else None,
                record.withdrawn_at.isoformat() if record.withdrawn_at else None,
                str(record.recorded_by) if record.recorded_by else None,
            ]

    return rows()


# --------------------------------------------------------------------------- registry
STAFF = frozenset(set(R) - {R.FARMER})
RESOURCES: dict[str, Resource] = {
    "farmers": Resource(
        "farmers",
        frozenset(
            {R.OWNER, R.DIRECTOR, R.TENANT_ADMIN, R.AUDITOR, R.CLUSTER_HEAD, R.STORE_MANAGER}
            | {R.FIELD_OFFICER, R.AGRONOMIST}
        ),
        FarmerFilters,
        FARMER_COLUMNS,
        _farmer_rows,
        description="GET /v1/farmers (agronomist: masked phone, no landmark)",
    ),
    "orders": Resource(
        "orders",
        STAFF - {R.AGRONOMIST},
        OrderFilters,
        ORDER_COLUMNS,
        _order_rows,
        description="GET /v1/orders",
    ),
    "payments": Resource(
        "payments",
        STAFF - {R.AGRONOMIST},
        PaymentFilters,
        PAYMENT_COLUMNS,
        _payment_rows,
        description="GET /v1/payments",
    ),
    "visits": Resource(
        "visits",
        frozenset(
            {R.OWNER, R.DIRECTOR, R.TENANT_ADMIN, R.AUDITOR, R.CLUSTER_HEAD, R.STORE_MANAGER}
            | {R.FIELD_OFFICER}
        ),
        VisitFilters,
        VISIT_COLUMNS,
        _visit_rows,
        description="GET /v1/visits",
    ),
    "flags": Resource(
        "flags",
        frozenset(
            {R.OWNER, R.DIRECTOR, R.AUDITOR, R.CLUSTER_HEAD, R.STORE_MANAGER, R.TENANT_ADMIN}
            | {R.FIELD_OFFICER, R.ACCOUNTANT}
        ),
        FlagFilters,
        FLAG_COLUMNS,
        _flag_rows,
        description="GET /v1/flags",
    ),
    "stock": Resource(
        "stock",
        frozenset(
            {R.OWNER, R.DIRECTOR, R.TENANT_ADMIN, R.AUDITOR, R.ACCOUNTANT, R.CLUSTER_HEAD}
            | {R.STORE_MANAGER}
        ),
        StockFilters,
        STOCK_COLUMNS,
        _stock_rows,
        description="GET /v1/stores/{id}/stock over every store in scope",
    ),
    "audit_logs": Resource(
        "audit_logs",
        TENANT_ADMINS,
        AuditExportFilters,
        AUDIT_COLUMNS,
        _audit_rows,
        description="GET /v1/audit-logs",
    ),
    "consent_records": Resource(
        "consent_records",
        TENANT_ADMINS,
        ConsentFilters,
        CONSENT_COLUMNS,
        _consent_rows,
        description="NF-013: every consent grant and withdrawal (append-only history)",
    ),
}


def register_accounting() -> None:
    """ST-008 resources (defined in ``accounting.py``; registered here to avoid a cycle)."""
    from farmerapp.exports import accounting

    for resource in accounting.resources():
        RESOURCES[resource.name] = resource


register_accounting()


def allowed(resource: Resource, actor: User) -> bool:
    return UserRole(actor.role) in resource.roles


#: Every role that may export at least one resource (the route policy of POST /v1/exports).
EXPORT_ROLES = tuple(sorted({r for res in RESOURCES.values() for r in res.roles}, key=str))

__all__ = [
    "EXPORT_ROLES",
    "RESOURCES",
    "AccountingFilters",
    "Resource",
    "allowed",
]
