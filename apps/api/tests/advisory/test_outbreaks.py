"""DX-013 / FM-009 / AN-006: the outbreak rule fires on seeded cluster data and not on a
steady baseline; alerts notify the district's farmers growing the crop (switchable), officers
and agronomists once; ``GET /v1/alerts`` and ``GET /v1/analytics/crop-health``."""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.models import OutbreakAlert
from farmerapp.advisory.outbreaks import WeekCount, detect_outbreaks, evaluate, week_start
from farmerapp.auth.models import UserRole
from farmerapp.db.models import Tenant
from farmerapp.diagnosis.models import CorpusProblem
from farmerapp.farmers.models import CropPlot, Farmer
from farmerapp.notifications.models import Notification
from farmerapp.tenants.settings import OutbreakSettings
from tests.advisory.conftest import FarmerLogin, approved_problem, confirmed_case
from tests.authz.conftest import Bearer, World
from tests.logcontract import assert_fields, capture, one_event

# Wednesday 2026-09-23 12:00 IST; its ISO week starts Monday 2026-09-21.
NOW = datetime(2026, 9, 23, 6, 30, tzinfo=UTC)
WEEK = date(2026, 9, 21)


def test_week_start_is_monday() -> None:
    assert week_start(date(2026, 9, 23)) == WEEK and week_start(WEEK) == WEEK
    assert week_start(date(2026, 9, 27)) == WEEK


def _counts(cases: dict[date, int]) -> dict:  # type: ignore[type-arg]
    import uuid

    key = ("Warangal", uuid.uuid4(), uuid.uuid4())
    by_week = {
        w: WeekCount(cases=n, farmers={uuid.uuid4() for _ in range(n)}) for w, n in cases.items()
    }
    return {key: by_week}


@pytest.mark.parametrize(
    ("history", "current", "fires"),
    [
        ([], 3, True),  # first cluster: mean 0
        ([], 2, False),  # below min_cases
        ([1, 1, 0, 2], 3, True),  # mean 1.0 -> 3 >= 2x
        ([3, 3, 3, 3], 5, False),  # mean 3.0 -> 5 < 6
        ([3, 3, 3, 3], 6, True),  # exactly 2x
        ([3, 3, 3, 3], 3, False),  # steady baseline
    ],
)
def test_rule(history: list[int], current: int, fires: bool) -> None:
    weeks = {WEEK - timedelta(weeks=i + 1): n for i, n in enumerate(history)}
    weeks[WEEK] = current
    (cell,) = evaluate(_counts(weeks), [WEEK], OutbreakSettings())
    assert cell.fires is fires and cell.cases == current
    assert cell.prior_mean == pytest.approx(sum(history) / 4)


async def _grow(session: AsyncSession, login: FarmerLogin, problem: CorpusProblem) -> None:
    """Give the demo farmer an active plot of the problem's crop."""
    session.add(
        CropPlot(
            tenant_id=login.plot.tenant_id,
            farm_id=login.farm.id,
            crop_id=problem.crop_id,
            season="kharif",
            sowing_date=date(2026, 7, 1),
        )
    )
    await session.flush()


async def _cluster(
    session: AsyncSession,
    world: World,
    login: FarmerLogin,
    problem: CorpusProblem,
    n: int,
    at: datetime,
) -> None:
    farmers = (
        (await session.execute(select(Farmer).where(Farmer.tenant_id == world.a.tenant.id)))
        .scalars()
        .all()
    )
    for i in range(n):
        await confirmed_case(
            session,
            tenant_id=world.a.tenant.id,
            farmer=farmers[i % len(farmers)],
            problem=problem,
            district=login.district,
            at=at - timedelta(hours=i),
            status="confirmed" if i % 2 == 0 else "answered",
        )


