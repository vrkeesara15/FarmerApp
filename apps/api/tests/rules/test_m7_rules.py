"""M7 rules beyond the golden fixtures: the event seams (VA-E10 through the day close's
``CashVarianceDetected``, VA-E07 through ``on_travel_claim_submitted``), the ports' null
adapters, the crop-calendar window maths, the service-area geometry and the reference seed."""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.flags.models import Flag
from farmerapp.payments import events as payment_events
from farmerapp.rules import events
from farmerapp.rules.checks.va_f05 import in_window
from farmerapp.rules.models import CropCalendar
from farmerapp.rules.ports import (
    InMemoryTravelClaims,
    NoLandCover,
    NoSegments,
    NoTravelClaims,
    TravelClaim,
    get_ports,
    override_ports,
)
from farmerapp.rules.reference import (
    TELANGANA_CROP_CALENDAR,
    StorePoint,
    seed_crop_calendar,
    service_area_setting,
)
from farmerapp.tenants.settings import ServiceArea, ServiceDistrict
from tests.rules.harness import DEFAULT_NOW, add_duty, base_world, when
from tests.rules.harness_m7 import seed_m7


def test_sowing_window_wraps_the_new_year() -> None:
    rabi = ("11-01", "01-31")
    assert in_window(date(2026, 1, 10), rabi, 0)
    assert in_window(date(2025, 11, 1), rabi, 0)
    assert not in_window(date(2026, 3, 1), rabi, 15)
    assert in_window(date(2026, 2, 14), rabi, 15)  # within the tolerance after the end
    assert in_window(date(2026, 5, 20), ("06-01", "08-15"), 15)
    assert not in_window(date(2026, 4, 1), ("06-01", "08-15"), 15)


def test_service_area_polygon_and_bbox() -> None:
    triangle = ServiceDistrict(
        code="TG-X", name="X", polygon=[[79.0, 17.0], [80.0, 17.0], [79.5, 18.0], [79.0, 17.0]]
    )
    box = ServiceDistrict(code="TG-Y", name="Y", bbox=[81.0, 17.0, 82.0, 18.0])
    area = ServiceArea(districts=[triangle, box])
    assert area.district_of(79.5, 17.2) == triangle
    assert area.district_of(79.1, 17.9) is None  # inside the triangle's box, outside it
    assert area.district_of(81.5, 17.5) == box
    setting = service_area_setting([StorePoint("WGL", "Warangal", "Telangana", 79.59, 17.97)])
    (district,) = ServiceArea.model_validate(setting).districts
    assert district.code == "TG-WGL" and district.contains(79.59, 17.97)


async def test_ports_default_to_no_rows(db_session: AsyncSession) -> None:
    ports = get_ports()
    assert isinstance(ports.segments, NoSegments)
    assert isinstance(ports.travel_claims, NoTravelClaims)
    assert isinstance(ports.land_cover, NoLandCover)
    tenant = uuid.uuid4()
    assert await ports.segments.members(db_session, tenant) == []
    assert await ports.travel_claims.claims(db_session, tenant) == []
    assert await ports.land_cover.classify(db_session, tenant, []) == {}


async def test_crop_calendar_seed_is_idempotent(db_session: AsyncSession) -> None:
    world = await base_world(db_session)
    assert await seed_crop_calendar(db_session, world.tenant_id) == len(TELANGANA_CROP_CALENDAR)
    assert await seed_crop_calendar(db_session, world.tenant_id) == 0
    count = await db_session.scalar(
        select(func.count())
        .select_from(CropCalendar)
        .where(CropCalendar.tenant_id == world.tenant_id)
    )
    assert count == len(TELANGANA_CROP_CALENDAR) == 11


async def test_cash_variance_event_raises_va_e10_in_the_close_transaction(
    db_session: AsyncSession,
) -> None:
    """The ST-006 day close dispatches ``CashVarianceDetected``; the writing subscriber runs
    VA-E10 in the same transaction (``day_close.variance``)."""
    events.register()
    world = await base_world(db_session)
    data = {"day_closes": [{"ref": "dc1", "at": "-2h", "expected": 1_000_000, "counted": 900_000}]}
    await seed_m7(db_session, world, data, DEFAULT_NOW)
    event = payment_events.CashVarianceDetected(
        tenant_id=world.tenant_id,
        day_close_id=world.refs["dc1"],
        store_id=world.refs["s1"],
        business_date=DEFAULT_NOW.date(),
        cash_expected_paise=1_000_000,
        cash_counted_paise=900_000,
        variance_paise=-100_000,
        threshold_paise=50_000,
        closed_by=world.refs["store_manager"],
        at=DEFAULT_NOW,
    )
    delivered = await payment_events.bus.dispatch(db_session, event)
    assert delivered >= 1
    flags = (
        (await db_session.execute(select(Flag).where(Flag.tenant_id == world.tenant_id)))
        .scalars()
        .all()
    )
    assert [(f.rule_id, f.subject_id, f.raised_by_mode) for f in flags] == [
        ("VA-E10", world.refs["store_manager"], "event")
    ]
    assert flags[0].evidence["metrics"]["variance_paise"] == -100_000


async def test_travel_claim_seam_raises_va_e07(db_session: AsyncSession) -> None:
    """FA-023's write path calls ``on_travel_claim_submitted``; VA-E07 reads the claim
    through the ``TravelClaimPort`` the travel package registers."""
    world = await base_world(db_session)
    await add_duty(
        db_session, world, {"ref": "d1", "start": "-30h", "end": "-22h", "km": 12.5}, DEFAULT_NOW
    )
    claim = TravelClaim(
        tenant_id=world.tenant_id,
        id=uuid.uuid4(),
        officer_id=world.refs["officer"],
        day=when("-26h", DEFAULT_NOW).date(),
        claimed_km=Decimal("30"),
        submitted_at=DEFAULT_NOW,
        duty_session_ids=(world.refs["d1"],),
    )
    with override_ports(travel_claims=InMemoryTravelClaims([claim])):
        await events.on_travel_claim_submitted(
            db_session, world.tenant_id, claim.id, officer_id=claim.officer_id, at=DEFAULT_NOW
        )
    (flag,) = (
        (await db_session.execute(select(Flag).where(Flag.tenant_id == world.tenant_id)))
        .scalars()
        .all()
    )
    assert flag.rule_id == "VA-E07" and flag.subject_id == world.refs["officer"]
    assert {"type": "ta_claim", "id": str(claim.id)} in flag.evidence["records"]
    assert flag.evidence["metrics"]["computed_km"] == 12.5
    assert isinstance(get_ports().travel_claims, NoTravelClaims)  # restored after the block
