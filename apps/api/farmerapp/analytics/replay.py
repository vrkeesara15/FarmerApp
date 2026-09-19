"""AN-003 / WC-002 officer day replay (console C22): track, stops, visits, gaps, timeline.

For one officer and one IST day:

* ``track`` — GeoJSON ``MultiLineString`` of the kept location points (accuracy <= 100 m,
  no implausible > 90 km/h jumps; the same filter as the duty-end summary,
  ``farmerapp.duty.track``), one line per duty session, broken at every gap;
* ``stops`` — >= 5 minutes within 100 m (``farmerapp.duty.track.summarise``);
* ``gaps`` — more than 30 minutes without a kept point while on duty (from the session start,
  between points, and up to the session end; an open session is measured up to now or the
  end of the day). ``reason`` is the officer's explanation once VV-008 stores one; ``null``
  until then;
* ``visits`` — pins with status colour (verified green, partial amber, unverified red, open
  grey), score, VV-004 components and the ProofChecklist rows;
* ``timeline`` — duty start / end, check-ins / check-outs, stops and gaps sorted by time;
* ``km`` — the haversine km of the kept points (the stored session km when a session has no
  points in the day).

Roles (SPEC 2.6 "Officer location track"): owner, director, tenant admin, auditor, the
cluster head of the officer's cluster and the officer themself. Store managers, accountants,
agronomists and farmers get 403; an officer outside the caller's scope is 404.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from itertools import pairwise
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import FiltersOut, ist_bounds
from farmerapp.analytics.schemas import (
    DayReplayOut,
    DutySessionBrief,
    GapOut,
    GeoJsonMultiLineString,
    ProofItemOut,
    ReplayPoint,
    ReplayVisitOut,
    StopOut,
    TimelineEvent,
)
from farmerapp.auth.models import User
from farmerapp.db.geo import haversine_m
from farmerapp.duty.track import MAX_ACCURACY_M, MAX_SPEED_MPS, TrackPoint, summarise
from farmerapp.farmers.models import Farmer
from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.location.router import MAX_TRACK_POINTS
from farmerapp.visits import scoring
from farmerapp.visits.models import Visit, VisitPhoto, VisitStatus

GAP_MIN = timedelta(minutes=30)

STATUS_COLOUR = {
    VisitStatus.VERIFIED.value: "green",
    VisitStatus.PARTIAL.value: "amber",
    VisitStatus.UNVERIFIED.value: "red",
    VisitStatus.OPEN.value: "grey",
}
MAX_POINTS = {
    "geofence": scoring.GEOFENCE_POINTS,
    "confirmation": scoring.CONFIRMATION_POINTS,
    "photo": scoring.PHOTO_POINTS,
    "duration": scoring.DURATION_POINTS,
    "integrity": scoring.INTEGRITY_POINTS,
}


@dataclass(frozen=True)
class Kept:
    ts: datetime
    lat: float
    lon: float
    accuracy_m: float


def usable(points: Sequence[Kept]) -> list[Kept]:
    """Accuracy <= 100 m, strictly increasing time, no jump faster than 90 km/h."""
    ordered = sorted((p for p in points if p.accuracy_m <= MAX_ACCURACY_M), key=lambda p: p.ts)
    kept: list[Kept] = []
    for p in ordered:
        if kept:
            prev = kept[-1]
            dt = (p.ts - prev.ts).total_seconds()
            if dt <= 0:
                continue
            if haversine_m(prev.lat, prev.lon, p.lat, p.lon) / dt > MAX_SPEED_MPS:
                continue
        kept.append(p)
    return kept


def find_gaps(
    session_start: datetime, session_end: datetime, times: Sequence[datetime]
) -> list[tuple[datetime, datetime]]:
    """Spans longer than 30 minutes with no point between ``session_start`` and ``session_end``."""
    marks = [session_start, *[t for t in times if session_start <= t <= session_end], session_end]
    return [(a, b) for a, b in pairwise(marks) if b - a > GAP_MIN]


def split_lines(
    points: Sequence[Kept], gaps: Sequence[tuple[datetime, datetime]]
) -> list[list[list[float]]]:
    """Line strings of consecutive points, broken wherever a gap lies between two points."""
    lines: list[list[list[float]]] = []
    current: list[list[float]] = []
    prev: Kept | None = None
    for p in points:
        if prev is not None and any(prev.ts <= a and b <= p.ts for a, b in gaps):
            if len(current) >= 2:
                lines.append(current)
            current = []
        current.append([round(p.lon, 7), round(p.lat, 7)])
        prev = p
    if len(current) >= 2:
        lines.append(current)
    return lines


def proof_items(components: dict[str, Any] | None) -> list[ProofItemOut]:
    comps = components or {}
    return [
        ProofItemOut(
            kind=kind,
            satisfied=int(comps.get(kind, 0) or 0) > 0,
            points=int(comps.get(kind, 0) or 0),
            max_points=maximum,
        )
        for kind, maximum in MAX_POINTS.items()
    ]


async def day_replay(
    session: AsyncSession,
    officer: User,
    day: date,
    filters: FiltersOut,
    now: datetime | None = None,
) -> DayReplayOut:
    now = now or datetime.now(UTC)
    day_start, day_end = ist_bounds(day, day)
    tid = officer.tenant_id

    sessions = (
        (
            await session.execute(
                select(DutySession)
                .where(
                    DutySession.tenant_id == tid,
                    DutySession.officer_id == officer.id,
                    DutySession.deleted_at.is_(None),
                    DutySession.start_at < day_end,
                    (DutySession.end_at.is_(None)) | (DutySession.end_at >= day_start),
                )
                .order_by(DutySession.start_at, DutySession.id)
            )
        )
        .scalars()
        .all()
    )
    rows = await session.execute(
        select(
            LocationPoint.ts,
            LocationPoint.lat,
            LocationPoint.lon,
            LocationPoint.accuracy_m,
            LocationPoint.duty_session_id,
        )
        .where(
            LocationPoint.tenant_id == tid,
            LocationPoint.officer_id == officer.id,
            LocationPoint.ts >= day_start,
            LocationPoint.ts < day_end,
        )
        .order_by(LocationPoint.ts, LocationPoint.id)
        .limit(MAX_TRACK_POINTS)
    )
    by_session: dict[uuid.UUID | None, list[Kept]] = {}
    for ts, lat, lon, acc, sid in rows:
        by_session.setdefault(sid, []).append(Kept(ts, float(lat), float(lon), float(acc)))

    lines: list[list[list[float]]] = []
    kept_all: list[Kept] = []
    stops: list[StopOut] = []
    gaps: list[GapOut] = []
    km = Decimal(0)
    briefs: list[DutySessionBrief] = []
    timeline: list[TimelineEvent] = []
    for ds in sessions:
        kept = usable(by_session.get(ds.id, []))
        kept_all.extend(kept)
        start = max(ds.start_at, day_start)
        end = min(ds.end_at or now, day_end)
        spans = find_gaps(start, end, [p.ts for p in kept]) if end > start else []
        lines.extend(split_lines(kept, spans))
        summary = summarise(TrackPoint(p.ts, p.lat, p.lon, p.accuracy_m) for p in kept)
        session_km = summary.km if kept else (ds.km or Decimal(0))
        km += session_km
        for s in summary.stops:
            stop = StopOut(
                lat=s["lat"],
                lon=s["lon"],
                start=datetime.fromisoformat(s["start"]),
                end=datetime.fromisoformat(s["end"]),
                duration_s=s["duration_s"],
            )
            stops.append(stop)
            timeline.append(
                TimelineEvent(
                    ts=stop.start,
                    type="stop",
                    detail={"end": stop.end.isoformat(), "duration_s": stop.duration_s},
                )
            )
        for a, b in spans:
            gap = GapOut(
                start=a,
                end=b,
                duration_s=int((b - a).total_seconds()),
                duty_session_id=ds.id,
                reason=None,  # TODO(VV-008): the officer's gap reason once the table exists
            )
            gaps.append(gap)
            timeline.append(
                TimelineEvent(
                    ts=a, type="gap_start", ref_id=ds.id, detail={"duration_s": gap.duration_s}
                )
            )
            timeline.append(TimelineEvent(ts=b, type="gap_end", ref_id=ds.id))
        briefs.append(
            DutySessionBrief(
                id=ds.id,
                start_at=ds.start_at,
                end_at=ds.end_at,
                end_reason=ds.end_reason,
                km=float(session_km),
            )
        )
        if day_start <= ds.start_at < day_end:
            timeline.append(TimelineEvent(ts=ds.start_at, type="duty_start", ref_id=ds.id))
        if ds.end_at is not None and day_start <= ds.end_at < day_end:
            timeline.append(
                TimelineEvent(
                    ts=ds.end_at,
                    type="duty_end",
                    ref_id=ds.id,
                    detail={"end_reason": ds.end_reason},
                )
            )

    photos = (
        select(func.count())
        .where(VisitPhoto.visit_id == Visit.id, VisitPhoto.deleted_at.is_(None))
        .correlate(Visit)
        .scalar_subquery()
    )
    visit_rows = await session.execute(
        select(Visit, Farmer.name, photos)
        .join(Farmer, Farmer.id == Visit.farmer_id)
        .where(
            Visit.tenant_id == tid,
            Visit.officer_id == officer.id,
            Visit.deleted_at.is_(None),
            Visit.checkin_at >= day_start,
            Visit.checkin_at < day_end,
        )
        .order_by(Visit.checkin_at, Visit.id)
    )
    visits: list[ReplayVisitOut] = []
    for v, farmer_name, photo_count in visit_rows:
        components = {k: int(x) for k, x in (v.score_components or {}).items()}
        visits.append(
            ReplayVisitOut(
                id=v.id,
                farmer_id=v.farmer_id,
                farmer_name=farmer_name,
                purpose=v.purpose,
                checkin_at=v.checkin_at,
                checkout_at=v.checkout_at,
                duration_s=v.duration_s,
                lat=v.checkin_lat,
                lon=v.checkin_lon,
                geofence_result=v.geofence_result,
                status=v.status,
                colour=STATUS_COLOUR.get(v.status, "grey"),
                score=v.score,
                score_components=components,
                proof=proof_items(components),
                confirmed_at=v.confirmed_at,
                photos=int(photo_count or 0),
            )
        )
        timeline.append(
            TimelineEvent(
                ts=v.checkin_at,
                type="visit_checkin",
                ref_id=v.id,
                detail={"status": v.status, "score": v.score, "farmer_name": farmer_name},
            )
        )
        if v.checkout_at is not None:
            timeline.append(TimelineEvent(ts=v.checkout_at, type="visit_checkout", ref_id=v.id))

    order = {"duty_start": 0, "gap_end": 1, "visit_checkin": 2, "stop": 3}
    timeline.sort(key=lambda e: (e.ts, order.get(e.type, 5)))
    kept_all.sort(key=lambda p: p.ts)
    return DayReplayOut(
        filters=filters,
        officer_id=officer.id,
        officer_name=officer.name,
        date=day,
        duty_sessions=briefs,
        km=float(km.quantize(Decimal("0.01"))),
        track=GeoJsonMultiLineString(coordinates=lines),
        points=[
            ReplayPoint(ts=p.ts, lat=p.lat, lon=p.lon, accuracy_m=p.accuracy_m) for p in kept_all
        ],
        stops=stops,
        gaps=gaps,
        visits=visits,
        timeline=timeline,
    )


__all__ = ["GAP_MIN", "day_replay", "find_gaps", "proof_items", "split_lines", "usable"]
