"""``make seed`` (SPEC 10.5): the Telangana demo tenant, idempotent, under 30 s.

Counts are asserted through the app role under each tenant's RLS scope, i.e. exactly what
the API will see. Geometry checks use PostGIS (no shapely in the test suite either).
"""

from __future__ import annotations

import time
import uuid
from decimal import Decimal

import pytest
from geoalchemy2 import Geometry
from sqlalchemy import cast, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import PILOT_CROPS, Crop
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import ConsentPurpose, ConsentRecord, CropPlot, Farm, Farmer, Season
from farmerapp.jobs.seed import (
    DEMO_TENANTS,
    FULL,
    SEEDED_TABLES,
    SMALL,
    SeedResult,
    demo_tenant_id,
    seed_demo,
)
from farmerapp.tenants.models import Cluster, Store, Village

FCC = demo_tenant_id("fcc")
GFL = demo_tenant_id("gfl")
TELANGANA_DISTRICTS = {"Warangal", "Karimnagar", "Nalgonda", "Khammam", "Nizamabad"}


async def _count(session: AsyncSession, model: type) -> int:
    return int(await session.scalar(select(func.count()).select_from(model)) or 0)


# Timing-sensitive (SPEC 10.5: the full seed under 30 s): it measures wall clock, so it runs
# in the serial phase, alone on the machine — under the parallel phase's ten xdist workers the
# same seed takes over 30 s on a busy laptop without anything being wrong.
@pytest.mark.serial
async def test_full_seed_counts_and_duration(db_session: AsyncSession) -> None:
    started = time.perf_counter()
    result = await seed_demo(db_session, FULL)
    elapsed = time.perf_counter() - started
    assert elapsed < 30, f"seed took {elapsed:.1f}s"

    assert result.totals["farmer"] == 210 and result.created["farmer"] == 210
    assert result.totals["store"] == 6 and result.totals["cluster"] == 3
    assert result.totals["village"] == 48
    assert result.totals["crop"] == 12  # six pilot crops per tenant
    assert result.created == result.totals  # empty database before

    async with tenant_scope(db_session, FCC):
        assert await _count(db_session, Farmer) == 200
        assert await _count(db_session, Village) == 40
        assert await _count(db_session, Cluster) == 2
        stores = (await db_session.execute(select(Store))).scalars().all()
        assert {s.district for s in stores} == TELANGANA_DISTRICTS
        assert all(s.state == "Telangana" and s.cluster_id is not None for s in stores)
        officers = (
            (await db_session.execute(select(User).where(User.role == UserRole.FIELD_OFFICER)))
            .scalars()
            .all()
        )
        assert len(officers) == 5
        assert {o.store_id for o in officers} == {s.id for s in stores}  # one per store
        assert all(o.cluster_id is not None for o in officers)
        farms = await _count(db_session, Farm)
        assert 200 <= farms <= 400
        plots = await _count(db_session, CropPlot)
        assert farms <= plots <= 2 * farms
        crops = {c.code for c in (await db_session.execute(select(Crop))).scalars()}
        assert crops == {code for code, *_ in PILOT_CROPS}
        # every officer registered farmers, every village has some
        by_officer = (
            await db_session.execute(
                select(Farmer.registered_by, func.count()).group_by(Farmer.registered_by)
            )
        ).all()
        assert len(by_officer) == 5 and all(n == 40 for _, n in by_officer)
        by_village = (
            await db_session.execute(
                select(Farmer.village_id, func.count()).group_by(Farmer.village_id)
            )
        ).all()
        assert len(by_village) == 40 and all(n == 5 for _, n in by_village)

    async with tenant_scope(db_session, GFL):
        assert await _count(db_session, Farmer) == 10
        assert await _count(db_session, Store) == 1
        assert await _count(db_session, Village) == 8
        officers = (
            (await db_session.execute(select(User).where(User.role == UserRole.FIELD_OFFICER)))
            .scalars()
            .all()
        )
        assert len(officers) == 1


async def test_seed_is_idempotent(db_session: AsyncSession) -> None:
    first = await seed_demo(db_session, SMALL)
    second = await seed_demo(db_session, SMALL)
    assert second.users_created == 0
    assert all(n == 0 for n in second.created.values()), second.created
    assert second.totals == first.totals
    assert first.totals["farmer"] == SMALL.farmers["fcc"] + SMALL.farmers["gfl"]
    # The full profile on top of the small one only adds what is missing.
    third = await seed_demo(db_session, FULL)
    assert third.created["farmer"] == 210 - first.totals["farmer"]
    assert third.totals["farmer"] == 210 and third.totals["store"] == 6
    fourth = await seed_demo(db_session, FULL)
    assert all(n == 0 for n in fourth.created.values())


async def test_seed_result_shape(db_session: AsyncSession) -> None:
    result = await seed_demo(db_session, SMALL)
    assert isinstance(result, SeedResult)
    assert set(result.created) == set(result.totals) == set(SEEDED_TABLES)
    assert [slug for slug, _ in result.tenants] == [t.slug for t in DEMO_TENANTS]


