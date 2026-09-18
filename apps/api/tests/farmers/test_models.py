"""M1 entities at the ORM level: FA-013 (2 farms, 3 crop plots), FA-012 duplicate phone,
farm geometry helpers (VA-F02/F03 groundwork), append-only consent (FM-002), audit, RLS."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.geo import ACRE_M2, offset, point_wkt, polygon_wkt
from farmerapp.db.models import AuditLog
from farmerapp.db.rls import APPEND_ONLY_TABLES
from farmerapp.db.session import clear_tenant, tenant_scope
from farmerapp.farmers.models import (
    ConsentChannel,
    ConsentPurpose,
    ConsentRecord,
    ConsentSubject,
    CropPlot,
    Farm,
    Farmer,
    IrrigationType,
    LandOwnership,
    Season,
    SoilType,
)
from farmerapp.jobs.seed import SMALL, demo_tenant_id, seed_demo
from farmerapp.tenants.models import Village
from tests.farmers.conftest import M1_TABLES, Graph

NOW = datetime(2026, 9, 18, 9, 0, tzinfo=UTC)


def square(lon: float, lat: float, side_m: float) -> str:
    return polygon_wkt(
        [
            (lon, lat),
            offset(lon, lat, side_m, 0),
            offset(lon, lat, side_m, side_m),
            offset(lon, lat, 0, side_m),
        ]
    )


async def test_farmer_with_two_farms_and_three_crop_plots(
    db_session: AsyncSession, graph: Graph
) -> None:
    """FA-013 acceptance at the model level."""
    farmer = Farmer(
        tenant_id=graph.tenant_id,
        phone="+919000155555",
        phone_last4="5555",
        name="Yadagiri Goud",
        village_id=graph.village.id,
        registered_by=graph.officer.id,
        land_ownership=LandOwnership.OWN,
    )
    db_session.add(farmer)
    await db_session.flush()
    lon, lat = 79.60, 17.97
    farms = [
        Farm(
            tenant_id=graph.tenant_id,
            farmer_id=farmer.id,
            name=f"Farm {i}",
            boundary=square(lon + i * 0.01, lat, 100.0),
            area_acres=Decimal("2.5"),
            soil=SoilType.BLACK,
            irrigation=IrrigationType.BOREWELL,
            ownership=LandOwnership.OWN,
        )
        for i in (1, 2)
    ]
    db_session.add_all(farms)
    await db_session.flush()
    plots = [
        CropPlot(
            tenant_id=graph.tenant_id,
            farm_id=farm.id,
            crop_id=graph.crops[code].id,
            variety=variety,
            season=Season.KHARIF,
            sowing_date=date(2026, 6, 20),
            area_acres=Decimal("1.0"),
        )
        for farm, code, variety in (
            (farms[0], "paddy", "MTU-1010"),
            (farms[0], "chilli", "Teja"),
            (farms[1], "cotton", "RCH-659"),
        )
    ]
    db_session.add_all(plots)
    await db_session.flush()

    farm_ids = (await db_session.execute(select(Farm.id).where(Farm.farmer_id == farmer.id))).all()
    assert len(farm_ids) == 2
    plot_rows = (
        (
            await db_session.execute(
                select(CropPlot).where(CropPlot.farm_id.in_([f.id for f in farms]))
            )
        )
        .scalars()
        .all()
    )
    assert len(plot_rows) == 3
    assert {p.crop_id for p in plot_rows} == {
        graph.crops[c].id for c in ("paddy", "chilli", "cotton")
    }
    assert farmer.version == 1 and farmer.consent_marketing is False and farmer.source == "officer"


async def test_duplicate_phone_in_tenant_is_rejected(
    db_session: AsyncSession, graph: Graph
) -> None:
    """FA-012: duplicate phone blocked (same tenant); the same phone in another tenant is fine."""
    kwargs = {
        "phone": "+919000166666",
        "phone_last4": "6666",
        "name": "A",
        "village_id": graph.village.id,
    }
    db_session.add(Farmer(tenant_id=graph.tenant_id, **kwargs))
    await db_session.flush()
    with pytest.raises(IntegrityError, match="uq_farmer_tenant_id"):
        async with db_session.begin_nested():
            db_session.add(Farmer(tenant_id=graph.tenant_id, **kwargs))
            await db_session.flush()
    async with tenant_scope(db_session, graph.other_tenant_id):
        db_session.add(
            Farmer(
                tenant_id=graph.other_tenant_id, **{**kwargs, "village_id": graph.other_village.id}
            )
        )
        await db_session.flush()


async def test_farm_area_and_centroid_are_computed_by_the_database(
    db_session: AsyncSession, graph: Graph
) -> None:
    """``ST_Area`` in acres and ``ST_Centroid`` are stored generated columns, loaded eagerly."""
    lon, lat = 79.6, 17.97
    side = (2 * ACRE_M2) ** 0.5  # a two-acre square
    farm = Farm(
        tenant_id=graph.tenant_id,
        farmer_id=graph.farmer.id,
        boundary=square(lon, lat, side),
        area_acres=Decimal("2.10"),
    )
    db_session.add(farm)
    await db_session.flush()
    assert farm.area_acres_computed is not None
    assert abs(float(farm.area_acres_computed) - 2.0) < 0.02
    assert farm.centroid is not None
    loaded = (await db_session.execute(select(Farm).where(Farm.id == farm.id))).scalar_one()
    assert loaded.centroid_lat is not None and loaded.centroid_lon is not None
    assert abs(loaded.centroid_lat - (lat + side / 2 / 111_320)) < 1e-5
    assert abs(loaded.centroid_lon - lon) < 0.001 and loaded.centroid_lon > lon
    assert loaded.boundary_geojson is not None and '"Polygon"' in loaded.boundary_geojson
    # VA-F03 groundwork: declared vs measured, overlap with another farm, all in SQL.
    ratio = await db_session.scalar(
        select(Farm.area_acres / Farm.area_acres_computed).where(Farm.id == farm.id)
    )
    assert ratio is not None and abs(float(ratio) - 1.05) < 0.02
    overlapping = Farm(
        tenant_id=graph.tenant_id,
        farmer_id=graph.farmer.id,
        boundary=square(lon + 0.0003, lat, side),
        area_acres=Decimal("2"),
    )
    db_session.add(overlapping)
    await db_session.flush()
    shared = await db_session.scalar(
        select(
            func.ST_Area(
                func.ST_Intersection(Farm.boundary, func.ST_GeogFromText(overlapping.boundary))
            )
        ).where(Farm.id == farm.id)
    )
    assert shared is not None
    assert 0 < float(shared) / (2 * ACRE_M2) < 1
    # VA-F02 groundwork: centroid within 50 m of another centroid
    near = await db_session.scalar(
        select(func.count())
        .select_from(Farm)
        .where(Farm.id != farm.id, func.ST_DWithin(Farm.centroid, farm.centroid, 50))
    )
    assert near == 1

    # A farm without a boundary yet has no computed values and can gain them later.
    bare = Farm(tenant_id=graph.tenant_id, farmer_id=graph.farmer.id, area_acres=Decimal("1"))
    db_session.add(bare)
    await db_session.flush()
    assert bare.area_acres_computed is None and bare.centroid is None
    bare.boundary = square(lon + 0.02, lat, 50.0)
    await db_session.flush()
    computed, version = (
        await db_session.execute(
            select(Farm.area_acres_computed, Farm.version).where(Farm.id == bare.id)
        )
    ).one()
    assert computed is not None and version == 2


async def test_geometry_rows_are_audited_as_json(db_session: AsyncSession, graph: Graph) -> None:
    """FA-006: creating and changing a farm (WKT in, WKB back) writes JSON-safe audit rows."""
    farm = Farm(
        tenant_id=graph.tenant_id,
        farmer_id=graph.farmer.id,
        boundary=square(79.6, 17.97, 60.0),
        area_acres=Decimal("0.9"),
        soil=SoilType.RED,
    )
    db_session.add(farm)
    await db_session.flush()
    created = (
        (
            await db_session.execute(
                select(AuditLog).where(AuditLog.entity == "farm", AuditLog.entity_id == farm.id)
            )
        )
        .scalars()
        .all()
    )
    assert len(created) == 1 and created[0].action == "farm.create"
    assert created[0].after is not None
    assert created[0].after["boundary"].startswith("SRID=4326;POLYGON")
    assert created[0].after["area_acres"] == "0.9" and created[0].after["soil"] == "red"
    loaded = (await db_session.execute(select(Farm).where(Farm.id == farm.id))).scalar_one()
    loaded.boundary = square(79.61, 17.97, 70.0)
    loaded.soil = SoilType.LOAMY
    await db_session.flush()
    rows = (
        (
            await db_session.execute(
                select(AuditLog)
                .where(AuditLog.entity == "farm", AuditLog.entity_id == farm.id)
                .order_by(AuditLog.created_at)
            )
        )
        .scalars()
        .all()
    )
    assert [r.action for r in rows] == ["farm.create", "farm.update"]
    update = rows[1]
    assert update.before is not None and update.after is not None
    assert update.before["soil"] == "red" and update.after["soil"] == "loamy"
    assert isinstance(update.before["boundary"], str)  # hex WKB as read back
    assert update.after["boundary"].startswith("SRID=4326;POLYGON")
    assert "area_acres_computed" not in update.after  # generated columns are not "changes"


async def test_crop_plot_needs_a_farm_and_a_crop(db_session: AsyncSession, graph: Graph) -> None:
    with pytest.raises(IntegrityError, match="fk_crop_plot_crop_id_crop"):
        async with db_session.begin_nested():
            db_session.add(
                CropPlot(
                    tenant_id=graph.tenant_id,
                    farm_id=graph.farm.id,
                    crop_id=uuid.uuid4(),
                    season=Season.RABI,
                    sowing_date=date(2025, 11, 5),
                )
            )
            await db_session.flush()
    with pytest.raises(IntegrityError, match="fk_crop_plot_farm_id_farm"):
        async with db_session.begin_nested():
            db_session.add(
                CropPlot(
                    tenant_id=graph.tenant_id,
                    farm_id=uuid.uuid4(),
                    crop_id=graph.crops["maize"].id,
                    season=Season.RABI,
                    sowing_date=date(2025, 11, 5),
                )
            )
            await db_session.flush()
    with pytest.raises(IntegrityError, match="ck_crop_plot_season"):
        async with db_session.begin_nested():
            db_session.add(
                CropPlot(
                    tenant_id=graph.tenant_id,
                    farm_id=graph.farm.id,
                    crop_id=graph.crops["maize"].id,
                    season="monsoon",
                    sowing_date=date(2025, 11, 5),
                )
            )
            await db_session.flush()


async def test_enum_check_constraints(db_session: AsyncSession, graph: Graph) -> None:
    for column, value, constraint in (
        ("soil", "mud", "ck_farm_soil"),
        ("irrigation", "rain", "ck_farm_irrigation"),
        ("ownership", "rented", "ck_farm_ownership"),
    ):
        with pytest.raises(IntegrityError, match=constraint):
            async with db_session.begin_nested():
                db_session.add(
                    Farm(
                        tenant_id=graph.tenant_id,
                        farmer_id=graph.farmer.id,
                        area_acres=Decimal("1"),
                        **{column: value},
                    )
                )
                await db_session.flush()
    with pytest.raises(IntegrityError, match="ck_farmer_source"):
        async with db_session.begin_nested():
            db_session.add(
                Farmer(
                    tenant_id=graph.tenant_id,
                    phone="+919000177777",
                    phone_last4="7777",
                    name="X",
                    village_id=graph.village.id,
                    source="fax",
                )
            )
            await db_session.flush()


# ------------------------------------------------------------------ consent (FM-002 data model)
def _consent(graph: Graph, purpose: str, **when: datetime) -> ConsentRecord:
    return ConsentRecord(
        tenant_id=graph.tenant_id,
        subject_type=ConsentSubject.FARMER,
        subject_id=graph.farmer.id,
        purpose=purpose,
        version="2026-09-v1",
        language="te",
        channel=ConsentChannel.APP,
        recorded_by=graph.officer.id,
        **when,
    )


async def test_consent_withdrawal_is_a_new_row(db_session: AsyncSession, graph: Graph) -> None:
    grant = _consent(graph, ConsentPurpose.MARKETING, granted_at=NOW)
    db_session.add(grant)
    await db_session.flush()
    withdraw = _consent(graph, ConsentPurpose.MARKETING, withdrawn_at=NOW.replace(day=19))
    db_session.add(withdraw)
    await db_session.flush()
    assert grant.granted and not withdraw.granted
    latest = (
        await db_session.execute(
            select(ConsentRecord)
            .where(
                ConsentRecord.subject_id == graph.farmer.id,
                ConsentRecord.purpose == ConsentPurpose.MARKETING,
            )
            .order_by(ConsentRecord.created_at.desc(), ConsentRecord.id.desc())
            .limit(1)
        )
    ).scalar_one()
    assert latest.withdrawn_at is not None and latest.id == withdraw.id
    # exactly one of granted_at / withdrawn_at
    for when in ({}, {"granted_at": NOW, "withdrawn_at": NOW}):
        with pytest.raises(IntegrityError, match="ck_consent_record_one_event"):
            async with db_session.begin_nested():
                db_session.add(_consent(graph, ConsentPurpose.DATA, **when))
                await db_session.flush()


@pytest.mark.parametrize(
    "statement",
    [
        "UPDATE consent_record SET withdrawn_at = now() WHERE id = :i",
        "DELETE FROM consent_record WHERE id = :i",
        "TRUNCATE consent_record",
    ],
)
async def test_consent_record_is_append_only(
    db_session: AsyncSession, graph: Graph, statement: str
) -> None:
    assert "consent_record" in APPEND_ONLY_TABLES
    row = _consent(graph, ConsentPurpose.DATA, granted_at=NOW)
    db_session.add(row)
    await db_session.flush()
    with pytest.raises(DBAPIError, match="permission denied"):
        async with db_session.begin_nested():
            await db_session.execute(text(statement), {"i": row.id})
    with pytest.raises(DBAPIError, match="permission denied"):
        async with db_session.begin_nested():
            row.withdrawn_at = NOW  # the ORM path is blocked too
            row.granted_at = None
            await db_session.flush()
    db_session.expire(row)


async def test_village_meeting_point_and_store_mapping(
    db_session: AsyncSession, graph: Graph
) -> None:
    """FA-014 / VV-003 need a village meeting point and the village -> store link."""
    village = Village(
        tenant_id=graph.tenant_id,
        name="Testpalli",
        district="Warangal",
        mandal="Hasanparthy",
        store_id=graph.store.id,
        location=point_wkt(79.55, 18.02),
        meeting_point=point_wkt(79.551, 18.021),
    )
    db_session.add(village)
    await db_session.flush()
    distance = await db_session.scalar(
        select(func.ST_Distance(Village.location, Village.meeting_point)).where(
            Village.id == village.id
        )
    )
    assert distance is not None and 100 < float(distance) < 200
    assert village.state == "Telangana" and village.store_id == graph.store.id


# ------------------------------------------------------------------ RLS on every M1 table
@pytest.mark.parametrize("table", M1_TABLES)
async def test_rls_hides_other_tenants_on_every_m1_table(
    db_session: AsyncSession, table: str
) -> None:
    await seed_demo(db_session, SMALL)
    fcc, gfl = demo_tenant_id("fcc"), demo_tenant_id("gfl")
    async with tenant_scope(db_session, fcc):
        rows = (await db_session.execute(text(f'SELECT tenant_id FROM "{table}"'))).all()
        assert rows and {r[0] for r in rows} == {fcc}
    async with tenant_scope(db_session, gfl):
        rows = (await db_session.execute(text(f'SELECT tenant_id FROM "{table}"'))).all()
        assert rows and {r[0] for r in rows} == {gfl}
    await clear_tenant(db_session)
    assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0


async def test_foreign_tenant_insert_is_rejected_by_rls(
    db_session: AsyncSession, graph: Graph
) -> None:
    with pytest.raises(DBAPIError, match="row-level security"):
        async with db_session.begin_nested():
            db_session.add(
                Farmer(
                    tenant_id=graph.other_tenant_id,
                    phone="+919000188888",
                    phone_last4="8888",
                    name="Intruder",
                    village_id=graph.other_village.id,
                )
            )
            await db_session.flush()


async def test_seed_writes_are_attributed_to_the_system(db_session: AsyncSession) -> None:
    result = await seed_demo(db_session, SMALL)
    async with tenant_scope(db_session, result.tenant_id):
        rows = (
            await db_session.execute(
                select(AuditLog.entity, AuditLog.actor_role, func.count())
                .where(AuditLog.action.like("%.create"))
                .group_by(AuditLog.entity, AuditLog.actor_role)
            )
        ).all()
    by_entity = {entity: (role, n) for entity, role, n in rows}
    for table in M1_TABLES:
        role, n = by_entity[table]
        assert role == audit.SYSTEM_ROLE and n >= 1, table
    assert by_entity["farmer"][1] == SMALL.farmers["fcc"]
