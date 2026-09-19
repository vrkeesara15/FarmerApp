"""VA-F03 — farm polygon sanity: measured area within ±``area_tolerance`` of the declared
acres, no self-intersection, and at most ``max_overlap`` of the farm covered by another
farmer's farm.

Inline (FA-012 registration and farm edits) the API already *rejects* a self-intersecting
boundary (422 ``farm_boundary_invalid``) and answers ``area_mismatch`` / ``farm_overlap``
warnings; this rule turns those warnings into flags for the store manager's review queue. In
batch it also catches invalid polygons that arrived another way (imports, older app builds).

One flag per farm (dedupe key ``farm:<id>``), about the farmer, with the polygon on the map.

Params: ``area_tolerance`` (fraction), ``max_overlap`` (fraction of the farm's area).
"""

from __future__ import annotations

import json
from decimal import Decimal

from geoalchemy2 import Geometry
from sqlalchemy import Float, and_, cast, func, select, true
from sqlalchemy.orm import aliased

from farmerapp.farmers.models import Farm, Farmer
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject

_GEOM = Geometry(srid=4326)


@rule("VA-F03")
async def check(ctx: RuleContext) -> list[Finding]:
    tolerance = Decimal(str(ctx.param("area_tolerance")))
    max_overlap = float(ctx.param("max_overlap"))
    farm = aliased(Farm)
    other = aliased(Farm)
    owner = aliased(Farmer)
    valid = func.ST_IsValid(cast(farm.boundary, _GEOM))
    overlap = (
        select(
            other.id.label("other_farm_id"),
            other.farmer_id.label("other_farmer_id"),
            cast(func.ST_Area(func.ST_Intersection(farm.boundary, other.boundary)), Float).label(
                "overlap_m2"
            ),
        )
        .join(owner, owner.id == other.farmer_id)
        .where(
            valid,
            other.tenant_id == farm.tenant_id,
            other.farmer_id != farm.farmer_id,
            other.deleted_at.is_(None),
            owner.deleted_at.is_(None),
            other.boundary.is_not(None),
            func.ST_IsValid(cast(other.boundary, _GEOM)),
            func.ST_Intersects(farm.boundary, other.boundary),
        )
        .order_by(func.ST_Area(func.ST_Intersection(farm.boundary, other.boundary)).desc())
        .limit(1)
        .lateral("overlap")
    )
    stmt = (
        select(
            farm,
            valid.label("valid"),
            cast(func.ST_Area(farm.boundary), Float).label("area_m2"),
            overlap,
        )
        .join(Farmer, Farmer.id == farm.farmer_id)
        .outerjoin(overlap, true())
        .where(
            and_(
                farm.tenant_id == ctx.tenant_id,
                farm.deleted_at.is_(None),
                Farmer.deleted_at.is_(None),
                farm.boundary.is_not(None),
            )
        )
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(farm.farmer_id.in_(ctx.subject_ids))
    findings: list[Finding] = []
    for row in (await ctx.session.execute(stmt)).all():
        f: Farm = row[0]
        reasons: list[str] = []
        metrics: dict[str, object] = {"declared_acres": float(f.area_acres)}
        if not row.valid:
            reasons.append("self_intersection")
        measured = f.area_acres_computed
        if measured is not None:
            metrics["measured_acres"] = float(measured)
            if row.valid and (
                measured <= 0 or abs(measured - f.area_acres) / f.area_acres > tolerance
            ):
                reasons.append("area_mismatch")
        records = [record("farmer", f.farmer_id), record("farm", f.id)]
        if row.overlap_m2 is not None and row.area_m2:
            share = float(row.overlap_m2) / float(row.area_m2)
            metrics["overlap_share"] = round(share, 3)
            if share > max_overlap:
                reasons.append("farm_overlap")
                records += [
                    record("farm", row.other_farm_id),
                    record("farmer", row.other_farmer_id),
                ]
        if not reasons:
            continue
        metrics["reasons"] = reasons
        polygons = [json.loads(f.boundary_geojson)] if f.boundary_geojson else []
        findings.append(
            Finding(
                subject_type=Subject.FARMER,
                subject_id=f.farmer_id,
                key=f"farm:{f.id}",
                title="Farm boundary needs review: "
                + ", ".join(r.replace("_", " ") for r in reasons),
                evidence=Evidence(records=records, polygons=polygons, metrics=metrics),
            )
        )
    return findings
