"""OPS-007 — store with zero sales on a working day, or a day not closed by 22:00.

``python -m farmerapp.jobs store-day-watch --tenant-id … [--date YYYY-MM-DD]`` (Cloud
Scheduler daily at 22:15 IST; ``--date`` re-checks an earlier day). For the business day
``day`` (IST, default today) of every store of the tenant, once the tenant's
``day_close_deadline_local_time`` (22:00) has passed:

* the day is skipped unless it is a **working day** of the tenant calendar
  (``TenantSettings.working_days``, Monday-Saturday by default, minus ``holidays``);
* ``store_zero_sales`` — no order of the store was placed that day (any channel, POS
  included; cancelled orders do not count);
* ``store_day_not_closed`` — no ``day_close`` row of that day with ``status = closed`` and
  ``closed_at`` at or before the deadline (a reopened day counts as not closed).

Each alert is a ``notification`` to the store's active store manager(s) and the cluster
head(s) of its cluster (the tenant's owners when the store has neither), **once** per store,
day and kind (re-runs are no-ops), plus a WARNING
log line ``store_day_alert``. Nothing else changes.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from enum import StrEnum

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.orders.models import Order, OrderStatus
from farmerapp.payments.config import IST
from farmerapp.payments.day_close import day_bounds
from farmerapp.payments.models import DayClose, DayCloseStatus
from farmerapp.tenants.models import Store
from farmerapp.tenants.settings import TenantSettings, get_tenant_settings

log = get_logger("farmerapp.ops.store_watch")


class StoreDayAlertKind(StrEnum):
    ZERO_SALES = NotificationKind.STORE_ZERO_SALES.value
    NOT_CLOSED = NotificationKind.STORE_DAY_NOT_CLOSED.value


@dataclass(frozen=True)
class StoreDayAlert:
    tenant_id: uuid.UUID
    store_id: uuid.UUID
    store_code: str
    day: date
    kind: StoreDayAlertKind
    notified: list[uuid.UUID]


@dataclass
class StoreDayReport:
    tenant_id: uuid.UUID
    day: date
    working_day: bool = True
    checked: bool = True  # False before the deadline
    stores: int = 0
    alerts: list[StoreDayAlert] = field(default_factory=list)


def deadline_of(day: date, settings: TenantSettings) -> datetime:
    return datetime.combine(day, settings.day_close_deadline(), tzinfo=IST).astimezone(UTC)


async def _stores(session: AsyncSession, tenant_id: uuid.UUID) -> list[Store]:
    rows = await session.execute(
        select(Store)
        .where(Store.tenant_id == tenant_id, Store.deleted_at.is_(None))
        .order_by(Store.code)
    )
    return list(rows.scalars())


async def _stores_with_sales(
    session: AsyncSession, tenant_id: uuid.UUID, day: date
) -> set[uuid.UUID]:
    start, end = day_bounds(day)
    rows = await session.execute(
        select(Order.store_id)
        .where(
            Order.tenant_id == tenant_id,
            Order.deleted_at.is_(None),
            Order.status != OrderStatus.CANCELLED.value,
            Order.placed_at >= start,
            Order.placed_at < end,
        )
        .distinct()
    )
    return set(rows.scalars())


async def _stores_closed(
    session: AsyncSession, tenant_id: uuid.UUID, day: date, deadline: datetime
) -> set[uuid.UUID]:
    rows = await session.execute(
        select(DayClose.store_id).where(
            DayClose.tenant_id == tenant_id,
            DayClose.business_date == day,
            DayClose.status == DayCloseStatus.CLOSED.value,
            DayClose.closed_at <= deadline,
        )
    )
    return set(rows.scalars())


async def _recipients(session: AsyncSession, store: Store) -> list[uuid.UUID]:
    """Active store managers of the store and cluster heads of its cluster."""
    by_store = and_(User.role == UserRole.STORE_MANAGER.value, User.store_id == store.id)
    either = (
        or_(
            by_store,
            and_(User.role == UserRole.CLUSTER_HEAD.value, User.cluster_id == store.cluster_id),
        )
        if store.cluster_id is not None
        else by_store
    )
    rows = await session.execute(
        select(User.id)
        .where(
            User.tenant_id == store.tenant_id,
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
            either,
        )
        .order_by(User.role, User.id)
    )
    found = list(rows.scalars())
    if found:
        return found
    # Nobody holds either role for this store: the alert goes to the tenant's owners rather
    # than nowhere (and the notification row is what makes a re-run a no-op).
    owners = await session.execute(
        select(User.id)
        .where(
            User.tenant_id == store.tenant_id,
            User.role == UserRole.OWNER.value,
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
        )
        .order_by(User.id)
    )
    return list(owners.scalars())


async def _already_alerted(
    session: AsyncSession, store: Store, day: date, kind: StoreDayAlertKind
) -> bool:
    found = await session.scalar(
        select(Notification.id)
        .where(
            Notification.tenant_id == store.tenant_id,
            Notification.kind == kind.value,
            Notification.data["store_id"].astext == str(store.id),
            Notification.data["day"].astext == day.isoformat(),
        )
        .limit(1)
    )
    return found is not None


async def _alert(
    session: AsyncSession, store: Store, day: date, kind: StoreDayAlertKind
) -> StoreDayAlert | None:
    if await _already_alerted(session, store, day, kind):
        return None
    recipients = await _recipients(session, store)
    for user_id in recipients:
        session.add(
            Notification(
                tenant_id=store.tenant_id,
                user_id=user_id,
                kind=kind.value,
                title_key=f"notification.{kind.value}.title",
                body_key=f"notification.{kind.value}.body",
                data={
                    "store_id": str(store.id),
                    "store_code": store.code,
                    "day": day.isoformat(),
                },
            )
        )
    log.warning(
        "store_day_alert",
        tenant_id=str(store.tenant_id),
        store_id=str(store.id),
        store_code=store.code,
        day=day.isoformat(),
        kind=kind.value,
        notified=len(recipients),
    )
    return StoreDayAlert(store.tenant_id, store.id, store.code, day, kind, recipients)


async def store_day_watch(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime | None = None,
    day: date | None = None,
) -> StoreDayReport:
    """One pass for one tenant (the session is bound to ``tenant_id``)."""
    now = now or datetime.now(UTC)
    day = day or now.astimezone(IST).date()
    settings = await get_tenant_settings(session, tenant_id)
    report = StoreDayReport(tenant_id=tenant_id, day=day)
    if not settings.is_working_day(day):
        report.working_day = False
        log.info("store_day_watch", tenant_id=str(tenant_id), day=day.isoformat(), skipped="off")
        return report
    deadline = deadline_of(day, settings)
    if now < deadline:
        report.checked = False
        log.info("store_day_watch", tenant_id=str(tenant_id), day=day.isoformat(), skipped="early")
        return report
    stores = await _stores(session, tenant_id)
    report.stores = len(stores)
    selling = await _stores_with_sales(session, tenant_id, day)
    closed = await _stores_closed(session, tenant_id, day, deadline)
    for store in stores:
        checks = (
            (store.id not in selling, StoreDayAlertKind.ZERO_SALES),
            (store.id not in closed, StoreDayAlertKind.NOT_CLOSED),
        )
        for failed, kind in checks:
            if failed:
                alert = await _alert(session, store, day, kind)
                if alert is not None:
                    report.alerts.append(alert)
    await session.flush()
    log.info(
        "store_day_watch",
        tenant_id=str(tenant_id),
        day=day.isoformat(),
        stores=report.stores,
        zero_sales=sum(a.kind == StoreDayAlertKind.ZERO_SALES for a in report.alerts),
        not_closed=sum(a.kind == StoreDayAlertKind.NOT_CLOSED for a in report.alerts),
    )
    return report


async def run_store_day_watch(
    tenant_ids: Sequence[uuid.UUID], *, now: datetime | None = None, day: date | None = None
) -> list[StoreDayReport]:
    reports: list[StoreDayReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await store_day_watch(session, tenant_id=tenant_id, now=now, day=day)
                )
    return reports


__all__ = [
    "StoreDayAlert",
    "StoreDayAlertKind",
    "StoreDayReport",
    "deadline_of",
    "run_store_day_watch",
    "store_day_watch",
]
