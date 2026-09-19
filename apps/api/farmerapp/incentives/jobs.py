"""WC-009 ``close-incentives`` job: on the 1st of each month (06:00 IST) freeze the previous
month's payouts with the active rule set (idempotent)."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, date, datetime, timedelta

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.incentives.service import CloseReport, close_month, month_start
from farmerapp.payments.config import IST


def previous_month(now: datetime) -> date:
    first = now.astimezone(IST).date().replace(day=1)
    return month_start(first - timedelta(days=1))


async def run_close_incentives(
    tenant_ids: Sequence[uuid.UUID], *, month: date | None = None, now: datetime | None = None
) -> list[CloseReport]:
    now = now or datetime.now(UTC)
    target = month_start(month) if month else previous_month(now)
    reports: list[CloseReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await close_month(session, tenant_id=tenant_id, month=target, now=now)
                )
    return reports


__all__ = ["previous_month", "run_close_incentives"]
