"""WC-014 usage counters and plan-limit enforcement.

Two operations, both O(1) against the tenant's size:

``record(session, tenant_id, metric, delta)``
    ``INSERT ... ON CONFLICT (tenant_id, metric, period) DO UPDATE SET count = count + delta``.
    One statement, one index probe. Head counts (officers, farmers, stores) go up on create
    and down on delete; monthly counters (photos, campaigns, LLM calls) only go up, in their
    own ``YYYY-MM`` row.

``check(session, tenant_id, metric, limits)``
    One primary-key read of the counter row, compared with the plan limit. Over it, the caller
    gets ``409 plan_limit_exceeded`` carrying ``metric``, ``limit``, ``current`` and ``plan``.

Why not ``SELECT count(*)``: at the NF-007 target a tenant holds 40,000 farmers and 400,000
photo rows; counting them on every registration is the O(tenant size) mistake this module
exists to avoid. ``recount`` exists for exactly two jobs — backfilling a tenant that predates
this table, and proving in a test that the incremental value equals the real one.

Counters are written with SQLAlchemy Core, not the ORM, so the FA-006 audit listener is not
involved (``UsageCounter.__audit__`` is ``False`` as well): a photo upload must not cost two
writes. The counter row belongs to the tenant, so the increment rides the caller's existing
tenant binding and RLS covers it like any other row.
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime

from sqlalchemy import Table, func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.platform_admin.errors import PlanLimitExceededError
from farmerapp.platform_admin.models import UsageCounter

#: The Core table behind the ORM class: counters are written with Core so the FA-006 audit listener (an ORM
#: ``before_flush`` hook) is not involved — see the module docstring.
_COUNTER: Table = UsageCounter.__table__  # type: ignore[assignment]
from farmerapp.platform_admin.plans import MONTHLY, TOTAL_PERIOD, Metric, PlanLimits
from farmerapp.platform_admin.state import get_tenant_state

#: Metric -> the SQL that recomputes it from the source tables (``recount`` only).
_SOURCE_SQL: Mapping[Metric, str] = {
    Metric.OFFICERS: (
        "SELECT count(*) FROM \"user\" WHERE tenant_id = :tid AND role = 'field_officer' "
        "AND deleted_at IS NULL"
    ),
    Metric.FARMERS: "SELECT count(*) FROM farmer WHERE tenant_id = :tid AND deleted_at IS NULL",
    Metric.STORES: "SELECT count(*) FROM store WHERE tenant_id = :tid AND deleted_at IS NULL",
    Metric.PHOTOS: (
        "SELECT (SELECT count(*) FROM visit_photo WHERE tenant_id = :tid "
        "AND created_at >= :start AND created_at < :end) "
        "+ (SELECT count(*) FROM farm_photo WHERE tenant_id = :tid "
        "AND created_at >= :start AND created_at < :end)"
    ),
    Metric.CAMPAIGNS: (
        "SELECT count(*) FROM campaign WHERE tenant_id = :tid "
        "AND created_at >= :start AND created_at < :end"
    ),
    Metric.LLM_CALLS: (
        "SELECT count(*) FROM llm_call_log WHERE tenant_id = :tid "
        "AND created_at >= :start AND created_at < :end"
    ),
}


def month_key(when: datetime | date | None = None) -> str:
    """``YYYY-MM`` of ``when`` in UTC (timestamps are UTC in the database)."""
    moment = when or datetime.now(UTC)
    return f"{moment.year:04d}-{moment.month:02d}"


def month_bounds(period: str) -> tuple[datetime, datetime]:
    """``[start, end)`` in UTC of a ``YYYY-MM`` period."""
    year, month = (int(part) for part in period.split("-", 1))
    start = datetime(year, month, 1, tzinfo=UTC)
    end = (
        datetime(year + 1, 1, 1, tzinfo=UTC)
        if month == 12
        else datetime(year, month + 1, 1, tzinfo=UTC)
    )
    return start, end


def period_for(metric: Metric, when: datetime | None = None) -> str:
    return month_key(when) if Metric(metric) in MONTHLY else TOTAL_PERIOD


async def record(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    metric: Metric,
    delta: int = 1,
    *,
    when: datetime | None = None,
) -> None:
    """Move a counter by ``delta`` (one statement). Never lets a counter go below zero."""
    if delta == 0:
        return
    period = period_for(metric, when)
    stmt = (
        pg_insert(_COUNTER)
        .values(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            metric=str(metric),
            period=period,
            count=max(delta, 0),
        )
        .on_conflict_do_update(
            constraint="uq_usage_counter_key",
            set_={
                "count": func.greatest(_COUNTER.c.count + delta, 0),
                "updated_at": func.now(),
            },
        )
    )
    await session.execute(stmt)


async def current(
    session: AsyncSession, tenant_id: uuid.UUID, metric: Metric, *, when: datetime | None = None
) -> int:
    value = await session.scalar(
        select(UsageCounter.count).where(
            UsageCounter.tenant_id == tenant_id,
            UsageCounter.metric == str(metric),
            UsageCounter.period == period_for(metric, when),
        )
    )
    return int(value or 0)


async def check(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    metric: Metric,
    limits: PlanLimits,
    *,
    plan: str,
    adding: int = 1,
    when: datetime | None = None,
) -> int:
    """Raise ``plan_limit_exceeded`` when ``adding`` more would pass the plan limit.

    Returns the current usage so the caller can log it. An unlimited metric is one read
    cheaper: it short-circuits before touching the counter table.
    """
    limit = limits.limit_for(metric)
    if limit is None:
        return -1
    used = await current(session, tenant_id, metric, when=when)
    if used + adding > limit:
        raise PlanLimitExceededError(metric=str(metric), limit=limit, current=used, plan=plan)
    return used


async def check_and_record(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    metric: Metric,
    *,
    adding: int = 1,
    when: datetime | None = None,
) -> None:
    """Enforce the tenant's limit for ``metric`` and count the new rows in one call.

    This is what the creation paths call: it resolves the tenant's plan through the cached
    tenant state (no extra query in the common case), checks, then increments.
    """
    state = await get_tenant_state(session, tenant_id)
    await check(session, tenant_id, metric, state.limits, plan=state.plan, adding=adding, when=when)
    await record(session, tenant_id, metric, adding, when=when)


# --------------------------------------------------------------------------- reporting
@dataclass(frozen=True)
class UsageLine:
    metric: str
    period: str
    used: int
    limit: int | None

    @property
    def remaining(self) -> int | None:
        return None if self.limit is None else max(self.limit - self.used, 0)

    @property
    def over(self) -> int:
        return 0 if self.limit is None else max(self.used - self.limit, 0)


async def snapshot(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    limits: PlanLimits,
    *,
    when: datetime | None = None,
) -> list[UsageLine]:
    """Every metric with its counter and limit, in one read of the tenant's counter rows."""
    periods = {metric: period_for(metric, when) for metric in Metric}
    rows = (
        await session.execute(
            select(UsageCounter.metric, UsageCounter.period, UsageCounter.count).where(
                UsageCounter.tenant_id == tenant_id,
                UsageCounter.period.in_(sorted(set(periods.values()))),
            )
        )
    ).all()
    counts: dict[tuple[str, str], int] = {(str(row[0]), str(row[1])): int(row[2]) for row in rows}
    return [
        UsageLine(
            metric=str(metric),
            period=periods[metric],
            used=counts.get((str(metric), periods[metric]), 0),
            limit=limits.limit_for(metric),
        )
        for metric in Metric
    ]


