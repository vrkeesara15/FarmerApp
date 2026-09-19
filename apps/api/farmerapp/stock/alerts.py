"""ST-004 nightly low-stock and expiry alerts (``python -m farmerapp.jobs stock-alerts``,
Cloud Scheduler 01:30 IST).

For every store of the tenant:

* **Low stock** (``notification.kind = stock_low``): a SKU whose on-hand quantity in the store
  (sum over its live batches; ``stock_batch.qty`` is the ledger cache kept in the movement's
  transaction) is below its reorder level — the store's ``reorder_level`` row, else the tenant
  default ``stock_alerts.default_reorder_level``. SKUs the store has never stocked and has no
  level for are ignored. **Deduplicated** per store and SKU until the SKU is restocked: no new
  alert while an earlier one is newer than the last receipt / transfer in.
* **Expiry** (``stock_expiry``): a batch with stock whose expiry is within a threshold of
  ``stock_alerts.expiry_days`` (60 and 30 days by default; an expired batch counts under the
  smallest). **Deduplicated** per batch and threshold: a batch alerts once at 60 days and
  once more at 30.

Alerts are ``notification`` rows (push delivery is the notifications package's job) to the
store's active store managers — the cluster head(s) of its cluster when it has none, the
tenant's owners as the last resort — with ``data`` carrying the store, SKU / batch, quantities
and the threshold for the deep link. ``title_key`` / ``body_key`` are i18n keys.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.catalog.models import Product, Sku
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification
from farmerapp.payments.config import IST
from farmerapp.stock.models import INBOUND_KINDS, StockBatch, StockMovement
from farmerapp.stock.reorder import ReorderLevel
from farmerapp.tenants.models import Store
from farmerapp.tenants.settings import get_tenant_settings

log = get_logger("farmerapp.stock.alerts")

LOW_STOCK_KIND = "stock_low"
EXPIRY_KIND = "stock_expiry"


@dataclass(frozen=True)
class LowStock:
    store_id: uuid.UUID
    sku_id: uuid.UUID
    on_hand: Decimal
    level: Decimal


@dataclass(frozen=True)
class Expiring:
    store_id: uuid.UUID
    batch_id: uuid.UUID
    sku_id: uuid.UUID
    batch_no: str
    expiry: date
    days_left: int
    threshold: int
    qty: Decimal


@dataclass
class StockAlertReport:
    tenant_id: uuid.UUID
    day: date
    low: list[LowStock] = field(default_factory=list)
    expiring: list[Expiring] = field(default_factory=list)
    notifications: int = 0
    deduplicated: int = 0


def threshold_for(days_left: int, thresholds: Sequence[int]) -> int | None:
    """The smallest threshold the batch is within (``None`` when outside all)."""
    within = [t for t in thresholds if days_left <= t]
    return min(within) if within else None


async def recipients(session: AsyncSession, store: Store) -> list[uuid.UUID]:
    active = [
        User.tenant_id == store.tenant_id,
        User.status == UserStatus.ACTIVE.value,
        User.deleted_at.is_(None),
    ]
    tiers = [
        [User.role == UserRole.STORE_MANAGER.value, User.store_id == store.id],
        (
            [User.role == UserRole.CLUSTER_HEAD.value, User.cluster_id == store.cluster_id]
            if store.cluster_id is not None
            else None
        ),
        [User.role == UserRole.OWNER.value],
    ]
    for tier in tiers:
        if tier is None:
            continue
        found = list(
            (
                await session.execute(select(User.id).where(*active, *tier).order_by(User.id))
            ).scalars()
        )
        if found:
            return found
    return []


def _pairs(rows: Any) -> dict[Any, Any]:
    return {key: value for key, value in rows}


async def _low_stock(session: AsyncSession, store: Store, default_level: int) -> list[LowStock]:
    on_hand: dict[uuid.UUID, Decimal] = _pairs(
        (
            await session.execute(
                select(StockBatch.sku_id, func.sum(StockBatch.qty))
                .where(
                    StockBatch.tenant_id == store.tenant_id,
                    StockBatch.store_id == store.id,
                    StockBatch.deleted_at.is_(None),
                )
                .group_by(StockBatch.sku_id)
            )
        ).tuples()
    )
    levels: dict[uuid.UUID, Decimal] = _pairs(
        (
            await session.execute(
                select(ReorderLevel.sku_id, ReorderLevel.reorder_level).where(
                    ReorderLevel.tenant_id == store.tenant_id,
                    ReorderLevel.store_id == store.id,
                    ReorderLevel.deleted_at.is_(None),
                )
            )
        ).tuples()
    )
    skus = set(on_hand) | set(levels)
    if not skus:
        return []
    active = set(
        (
            await session.execute(
                select(Sku.id)
                .join(Product, Product.id == Sku.product_id)
                .where(
                    Sku.id.in_(skus),
                    Sku.active.is_(True),
                    Sku.deleted_at.is_(None),
                    Product.active.is_(True),
                )
            )
        ).scalars()
    )
    out: list[LowStock] = []
    for sku_id in sorted(active, key=str):
        qty = Decimal(on_hand.get(sku_id) or 0)
        level = Decimal(levels[sku_id]) if sku_id in levels else Decimal(default_level)
        if qty < level:
            out.append(LowStock(store.id, sku_id, qty, level))
    return out


async def _expiring(
    session: AsyncSession, store: Store, today: date, thresholds: Sequence[int]
) -> list[Expiring]:
    horizon = max(thresholds)
    rows = (
        await session.execute(
            select(StockBatch).where(
                StockBatch.tenant_id == store.tenant_id,
                StockBatch.store_id == store.id,
                StockBatch.deleted_at.is_(None),
                StockBatch.qty > 0,
                StockBatch.expiry.is_not(None),
                StockBatch.expiry <= today + timedelta(days=horizon),
            )
        )
    ).scalars()
    out: list[Expiring] = []
    for b in rows:
        if b.expiry is None:  # pragma: no cover - the query filters them out
            continue
        days_left = (b.expiry - today).days
        threshold = threshold_for(days_left, thresholds)
        if threshold is None:
            continue
        out.append(
            Expiring(store.id, b.id, b.sku_id, b.batch_no, b.expiry, days_left, threshold, b.qty)
        )
    return out


async def _low_alerted_since_restock(
    session: AsyncSession, low: LowStock, tenant_id: uuid.UUID
) -> bool:
    restocked = await session.scalar(
        select(func.max(StockMovement.created_at)).where(
            StockMovement.tenant_id == tenant_id,
            StockMovement.store_id == low.store_id,
            StockMovement.sku_id == low.sku_id,
            StockMovement.kind.in_([k.value for k in INBOUND_KINDS]),
        )
    )
    stmt = select(Notification.id).where(
        Notification.tenant_id == tenant_id,
        Notification.kind == LOW_STOCK_KIND,
        Notification.data["store_id"].astext == str(low.store_id),
        Notification.data["sku_id"].astext == str(low.sku_id),
    )
    if restocked is not None:
        stmt = stmt.where(Notification.created_at > restocked)
    return (await session.scalar(stmt.limit(1))) is not None


async def _expiry_alerted(session: AsyncSession, e: Expiring, tenant_id: uuid.UUID) -> bool:
    found = await session.scalar(
        select(Notification.id)
        .where(
            Notification.tenant_id == tenant_id,
            Notification.kind == EXPIRY_KIND,
            Notification.data["batch_id"].astext == str(e.batch_id),
            Notification.data["threshold_days"].astext == str(e.threshold),
        )
        .limit(1)
    )
    return found is not None


def _notify(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    users: list[uuid.UUID],
    kind: str,
    data: dict[str, object],
) -> int:
    for user_id in users:
        session.add(
            Notification(
                tenant_id=tenant_id,
                # Wall clock (not the transaction's now()): compared with the wall-clock
                # time of the last receipt movement for the restock dedupe.
                created_at=datetime.now(UTC),
                user_id=user_id,
                kind=kind,
                title_key=f"notification.{kind}.title",
                body_key=f"notification.{kind}.body",
                data=data,
            )
        )
    return len(users)


async def stock_alerts(
    session: AsyncSession, *, tenant_id: uuid.UUID, now: datetime | None = None
) -> StockAlertReport:
    now = now or datetime.now(UTC)
    today = now.astimezone(IST).date()
    settings = await get_tenant_settings(session, tenant_id)
    thresholds = sorted(set(settings.stock_alerts.expiry_days), reverse=True)
    report = StockAlertReport(tenant_id=tenant_id, day=today)
    stores = (
        (
            await session.execute(
                select(Store)
                .where(Store.tenant_id == tenant_id, Store.deleted_at.is_(None))
                .order_by(Store.code)
            )
        )
        .scalars()
        .all()
    )
    for store in stores:
        users: list[uuid.UUID] | None = None
        for low in await _low_stock(session, store, settings.stock_alerts.default_reorder_level):
            report.low.append(low)
            if await _low_alerted_since_restock(session, low, tenant_id):
                report.deduplicated += 1
                continue
            users = users if users is not None else await recipients(session, store)
            report.notifications += _notify(
                session,
                tenant_id,
                users,
                LOW_STOCK_KIND,
                {
                    "store_id": str(store.id),
                    "store_code": store.code,
                    "sku_id": str(low.sku_id),
                    "on_hand": str(low.on_hand),
                    "reorder_level": str(low.level),
                    "day": today.isoformat(),
                },
            )
        for e in await _expiring(session, store, today, thresholds):
            report.expiring.append(e)
            if await _expiry_alerted(session, e, tenant_id):
                report.deduplicated += 1
                continue
            users = users if users is not None else await recipients(session, store)
            report.notifications += _notify(
                session,
                tenant_id,
                users,
                EXPIRY_KIND,
                {
                    "store_id": str(store.id),
                    "store_code": store.code,
                    "sku_id": str(e.sku_id),
                    "batch_id": str(e.batch_id),
                    "batch_no": e.batch_no,
                    "expiry": e.expiry.isoformat(),
                    "days_left": e.days_left,
                    "threshold_days": e.threshold,
                    "qty": str(e.qty),
                },
            )
        await session.flush()
    log.info(
        "stock_alerts",
        tenant_id=str(tenant_id),
        day=today.isoformat(),
        low=len(report.low),
        expiring=len(report.expiring),
        notifications=report.notifications,
        deduplicated=report.deduplicated,
    )
    return report


async def run_stock_alerts(
    tenant_ids: Sequence[uuid.UUID], *, now: datetime | None = None
) -> list[StockAlertReport]:
    reports: list[StockAlertReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(await stock_alerts(session, tenant_id=tenant_id, now=now))
    return reports


__all__ = [
    "EXPIRY_KIND",
    "LOW_STOCK_KIND",
    "StockAlertReport",
    "run_stock_alerts",
    "stock_alerts",
    "threshold_for",
]
