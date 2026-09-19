"""VA-E03 — visits clustered at one spot: on one IST day an officer checks in visits to at
least ``min_farms`` different farms whose check-in points are all within ``radius_m`` of
each other, away from any registered meeting point.

* Visits at a meeting are expected to sit together: a visit recorded at the meeting point
  (``geofence_result = meeting_point``), of purpose ``meeting``, or checked in within the
  meeting-point radius of any village of the tenant (``village.meeting_point_radius_m``, else
  the tenant ``geofence_radius_m``) is left out.
* "Farms" are distinct ``farm_id`` s (the farmer when a visit names no farm), so repeated
  visits to one farm never make a cluster.
* Clustering: for each visit, its neighbours within ``radius_m`` are added nearest first
  while every pair stays within ``radius_m`` (a clique, not a chain); the largest cluster of
  the officer-day is the evidence (centroid + every visit on the map).

Batch (nightly): visits checked in during the last ``lookback_hours``. One flag per officer
and IST day (key ``cluster:<day>``).

Params: ``min_farms``, ``radius_m``, ``lookback_hours``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import aliased

from farmerapp.db.geo import haversine_m
from farmerapp.db.models.tenant import Tenant
from farmerapp.rules.checks.common import geo_point, ist_day
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.models import Village
from farmerapp.tenants.settings import tenant_settings
from farmerapp.visits.models import GeofenceResult, Visit, VisitPurpose


@dataclass(frozen=True)
class _Visit:
    id: uuid.UUID
    officer: uuid.UUID
    farm: uuid.UUID
    lon: float
    lat: float
    day: str


def clusters(visits: list[_Visit], radius_m: float) -> list[list[_Visit]]:
    """For each visit, the clique of visits (itself first) pairwise within ``radius_m``."""
    out: list[list[_Visit]] = []
    for centre in visits:
        others = sorted(
            (haversine_m(centre.lat, centre.lon, v.lat, v.lon), str(v.id), v)
            for v in visits
            if v.id != centre.id
        )
        members = [centre]
        for distance, _id, visit in others:
            if distance > radius_m:
                break
            if all(haversine_m(m.lat, m.lon, visit.lat, visit.lon) <= radius_m for m in members):
                members.append(visit)
        out.append(members)
    return out


async def _meeting_radius_default(ctx: RuleContext) -> int:
    raw = await ctx.session.scalar(select(Tenant.settings).where(Tenant.id == ctx.tenant_id))
    return tenant_settings(raw).geofence_radius_m


@rule("VA-E03")
async def check(ctx: RuleContext) -> list[Finding]:
    min_farms = int(ctx.param("min_farms"))
    radius = float(ctx.param("radius_m"))
    since = ctx.now - timedelta(hours=float(ctx.param("lookback_hours")))
    default_radius = await _meeting_radius_default(ctx)
    meeting = aliased(Village)
    near_meeting = (
        select(meeting.id)
        .where(
            meeting.tenant_id == ctx.tenant_id,
            meeting.meeting_point.is_not(None),
            func.ST_DWithin(
                meeting.meeting_point,
                Visit.checkin_point,
                func.coalesce(meeting.meeting_point_radius_m, default_radius),
            ),
        )
        .exists()
    )
    stmt = select(
        Visit.id,
        Visit.officer_id,
        func.coalesce(Visit.farm_id, Visit.farmer_id),
        Visit.checkin_lon,
        Visit.checkin_lat,
        Visit.checkin_at,
    ).where(
        Visit.tenant_id == ctx.tenant_id,
        Visit.deleted_at.is_(None),
        Visit.checkin_at >= since,
        Visit.checkin_at <= ctx.now,
        Visit.geofence_result != GeofenceResult.MEETING_POINT.value,
        Visit.purpose != VisitPurpose.MEETING.value,
        ~near_meeting,
    )
    groups: dict[tuple[uuid.UUID, str], list[_Visit]] = {}
    for visit_id, officer, farm, lon, lat, at in (await ctx.session.execute(stmt)).tuples():
        day = ist_day(at).isoformat()
        groups.setdefault((officer, day), []).append(_Visit(visit_id, officer, farm, lon, lat, day))
    findings: list[Finding] = []
    for (officer, day), visits in sorted(groups.items(), key=str):
        if len({v.farm for v in visits}) < min_farms:
            continue
        best = max(
            clusters(sorted(visits, key=lambda v: str(v.id)), radius),
            key=lambda c: (len({v.farm for v in c}), len(c)),
        )
        farms = len({v.farm for v in best})
        if farms < min_farms:
            continue
        lon = sum(v.lon for v in best) / len(best)
        lat = sum(v.lat for v in best) / len(best)
        spread = max(haversine_m(lat, lon, v.lat, v.lon) for v in best)
        members = sorted(best, key=lambda v: str(v.id))
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"cluster:{day}",
                title=f"{farms} farms' visits checked in within {radius:.0f} m of each other",
                evidence=Evidence(
                    records=[record("user", officer)] + [record("visit", v.id) for v in members],
                    points=[geo_point(lon, lat)] + [geo_point(v.lon, v.lat) for v in members],
                    metrics={
                        "reason": "clustered_visits",
                        "day": day,
                        "farms": farms,
                        "visits": len(members),
                        "radius_m": radius,
                        "centroid": {"lon": round(lon, 7), "lat": round(lat, 7)},
                        "max_distance_from_centroid_m": round(spread, 1),
                    },
                ),
            )
        )
    return findings
