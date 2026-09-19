"""OPS-009 / DX-006 — diagnosis review queue age and the daily LLM fallback rate.

``python -m farmerapp.jobs diagnosis-queue-age --tenant … [--date YYYY-MM-DD]`` (Cloud
Scheduler hourly). For one tenant:

* **Queue age** — every diagnosis waiting for an agronomist (provisional / out of scope /
  flagged, not reviewed) older than ``QUEUE_ALERT_HOURS`` (18 h, DX-006: reviewed within
  24 h in season) is alerted **once**: a ``diagnosis_queue_aged`` notification to the
  tenant's active agronomists (owners when there is none) and ``age_alerted_at`` set on the
  row; a WARNING ``diagnosis_queue_aged`` log line carries the counts for the log-based alert.
  Every run logs ``diagnosis_queue_snapshot`` (queue size, overdue count, oldest age in hours)
  for the OPS-009 business metric.
* **Stale queued** — a ``queued`` diagnosis older than ``STALE_QUEUED`` (a lost Pub/Sub
  message, a publish failure) is delivered again (published, or processed inline).
* **LLM fallback rate** — of the diagnoses answered on the IST day (default today),
  the share that needed the LLM: ``diagnosis_llm_fallback_rate`` every run; above 40 % (with
  at least ``MIN_SAMPLE`` answers) a WARNING ``diagnosis_llm_fallback_alert`` and, once per
  day, a ``diagnosis_llm_rate`` notification to the agronomists and owners ("product").
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.models import Diagnosis, DiagnosisStatus
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.payments.config import IST
from farmerapp.payments.day_close import day_bounds

log = get_logger("farmerapp.ops.diagnosis_watch")

QUEUE_ALERT_HOURS = 18
LLM_RATE_ALERT = 0.40
MIN_SAMPLE = 5
STALE_QUEUED = timedelta(minutes=15)


@dataclass
class DiagnosisWatchReport:
    tenant_id: uuid.UUID
    day: date
    queue: int = 0
    overdue: int = 0
    oldest_hours: float | None = None
    alerted: list[uuid.UUID] = field(default_factory=list)
    notified: list[uuid.UUID] = field(default_factory=list)
    redelivered: list[uuid.UUID] = field(default_factory=list)
    answered: int = 0
    llm_fallbacks: int = 0
    llm_rate: float | None = None
    llm_alert: bool = False


async def _users(
    session: AsyncSession, tenant_id: uuid.UUID, roles: Sequence[UserRole]
) -> list[uuid.UUID]:
    rows = await session.execute(
        select(User.id)
        .where(
            User.tenant_id == tenant_id,
            User.role.in_([r.value for r in roles]),
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
        )
        .order_by(User.role, User.id)
    )
    return list(rows.scalars())


async def _agronomists(session: AsyncSession, tenant_id: uuid.UUID) -> list[uuid.UUID]:
    found = await _users(session, tenant_id, [UserRole.AGRONOMIST])
    return found or await _users(session, tenant_id, [UserRole.OWNER])


def _notification(
    tenant_id: uuid.UUID, user_id: uuid.UUID, kind: NotificationKind, data: dict[str, object]
) -> Notification:
    return Notification(
        tenant_id=tenant_id,
        user_id=user_id,
        kind=kind.value,
        title_key=f"notification.{kind.value}.title",
        body_key=f"notification.{kind.value}.body",
        data=data,
    )


async def _queue_age(session: AsyncSession, report: DiagnosisWatchReport, now: datetime) -> None:
    from farmerapp.diagnosis.models import REVIEWABLE

    tid = report.tenant_id
    waiting = [
        Diagnosis.tenant_id == tid,
        Diagnosis.deleted_at.is_(None),
        Diagnosis.reviewed_at.is_(None),
        (Diagnosis.status.in_([s.value for s in REVIEWABLE]))
        | (Diagnosis.flagged.is_(True) & (Diagnosis.status != DiagnosisStatus.QUEUED.value)),
    ]
    size, oldest = (
        await session.execute(select(func.count(), func.min(Diagnosis.created_at)).where(*waiting))
    ).one()
    report.queue = int(size or 0)
    report.oldest_hours = (
        round((now - oldest).total_seconds() / 3600, 2) if oldest is not None else None
    )
    cutoff = now - timedelta(hours=QUEUE_ALERT_HOURS)
    report.overdue = int(
        await session.scalar(
            select(func.count())
            .select_from(Diagnosis)
            .where(*waiting, Diagnosis.created_at <= cutoff)
        )
        or 0
    )
    fresh = (
        (
            await session.execute(
                select(Diagnosis)
                .where(*waiting, Diagnosis.created_at <= cutoff, Diagnosis.age_alerted_at.is_(None))
                .order_by(Diagnosis.created_at)
                .with_for_update(skip_locked=True)
            )
        )
        .scalars()
        .all()
    )
    if fresh:
        recipients = await _agronomists(session, tid)
        for row in fresh:
            row.age_alerted_at = now
            report.alerted.append(row.id)
        oldest_row = fresh[0]
        for user_id in recipients:
            session.add(
                _notification(
                    tid,
                    user_id,
                    NotificationKind.DIAGNOSIS_QUEUE_AGED,
                    {
                        "count": len(fresh),
                        "oldest_diagnosis_id": str(oldest_row.id),
                        "oldest_hours": round(
                            (now - oldest_row.created_at).total_seconds() / 3600, 1
                        ),
                        "diagnosis_ids": [str(r.id) for r in fresh[:50]],
                    },
                )
            )
        report.notified = recipients
        log.warning(
            "diagnosis_queue_aged",
            tenant_id=str(tid),
            newly_overdue=len(fresh),
            overdue=report.overdue,
            oldest_hours=report.oldest_hours,
            notified=len(recipients),
        )
    log.info(
        "diagnosis_queue_snapshot",
        tenant_id=str(tid),
        queue=report.queue,
        overdue=report.overdue,
        oldest_hours=report.oldest_hours,
    )


async def _stale_queued(
    session: AsyncSession,
    report: DiagnosisWatchReport,
    now: datetime,
    services: DiagnosisServices | None,
) -> None:
    if services is None:
        return
    from farmerapp.diagnosis.service import deliver_diagnosis

    stale = (
        (
            await session.execute(
                select(Diagnosis)
                .where(
                    Diagnosis.tenant_id == report.tenant_id,
                    Diagnosis.status == DiagnosisStatus.QUEUED.value,
                    Diagnosis.deleted_at.is_(None),
                    Diagnosis.created_at <= now - STALE_QUEUED,
                )
                .order_by(Diagnosis.created_at)
                .limit(100)
            )
        )
        .scalars()
        .all()
    )
    for row in stale:
        await deliver_diagnosis(session, services, row, now=now)
        report.redelivered.append(row.id)
    if stale:
        log.warning("diagnosis_redelivered", tenant_id=str(report.tenant_id), count=len(stale))


async def _llm_rate(session: AsyncSession, report: DiagnosisWatchReport, now: datetime) -> None:
    tid = report.tenant_id
    start, end = day_bounds(report.day)
    answered, fallbacks = (
        await session.execute(
            select(
                func.count(),
                func.count().filter(Diagnosis.llm_used.is_(True)),
            ).where(
                Diagnosis.tenant_id == tid,
                Diagnosis.deleted_at.is_(None),
                Diagnosis.answered_at >= start,
                Diagnosis.answered_at < end,
            )
        )
    ).one()
    report.answered, report.llm_fallbacks = int(answered or 0), int(fallbacks or 0)
    report.llm_rate = round(report.llm_fallbacks / report.answered, 4) if report.answered else None
    log.info(
        "diagnosis_llm_fallback_rate",
        tenant_id=str(tid),
        day=report.day.isoformat(),
        answered=report.answered,
        llm_fallbacks=report.llm_fallbacks,
        rate=report.llm_rate,
    )
    if report.llm_rate is None or report.answered < MIN_SAMPLE:
        return
    if report.llm_rate <= LLM_RATE_ALERT:
        return
    report.llm_alert = True
    log.warning(
        "diagnosis_llm_fallback_alert",
        tenant_id=str(tid),
        day=report.day.isoformat(),
        rate=report.llm_rate,
        threshold=LLM_RATE_ALERT,
        answered=report.answered,
    )
    already = await session.scalar(
        select(Notification.id)
        .where(
            Notification.tenant_id == tid,
            Notification.kind == NotificationKind.DIAGNOSIS_LLM_RATE.value,
            Notification.data["day"].astext == report.day.isoformat(),
        )
        .limit(1)
    )
    if already is not None:
        return
    recipients = await _users(session, tid, [UserRole.AGRONOMIST, UserRole.OWNER])
    for user_id in recipients:
        session.add(
            _notification(
                tid,
                user_id,
                NotificationKind.DIAGNOSIS_LLM_RATE,
                {
                    "day": report.day.isoformat(),
                    "rate": report.llm_rate,
                    "answered": report.answered,
                    "threshold": LLM_RATE_ALERT,
                },
            )
        )


async def diagnosis_watch(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime | None = None,
    day: date | None = None,
    services: DiagnosisServices | None = None,
) -> DiagnosisWatchReport:
    now = now or datetime.now(UTC)
    report = DiagnosisWatchReport(tenant_id=tenant_id, day=day or now.astimezone(IST).date())
    await _queue_age(session, report, now)
    await _stale_queued(session, report, now, services)
    await _llm_rate(session, report, now)
    await session.flush()
    return report


async def run_diagnosis_watch(
    tenant_ids: Sequence[uuid.UUID],
    *,
    now: datetime | None = None,
    day: date | None = None,
    services: DiagnosisServices | None = None,
) -> list[DiagnosisWatchReport]:
    reports: list[DiagnosisWatchReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await diagnosis_watch(
                        session, tenant_id=tenant_id, now=now, day=day, services=services
                    )
                )
    return reports


__all__ = [
    "LLM_RATE_ALERT",
    "MIN_SAMPLE",
    "QUEUE_ALERT_HOURS",
    "STALE_QUEUED",
    "DiagnosisWatchReport",
    "diagnosis_watch",
    "run_diagnosis_watch",
]
