"""WC-014 batch jobs: recount usage, generate statements, list tenants for other jobs.

Both jobs iterate tenants **one at a time**, each in its own transaction and its own tenant
binding, and never hold more than one tenant's working set (NF-007: at the scale target there
are 50 tenants, one of which has 2 million farmers between them — a job that loads "all
tenants" into memory is the shape that stops working, so no job here does).

``all_tenant_ids`` is the one place that answers "which tenants exist?" for a scheduled job.
It reads the platform registry under the platform tenant's own binding — no RLS bypass, no
cross-tenant SELECT — and yields ids lazily.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import select

from farmerapp.db import audit
from farmerapp.db.session import job_session, tenant_scope
from farmerapp.logging import get_logger
from farmerapp.platform_admin.billing import generate_statement
from farmerapp.platform_admin.models import (
    PLATFORM_TENANT_ID,
    PlatformTenant,
    TenantStatus,
)
from farmerapp.platform_admin.usage import month_key, recount

log = get_logger("farmerapp.platform_admin.jobs")

#: How many registry rows one page of ``all_tenant_ids`` reads.
PAGE = 200


async def all_tenant_ids(
    *, statuses: Sequence[str] = (TenantStatus.ACTIVE, TenantStatus.SUSPENDED)
) -> AsyncIterator[tuple[uuid.UUID, str]]:
    """``(tenant_id, slug)`` of every registered tenant, a page at a time."""
    after = ""
    while True:
        async with job_session(PLATFORM_TENANT_ID) as session:
            rows = (
                (
                    await session.execute(
                        select(PlatformTenant.subject_tenant_id, PlatformTenant.slug)
                        .where(
                            PlatformTenant.tenant_id == PLATFORM_TENANT_ID,
                            PlatformTenant.deleted_at.is_(None),
                            PlatformTenant.status.in_(list(statuses)),
                            PlatformTenant.slug > after,
                        )
                        .order_by(PlatformTenant.slug)
                        .limit(PAGE)
                    )
                )
                .tuples()
                .all()
            )
        if not rows:
            return
        for tenant_id, slug in rows:
            yield tenant_id, slug
        after = rows[-1][1]


@dataclass(frozen=True)
class RecountReport:
    tenant_id: uuid.UUID
    counts: dict[str, int]


async def run_recount(
    tenant_ids: Sequence[uuid.UUID], *, now: datetime | None = None
) -> list[RecountReport]:
    """Recompute every usage counter from the source tables, one tenant per transaction."""
    reports: list[RecountReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                counts = await recount(session, tenant_id, when=now)
        log.info("usage_recounted", tenant_id=str(tenant_id), counts=counts)
        reports.append(RecountReport(tenant_id=tenant_id, counts=counts))
    return reports


@dataclass(frozen=True)
class StatementReport:
    tenant_id: uuid.UUID
    period: str
    total_paise: int
    overage_paise: int


async def run_statements(
    tenant_ids: Sequence[uuid.UUID], *, period: str | None = None, now: datetime | None = None
) -> list[StatementReport]:
    """Generate the monthly statement for each tenant (one transaction each)."""
    moment = now or datetime.now(UTC)
    key = period or month_key(moment)
    reports: list[StatementReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session, tenant_scope(session, tenant_id):
                statement = await generate_statement(session, tenant_id, period=key, now=moment)
                reports.append(
                    StatementReport(
                        tenant_id=tenant_id,
                        period=statement.period,
                        total_paise=statement.total_paise,
                        overage_paise=statement.overage_paise,
                    )
                )
    return reports


__all__ = [
    "PAGE",
    "RecountReport",
    "StatementReport",
    "all_tenant_ids",
    "run_recount",
    "run_statements",
]
