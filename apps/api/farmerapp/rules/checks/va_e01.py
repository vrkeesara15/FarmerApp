"""VA-E01 — mock location, rooted device or clock drift above ``max_clock_drift_s`` while on
duty (FA-028 signals).

Three sources, all only ever recorded on duty (FA-010):

* the duty start (``duty_session.device_integrity``),
* every location point (``location_point.is_mock / is_rooted / clock_drift_s``; the drift is
  the server-computed ``sent_at - received_at`` of the batch),
* the visit check-in (``visit.device_integrity``).

Event mode on ``duty.started`` / ``location.batch`` (``ctx.subject_ids`` = duty sessions)
and ``visit.created`` (= visits). The event only tells *which officer-days* to look at: the
flag gathers every signal of that officer on that IST day, so the first flag of a day
carries all evidence known so far and later events of the same day are deduped (key
``integrity:<day>``) — one flag per officer per day.

Params: ``max_clock_drift_s``, ``max_evidence_points``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import date
from typing import Any

from sqlalchemy import func, or_, select

from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.rules.checks.common import geo_point, ist_day, ist_day_bounds
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.visits.models import Visit

MOCK = "mock_location"
ROOTED = "rooted_device"
DRIFT = "clock_drift"


@dataclass
class _Day:
    records: list[dict[str, str]] = field(default_factory=list)
    points: list[dict[str, Any]] = field(default_factory=list)
    reasons: set[str] = field(default_factory=set)
    max_drift_s: int = 0
    counts: dict[str, int] = field(default_factory=lambda: {"duty": 0, "points": 0, "visits": 0})


def _issues(integrity: dict[str, Any] | None, max_drift: int) -> tuple[set[str], int]:
    integrity = integrity or {}
    drift = int(integrity.get("clock_drift_s") or 0)
    found = set()
    if integrity.get("is_mock"):
        found.add(MOCK)
    if integrity.get("is_rooted"):
        found.add(ROOTED)
    if abs(drift) > max_drift:
        found.add(DRIFT)
    return found, drift


async def _officer_days(
    ctx: RuleContext, ids: tuple[uuid.UUID, ...]
) -> set[tuple[uuid.UUID, date]]:
    """The officer-days the event touched (a duty session's days, a visit's check-in day)."""
    days: set[tuple[uuid.UUID, date]] = set()
    visits = await ctx.session.execute(
        select(Visit.officer_id, Visit.checkin_at).where(
            Visit.tenant_id == ctx.tenant_id, Visit.id.in_(ids)
        )
    )
    days |= {(officer, ist_day(at)) for officer, at in visits.tuples()}
    duties = await ctx.session.execute(
        select(DutySession.officer_id, DutySession.start_at).where(
            DutySession.tenant_id == ctx.tenant_id, DutySession.id.in_(ids)
        )
    )
    days |= {(officer, ist_day(at)) for officer, at in duties.tuples()}
    # A session may run past IST midnight: the days of its points count too.
    point_days = await ctx.session.execute(
        select(LocationPoint.officer_id, func.min(LocationPoint.ts), func.max(LocationPoint.ts))
        .where(LocationPoint.tenant_id == ctx.tenant_id, LocationPoint.duty_session_id.in_(ids))
        .group_by(LocationPoint.officer_id)
    )
    for officer, first, last in point_days.tuples():
        if first is not None and last is not None:
            days |= {(officer, ist_day(first)), (officer, ist_day(last))}
    return days


async def _collect(
    ctx: RuleContext, officer: uuid.UUID, day: date, max_drift: int, max_points: int
) -> _Day:
    start, end = ist_day_bounds(day)
    out = _Day()
    duties = await ctx.session.execute(
        select(
            DutySession.id,
            DutySession.device_integrity,
            DutySession.start_lon,
            DutySession.start_lat,
        )
        .where(
            DutySession.tenant_id == ctx.tenant_id,
            DutySession.officer_id == officer,
            DutySession.start_at >= start,
            DutySession.start_at < end,
        )
        .order_by(DutySession.start_at, DutySession.id)
    )
    for duty_id, integrity, lon, lat in duties.tuples():
        found, drift = _issues(integrity, max_drift)
        if found:
            out.reasons |= found
            out.max_drift_s = max(out.max_drift_s, abs(drift))
            out.records.append(record("duty_session", duty_id))
            out.counts["duty"] += 1
            if lon is not None and lat is not None:
                out.points.append(geo_point(lon, lat))
    points = await ctx.session.execute(
        select(
            LocationPoint.id,
            LocationPoint.is_mock,
            LocationPoint.is_rooted,
            LocationPoint.clock_drift_s,
            LocationPoint.lon,
            LocationPoint.lat,
        )
        .where(
            LocationPoint.tenant_id == ctx.tenant_id,
            LocationPoint.officer_id == officer,
            LocationPoint.ts >= start,
            LocationPoint.ts < end,
            or_(
                LocationPoint.is_mock.is_(True),
                LocationPoint.is_rooted.is_(True),
                func.abs(LocationPoint.clock_drift_s) > max_drift,
            ),
        )
        .order_by(LocationPoint.ts, LocationPoint.id)
    )
    for point_id, is_mock, is_rooted, drift, lon, lat in points.tuples():
        found, _ = _issues(
            {"is_mock": is_mock, "is_rooted": is_rooted, "clock_drift_s": drift}, max_drift
        )
        out.reasons |= found
        out.max_drift_s = max(out.max_drift_s, abs(drift))
        out.counts["points"] += 1
        if out.counts["points"] <= max_points:
            out.records.append(record("location_point", point_id))
            out.points.append(geo_point(lon, lat))
    visits = await ctx.session.execute(
        select(Visit.id, Visit.device_integrity, Visit.checkin_lon, Visit.checkin_lat)
        .where(
            Visit.tenant_id == ctx.tenant_id,
            Visit.officer_id == officer,
            Visit.checkin_at >= start,
            Visit.checkin_at < end,
            Visit.deleted_at.is_(None),
        )
        .order_by(Visit.checkin_at, Visit.id)
    )
    for visit_id, integrity, lon, lat in visits.tuples():
        found, drift = _issues(integrity, max_drift)
        if found:
            out.reasons |= found
            out.max_drift_s = max(out.max_drift_s, abs(drift))
            out.records.append(record("visit", visit_id))
            out.points.append(geo_point(lon, lat))
            out.counts["visits"] += 1
    return out


@rule("VA-E01")
async def check(ctx: RuleContext) -> list[Finding]:
    if not ctx.subject_ids:
        return []  # event rule: the event names the duty sessions / visits
    max_drift = int(ctx.param("max_clock_drift_s"))
    max_points = int(ctx.param("max_evidence_points"))
    findings: list[Finding] = []
    for officer, day in sorted(await _officer_days(ctx, ctx.subject_ids), key=str):
        found = await _collect(ctx, officer, day, max_drift, max_points)
        if not found.reasons:
            continue
        reasons = sorted(found.reasons)
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"integrity:{day.isoformat()}",
                title="Device integrity on duty: "
                + ", ".join(r.replace("_", " ") for r in reasons),
                evidence=Evidence(
                    records=[record("user", officer), *found.records],
                    points=found.points,
                    metrics={
                        "reasons": reasons,
                        "day": day.isoformat(),
                        "max_clock_drift_s": found.max_drift_s,
                        "clock_drift_limit_s": max_drift,
                        "duty_sessions": found.counts["duty"],
                        "location_points": found.counts["points"],
                        "visits": found.counts["visits"],
                    },
                ),
            )
        )
    return findings
