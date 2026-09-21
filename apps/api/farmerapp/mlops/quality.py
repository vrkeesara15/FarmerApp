"""AN-007 diagnosis quality summary (``GET /v1/diagnoses/quality``).

Over the diagnoses requested in the last ``days`` (IST days, default 30) of the tenant:

* ``corpus_share`` — answered by the corpus (``source = corpus``) / requests;
* ``escalation_rate`` — sent to an agronomist / requests, where *sent* means the result was
  provisional or out of scope, the case was flagged or an expert was asked (FM-006), or an
  agronomist reviewed it;
* review SLA — escalations reviewed, within 24 h of entering the queue (the expert request,
  else the request), average and median review hours, the open queue and how much of it is
  past 24 h;
* ``evaluation_alert_drop_points`` -- the DX-011 alert threshold the console shows next to
  the latest run's delta;
* ``by_source`` / ``by_status`` counts, ``top_unknowns`` (out-of-scope cases by crop and
  reason, DX-010) and the latest DX-011 evaluation run with its delta.

Replaces the console's client-side computation over the review queue (C62).
"""

from __future__ import annotations

import statistics
import uuid
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.crops import Crop
from farmerapp.diagnosis.models import REVIEWABLE, Diagnosis, DiagnosisSource, DiagnosisStatus
from farmerapp.mlops.models import EvaluationRun, EvaluationStatus
from farmerapp.mlops.schemas import (
    EvaluationSummaryOut,
    QualityOut,
    ReviewSlaOut,
    UnknownOut,
)
from farmerapp.payments.config import IST
from farmerapp.tenants.settings import get_tenant_settings

REVIEW_SLA_HOURS = 24
_ESCALATED = {
    DiagnosisStatus.PROVISIONAL.value,
    DiagnosisStatus.OUT_OF_SCOPE.value,
    DiagnosisStatus.CONFIRMED.value,
    DiagnosisStatus.CORRECTED.value,
}


def _ratio(a: int, b: int) -> float | None:
    return round(a / b, 4) if b else None


async def latest_evaluation(session: AsyncSession, tenant_id: uuid.UUID) -> EvaluationRun | None:
    row: EvaluationRun | None = await session.scalar(
        select(EvaluationRun)
        .where(EvaluationRun.tenant_id == tenant_id, EvaluationRun.deleted_at.is_(None))
        .order_by(EvaluationRun.started_at.desc(), EvaluationRun.id.desc())
        .limit(1)
    )
    return row


async def quality_summary(
    session: AsyncSession, tenant_id: uuid.UUID, *, now: datetime, days: int = 30
) -> QualityOut:
    today = now.astimezone(IST).date()
    since_day = today - timedelta(days=days - 1)
    since = datetime.combine(since_day, datetime.min.time(), tzinfo=IST)
    rows = (
        await session.execute(
            select(
                Diagnosis.status,
                Diagnosis.source,
                Diagnosis.flagged,
                Diagnosis.created_at,
                Diagnosis.expert_requested_at,
                Diagnosis.reviewed_at,
                Diagnosis.crop_id,
                Diagnosis.out_of_scope_reason,
            ).where(
                Diagnosis.tenant_id == tenant_id,
                Diagnosis.deleted_at.is_(None),
                Diagnosis.created_at >= since,
            )
        )
    ).all()
    by_source: dict[str, int] = {}
    by_status: dict[str, int] = {}
    unknowns: dict[tuple[uuid.UUID | None, str], int] = {}
    escalated = reviewed = within = open_queue = overdue = 0
    review_hours: list[float] = []
    for r in rows:
        by_source[r.source or "none"] = by_source.get(r.source or "none", 0) + 1
        by_status[r.status] = by_status.get(r.status, 0) + 1
        is_escalated = (
            r.status in _ESCALATED
            or r.flagged
            or r.expert_requested_at is not None
            or r.reviewed_at is not None
        )
        if r.status == DiagnosisStatus.OUT_OF_SCOPE.value:
            key = (r.crop_id, r.out_of_scope_reason or "unspecified")
            unknowns[key] = unknowns.get(key, 0) + 1
        if not is_escalated:
            continue
        escalated += 1
        entered = r.expert_requested_at or r.created_at
        if r.reviewed_at is not None:
            reviewed += 1
            hours = max((r.reviewed_at - entered).total_seconds() / 3600, 0.0)
            review_hours.append(hours)
            within += hours <= REVIEW_SLA_HOURS
        elif r.status in {s.value for s in REVIEWABLE} or r.flagged:
            open_queue += 1
            overdue += (now - entered) > timedelta(hours=REVIEW_SLA_HOURS)
    requests = len(rows)
    crops = {
        c.id: c.code for c in await session.scalars(select(Crop).where(Crop.tenant_id == tenant_id))
    }
    top = sorted(unknowns.items(), key=lambda kv: (-kv[1], str(kv[0][0]), kv[0][1]))[:10]
    evaluation = await latest_evaluation(session, tenant_id)
    alert_points = (await get_tenant_settings(session, tenant_id)).diagnosis_evaluation

    corpus = by_source.get(DiagnosisSource.CORPUS.value, 0)
    return QualityOut(
        days=days,
        from_date=since_day,
        to_date=today,
        requests=requests,
        answered_by_corpus=corpus,
        corpus_share=_ratio(corpus, requests),
        escalated=escalated,
        escalation_rate=_ratio(escalated, requests),
        llm_share=_ratio(by_source.get(DiagnosisSource.LLM.value, 0), requests),
        by_source=dict(sorted(by_source.items())),
        by_status=dict(sorted(by_status.items())),
        review=ReviewSlaOut(
            sla_hours=REVIEW_SLA_HOURS,
            reviewed=reviewed,
            reviewed_within_sla=within,
            sla_rate=_ratio(within, escalated),
            avg_review_hours=round(statistics.fmean(review_hours), 2) if review_hours else None,
            median_review_hours=round(statistics.median(review_hours), 2) if review_hours else None,
            open_queue=open_queue,
            open_overdue=overdue,
        ),
        top_unknowns=[
            UnknownOut(
                crop_id=crop_id,
                crop_code=crops.get(crop_id) if crop_id else None,
                reason=reason,
                cases=cases,
            )
            for (crop_id, reason), cases in top
        ],
        latest_evaluation=EvaluationSummaryOut.from_row(evaluation) if evaluation else None,
        evaluation_alert_drop_points=alert_points.alert_drop_points,
    )


async def evaluation_runs(
    session: AsyncSession, tenant_id: uuid.UUID, *, limit: int = 30
) -> list[EvaluationRun]:
    return list(
        await session.scalars(
            select(EvaluationRun)
            .where(EvaluationRun.tenant_id == tenant_id, EvaluationRun.deleted_at.is_(None))
            .order_by(EvaluationRun.started_at.desc(), EvaluationRun.id.desc())
            .limit(limit)
        )
    )


async def ok_runs(session: AsyncSession, tenant_id: uuid.UUID) -> int:
    return int(
        await session.scalar(
            select(func.count())
            .select_from(EvaluationRun)
            .where(
                EvaluationRun.tenant_id == tenant_id,
                EvaluationRun.status == EvaluationStatus.OK.value,
            )
        )
        or 0
    )


__all__ = ["REVIEW_SLA_HOURS", "evaluation_runs", "latest_evaluation", "ok_runs", "quality_summary"]
