"""OPS-008 groundwork: daily payment reconciliation (provider settlements vs our payments).

For one tenant and business day (IST): the provider's settlement records of that day
(``PaymentProvider.fetch_settlements``) are matched by provider payment id against our
provider payments (UPI QR / links) that are ``paid`` / ``reconciled`` with ``paid_at`` on
that day. Mismatches:

* ``missing_in_settlement`` — we marked it paid, the provider did not settle it;
* ``missing_locally`` — the provider settled a payment of this tenant we do not have as
  paid (a lost / flagged webhook);
* ``amount_mismatch`` — both sides know it, the amounts differ.

Nothing is changed (dry run): the report is printed by ``jobs reconcile-payments`` and, when
there are mismatches, every active accountant of the tenant gets a notification (the
"finance ticket" of SPEC 12.2 until the ticketing integration exists).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date
from typing import Literal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification
from farmerapp.payments.day_close import day_bounds
from farmerapp.payments.models import PROVIDER_MODES, SETTLED_STATUSES, Payment
from farmerapp.payments.providers import PaymentProvider, SettlementRecord

log = get_logger("farmerapp.payments.reconcile")

MISMATCH_KIND = "payment_reconciliation"
MISMATCH_TITLE = "notification.payment_reconciliation.title"
MISMATCH_BODY = "notification.payment_reconciliation.body"

MismatchKind = Literal["missing_in_settlement", "missing_locally", "amount_mismatch"]


@dataclass(frozen=True)
class Mismatch:
    kind: MismatchKind
    provider_ref: str | None
    payment_id: uuid.UUID | None = None
    ours_paise: int | None = None
    theirs_paise: int | None = None


@dataclass
class ReconcileReport:
    tenant_id: uuid.UUID
    day: date
    settlements: int = 0
    paid_payments: int = 0
    matched: int = 0
    mismatches: list[Mismatch] = field(default_factory=list)
    notified: int = 0


def _ours(record: SettlementRecord, tenant_id: uuid.UUID) -> bool:
    tenant = record.notes.get("tenant_id")
    return tenant is None or tenant == str(tenant_id)


async def reconcile_payments(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    day: date,
    provider: PaymentProvider,
    *,
    notify: bool = True,
) -> ReconcileReport:
    report = ReconcileReport(tenant_id=tenant_id, day=day)
    records = [r for r in await provider.fetch_settlements(day) if _ours(r, tenant_id)]
    start, end = day_bounds(day)
    paid = (
        (
            await session.execute(
                select(Payment).where(
                    Payment.tenant_id == tenant_id,
                    Payment.deleted_at.is_(None),
                    Payment.mode.in_([m.value for m in PROVIDER_MODES]),
                    Payment.status.in_([s.value for s in SETTLED_STATUSES]),
                    Payment.paid_at >= start,
                    Payment.paid_at < end,
                )
            )
        )
        .scalars()
        .all()
    )
    report.settlements, report.paid_payments = len(records), len(paid)
    by_ref = {p.provider_ref: p for p in paid if p.provider_ref}
    seen: set[str] = set()
    for record in records:
        payment = by_ref.get(record.payment_ref)
        seen.add(record.payment_ref)
        if payment is None:
            report.mismatches.append(
                Mismatch("missing_locally", record.payment_ref, theirs_paise=record.amount_paise)
            )
        elif payment.amount_paise != record.amount_paise:
            report.mismatches.append(
                Mismatch(
                    "amount_mismatch",
                    record.payment_ref,
                    payment.id,
                    payment.amount_paise,
                    record.amount_paise,
                )
            )
        else:
            report.matched += 1
    for payment in paid:
        if payment.provider_ref not in seen:
            report.mismatches.append(
                Mismatch(
                    "missing_in_settlement",
                    payment.provider_ref,
                    payment.id,
                    ours_paise=payment.amount_paise,
                )
            )
    if report.mismatches and notify:
        report.notified = await _notify_accountants(session, report)
    log.info(
        "payments_reconciled",
        tenant_id=str(tenant_id),
        day=day.isoformat(),
        settlements=report.settlements,
        paid=report.paid_payments,
        matched=report.matched,
        mismatches=len(report.mismatches),
    )
    return report


async def _notify_accountants(session: AsyncSession, report: ReconcileReport) -> int:
    accountants = (
        (
            await session.execute(
                select(User).where(
                    User.tenant_id == report.tenant_id,
                    User.role == UserRole.ACCOUNTANT.value,
                    User.status == UserStatus.ACTIVE.value,
                    User.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    counts: dict[str, int] = {}
    for m in report.mismatches:
        counts[m.kind] = counts.get(m.kind, 0) + 1
    for accountant in accountants:
        session.add(
            Notification(
                tenant_id=report.tenant_id,
                user_id=accountant.id,
                kind=MISMATCH_KIND,
                title_key=MISMATCH_TITLE,
                body_key=MISMATCH_BODY,
                data={"day": report.day.isoformat(), "mismatches": counts},
            )
        )
    await session.flush()
    return len(accountants)


async def run_reconcile(
    tenant_ids: Sequence[uuid.UUID], day: date, provider: PaymentProvider
) -> list[ReconcileReport]:
    reports: list[ReconcileReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(await reconcile_payments(session, tenant_id, day, provider))
    return reports


__all__ = ["Mismatch", "ReconcileReport", "reconcile_payments", "run_reconcile"]
