"""VA-E02 — impossible travel: the speed between consecutive on-duty points of a duty
session is above ``max_speed_kmh``.

Accuracy filtering (VV-002 metadata): points reporting an accuracy worse than
``max_accuracy_m`` are dropped before pairing, and a leg no longer than the two points'
combined accuracy is GPS jitter, never travel (two fixes 10 s apart with 80 m accuracy can
be 150 m apart while the officer stands still). The speed is the great-circle distance over
the difference of the device timestamps; legs with no time between them are skipped.

Event mode on ``location.batch`` (``ctx.subject_ids`` = duty sessions): the whole session is
re-read (a session is at most one working day of points, served by the
``(duty_session_id, ts)`` index), so a leg spanning two batches is caught too. One flag per
officer and IST day (key ``travel:<day>``); the fastest leg is the evidence, with both points
on the map.

Params: ``max_speed_kmh``, ``max_accuracy_m``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from itertools import pairwise

from sqlalchemy import select

from farmerapp.db.geo import haversine_m
from farmerapp.location.models import LocationPoint
from farmerapp.rules.checks.common import geo_point, ist_day
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject


@dataclass(frozen=True)
class _Fix:
    id: uuid.UUID
    officer: uuid.UUID
    ts: datetime
    lon: float
    lat: float
    accuracy_m: float


@dataclass(frozen=True)
class _Leg:
    a: _Fix
    b: _Fix
    distance_m: float
    seconds: float

    @property
    def speed_kmh(self) -> float:
        return self.distance_m / self.seconds * 3.6


def fast_legs(fixes: list[_Fix], *, max_speed_kmh: float, max_accuracy_m: float) -> list[_Leg]:
    """Consecutive legs faster than ``max_speed_kmh`` after the accuracy filtering."""
    kept = [f for f in fixes if f.accuracy_m <= max_accuracy_m]
    legs: list[_Leg] = []
    for a, b in pairwise(kept):
        seconds = (b.ts - a.ts).total_seconds()
        if seconds <= 0:
            continue
        distance = haversine_m(a.lat, a.lon, b.lat, b.lon)
        if distance <= a.accuracy_m + b.accuracy_m:
            continue  # within the fixes' uncertainty: jitter
        leg = _Leg(a=a, b=b, distance_m=distance, seconds=seconds)
        if leg.speed_kmh > max_speed_kmh:
            legs.append(leg)
    return legs


@rule("VA-E02")
async def check(ctx: RuleContext) -> list[Finding]:
    if not ctx.subject_ids:
        return []  # event rule: the event names the duty sessions
    max_speed = float(ctx.param("max_speed_kmh"))
    max_accuracy = float(ctx.param("max_accuracy_m"))
    rows = await ctx.session.execute(
        select(
            LocationPoint.duty_session_id,
            LocationPoint.id,
            LocationPoint.officer_id,
            LocationPoint.ts,
            LocationPoint.lon,
            LocationPoint.lat,
            LocationPoint.accuracy_m,
        )
        .where(
            LocationPoint.tenant_id == ctx.tenant_id,
            LocationPoint.duty_session_id.in_(ctx.subject_ids),
        )
        .order_by(LocationPoint.duty_session_id, LocationPoint.ts, LocationPoint.id)
    )
    by_session: dict[uuid.UUID, list[_Fix]] = {}
    for session_id, point_id, officer, ts, lon, lat, accuracy in rows.tuples():
        if session_id is not None:
            by_session.setdefault(session_id, []).append(
                _Fix(point_id, officer, ts, lon, lat, accuracy)
            )
    worst: dict[tuple[uuid.UUID, str], tuple[uuid.UUID, _Leg, int]] = {}
    for session_id, fixes in sorted(by_session.items(), key=lambda kv: str(kv[0])):
        for leg in fast_legs(fixes, max_speed_kmh=max_speed, max_accuracy_m=max_accuracy):
            key = (leg.a.officer, ist_day(leg.a.ts).isoformat())
            current = worst.get(key)
            count = (current[2] if current else 0) + 1
            if current is None or leg.speed_kmh > current[1].speed_kmh:
                worst[key] = (session_id, leg, count)
            else:
                worst[key] = (current[0], current[1], count)
    findings: list[Finding] = []
    for (officer, day), (session_id, leg, count) in sorted(worst.items(), key=str):
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"travel:{day}",
                title=f"Impossible travel: {leg.speed_kmh:.0f} km/h between two points",
                evidence=Evidence(
                    records=[
                        record("user", officer),
                        record("duty_session", session_id),
                        record("location_point", leg.a.id),
                        record("location_point", leg.b.id),
                    ],
                    points=[geo_point(leg.a.lon, leg.a.lat), geo_point(leg.b.lon, leg.b.lat)],
                    metrics={
                        "reason": "impossible_travel",
                        "day": day,
                        "speed_kmh": round(leg.speed_kmh, 1),
                        "distance_m": round(leg.distance_m),
                        "seconds": round(leg.seconds),
                        "from_ts": leg.a.ts.isoformat(),
                        "to_ts": leg.b.ts.isoformat(),
                        "accuracy_m": [leg.a.accuracy_m, leg.b.accuracy_m],
                        "fast_legs": count,
                        "max_speed_kmh": max_speed,
                    },
                ),
            )
        )
    return findings
