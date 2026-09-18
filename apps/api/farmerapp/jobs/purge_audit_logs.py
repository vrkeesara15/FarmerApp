"""``purge-audit-logs``: NF-012 retention for the FA-006 trail — **dry run only** for now.

Audit logs are kept one year minimum (SPEC 7, NF-012). This job reports, per tenant, how
many rows are older than the retention window (default 400 days: a year plus a margin for
the archival step) and deletes nothing: the app role cannot delete audit rows at all
(migration 0004). The real purge runs as the migrate role after the rows are archived to the
exports bucket; that lands with OPS / NF-012 and will reuse ``PurgeReport``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.models import AuditLog
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger

DEFAULT_RETENTION_DAYS = 400
MINIMUM_RETENTION_DAYS = 365  # NF-012: audit logs 1 year minimum

log = get_logger("farmerapp.jobs.purge_audit_logs")


@dataclass(frozen=True)
class PurgeReport:
    tenant_id: uuid.UUID
    older_than_days: int
    cutoff: datetime
    rows: int
    dry_run: bool = True


async def purge_audit_logs(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    older_than_days: int = DEFAULT_RETENTION_DAYS,
    now: datetime | None = None,
) -> PurgeReport:
    """Count the tenant's audit rows past retention. Never deletes (see module docstring)."""
    if older_than_days < MINIMUM_RETENTION_DAYS:
        raise ValueError(
            f"older_than_days={older_than_days} is below the NF-012 minimum of "
            f"{MINIMUM_RETENTION_DAYS} days"
        )
    cutoff = (now or datetime.now(UTC)) - timedelta(days=older_than_days)
    rows = await session.scalar(
        select(func.count())
        .select_from(AuditLog)
        .where(AuditLog.tenant_id == tenant_id, AuditLog.created_at < cutoff)
    )
    report = PurgeReport(
        tenant_id=tenant_id, older_than_days=older_than_days, cutoff=cutoff, rows=rows or 0
    )
    log.info(
        "audit_purge_dry_run",
        tenant_id=str(tenant_id),
        older_than_days=older_than_days,
        cutoff=cutoff.isoformat(),
        rows=report.rows,
    )
    return report


async def run_purge(
    tenant_ids: list[uuid.UUID], older_than_days: int = DEFAULT_RETENTION_DAYS
) -> list[PurgeReport]:
    reports: list[PurgeReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await purge_audit_logs(
                        session, tenant_id=tenant_id, older_than_days=older_than_days
                    )
                )
    return reports


__all__ = [
    "DEFAULT_RETENTION_DAYS",
    "MINIMUM_RETENTION_DAYS",
    "PurgeReport",
    "purge_audit_logs",
    "run_purge",
]