async def test_rule_fires_on_seeded_cluster_and_notifies_once(
    db_session: AsyncSession,
    world: World,
    login: FarmerLogin,
    caplog: pytest.LogCaptureFixture,
) -> None:
    capture(caplog)
    problem = await approved_problem(db_session, world.a.tenant.id)
    await _grow(db_session, login, problem)
    await _cluster(db_session, world, login, problem, 4, NOW)
    report = await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert len(report.fired) == 1 and len(report.created) == 1
    alert = await db_session.get_one(OutbreakAlert, report.created[0])
    assert alert.district == login.district and alert.week_start == WEEK
    assert alert.case_count == 4 and alert.crop_id == problem.crop_id
    assert (alert.iso_year, alert.iso_week) == (2026, 39)
    assert alert.rule["min_cases"] == 3 and alert.rule["ratio"] == 2.0
    notes = (
        (
            await db_session.execute(
                select(Notification).where(Notification.kind == "outbreak_alert")
            )
        )
        .scalars()
        .all()
    )
    recipients = {n.user_id: n for n in notes}
    assert login.user.id in recipients  # the farmer growing the crop in the district
    assert recipients[login.user.id].body_key == "notification.outbreak_alert.farmer.body"
    assert world.a.user(UserRole.AGRONOMIST).id in recipients
    assert login.farmer.registered_by in recipients  # their officer
    assert recipients[world.a.user(UserRole.AGRONOMIST).id].data["alert_id"] == str(alert.id)
    assert alert.notified["farmers"] >= 1 and alert.notified["agronomists"] >= 1
    line = one_event(caplog, "outbreak_alert_raised")
    assert_fields(line, tenant_id=str, alert_id=str, district=str, cases=int)
    # second run: same alert refreshed, nobody notified again
    await _cluster(db_session, world, login, problem, 1, NOW + timedelta(hours=2))
    again = await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert again.created == [] and len(again.fired) == 1
    await db_session.refresh(alert)
    assert alert.case_count == 5
    count = await db_session.scalar(
        select(func.count()).select_from(Notification).where(Notification.kind == "outbreak_alert")
    )
    assert count == len(notes)


async def test_rule_does_not_fire_on_baseline_data(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    problem = await approved_problem(db_session, world.a.tenant.id)
    for weeks_ago in range(5):  # a steady 3 cases every week, the current one included
        await _cluster(db_session, world, login, problem, 3, NOW - timedelta(weeks=weeks_ago))
    report = await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert report.cells >= 1 and report.fired == [] and report.created == []
    assert await db_session.scalar(select(func.count()).select_from(OutbreakAlert)) == 0


async def test_provisional_and_other_districts_do_not_count(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    problem = await approved_problem(db_session, world.a.tenant.id)
    farmers = (await db_session.execute(select(Farmer))).scalars().all()
    for i in range(3):
        await confirmed_case(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer=farmers[i],
            problem=problem,
            district=login.district,
            at=NOW,
            status="provisional",
        )
        await confirmed_case(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer=farmers[i],
            problem=problem,
            district=f"Elsewhere {i}",
            at=NOW,
        )
    report = await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert report.fired == []
    # answered corpus cases can be excluded by the tenant
    tenant = await db_session.get_one(Tenant, world.a.tenant.id)
    tenant.settings = {**(tenant.settings or {}), "outbreak": {"include_answered": False}}
    await db_session.flush()
    await _cluster(db_session, world, login, problem, 4, NOW)  # 2 confirmed + 2 answered
    assert (await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=NOW)).fired == []


async def test_farmer_alerts_can_be_switched_off(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    tenant = await db_session.get_one(Tenant, world.a.tenant.id)
    tenant.settings = {**(tenant.settings or {}), "outbreak": {"farmer_alerts_enabled": False}}
    await db_session.flush()
    problem = await approved_problem(db_session, world.a.tenant.id)
    await _grow(db_session, login, problem)
    await _cluster(db_session, world, login, problem, 3, NOW)
    report = await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert report.notified_farmers == 0 and report.notified_staff >= 1
    farmer_notes = await db_session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.kind == "outbreak_alert", Notification.user_id == login.user.id)
    )
    assert farmer_notes == 0


