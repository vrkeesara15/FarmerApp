"""NF-012 retention sweep: one command that reports — and, with ``--apply``, enforces —
every class in ``farmerapp.retention.policy``.

``python -m farmerapp.jobs retention-sweep --tenant-id <id>`` answers, per class and per
table, how many rows are past their window. **Dry run by default**: nothing is deleted
unless ``--apply`` is passed, and even then only classes whose action is ``PURGE`` and whose
rows the runtime role may delete are touched. ``RETAIN`` classes (financial records, 8 years)
are never deleted by any flag — the window is a floor, and the report exists so the operator
can see that the floor is respected. ``ARCHIVE`` (photos) happens in the bucket's lifecycle
rule, so the sweep reports the count and names the owner.

The counts are per tenant, under RLS, so a sweep can be scheduled per tenant and a mistake
cannot reach across tenants. Row counts are the report; the job logs one
``retention_class`` line per class with the numbers Cloud Monitoring turns into the
"retention purge ran" signal (OPS-005).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session, set_tenant
from farmerapp.logging import get_logger
from farmerapp.platform_admin.plans import effective_retention_days
from farmerapp.platform_admin.state import get_tenant_state
from farmerapp.retention.policy import POLICY, RetentionAction, RetentionClass, policy_for

log = get_logger("farmerapp.retention")

__all__ = ["ClassReport", "SweepReport", "TableReport", "run_sweep", "sweep"]


@dataclass(frozen=True)
class TableReport:
    table: str
    due: int
    deleted: int = 0


@dataclass(frozen=True)
class ClassReport:
    name: str
    action: RetentionAction
    days: int
    cutoff: datetime
    tables: tuple[TableReport, ...]
    applied: bool
    owner: str
    #: Why nothing was deleted although rows are due (empty when the sweep did the work).
    deferred_to: str = ""

    @property
    def due(self) -> int:
        return sum(t.due for t in self.tables)

    @property
    def deleted(self) -> int:
        return sum(t.deleted for t in self.tables)


@dataclass
class SweepReport:
    tenant_id: uuid.UUID
    now: datetime
    applied: bool
    classes: list[ClassReport] = field(default_factory=list)

    @property
    def due(self) -> int:
        return sum(c.due for c in self.classes)

    @property
    def deleted(self) -> int:
        return sum(c.deleted for c in self.classes)


def _quote(identifier: str) -> str:
    """Identifiers come from ``policy.py`` constants, never from input; quote anyway."""
    return '"' + identifier.replace('"', '""') + '"'


#: B608 on the two statements below: ``table`` and ``column`` are identifiers from the
#: :mod:`farmerapp.retention.policy` constants — a closed set, never a request value — and both
#: go through :func:`_quote`. The cutoff is a bound parameter. Same judgement, and the same
#: markers, as ``farmerapp/mlops/reembed.py``.
async def _count(session: AsyncSession, table: str, column: str, cutoff: datetime) -> int:
    stmt = text(f"SELECT count(*) FROM {_quote(table)} WHERE {_quote(column)} < :cutoff")  # nosec B608
    return int((await session.scalar(stmt, {"cutoff": cutoff})) or 0)


async def _delete(session: AsyncSession, table: str, column: str, cutoff: datetime) -> int:
    result = await session.execute(
        text(f"DELETE FROM {_quote(table)} WHERE {_quote(column)} < :cutoff"),  # nosec B608
        {"cutoff": cutoff},
    )
    return int(getattr(result, "rowcount", 0) or 0)


def _deferred_to(entry: RetentionClass) -> str:
    """Why this class is reported rather than swept, in the operator's words."""
    if entry.action is RetentionAction.RETAIN:
        return f"retained: {entry.days} days is a floor, not a deadline ({entry.spec})"
    if entry.action is RetentionAction.ARCHIVE:
        return f"archived by {entry.owner}"
    if entry.migrate_role:
        return f"needs the migrate role: run {entry.owner}"
    if entry.owner != "farmerapp.retention.sweep":
        return f"purged by {entry.owner}"
    return ""


async def sweep_class(
    session: AsyncSession,
    entry: RetentionClass,
    *,
    tenant_id: uuid.UUID,
    now: datetime,
    apply: bool,
    days: int | None = None,
) -> ClassReport:
    # WC-014: a plan may *lengthen* a retention window (``plans.effective_retention_days``);
    # it can never shorten one, so a cheaper plan cannot buy a shorter DPDP promise.
    window = entry.days if days is None else days
    cutoff = now - timedelta(days=window)
    deferred = _deferred_to(entry)
    may_delete = apply and not deferred
    tables: list[TableReport] = []
    for table in entry.tables:
        due = await _count(session, table, entry.date_column, cutoff)
        deleted = 0
        if may_delete and due:
            deleted = await _delete(session, table, entry.date_column, cutoff)
        tables.append(TableReport(table=table, due=due, deleted=deleted))
    report = ClassReport(
        name=entry.name,
        action=entry.action,
        days=window,
        cutoff=cutoff,
        tables=tuple(tables),
        applied=may_delete,
        owner=entry.owner,
        deferred_to=deferred,
    )
    log.info(
        "retention_class",
        tenant_id=str(tenant_id),
        retention_class=entry.name,
        action=str(entry.action),
        days=window,
        cutoff=cutoff.isoformat(),
        rows_due=report.due,
        rows_deleted=report.deleted,
        dry_run=not may_delete,
        deferred_to=deferred,
    )
    return report


async def sweep(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime | None = None,
    apply: bool = False,
    classes: tuple[str, ...] = (),
) -> SweepReport:
    """Report (and optionally purge) every retention class for one tenant.

    ``apply=False`` is the default everywhere, including the scheduled job: turning a
    retention sweep into a delete is a deliberate act (``--apply``, and in prd a Terraform
    variable, exactly as ``purge-location-points`` already works).
    """
    # Bind the tenant before counting anything: the sweep must never see another tenant's
    # rows, whatever the caller left on the session (RLS, SEC-012).
    await set_tenant(session, tenant_id)
    moment = now or datetime.now(UTC)
    wanted = [policy_for(name) for name in classes] if classes else list(POLICY)
    report = SweepReport(tenant_id=tenant_id, now=moment, applied=apply)
    state = await get_tenant_state(session, tenant_id)  # WC-014 plan retention overrides
    for entry in wanted:
        report.classes.append(
            await sweep_class(
                session,
                entry,
                tenant_id=tenant_id,
                now=moment,
                apply=apply,
                days=effective_retention_days(entry, state.limits),
            )
        )
    log.info(
        "retention_sweep",
        tenant_id=str(tenant_id),
        rows_due=report.due,
        rows_deleted=report.deleted,
        dry_run=not apply,
        classes=len(report.classes),
    )
    return report


async def run_sweep(
    tenant_ids: list[uuid.UUID],
    *,
    apply: bool = False,
    classes: tuple[str, ...] = (),
    now: datetime | None = None,
) -> list[SweepReport]:
    reports: list[SweepReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await sweep(session, tenant_id=tenant_id, now=now, apply=apply, classes=classes)
                )
    return reports
