"""``purge-expired``: drop expired upload sessions (with their staged chunks) and expired
``Idempotency-Key`` rows (NF-003). Runs as the app role per tenant; both tables allow
DELETE. Scheduled every 15 minutes by Cloud Scheduler (OPS) — locally on demand."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.idempotency import IdempotencyKey
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.uploads.models import UploadChunk, UploadSession, UploadStatus

log = get_logger("farmerapp.jobs.purge_expired")


@dataclass(frozen=True)
class PurgeExpiredReport:
    tenant_id: uuid.UUID
    upload_sessions: int
    upload_chunks: int
    idempotency_keys: int


async def purge_expired(
    session: AsyncSession, *, tenant_id: uuid.UUID, now: datetime | None = None
) -> PurgeExpiredReport:
    now = now or datetime.now(UTC)
    expired = select(UploadSession.id).where(
        UploadSession.tenant_id == tenant_id,
        UploadSession.status == UploadStatus.PENDING,
        UploadSession.expires_at <= now,
    )
    chunks = await session.scalar(
        select(func.count()).select_from(UploadChunk).where(UploadChunk.upload_id.in_(expired))
    )
    await session.execute(delete(UploadChunk).where(UploadChunk.upload_id.in_(expired)))
    sessions = await session.execute(
        delete(UploadSession).where(UploadSession.id.in_(expired)).returning(UploadSession.id)
    )
    keys = await session.execute(
        delete(IdempotencyKey)
        .where(IdempotencyKey.tenant_id == tenant_id, IdempotencyKey.expires_at <= now)
        .returning(IdempotencyKey.id)
    )
    report = PurgeExpiredReport(
        tenant_id=tenant_id,
        upload_sessions=len(sessions.all()),
        upload_chunks=int(chunks or 0),
        idempotency_keys=len(keys.all()),
    )
    log.info(
        "purge_expired",
        tenant_id=str(tenant_id),
        upload_sessions=report.upload_sessions,
        upload_chunks=report.upload_chunks,
        idempotency_keys=report.idempotency_keys,
    )
    return report


async def run_purge_expired(tenant_ids: list[uuid.UUID]) -> list[PurgeExpiredReport]:
    reports: list[PurgeExpiredReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(await purge_expired(session, tenant_id=tenant_id))
    return reports


__all__ = ["PurgeExpiredReport", "purge_expired", "run_purge_expired"]
