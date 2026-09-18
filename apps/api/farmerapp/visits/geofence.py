"""FA-014 / VV-003 geofence evaluation at check-in.

A check-in point is

* ``inside`` when it lies within the farm's registration polygon buffered by the tenant's
  ``geofence_radius_m`` (default 150 m; ``ST_DWithin`` on ``geography``, spheroid metres);
* ``meeting_point`` when it lies within the village meeting point's radius
  (``village.meeting_point_radius_m``, or the tenant default when NULL);
* ``outside`` otherwise. The result carries the distance to the nearest allowed target and
  which target it was, so the app can explain ("320 m from the farm boundary") and the
  officer can ask for an override with a note.

The decision is taken by PostGIS (the database is the authority on geometry; the scorer's
haversine is only for photo evidence). A farm without a boundary and a village without a
meeting point leave nothing to test against: the check-in is ``outside`` with
``target = None`` and needs an override (assumption: no geofence means no automatic credit).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Literal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.geo import point_wkt
from farmerapp.farmers.models import Farm
from farmerapp.tenants.models import Village
from farmerapp.visits.models import GeofenceResult

Target = Literal["farm", "meeting_point"]


@dataclass(frozen=True)
class GeofenceCheck:
    result: GeofenceResult
    distance_m: float | None  # to the nearest allowed target (0 when inside)
    target: Target | None  # which target the distance refers to
    radius_m: int | None  # the radius that applied to that target

    @property
    def allowed(self) -> bool:
        return self.result in (GeofenceResult.INSIDE, GeofenceResult.MEETING_POINT)


@dataclass(frozen=True)
class _Candidate:
    target: Target
    distance_m: float
    radius_m: int
    within: bool


async def evaluate(
    session: AsyncSession,
    *,
    lat: float,
    lon: float,
    farm: Farm | None,
    village: Village | None,
    default_radius_m: int,
) -> GeofenceCheck:
    """VV-003: test the point against the farm polygon, then the village meeting point."""
    point = func.ST_GeogFromText(point_wkt(lon, lat))
    candidates: list[_Candidate] = []
    if farm is not None and farm.boundary is not None:
        row = (
            await session.execute(
                select(
                    func.ST_Distance(Farm.boundary, point),
                    func.ST_DWithin(Farm.boundary, point, default_radius_m),
                ).where(Farm.id == farm.id)
            )
        ).one()
        candidates.append(
            _Candidate(
                target="farm",
                distance_m=float(row[0]),
                radius_m=default_radius_m,
                within=bool(row[1]),
            )
        )
    if village is not None and village.meeting_point is not None:
        radius = village.meeting_point_radius_m or default_radius_m
        row = (
            await session.execute(
                select(
                    func.ST_Distance(Village.meeting_point, point),
                    func.ST_DWithin(Village.meeting_point, point, radius),
                ).where(Village.id == village.id)
            )
        ).one()
        candidates.append(
            _Candidate(
                target="meeting_point",
                distance_m=float(row[0]),
                radius_m=radius,
                within=bool(row[1]),
            )
        )
    for candidate in candidates:  # farm first: a farm visit beats a meeting nearby
        if candidate.within:
            result = (
                GeofenceResult.INSIDE
                if candidate.target == "farm"
                else GeofenceResult.MEETING_POINT
            )
            return GeofenceCheck(
                result=result,
                distance_m=round(candidate.distance_m, 1),
                target=candidate.target,
                radius_m=candidate.radius_m,
            )
    if not candidates:
        return GeofenceCheck(
            result=GeofenceResult.OUTSIDE, distance_m=None, target=None, radius_m=None
        )
    nearest = min(candidates, key=lambda c: c.distance_m)
    return GeofenceCheck(
        result=GeofenceResult.OUTSIDE,
        distance_m=round(nearest.distance_m, 1),
        target=nearest.target,
        radius_m=nearest.radius_m,
    )


async def farm_of(session: AsyncSession, tenant_id: uuid.UUID, farm_id: uuid.UUID) -> Farm | None:
    farm = await session.get(Farm, farm_id)
    if farm is None or farm.tenant_id != tenant_id or farm.deleted_at is not None:
        return None
    return farm


async def village_of(
    session: AsyncSession, tenant_id: uuid.UUID, village_id: uuid.UUID | None
) -> Village | None:
    if village_id is None:
        return None
    village = await session.get(Village, village_id)
    if village is None or village.tenant_id != tenant_id or village.deleted_at is not None:
        return None
    return village


__all__ = ["GeofenceCheck", "Target", "evaluate", "farm_of", "village_of"]
