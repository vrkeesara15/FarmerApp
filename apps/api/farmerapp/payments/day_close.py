"""Day-end totals and the store day close (ST-002, ST-006, VA-E10 hook).

Business days are IST calendar days. A payment belongs to the day it was received:
``coalesce(paid_at, created_at)`` inside ``[date 00:00 IST, next day 00:00 IST)``.

* ``GET /v1/stores/{id}/day-summary?date=`` — money received by mode (all five modes,
  zero-filled; statuses ``paid`` / ``reconciled`` / ``pending_reconciliation``), what is
  still waiting on the provider, failures, refunds and the cash the drawer should hold.
* ``POST /v1/stores/{id}/day-close`` — the manager counts the cash: expected = the day's
  cash payments (including those ``pending_reconciliation``), variance = counted -
  expected. The day's ``pending_reconciliation`` cash payments become ``reconciled`` (with
  ``day_close_id``). When |variance| is above the tenant's
  ``day_close_variance_threshold_paise`` (default Rs 500) every active auditor of the tenant
  gets a notification and ``CashVarianceDetected`` is published (VA-E10, M4). One close per
  store and date: a second close is 409 ``day_already_closed``.
* ``POST /v1/stores/{id}/day-close/{close_id}/reopen`` — a cluster head (own cluster) or the
  owner / director reopens a close with a reason: its cash payments go back to
  ``pending_reconciliation`` and the next close updates the same row.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, time, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import ColumnElement, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ConflictError, NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import visible_store_filters
from farmerapp.db.models.tenant import Tenant
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification
from farmerapp.payments.config import IST, payment_settings
from farmerapp.payments.events import CashVarianceDetected, bus
from farmerapp.payments.models import (
    RECEIVED_STATUSES,
    DayClose,
    DayCloseStatus,
    Payment,
    PaymentMode,
    PaymentStatus,
)
from farmerapp.payments.schemas import (
    CountAmount,
    DayCloseIn,
    DayCloseOut,
    DayCloseReopenIn,
    DaySummaryOut,
    ModeTotal,
)
from farmerapp.payments.service import validate_blob
from farmerapp.tenants.models import Store
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.uploads.router import get_blob_store

log = get_logger("farmerapp.payments.day_close")

TIMEZONE_NAME = "Asia/Kolkata"
VARIANCE_KIND = "day_close_variance"  # notification.kind (VA-E10 / ST-006)
VARIANCE_TITLE = "notification.day_close_variance.title"
VARIANCE_BODY = "notification.day_close_variance.body"

SUMMARY_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
)
CLOSE_ROLES = (Role.OWNER, Role.ACCOUNTANT, Role.CLUSTER_HEAD, Role.STORE_MANAGER)
REOPEN_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD)


class DayAlreadyClosedError(ConflictError):
    code = "day_already_closed"


class DayCloseNotClosedError(ConflictError):
    code = "day_close_not_closed"


class FutureBusinessDateError(AppError):
    status = 422
    code = "future_business_date"


class DepositSlipRequiredError(AppError):
    status = 422
    code = "deposit_slip_required"


# --------------------------------------------------------------------------- helpers
def ist_today(now: datetime) -> date:
    return now.astimezone(IST).date()


def day_bounds(day: date) -> tuple[datetime, datetime]:
    """``[day 00:00 IST, next day 00:00 IST)`` in UTC."""
    start = datetime.combine(day, time(0), tzinfo=IST).astimezone(UTC)
    return start, start + timedelta(days=1)


RECEIVED_AT = func.coalesce(Payment.paid_at, Payment.created_at)


def _day_filters(store_id: uuid.UUID, day: date) -> list[ColumnElement[bool]]:
    start, end = day_bounds(day)
    return [
        Payment.store_id == store_id,
        Payment.deleted_at.is_(None),
        start <= RECEIVED_AT,
        end > RECEIVED_AT,
    ]


async def visible_store(session: AsyncSession, actor: User, store_id: uuid.UUID) -> Store:
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


async def expected_cash(session: AsyncSession, store_id: uuid.UUID, day: date) -> int:
    total = await session.scalar(
        select(func.coalesce(func.sum(Payment.amount_paise), 0)).where(
            *_day_filters(store_id, day),
            Payment.mode == PaymentMode.CASH.value,
            Payment.status.in_([s.value for s in RECEIVED_STATUSES]),
        )
    )
    return int(total or 0)


async def _close_for(session: AsyncSession, store_id: uuid.UUID, day: date) -> DayClose | None:
    return (
        await session.execute(
            select(DayClose).where(
                DayClose.store_id == store_id,
                DayClose.business_date == day,
                DayClose.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


# --------------------------------------------------------------------------- summary
async def day_summary(session: AsyncSession, store: Store, day: date) -> DaySummaryOut:
    rows = (
        await session.execute(
            select(Payment.mode, Payment.status, func.count(), func.sum(Payment.amount_paise))
            .where(*_day_filters(store.id, day))
            .group_by(Payment.mode, Payment.status)
        )
    ).all()
    received = {s.value for s in RECEIVED_STATUSES}
    by_mode = {m: [0, 0] for m in PaymentMode}
    waiting, failed, refunds = [0, 0], [0, 0], [0, 0]
    pending_cash = 0
    for mode, status, count, amount in rows:
        amount = int(amount or 0)
        if status in received:
            by_mode[PaymentMode(mode)][0] += count
            by_mode[PaymentMode(mode)][1] += amount
            if status == PaymentStatus.PENDING_RECONCILIATION:
                pending_cash += amount
        elif status in (PaymentStatus.CREATED, PaymentStatus.PENDING):
            waiting[0] += count
            waiting[1] += amount
        elif status == PaymentStatus.FAILED:
            failed[0] += count
            failed[1] += amount
        elif status == PaymentStatus.REFUNDED:
            refunds[0] += count
            refunds[1] += amount
    close = await _close_for(session, store.id, day)
    return DaySummaryOut(
        store_id=store.id,
        business_date=day,
        timezone=TIMEZONE_NAME,
        by_mode=[ModeTotal(mode=m, count=c, amount_paise=a) for m, (c, a) in by_mode.items()],
        total_received_paise=sum(  # credit is a khata debit, not money received
            a for m, (_c, a) in by_mode.items() if m != PaymentMode.CREDIT
        ),
        waiting=CountAmount(count=waiting[0], amount_paise=waiting[1]),
        failed=CountAmount(count=failed[0], amount_paise=failed[1]),
        refunds=CountAmount(count=refunds[0], amount_paise=refunds[1]),
        expected_cash_paise=by_mode[PaymentMode.CASH][1],
        cash_pending_reconciliation_paise=pending_cash,
        day_close=DayCloseOut.model_validate(close) if close is not None else None,
    )


# --------------------------------------------------------------------------- close
async def _notify_auditors(session: AsyncSession, close: DayClose, threshold: int) -> int:
    auditors = (
        (
            await session.execute(
                select(User).where(
                    User.tenant_id == close.tenant_id,
                    User.role == UserRole.AUDITOR.value,
                    User.status == UserStatus.ACTIVE.value,
                    User.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    for auditor in auditors:
        session.add(
            Notification(
                tenant_id=close.tenant_id,
                user_id=auditor.id,
                kind=VARIANCE_KIND,
                title_key=VARIANCE_TITLE,
                body_key=VARIANCE_BODY,
                data={
                    "day_close_id": str(close.id),
                    "store_id": str(close.store_id),
                    "business_date": close.business_date.isoformat(),
                    "variance_paise": close.variance_paise,
                    "threshold_paise": threshold,
                },
            )
        )
    return len(auditors)


async def close_day(
    session: AsyncSession,
    actor: User,
    store: Store,
    body: DayCloseIn,
    *,
    blobs: BlobStore,
    now: datetime,
) -> DayClose:
    if body.business_date > ist_today(now):
        raise FutureBusinessDateError("The business date is in the future.")
    if body.cash_counted_paise > 0 and not body.deposit_slip_uri:
        raise DepositSlipRequiredError("Counted cash needs the deposit slip photo.")
    if body.deposit_slip_uri:
        await validate_blob(body.deposit_slip_uri, actor.tenant_id, blobs)
    existing = await _close_for(session, store.id, body.business_date)
    if existing is not None and existing.status == DayCloseStatus.CLOSED:
        raise DayAlreadyClosedError("This store's day is already closed.")

    expected = await expected_cash(session, store.id, body.business_date)
    variance = body.cash_counted_paise - expected
    settings = payment_settings((await session.get_one(Tenant, actor.tenant_id)).settings)
    threshold = settings.day_close_variance_threshold_paise
    flagged = abs(variance) > threshold
    close = existing or DayClose(tenant_id=actor.tenant_id, store_id=store.id)
    close.business_date = body.business_date
    close.cash_expected_paise = expected
    close.cash_counted_paise = body.cash_counted_paise
    close.variance_paise = variance
    close.deposit_slip_uri = body.deposit_slip_uri
    close.notes = body.notes
    close.closed_by = actor.id
    close.closed_at = now
    close.status = DayCloseStatus.CLOSED.value
    close.variance_flagged = flagged
    if existing is None:
        session.add(close)
    await session.flush()

    pending = (
        (
            await session.execute(
                select(Payment).where(
                    *_day_filters(store.id, body.business_date),
                    Payment.mode == PaymentMode.CASH.value,
                    Payment.status == PaymentStatus.PENDING_RECONCILIATION.value,
                )
            )
        )
        .scalars()
        .all()
    )
    for payment in pending:
        payment.status = PaymentStatus.RECONCILED.value
        payment.day_close_id = close.id
    await session.flush()

    if flagged:
        notified = await _notify_auditors(session, close, threshold)
        await session.flush()
        bus.publish(
            CashVarianceDetected(
                tenant_id=close.tenant_id,
                day_close_id=close.id,
                store_id=close.store_id,
                business_date=close.business_date,
                cash_expected_paise=expected,
                cash_counted_paise=body.cash_counted_paise,
                variance_paise=variance,
                threshold_paise=threshold,
                closed_by=actor.id,
                at=now,
            )
        )
        log.warning(
            "day_close_variance_flagged",
            day_close_id=str(close.id),
            store_id=str(store.id),
            variance_paise=variance,
            threshold_paise=threshold,
            auditors_notified=notified,
        )
    log.info(
        "day_closed",
        day_close_id=str(close.id),
        store_id=str(store.id),
        business_date=body.business_date.isoformat(),
        reconciled=len(pending),
    )
    return close


async def reopen_day(
    session: AsyncSession,
    actor: User,
    store: Store,
    close_id: uuid.UUID,
    body: DayCloseReopenIn,
    *,
    now: datetime,
) -> DayClose:
    close = await session.get(DayClose, close_id)
    if close is None or close.store_id != store.id or close.deleted_at is not None:
        raise NotFoundError("Day close not found.")
    if close.status != DayCloseStatus.CLOSED:
        raise DayCloseNotClosedError("This day close is already reopened.")
    close.status = DayCloseStatus.REOPENED.value
    close.reopened_by = actor.id
    close.reopened_at = now
    close.reopen_reason = body.reason
    reconciled = (
        (
            await session.execute(
                select(Payment).where(
                    Payment.day_close_id == close.id,
                    Payment.mode == PaymentMode.CASH.value,
                    Payment.status == PaymentStatus.RECONCILED.value,
                )
            )
        )
        .scalars()
        .all()
    )
    for payment in reconciled:
        payment.status = PaymentStatus.PENDING_RECONCILIATION.value
        payment.day_close_id = None
    await session.flush()
    log.info("day_close_reopened", day_close_id=str(close.id), payments=len(reconciled))
    return close


# --------------------------------------------------------------------------- routes
router = APIRouter(prefix="/stores", tags=["day-close"])


@router.get(
    "/{id}/day-summary",
    operation_id="getStoreDaySummary",
    summary="Day-end totals by payment mode, refunds and expected cash (ST-002)",
    response_model=DaySummaryOut,
    responses=problem_responses((404, "not_found")),
)
async def get_day_summary(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*SUMMARY_ROLES)],
    session: DbSession,
    auth: Services,
    day: Annotated[date | None, Query(alias="date")] = None,
) -> DaySummaryOut:
    store = await visible_store(session, actor, id)
    return await day_summary(session, store, day or ist_today(auth.clock.now()))


@router.post(
    "/{id}/day-close",
    operation_id="closeStoreDay",
    summary="Close the store's day: cash count, variance, deposit slip (ST-006)",
    status_code=201,
    response_model=DayCloseOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "day_already_closed"),
        (422, "future_business_date"),
        (422, "deposit_slip_required"),
        (422, "invalid_blob"),
    ),
)
async def post_day_close(
    id: uuid.UUID,
    body: DayCloseIn,
    actor: Annotated[User, require_roles(*CLOSE_ROLES)],
    session: DbSession,
    auth: Services,
    blobs: Annotated[BlobStore, Depends(get_blob_store)],
) -> DayCloseOut:
    store = await visible_store(session, actor, id)
    close = await close_day(session, actor, store, body, blobs=blobs, now=auth.clock.now())
    return DayCloseOut.model_validate(close)


@router.post(
    "/{id}/day-close/{close_id}/reopen",
    operation_id="reopenStoreDay",
    summary="Reopen a closed day (cluster head, owner or director)",
    response_model=DayCloseOut,
    responses=problem_responses((404, "not_found"), (409, "day_close_not_closed")),
)
async def post_day_close_reopen(
    id: uuid.UUID,
    close_id: uuid.UUID,
    body: DayCloseReopenIn,
    actor: Annotated[User, require_roles(*REOPEN_ROLES)],
    session: DbSession,
    auth: Services,
) -> DayCloseOut:
    store = await visible_store(session, actor, id)
    close = await reopen_day(session, actor, store, close_id, body, now=auth.clock.now())
    return DayCloseOut.model_validate(close)


__all__ = [
    "CLOSE_ROLES",
    "IST",
    "REOPEN_ROLES",
    "SUMMARY_ROLES",
    "close_day",
    "day_bounds",
    "day_summary",
    "expected_cash",
    "ist_today",
    "reopen_day",
    "router",
    "visible_store",
]