async def test_farm_polygons_are_valid_sized_and_do_not_overlap(db_session: AsyncSession) -> None:
    await seed_demo(db_session, FULL)
    async with tenant_scope(db_session, FCC):
        rows = (
            await db_session.execute(
                select(
                    Farm.area_acres,
                    Farm.area_acres_computed,
                    func.ST_IsValid(cast(Farm.boundary, Geometry())),
                    func.ST_NumPoints(func.ST_ExteriorRing(cast(Farm.boundary, Geometry()))),
                )
            )
        ).all()
        assert rows
        for declared, computed, valid, points in rows:
            assert valid is True
            assert points == 5  # four corners, closed
            assert computed is not None and Decimal("0.4") <= computed <= Decimal("5.5")
            # VA-F03: declared acres within ±30% of the measured polygon
            assert abs(float(declared) - float(computed)) / float(computed) < 0.3
        overlaps = await db_session.scalar(
            text(
                "SELECT count(*) FROM farm a JOIN farm b ON a.id < b.id "
                "AND ST_Intersects(a.boundary, b.boundary) "
                "AND ST_Area(ST_Intersection(a.boundary, b.boundary)) > 1"
            )
        )
        assert overlaps == 0
        # centroids are inside the boundary and the village is a few km from its store
        outside = await db_session.scalar(
            text("SELECT count(*) FROM farm WHERE NOT ST_Covers(boundary, centroid)")
        )
        assert outside == 0
        far = await db_session.scalar(
            text(
                "SELECT count(*) FROM village v JOIN store s ON s.id = v.store_id "
                "WHERE ST_Distance(v.location, s.location) NOT BETWEEN 5000 AND 25000"
            )
        )
        assert far == 0
        near = await db_session.scalar(
            text(
                "SELECT count(*) FROM farm f JOIN farmer fr ON fr.id = f.farmer_id "
                "JOIN village v ON v.id = fr.village_id "
                "WHERE ST_Distance(f.centroid, v.location) > 3000"
            )
        )
        assert near == 0


async def test_farmers_farms_plots_and_consents(db_session: AsyncSession) -> None:
    await seed_demo(db_session, FULL)
    async with tenant_scope(db_session, FCC):
        farmers = (await db_session.execute(select(Farmer))).scalars().all()
        assert len(farmers) == 200
        assert len({f.phone for f in farmers}) == 200
        assert all(f.phone_last4 == f.phone[-4:] and f.language == "te" for f in farmers)
        assert all(f.registered_by is not None and f.source == "officer" for f in farmers)
        assert all(f.land_ownership in ("own", "leased") for f in farmers)
        assert 0.4 < sum(f.consent_marketing for f in farmers) / 200 < 0.75
        # the demo farmer login owns one farmer record
        linked = [f for f in farmers if f.user_id is not None]
        assert len(linked) == 1 and linked[0].phone == "+919000000010"

        per_farmer: dict[uuid.UUID, int] = {
            farmer_id: n
            for farmer_id, n in (
                await db_session.execute(
                    select(Farm.farmer_id, func.count()).group_by(Farm.farmer_id)
                )
            ).all()
        }
        assert set(per_farmer.values()) == {1, 2} and len(per_farmer) == 200

        plots = (await db_session.execute(select(CropPlot))).scalars().all()
        assert {p.season for p in plots} == {Season.KHARIF, Season.RABI}
        assert all(p.variety and p.stage and p.expected_harvest for p in plots)
        assert all(p.expected_harvest > p.sowing_date for p in plots if p.expected_harvest)
        assert all(p.area_acres is not None and p.area_acres > 0 for p in plots)
        kharif = [p for p in plots if p.season == Season.KHARIF]
        assert all(p.sowing_date.year == 2026 and p.sowing_date.month in (6, 7) for p in kharif)

        consents = (await db_session.execute(select(ConsentRecord))).scalars().all()
        data = [c for c in consents if c.purpose == ConsentPurpose.DATA]
        assert len(data) == 200 and all(c.granted_at is not None for c in data)
        marketing = [c for c in consents if c.purpose == ConsentPurpose.MARKETING]
        granted = {c.subject_id for c in marketing if c.granted_at is not None}
        withdrawn = {c.subject_id for c in marketing if c.withdrawn_at is not None}
        assert withdrawn <= granted and withdrawn
        cache = {f.id: f.consent_marketing for f in farmers}
        assert all(cache[s] is False for s in withdrawn)
        assert all(cache[s] is True for s in granted - withdrawn)
        assert all(cache[f.id] is False for f in farmers if f.id not in granted)
        assert all(c.channel == "officer" and c.version == "2026-09-v1" for c in consents)


async def test_tenants_do_not_see_each_other(db_session: AsyncSession) -> None:
    await seed_demo(db_session, SMALL)
    async with tenant_scope(db_session, GFL):
        farmers = (await db_session.execute(select(Farmer))).scalars().all()
        assert farmers and all(f.tenant_id == GFL for f in farmers)
        assert all(f.phone.startswith("+9191") for f in farmers)
    async with tenant_scope(db_session, uuid.uuid4()):
        assert await _count(db_session, Farmer) == 0
