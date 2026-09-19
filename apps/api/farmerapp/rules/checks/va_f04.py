"""VA-F04 — farm location plausibility: the farm centroid is outside the tenant's service
districts, or on a road, water body or built-up area.

* **Service districts** — tenant setting ``service_area.districts`` (code, name, state and a
  ``bbox`` or ``polygon`` in lon / lat). The centroid (the database's generated
  ``farm.centroid``) must fall inside one of them. A tenant without districts is not checked.
* **Land cover** — ``LandCoverPort.classify`` (``farmerapp.rules.ports``) returns the dominant
  class under each farm; ``params.implausible_cover`` (built-up, water, road) flags. The
  null adapter (default until a land-cover dataset is loaded into PostGIS — human gate)
  classifies nothing, so only the district half runs.

Batch (nightly), every farm with a boundary. One flag per farm (key ``farm:<id>``) about
its farmer, listing every reason.

Params: ``check_service_area``, ``check_land_cover``, ``implausible_cover``.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select

from farmerapp.farmers.models import Farm, Farmer
from farmerapp.rules.checks.common import geo_point
from farmerapp.rules.ports import FarmLocation, LandCover, get_ports
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.settings import get_tenant_settings


@rule("VA-F04")
async def check(ctx: RuleContext) -> list[Finding]:
    settings = await get_tenant_settings(ctx.session, ctx.tenant_id)
    area = settings.service_area if bool(ctx.param("check_service_area")) else None
    if area is not None and not area.districts:
        area = None
    implausible = {LandCover(str(c)) for c in ctx.param("implausible_cover")}
    stmt = (
        select(Farm.id, Farm.farmer_id, Farm.centroid_lon, Farm.centroid_lat)
        .join(Farmer, Farmer.id == Farm.farmer_id)
        .where(
            Farm.tenant_id == ctx.tenant_id,
            Farm.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            Farm.boundary.is_not(None),
        )
        .order_by(Farm.id)
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(Farm.farmer_id.in_(ctx.subject_ids))
    rows = (await ctx.session.execute(stmt)).tuples().all()
    farms = [
        FarmLocation(farm_id=fid, lon=float(lon), lat=float(lat))
        for fid, _farmer, lon, lat in rows
        if lon is not None and lat is not None
    ]
    owners = {fid: farmer for fid, farmer, _lon, _lat in rows}
    if not farms:
        return []
    cover: dict[uuid.UUID, LandCover] = {}
    if bool(ctx.param("check_land_cover")):
        cover = dict(await get_ports().land_cover.classify(ctx.session, ctx.tenant_id, farms))
    findings: list[Finding] = []
    for farm in farms:
        reasons: list[str] = []
        if area is not None and area.district_of(farm.lon, farm.lat) is None:
            reasons.append("outside_service_area")
        land = cover.get(farm.farm_id)
        if land is not None and land in implausible:
            reasons.append(f"land_cover_{land.value}")
        if not reasons:
            continue
        farmer_id = owners[farm.farm_id]
        findings.append(
            Finding(
                subject_type=Subject.FARMER,
                subject_id=farmer_id,
                key=f"farm:{farm.farm_id}",
                title="Farm location implausible: "
                + ", ".join(r.replace("_", " ") for r in reasons),
                evidence=Evidence(
                    records=[record("farmer", farmer_id), record("farm", farm.farm_id)],
                    points=[geo_point(farm.lon, farm.lat)],
                    metrics={
                        "reasons": reasons,
                        "land_cover": land.value if land is not None else None,
                        "service_districts": [d.code for d in area.districts] if area else [],
                    },
                ),
            )
        )
    return findings
