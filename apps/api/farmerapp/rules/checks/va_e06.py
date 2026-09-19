"""VA-E06 — duty with no activity: more than ``max_idle_hours`` of a duty session without a
visit, a stop boundary or movement.

The activity timeline of a session is its start, its end (or ``now`` while it is open),
every check-in and check-out of the officer's visits in it (meetings included), and every
location point that moved at least ``min_movement_m`` from the last activity anchor (points
with an accuracy worse than ``max_accuracy_m`` are ignored). A stop (duty/track.py: a run of
points within the stop radius) begins and ends with such a movement, so arriving at or
leaving a stop is activity; sitting at one place with no visit is not. The longest gap
between consecutive activity instants above the threshold raises the flag.

Batch (nightly): sessions overlapping the last ``lookback_hours``. One flag per session
(key ``idle:<session>``), low severity, for the cluster head.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from itertools import pairwise

from sqlalchemy import or_, select

from farmerapp.db.geo import haversine_m
from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.rules.checks.common import geo_point
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.visits.models import Visit


@rule("VA-E06")
async def check(ctx: RuleContext) -> list[Finding]:
    max_idle = timedelta(hours=float(ctx.param("max_idle_hours")))
    min_move = float(ctx.param("min_movement_m"))
    max_accuracy = float(ctx.param("max_accuracy_m"))
    since = ctx.now - timedelta(hours=float(ctx.param("lookback_hours")))
    stmt = (
        select(DutySession.id, DutySession.officer_id, DutySession.start_at, DutySession.end_at)
        .where(
            DutySession.tenant_id == ctx.tenant_id,
            DutySession.deleted_at.is_(None),
            DutySession.start_at <= ctx.now,
            or_(DutySession.end_at.is_(None), DutySession.end_at >= since),
        )
        .order_by(DutySession.start_at, DutySession.id)
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(DutySession.id.in_(ctx.subject_ids))
    findings: list[Finding] = []
    for duty_id, officer, start, end in (await ctx.session.execute(stmt)).tuples():
        until = min(end, ctx.now) if end is not None else ctx.now
        instants: list[tuple[datetime, str, uuid.UUID | None]] = [
            (start, "duty_start", None),
            (until, "duty_end" if end is not None else "now", None),
        ]
        visits = await ctx.session.execute(
            select(Visit.id, Visit.checkin_at, Visit.checkout_at).where(
                Visit.tenant_id == ctx.tenant_id,
                Visit.officer_id == officer,
                Visit.deleted_at.is_(None),
                Visit.checkin_at <= until,
                or_(Visit.checkout_at.is_(None), Visit.checkout_at >= start),
            )
        )
        for visit_id, checkin, checkout in visits.tuples():
            for at in (checkin, checkout):
                if at is not None and start <= at <= until:
                    instants.append((at, "visit", visit_id))
        points = await ctx.session.execute(
            select(LocationPoint.ts, LocationPoint.lon, LocationPoint.lat)
            .where(
                LocationPoint.tenant_id == ctx.tenant_id,
                LocationPoint.duty_session_id == duty_id,
                LocationPoint.ts >= start,
                LocationPoint.ts <= until,
                LocationPoint.accuracy_m <= max_accuracy,
            )
            .order_by(LocationPoint.ts)
        )
        anchor: tuple[float, float] | None = None
        where: dict[datetime, tuple[float, float]] = {}
        for ts, lon, lat in points.tuples():
            if anchor is None:
                anchor = (lon, lat)
                where[ts] = anchor
                continue
            if haversine_m(anchor[1], anchor[0], lat, lon) >= min_move:
                anchor = (lon, lat)
                instants.append((ts, "movement", None))
            where[ts] = anchor
        instants.sort(key=lambda i: i[0])
        worst: tuple[timedelta, datetime, datetime] | None = None
        for (a, _ka, _ia), (b, _kb, _ib) in pairwise(instants):
            gap = b - a
            if worst is None or gap > worst[0]:
                worst = (gap, a, b)
        if worst is None or worst[0] <= max_idle:
            continue
        gap, idle_from, idle_to = worst
        seen = [xy for ts, xy in where.items() if idle_from <= ts <= idle_to]
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"idle:{duty_id}",
                title=f"{int(gap.total_seconds() // 60)} min on duty with no visit or movement",
                evidence=Evidence(
                    records=[record("user", officer), record("duty_session", duty_id)],
                    points=[geo_point(*seen[0])] if seen else [],
                    metrics={
                        "reason": "idle_on_duty",
                        "idle_from": idle_from.isoformat(),
                        "idle_to": idle_to.isoformat(),
                        "idle_minutes": int(gap.total_seconds() // 60),
                        "max_idle_hours": float(ctx.param("max_idle_hours")),
                        "visits_in_session": sum(1 for i in instants if i[1] == "visit"),
                    },
                ),
            )
        )
    return findings
