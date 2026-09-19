"""M7 rules beyond the golden fixtures: the event seams (VA-E10 through the day close's
``CashVarianceDetected``, VA-E07 through ``on_travel_claim_submitted``), the ports' null
adapters, the crop-calendar window maths, the service-area geometry and the reference seed."""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.duty.models import TrackGap
from farmerapp.duty.processing import process_session
from farmerapp.flags.models import Flag
from farmerapp.location.models import DutySession
from farmerapp.payments import events as payment_events
from farmerapp.rules import events
from farmerapp.rules.checks.va_f05 import in_window
from farmerapp.rules.models import CropCalendar
from farmerapp.rules.ports import (
    InMemoryTravelClaims,
    NoLandCover,
    NoSegments,
    NoTravelClaims,
    Ports,
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
from tests.rules.harness import DEFAULT_NOW, add_duty, base_world, run_fixture, seed, when
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
    ports = Ports()  # the defaults (the app registers the travel package's real adapter)
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
    assert not isinstance(get_ports().travel_claims, InMemoryTravelClaims)  # restored


# --------------------------------------------------------------------------- VA-E06 x VV-006
def _stationary(duty: str, hours: list[float], **extra: Any) -> list[dict[str, Any]]:
    """A fix every 10 minutes at the origin over each ``(from_h, to_h)`` pair (hours ago)."""
    out: list[dict[str, Any]] = []
    for lo, hi in zip(hours[::2], hours[1::2], strict=True):
        for step in range(round((lo - hi) * 60) // 10 + 1):
            ago = lo * 60 - step * 10  # minutes ago
            out.append(
                {"duty": duty, "at": f"-{ago / 60:.4f}h", "east_m": 0, "north_m": 0, **extra}
            )
    return out


async def _processed_vs_raw(db_session: AsyncSession, data: dict[str, Any]) -> list[Flag]:
    """Seed the same track for ``officer`` (session ``p``, processed by VV-006 at duty end)
    and ``officer2`` (session ``r``, never processed), then run VA-E06."""
    world = await base_world(db_session)
    await seed(db_session, world, data, DEFAULT_NOW)
    duty = await db_session.get_one(DutySession, world.refs["p"])
    await process_session(db_session, duty, now=DEFAULT_NOW)
    assert duty.processed_at is not None
    _world, outcome = await run_fixture(db_session, "VA-E06", {"mode": "batch"}, world=world)
    return outcome.flags


def _both(points: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [p for spec in points for p in ({**spec, "duty": "p"}, {**spec, "duty": "r"})]


async def test_va_e06_does_not_count_a_track_gap_as_idle(db_session: AsyncSession) -> None:
    """Six hours of duty at one spot with a 3.5 h tracking outage in the middle (a VV-006
    gap, explained through VV-008): the processed session has at most 1.5 h of observed
    idleness; the unprocessed one reads the outage as 3.5 h idle (the raw pass)."""
    points = _both(_stationary("x", [7, 5.5, 2, 1]))
    data = {
        "seed": {
            "duty": [
                {"ref": "p", "officer": "officer", "start": "-7h", "end": "-1h"},
                {"ref": "r", "officer": "officer2", "start": "-7h", "end": "-1h"},
            ],
            "points": points,
        }
    }
    flags = await _processed_vs_raw(db_session, data)
    assert len(flags) == 1
    (flag,) = flags
    assert flag.evidence["metrics"]["track_processed"] is False
    assert flag.evidence["metrics"]["gap_minutes_excluded"] == 0
    gaps = (await db_session.execute(select(TrackGap))).scalars().all()
    assert len(gaps) == 1 and gaps[0].duration_s == int(3.5 * 3600)


async def test_va_e06_ignores_gps_jitter_on_processed_tracks(db_session: AsyncSession) -> None:
    """Five hours at one spot with one bad fix 5 km away (a > 90 km/h jump the VV-006 filter
    drops): the raw pass reads the jump as two movements and splits the idle time; the
    processed session is one stop and raises the idle flag."""
    points = _stationary("x", [6, 1])
    points.append({"duty": "x", "at": "-3.49h", "east_m": 5000, "north_m": 0})
    data = {
        "seed": {
            "duty": [
                {"ref": "p", "officer": "officer", "start": "-6h", "end": "-1h"},
                {"ref": "r", "officer": "officer2", "start": "-6h", "end": "-1h"},
            ],
            "points": _both(points),
        }
    }
    flags = await _processed_vs_raw(db_session, data)
    assert [f.evidence["metrics"]["track_processed"] for f in flags] == [True]
    (flag,) = flags
    assert flag.evidence["metrics"]["idle_minutes"] >= 4 * 60
