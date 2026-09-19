"""VA-E06 — duty with no activity: more than ``max_idle_hours`` of a duty session without a
visit, a stop boundary or movement, plus the unexplained tracking gaps of a duty day.

The activity timeline of a session is its start, its end (or ``now`` while it is open),
every check-in and check-out of the officer's visits in it (meetings included), and every
location point that moved at least ``min_movement_m`` from the last activity anchor (points
with an accuracy worse than ``max_accuracy_m`` are ignored). A stop (duty/track.py: a run of
points within the stop radius) begins and ends with such a movement, so arriving at or
leaving a stop is activity; sitting at one place with no visit is not. The longest gap
between consecutive activity instants above the threshold raises the flag.

Processed sessions (VV-006, ``duty_session.processed_at`` set at duty end or by the
``process-tracks`` job) use the processed track where it is more accurate:

* movement is measured on the fixes the VV-006 filter keeps (accuracy, duplicate timestamps
  and > 90 km/h jumps dropped, ``farmerapp.duty.track``), so GPS jitter is not activity;
* the start and end of every stored stop (>= 5 min within 100 m) are activity instants;
* the stored track gaps (> 30 min without a kept fix; VV-008 asks the officer for a reason)
  are not idle time: the app samples a stationary officer every few minutes, so a gap is a
  tracking outage, not evidence of sitting still. Their overlap is subtracted from each idle
  span (``gap_minutes_excluded``); gaps are reviewed through VV-008, not here.

Unprocessed sessions (open, or ended before VV-006) keep the raw-point pass above.

**Unexplained tracking gaps** (second check, coaching). A gap is a tracking outage, not
idle time, so it never feeds the idle span above — but an outage nobody explains is its own
signal. A stored ``track_gap`` (VV-006: > 30 min without a kept fix while on duty) at least
``unexplained_gap_hours`` long (tenant setting, default 3) that still has no VV-008 reason
``reason_grace_hours`` (24 h) after it ended raises one low-severity coaching flag for the
cluster head (key ``gap:<gap>``, reason ``unexplained_track_gap``). Recording a reason
afterwards does not reopen it: the flag is resolved by the cluster head, and the dedupe key
keeps the nightly run from raising a second one.

Batch (nightly): sessions overlapping the last ``lookback_hours``, gaps that ended within
the last ``gap_lookback_hours``. One flag per session (key ``idle:<session>``) and one per
unexplained gap, low severity, for the cluster head.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from itertools import pairwise

from sqlalchemy import or_, select

from farmerapp.db.geo import haversine_m
from farmerapp.duty.models import TrackGap
from farmerapp.duty.track import TrackPoint, _usable
from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.rules.checks.common import geo_point
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.settings import get_tenant_settings
from farmerapp.visits.models import Visit


@rule("VA-E06")
async def check(ctx: RuleContext) -> list[Finding]:
    return await _idle_on_duty(ctx) + await _unexplained_gaps(ctx)


async def _idle_on_duty(ctx: RuleContext) -> list[Finding]:
    max_idle = timedelta(hours=float(ctx.param("max_idle_hours")))
    min_move = float(ctx.param("min_movement_m"))
    max_accuracy = float(ctx.param("max_accuracy_m"))
    since = ctx.now - timedelta(hours=float(ctx.param("lookback_hours")))
    stmt = (
        select(
            DutySession.id,
            DutySession.officer_id,
            DutySession.start_at,
            DutySession.end_at,
            DutySession.processed_at,
            DutySession.stops,
        )
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
    for duty_id, officer, start, end, processed_at, stops in (
        await ctx.session.execute(stmt)
    ).tuples():
        processed = processed_at is not None
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
            select(LocationPoint.ts, LocationPoint.lon, LocationPoint.lat, LocationPoint.accuracy_m)
            .where(
                LocationPoint.tenant_id == ctx.tenant_id,
                LocationPoint.duty_session_id == duty_id,
                LocationPoint.ts >= start,
                LocationPoint.ts <= until,
                LocationPoint.accuracy_m <= max_accuracy,
            )
            .order_by(LocationPoint.ts)
        )
        fixes = [
            TrackPoint(ts=ts, lat=lat, lon=lon, accuracy_m=float(acc))
            for ts, lon, lat, acc in points.tuples()
        ]
        gaps: list[tuple[datetime, datetime]] = []
        if processed:
            fixes = _usable(fixes)  # the VV-006 filter: jitter jumps are not movement
            for stop in stops or []:
                for key in ("start", "end"):
                    at = datetime.fromisoformat(stop[key])
                    if start <= at <= until:
                        instants.append((at, "stop", None))
            gap_rows = await ctx.session.execute(
                select(TrackGap.start_at, TrackGap.end_at).where(
                    TrackGap.tenant_id == ctx.tenant_id,
                    TrackGap.duty_session_id == duty_id,
                    TrackGap.deleted_at.is_(None),
                )
            )
            gaps = list(gap_rows.tuples())
        anchor: tuple[float, float] | None = None
        where: dict[datetime, tuple[float, float]] = {}
        for fix in fixes:
            ts, lon, lat = fix.ts, fix.lon, fix.lat
            if anchor is None:
                anchor = (lon, lat)
                where[ts] = anchor
                continue
            if haversine_m(anchor[1], anchor[0], lat, lon) >= min_move:
                anchor = (lon, lat)
                instants.append((ts, "movement", None))
            where[ts] = anchor
        instants.sort(key=lambda i: i[0])
        worst: tuple[timedelta, datetime, datetime, timedelta] | None = None
        for (a, _ka, _ia), (b, _kb, _ib) in pairwise(instants):
            outage = _overlap(gaps, a, b)
            idle = b - a - outage
            if worst is None or idle > worst[0]:
                worst = (idle, a, b, outage)
        if worst is None or worst[0] <= max_idle:
            continue
        gap, idle_from, idle_to, outage = worst
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
                        "track_processed": processed,
                        "gap_minutes_excluded": int(outage.total_seconds() // 60),
                    },
                ),
            )
        )
    return findings


async def _unexplained_gaps(ctx: RuleContext) -> list[Finding]:
    """Tracking gaps of a duty session, long enough to matter and still unexplained a day
    after they ended (VV-008 is where the officer records the reason)."""
    settings = await get_tenant_settings(ctx.session, ctx.tenant_id)
    min_gap = timedelta(hours=float(settings.unexplained_gap_hours))
    grace = timedelta(hours=float(ctx.param("reason_grace_hours")))
    since = ctx.now - timedelta(hours=float(ctx.param("gap_lookback_hours")))
    stmt = (
        select(
            TrackGap.id,
            TrackGap.officer_id,
            TrackGap.duty_session_id,
            TrackGap.start_at,
            TrackGap.end_at,
            TrackGap.duration_s,
        )
        .join(DutySession, DutySession.id == TrackGap.duty_session_id)
        .where(
            TrackGap.tenant_id == ctx.tenant_id,
            TrackGap.deleted_at.is_(None),
            TrackGap.reason.is_(None),
            TrackGap.duration_s >= int(min_gap.total_seconds()),
            TrackGap.end_at <= ctx.now - grace,
            TrackGap.end_at >= since,
            DutySession.deleted_at.is_(None),
        )
        .order_by(TrackGap.start_at, TrackGap.id)
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(TrackGap.duty_session_id.in_(ctx.subject_ids))
    findings: list[Finding] = []
    for gap_id, officer, duty_id, start, end, duration_s in (
        await ctx.session.execute(stmt)
    ).tuples():
        hours = duration_s / 3600
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"gap:{gap_id}",
                title=f"{hours:.1f} h without tracking on duty, still unexplained",
                evidence=Evidence(
                    records=[
                        record("user", officer),
                        record("duty_session", duty_id),
                        record("track_gap", gap_id),
                    ],
                    metrics={
                        "reason": "unexplained_track_gap",
                        "gap_from": start.isoformat(),
                        "gap_to": end.isoformat(),
                        "gap_minutes": duration_s // 60,
                        "unexplained_gap_hours": float(settings.unexplained_gap_hours),
                        "reason_grace_hours": float(ctx.param("reason_grace_hours")),
                    },
                ),
            )
        )
    return findings


def _overlap(spans: list[tuple[datetime, datetime]], a: datetime, b: datetime) -> timedelta:
    """Total time of ``spans`` (disjoint track gaps) inside ``[a, b]``."""
    total = timedelta(0)
    for lo, hi in spans:
        lo, hi = max(lo, a), min(hi, b)
        if hi > lo:
            total += hi - lo
    return total
