"""Jobs of the validation agents: the nightly batch runner and the OPS-010 SLA escalation.

* ``run_rules_job`` — ``python -m farmerapp.jobs run-rules --mode batch --tenant fcc``: every
  enabled batch rule per tenant, one transaction per tenant, as the system actor. Scheduled
  nightly at 02:00 IST (Cloud Scheduler -> Cloud Run Job, infra). Re-running is safe: the
  dedupe key never duplicates an unresolved flag.
* ``run_sla_escalation`` — ``python -m farmerapp.jobs flags-sla-escalation --tenant fcc``:
  unresolved flags past their SLA move one rung up (``flags.service.escalate_overdue``).
  Hourly.

Tenants are given by id, or by the slug of a demo tenant (``fcc`` / ``gfl``): the job runs
as the app role under RLS and cannot look a tenant up by slug before one is bound.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.flags.service import Escalation, escalate_overdue
from farmerapp.rules.engine import RunReport, run_rules
from farmerapp.rules.loader import RuleSet, get_rule_set
from farmerapp.rules.schema import Mode

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]


class UnknownTenantError(ValueError):
    pass


def resolve_tenant(value: str) -> uuid.UUID:
    """A tenant id, or the slug of a demo tenant."""
    try:
        return uuid.UUID(value)
    except ValueError:
        from farmerapp.jobs.seed import DEMO_TENANTS

        for demo in DEMO_TENANTS:
            if demo.slug == value:
                return demo.id
    raise UnknownTenantError(f"unknown tenant {value!r}: pass the tenant id")


async def run_rules_job(
    tenant_ids: Iterable[uuid.UUID],
    *,
    mode: Mode = Mode.BATCH,
    rule_ids: Iterable[str] | None = None,
    now: datetime | None = None,
    session_provider: SessionProvider = job_session,
    rule_set: RuleSet | None = None,
) -> list[RunReport]:
    now = now or datetime.now(UTC)
    wanted = list(rule_ids) if rule_ids is not None else None
    reports: list[RunReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with session_provider(tenant_id) as session:
                reports.append(
                    await run_rules(
                        session, tenant_id, mode, rule_ids=wanted, now=now, rule_set=rule_set
                    )
                )
    return reports


@dataclass(frozen=True)
class SlaReport:
    tenant_id: uuid.UUID
    escalations: list[Escalation]


async def run_sla_escalation(
    tenant_ids: Iterable[uuid.UUID],
    *,
    now: datetime | None = None,
    session_provider: SessionProvider = job_session,
    rule_set: RuleSet | None = None,
) -> list[SlaReport]:
    now = now or datetime.now(UTC)
    rules = rule_set or get_rule_set()
    sla_hours = {r.id: r.sla_hours for r in rules}
    reports: list[SlaReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with session_provider(tenant_id) as session:
                moved = await escalate_overdue(session, tenant_id, now=now, sla_hours=sla_hours)
        reports.append(SlaReport(tenant_id=tenant_id, escalations=moved))
    return reports


__all__ = [
    "SlaReport",
    "UnknownTenantError",
    "resolve_tenant",
    "run_rules_job",
    "run_sla_escalation",
]