async def test_alerts_api_for_farmer_and_staff(
    client: AsyncClient,
    bearer: Bearer,
    db_session: AsyncSession,
    world: World,
    login: FarmerLogin,
) -> None:
    problem = await approved_problem(db_session, world.a.tenant.id)
    await _grow(db_session, login, problem)
    now = datetime.now(UTC)
    await _cluster(db_session, world, login, problem, 3, now - timedelta(minutes=5))
    report = await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=now)
    assert report.created
    resp = await client.get("/v1/alerts", headers=bearer(login.user))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["districts"] == [login.district]
    (item,) = body["items"]
    assert item["id"] == str(report.created[0]) and item["grows_crop"] is True
    assert item["case_count"] == 3 and item["problem_names"] and item["crop_code"]
    agronomist = world.a.user(UserRole.AGRONOMIST)
    staff = await client.get(
        "/v1/alerts", params={"district": login.district}, headers=bearer(agronomist)
    )
    assert [i["id"] for i in staff.json()["items"]] == [item["id"]]
    assert staff.json()["items"][0]["grows_crop"] is None
    none = await client.get(
        "/v1/alerts", params={"district": "Nowhere"}, headers=bearer(agronomist)
    )
    assert none.json()["items"] == []
    other = await client.get("/v1/alerts", headers=bearer(world.b.user(UserRole.OWNER)))
    assert other.json()["items"] == []


async def test_crop_health_map(
    client: AsyncClient,
    bearer: Bearer,
    db_session: AsyncSession,
    world: World,
    login: FarmerLogin,
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.INFO)
    problem = await approved_problem(db_session, world.a.tenant.id)
    now = datetime.now(UTC)
    await _cluster(db_session, world, login, problem, 1, now - timedelta(weeks=2))
    await _cluster(db_session, world, login, problem, 4, now - timedelta(minutes=5))
    await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=now)
    resp = await client.get(
        "/v1/analytics/crop-health", params={"weeks": 4}, headers=bearer(world.a.owner)
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["weeks"] == 4 and body["rule"]["min_cases"] == 3
    cells = [c for c in body["items"] if c["district"] == login.district]
    assert [c["confirmed_cases"] for c in cells] == [1, 4]
    assert [c["outbreak"] for c in cells] == [False, True]
    assert cells[1]["alert_id"] is not None and cells[0]["alert_id"] is None
    assert cells[1]["prior_mean"] == 0.25
    assert "latitude" not in resp.text and "farmer_id" not in resp.text  # district level only
    filtered = await client.get(
        "/v1/analytics/crop-health",
        params={"district": "Nowhere"},
        headers=bearer(world.a.user(UserRole.AGRONOMIST)),
    )
    assert filtered.json()["items"] == []


async def test_owner_home_crop_health_card_lists_the_active_alerts(
    client: AsyncClient,
    bearer: Bearer,
    db_session: AsyncSession,
    world: World,
    login: FarmerLogin,
) -> None:
    """WC-001 / AN-006: the owner home card is no longer empty once an alert is raised, and it
    stays district-level (AN-014). The console renders `title` as it stands."""
    problem = await approved_problem(db_session, world.a.tenant.id)
    now = datetime.now(UTC)
    empty = await client.get("/v1/analytics/owner-home", headers=bearer(world.a.owner))
    assert empty.status_code == 200, empty.text
    assert empty.json()["crop_health_alerts"] == []

    await _cluster(db_session, world, login, problem, 4, now - timedelta(minutes=5))
    await detect_outbreaks(db_session, tenant_id=world.a.tenant.id, now=now)
    resp = await client.get("/v1/analytics/owner-home", headers=bearer(world.a.owner))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    card = body["crop_health_alerts"]
    assert len(card) == 1
    item = card[0]
    assert item["district"] == login.district and item["case_count"] == 4
    assert item["status"] == "active" and item["title"] and login.district in item["title"]
    assert (
        item["problem"]
        and item["week_start"]
        == week_start((now + timedelta(hours=5, minutes=30)).date()).isoformat()
    )
    assert "pending_an006" not in resp.text
    assert "latitude" not in resp.text and "farmer_id" not in resp.text

    other = await client.get("/v1/analytics/owner-home", headers=bearer(world.b.owner))
    assert other.json()["crop_health_alerts"] == []
