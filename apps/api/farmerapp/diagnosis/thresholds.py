"""DX-003 thresholds: stored in ``diagnosis_threshold``, versioned per crop, audited.

``thresholds_for(session, tenant, crop)``: the newest row of the crop, else the newest
tenant default (``crop_id`` NULL), else the built-in defaults (``config_version`` 0).
``set_thresholds`` appends the next version (rows are never edited: the audit trail and the
``config_version`` stored on each diagnosis keep every past decision reproducible).
"""

from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.diagnosis.decision import Thresholds
from farmerapp.diagnosis.models import DiagnosisThreshold


def _to_thresholds(row: DiagnosisThreshold) -> Thresholds:
    return Thresholds(
        t1=row.t1,
        agreement=row.agreement,
        min_similarity=row.min_similarity,
        config_version=row.config_version,
        crop_id=row.crop_id,
    )


async def _latest(
    session: AsyncSession, tenant_id: uuid.UUID, crop_id: uuid.UUID | None
) -> DiagnosisThreshold | None:
    crop_filter = (
        DiagnosisThreshold.crop_id.is_(None)
        if crop_id is None
        else DiagnosisThreshold.crop_id == crop_id
    )
    stmt = (
        select(DiagnosisThreshold)
        .where(
            DiagnosisThreshold.tenant_id == tenant_id,
            DiagnosisThreshold.deleted_at.is_(None),
            crop_filter,
        )
        .order_by(DiagnosisThreshold.config_version.desc())
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def thresholds_for(
    session: AsyncSession, tenant_id: uuid.UUID, crop_id: uuid.UUID | None
) -> Thresholds:
    if crop_id is not None:
        row = await _latest(session, tenant_id, crop_id)
        if row is not None:
            return _to_thresholds(row)
    default = await _latest(session, tenant_id, None)
    return _to_thresholds(default) if default is not None else Thresholds()


async def set_thresholds(
    session: AsyncSession,
    actor: User,
    *,
    crop_id: uuid.UUID | None,
    t1: float,
    agreement: float,
    min_similarity: float,
    note: str | None,
) -> DiagnosisThreshold:
    crop_filter = (
        DiagnosisThreshold.crop_id.is_(None)
        if crop_id is None
        else DiagnosisThreshold.crop_id == crop_id
    )
    current = await session.scalar(
        select(func.max(DiagnosisThreshold.config_version)).where(
            DiagnosisThreshold.tenant_id == actor.tenant_id, crop_filter
        )
    )
    row = DiagnosisThreshold(
        tenant_id=actor.tenant_id,
        crop_id=crop_id,
        t1=t1,
        agreement=agreement,
        min_similarity=min_similarity,
        config_version=int(current or 0) + 1,
        set_by=actor.id,
        note=note,
    )
    session.add(row)
    await session.flush()
    await session.refresh(row)
    return row


async def threshold_history(
    session: AsyncSession, tenant_id: uuid.UUID
) -> list[DiagnosisThreshold]:
    rows = await session.execute(
        select(DiagnosisThreshold)
        .where(DiagnosisThreshold.tenant_id == tenant_id, DiagnosisThreshold.deleted_at.is_(None))
        .order_by(DiagnosisThreshold.crop_id.nulls_first(), DiagnosisThreshold.config_version)
    )
    return list(rows.scalars())


__all__ = ["set_thresholds", "threshold_history", "thresholds_for"]
