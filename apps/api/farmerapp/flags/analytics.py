"""The analytics ``FlagCountsPort`` adapter over the ``flag`` table (AN-001, AN-002, WC-001).

The owner home ("open validation flags" KPI, its trend and last-year value, the open
high-severity list) and the field team scorecard ("flags" column) read open flags through
``farmerapp.analytics.ports``; ``create_app`` registers this adapter on
``app.state.flag_counts``.

* **Open as of T**: raised before T and not resolved by T (``resolved_at`` is set exactly
  when a flag is resolved), so trend buckets and the same period last year are historical.
  Without T: the unresolved statuses (open, in review, escalated).
* **Role scope**: ``FlagQuery.viewer`` applies ``flags.service.flag_filters`` — the WC-010
  inbox rule — so a store manager counts only their store's farmer-data flags (and what
  they own), a cluster head their cluster's, a field officer flags about themselves.
* **Analytics narrowing** on top: flags of the stores in ``store_ids`` (``scope_store_id``)
  or about the officers in ``officer_ids``; with ``officer_only`` just the latter.
* **The officer of a flag**: the subject of an employee flag, the officer of a visit flag;
  farmer and store flags belong to no officer (they are not in the scorecard column).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import datetime

from sqlalchemy import ColumnElement, and_, case, false, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.ports import FlagCounts, FlagQuery, FlagSummary
from farmerapp.flags.models import UNRESOLVED, Flag
from farmerapp.flags.service import flag_filters
from farmerapp.rules.schema import Severity, Subject
from farmerapp.visits.models import Visit


def _officer() -> ColumnElement[uuid.UUID | None]:
    visit_officer = (
        select(Visit.officer_id)
        .where(Visit.id == Flag.subject_id, Visit.tenant_id == Flag.tenant_id)
        .scalar_subquery()
    )
    return case(
        (Flag.subject_type == Subject.EMPLOYEE.value, Flag.subject_id),
        (Flag.subject_type == Subject.VISIT.value, visit_officer),
        else_=None,
    )


def _open_at(at: datetime | None) -> ColumnElement[bool]:
    if at is None:
        return Flag.status.in_([s.value for s in UNRESOLVED])
    return and_(Flag.created_at < at, or_(Flag.resolved_at.is_(None), Flag.resolved_at >= at))


def _where(
    query: FlagQuery, officer: ColumnElement[uuid.UUID | None], *, open_filter: bool = True
) -> list[ColumnElement[bool]]:
    where: list[ColumnElement[bool]] = [
        Flag.tenant_id == query.tenant_id,
        Flag.deleted_at.is_(None),
    ]
    if open_filter:
        where.append(_open_at(query.opened_before))
    if query.viewer is not None:
        if query.viewer.tenant_id != query.tenant_id:
            return [*where, false()]
        where += flag_filters(query.viewer)
    officers = list(query.officer_ids) if query.officer_ids is not None else None
    if query.officer_only:
        where.append(officer.in_(officers) if officers is not None else false())
        return where
    narrowing: list[ColumnElement[bool]] = []
    if query.store_ids is not None:
        narrowing.append(Flag.scope_store_id.in_(list(query.store_ids)))
    if officers is not None:
        narrowing.append(officer.in_(officers))
    if narrowing:
        where.append(or_(*narrowing))
    return where


class FlagTableCounts:
    """``FlagCountsPort`` reading the ``flag`` table under the caller's RLS session."""

    async def counts(self, session: AsyncSession, query: FlagQuery) -> FlagCounts:
        officer = _officer().label("officer_id")
        stmt = (
            select(officer, Flag.severity, func.count())
            .where(*_where(query, _officer()))
            .group_by(officer, Flag.severity)
        )
        total = high = 0
        by_officer: dict[uuid.UUID, int] = defaultdict(int)
        for officer_id, severity, n in (await session.execute(stmt)).tuples():
            total += n
            if severity == Severity.HIGH.value:
                high += n
            if officer_id is not None:
                by_officer[officer_id] += n
        return FlagCounts(open_total=total, open_high=high, by_officer=dict(by_officer))

    async def open_totals(
        self, session: AsyncSession, query: FlagQuery, instants: list[datetime]
    ) -> list[int]:
        """Open flags as of each instant, in one query (the owner-home trend; NF-005)."""
        if not instants:
            return []
        where = _where(query, _officer(), open_filter=False)  # "open as of T" per FILTER
        columns = [func.count().filter(_open_at(at)) for at in instants]
        row = (await session.execute(select(*columns).where(*where))).one()
        return [int(n or 0) for n in row]

    async def open_high_severity(
        self, session: AsyncSession, query: FlagQuery, limit: int
    ) -> list[FlagSummary]:
        stmt = (
            select(
                Flag.id,
                Flag.rule_id,
                Flag.severity,
                Flag.title,
                Flag.created_at,
                _officer().label("officer_id"),
                Flag.scope_store_id,
                Flag.subject_type,
                Flag.subject_id,
            )
            .where(*_where(query, _officer()), Flag.severity == Severity.HIGH.value)
            .order_by(Flag.created_at.desc(), Flag.id)
            .limit(limit)
        )
        return [
            FlagSummary(
                id=flag_id,
                rule=rule_id,
                severity=severity,
                title=title,
                opened_at=created_at,
                officer_id=officer_id,
                store_id=store_id,
                farmer_id=subject_id if subject_type == Subject.FARMER.value else None,
            )
            for (
                flag_id,
                rule_id,
                severity,
                title,
                created_at,
                officer_id,
                store_id,
                subject_type,
                subject_id,
            ) in (await session.execute(stmt)).tuples()
        ]


FLAG_TABLE_COUNTS = FlagTableCounts()

__all__ = ["FLAG_TABLE_COUNTS", "FlagTableCounts"]
