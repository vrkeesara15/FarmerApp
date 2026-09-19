"""OPS-008: daily payment reconciliation (provider settlements vs our payments).

For one tenant and business day (IST): the provider's settlement records of that day
(``PaymentProvider.fetch_settlements``) are matched by provider payment id against our
provider payments (UPI QR / links) that are ``paid`` / ``reconciled`` with ``paid_at`` on
that day. Mismatches:

* ``missing_in_settlement`` — we marked it paid, the provider did not settle it;
* ``missing_locally`` — the provider settled a payment of this tenant we do not have as
  paid (a lost / flagged webhook);
* ``amount_mismatch`` — both sides know it, the amounts differ.

No payment is changed (dry run): the report is printed by ``jobs reconcile-payments``. When
there are mismatches the job opens the SPEC 12.2 **finance ticket**:

* a flag with the system rule id ``OPS-008`` about the tenant (``subject_type = tenant``,
  key = the business day, so one ticket per tenant and day; a re-run of the same day is a
  no-op while it is unresolved or was already reviewed), severity high, owned by an auditor
  (ladder fallback: owner), the tenant's active accountants as ``watchers``, SLA 24 h
  (OPS-010 escalates it like any flag). Evidence: the mismatched payments as records and
  every mismatch (kind, provider ref, ours / theirs paise) in ``metrics``. It appears in the
  WC-010 inbox; accountants see the finance tickets they watch.
* a ``payment_reconciliation`` notification to every active accountant (with the flag id).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Literal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.payments.day_close import day_bounds
from farmerapp.payments.models import PROVIDER_MODES, SETTLED_STATUSES, Payment
from farmerapp.payments.providers import PaymentProvider, SettlementRecord
from farmerapp.rules.registry import Evidence, Finding
from farmerapp.rules.registry import record as evidence_record
from farmerapp.rules.schema import OwnerRole, Severity, Subject

log = get_logger("farmerapp.payments.reconcile")

MISMATCH_KIND = NotificationKind.PAYMENT_RECONCILIATION.value
FINANCE_RULE_ID = "OPS-008"
FINANCE_SLA_HOURS = 24
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
    flag_id: uuid.UUID | None = None  # the finance ticket (None: no mismatch or deduped)


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
    now: datetime | None = None,
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
        accountants = await _accountants(session, tenant_id)
        report.flag_id = await _finance_ticket(
            session, report, accountants, now=now or datetime.now(UTC)
        )
        if report.flag_id is not None:  # a re-run of a ticketed day notifies nobody again
            report.notified = await _notify_accountants(session, report, accountants)
    log.info(
        "payments_reconciled",
        tenant_id=str(tenant_id),
        day=day.isoformat(),
        settlements=report.settlements,
        paid=report.paid_payments,
        matched=report.matched,
        mismatches=len(report.mismatches),
        flag_id=str(report.flag_id) if report.flag_id else None,
    )
    return report


async def _accountants(session: AsyncSession, tenant_id: uuid.UUID) -> list[uuid.UUID]:
    rows = await session.execute(
        select(User.id)
        .where(
            User.tenant_id == tenant_id,
            User.role == UserRole.ACCOUNTANT.value,
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
        )
        .order_by(User.created_at, User.id)
    )
    return list(rows.scalars())


def _counts(report: ReconcileReport) -> dict[str, int]:
    counts: dict[str, int] = {}
    for m in report.mismatches:
        counts[m.kind] = counts.get(m.kind, 0) + 1
    return counts


async def _finance_ticket(
    session: AsyncSession,
    report: ReconcileReport,
    accountants: list[uuid.UUID],
    *,
    now: datetime,
) -> uuid.UUID | None:
    """The OPS-008 flag for this tenant and day (``None`` when it already exists)."""
    from farmerapp.flags.service import raise_system_flag  # flags import payments models

    evidence = Evidence(
        records=[
            evidence_record("payment", m.payment_id) for m in report.mismatches if m.payment_id
        ],
        metrics={
            "day": report.day.isoformat(),
            "settlements": report.settlements,
            "paid_payments": report.paid_payments,
            "matched": report.matched,
            "counts": _counts(report),
            "mismatches": [
                {
                    "kind": m.kind,
                    "provider_ref": m.provider_ref,
                    "payment_id": str(m.payment_id) if m.payment_id else None,
                    "ours_paise": m.ours_paise,
                    "theirs_paise": m.theirs_paise,
                }
                for m in report.mismatches
            ],
        },
    )
    finding = Finding(
        subject_type=Subject.TENANT,
        subject_id=report.tenant_id,
        key=report.day.isoformat(),
        title=f"Payment reconciliation {report.day.isoformat()}: "
        f"{len(report.mismatches)} mismatch(es) with the provider settlements",
        evidence=evidence,
    )
    flag = await raise_system_flag(
        session,
        tenant_id=report.tenant_id,
        rule_id=FINANCE_RULE_ID,
        finding=finding,
        severity=Severity.HIGH,
        owner_role=OwnerRole.AUDITOR,
        sla_hours=FINANCE_SLA_HOURS,
        now=now,
        watchers=accountants,
    )
    return flag.id if flag is not None else None


async def _notify_accountants(
    session: AsyncSession, report: ReconcileReport, accountants: list[uuid.UUID]
) -> int:
    counts = _counts(report)
    for accountant_id in accountants:
        session.add(
            Notification(
                tenant_id=report.tenant_id,
                user_id=accountant_id,
                kind=MISMATCH_KIND,
                title_key=MISMATCH_TITLE,
                body_key=MISMATCH_BODY,
                data={
                    "day": report.day.isoformat(),
                    "mismatches": counts,
                    "flag_id": str(report.flag_id) if report.flag_id else None,
                },
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


__all__ = [
    "FINANCE_RULE_ID",
    "Mismatch",
    "ReconcileReport",
    "reconcile_payments",
    "run_reconcile",
]