async def recount(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    metrics: Sequence[Metric] = tuple(Metric),
    when: datetime | None = None,
) -> dict[str, int]:
    """Recompute counters from the source tables and store them (backfill / drift check).

    Deliberately *not* on any request path: these are the ``count(*)`` queries the incremental
    counters exist to avoid. The ``usage-recount`` job runs it per tenant, one tenant at a time.
    """
    out: dict[str, int] = {}
    for metric in metrics:
        period = period_for(metric, when)
        params: dict[str, object] = {"tid": str(tenant_id)}
        if period != TOTAL_PERIOD:
            start, end = month_bounds(period)
            params |= {"start": start, "end": end}
        value = int(await session.scalar(text(_SOURCE_SQL[metric]), params) or 0)
        stmt = (
            pg_insert(_COUNTER)
            .values(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                metric=str(metric),
                period=period,
                count=value,
            )
            .on_conflict_do_update(
                constraint="uq_usage_counter_key",
                set_={"count": value, "updated_at": func.now()},
            )
        )
        await session.execute(stmt)
        out[str(metric)] = value
    return out


__all__ = [
    "UsageLine",
    "check",
    "check_and_record",
    "current",
    "month_bounds",
    "month_key",
    "period_for",
    "record",
    "recount",
    "snapshot",
]
