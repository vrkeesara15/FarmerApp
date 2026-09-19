"""FM-007 crop calendar: templates seeded for the pilot crops, generation from the sowing date,
regeneration when the sowing date / crop / templates change (done tasks kept), task updates,
reminders (quiet hours, once), the sync entity and template maintenance."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.calendar import calendar_reminders, ensure_calendar, plot_tasks
from farmerapp.advisory.models import CropPlotTask, CropTaskTemplate, TaskStatus
from farmerapp.advisory.templates import PILOT_CALENDARS, TITLES
from farmerapp.auth.models import UserRole
from farmerapp.catalog.crops import PILOT_CROPS, Crop
from farmerapp.db.models import Tenant
from farmerapp.farmers.models import CropPlot
from farmerapp.notifications.models import Notification
from farmerapp.sync.models import SyncChange
from tests.advisory.conftest import FarmerLogin
from tests.authz.conftest import Bearer, World


async def _templates(session: AsyncSession, tenant_id: uuid.UUID, crop_id: uuid.UUID) -> int:
    return int(
        await session.scalar(
            select(func.count())
            .select_from(CropTaskTemplate)
            .where(CropTaskTemplate.tenant_id == tenant_id, CropTaskTemplate.crop_id == crop_id)
        )
        or 0
    )


# ------------------------------------------------------------------ seed + generation
async def test_seed_has_templates_for_the_six_pilot_crops(
    db_session: AsyncSession, world: World
) -> None:
    assert set(PILOT_CALENDARS) == {code for code, *_ in PILOT_CROPS}
    crops = (
        await db_session.execute(select(Crop).where(Crop.tenant_id == world.a.tenant.id))
    ).scalars()
    for crop in crops:
        if crop.code in PILOT_CALENDARS:
            assert await _templates(db_session, world.a.tenant.id, crop.id) == len(
                PILOT_CALENDARS[crop.code]
            )
    row = await db_session.scalar(select(CropTaskTemplate).limit(1))
    assert row is not None and set(row.titles) == {"en", "te", "hi", "kn", "mr"}
    assert set(row.instructions) == {"en", "te", "hi", "kn", "mr"}
    assert all(set(t) == {"en", "te", "hi", "kn", "mr"} for t in TITLES.values())
    # The seed is idempotent: a second run adds nothing.
    from farmerapp.advisory.templates import seed_crop_task_templates

    assert await seed_crop_task_templates(db_session, world.a.tenant.id) == 0


async def test_my_calendar_is_generated_from_the_sowing_date(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, db_session: AsyncSession
) -> None:
    resp = await client.get("/v1/me/calendar", headers=bearer(login.user))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["farmer_id"] == str(login.farmer.id)
    plot = next(p for p in body["plots"] if p["crop_plot_id"] == str(login.plot.id))
    expected = PILOT_CALENDARS[login.crop.code]
    assert len(plot["tasks"]) == len(expected)
    by_key = {t["task_key"]: t for t in plot["tasks"]}
    for task in expected:
        got = by_key[f"{login.crop.code}.{task.key}"]
        due = login.plot.sowing_date + timedelta(days=task.day_offset)
        assert got["due_date"] == due.isoformat()
        assert got["end_date"] == (due + timedelta(days=task.duration_days - 1)).isoformat()
        assert got["task_type"] == task.task_type.value
        assert got["titles"]["en"] and got["instructions"]["te"]
        assert got["status"] == "pending" and got["reminder_enabled"] is True
    assert {t["task_type"] for t in plot["tasks"]} >= {"sow", "fertilise", "spray", "harvest"}
    # Reading again generates nothing new (idempotent).
    again = await client.get("/v1/me/calendar", headers=bearer(login.user))
    assert [t["id"] for p in again.json()["plots"] for t in p["tasks"]] == [
        t["id"] for p in body["plots"] for t in p["tasks"]
    ]
    # Every task is in the sync feed (offline calendar).
    changes = await db_session.scalar(
        select(func.count()).select_from(SyncChange).where(SyncChange.entity == "crop_plot_task")
    )
    assert changes == sum(len(p["tasks"]) for p in body["plots"])


async def test_sowing_date_change_regenerates_pending_and_keeps_done(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, db_session: AsyncSession, world: World
) -> None:
    await ensure_calendar(db_session, login.plot)
    tasks = await plot_tasks(db_session, login.plot.id)
    done, muted = tasks[0], tasks[1]
    resp = await client.patch(
        f"/v1/calendar/tasks/{done.id}", json={"status": "done"}, headers=bearer(login.user)
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "done" and resp.json()["done_at"]
    resp = await client.patch(
        f"/v1/calendar/tasks/{muted.id}",
        json={"reminder_enabled": False},
        headers=bearer(login.user),
    )
    assert resp.status_code == 200 and resp.json()["reminder_enabled"] is False
    done_due = done.due_date

    officer = world.a.user(UserRole.FIELD_OFFICER)
    new_sowing = login.plot.sowing_date + timedelta(days=10)
    owner_of_plot = login.farmer.registered_by
    actor = next(u for u in world.a.everyone if u.id == owner_of_plot) if owner_of_plot else officer
    resp = await client.patch(
        f"/v1/crop-plots/{login.plot.id}",
        json={"sowing_date": new_sowing.isoformat()},
        headers=bearer(actor),
    )
    assert resp.status_code == 200, resp.text
    after = {t.id: t for t in await plot_tasks(db_session, login.plot.id)}
    assert set(after) == {t.id for t in tasks}  # updated in place, ids stable for the app
    assert after[done.id].status == "done" and after[done.id].due_date == done_due
    moved = after[muted.id]
    assert moved.due_date == muted.due_date  # same object, refreshed below
    await db_session.refresh(moved)
    template = PILOT_CALENDARS[login.crop.code]
    offsets = {f"{login.crop.code}.{t.key}": t.day_offset for t in template}
    assert moved.due_date == new_sowing + timedelta(days=offsets[moved.task_key])
    assert moved.reminder_enabled is False  # the farmer's switch survives
    assert moved.basis_sowing_date == new_sowing


async def test_crop_change_replaces_pending_tasks(
    db_session: AsyncSession, login: FarmerLogin, world: World
) -> None:
    from farmerapp.farmers import service as farmers
    from farmerapp.farmers.schemas import CropPlotUpdate

    await ensure_calendar(db_session, login.plot)
    first = (await plot_tasks(db_session, login.plot.id))[0]
    first.status = TaskStatus.DONE.value
    first.done_at = datetime.now(UTC)
    await db_session.flush()
    other = (
        (
            await db_session.execute(
                select(Crop).where(
                    Crop.tenant_id == world.a.tenant.id,
                    Crop.code != login.crop.code,
                    Crop.code.in_(list(PILOT_CALENDARS)),
                )
            )
        )
        .scalars()
        .first()
    )
    assert other is not None
    await farmers.update_crop_plot(db_session, login.plot, CropPlotUpdate(crop_id=other.id))
    tasks = await plot_tasks(db_session, login.plot.id)
    keys = {t.task_key for t in tasks}
    assert first.id in {t.id for t in tasks}  # done history kept
    assert {f"{other.code}.{t.key}" for t in PILOT_CALENDARS[other.code]} <= keys
    assert not any(
        t.task_key.startswith(f"{login.crop.code}.") and t.status == "pending" for t in tasks
    )


async def test_template_change_and_delete_follow_on_next_read(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, db_session: AsyncSession, world: World
) -> None:
    await ensure_calendar(db_session, login.plot)
    agronomist = world.a.user(UserRole.AGRONOMIST)
    listed = await client.get(
        "/v1/calendar/templates", params={"crop_id": str(login.crop.id)}, headers=bearer(agronomist)
    )
    assert listed.status_code == 200
    items = listed.json()["items"]
    assert len(items) == len(PILOT_CALENDARS[login.crop.code])
    target, dropped = items[-1], items[-2]
    resp = await client.patch(
        f"/v1/calendar/templates/{target['id']}",
        json={"day_offset": target["day_offset"] + 3, "version": target["version"]},
        headers=bearer(agronomist),
    )
    assert resp.status_code == 200, resp.text
    resp = await client.delete(
        f"/v1/calendar/templates/{dropped['id']}", headers=bearer(agronomist)
    )
    assert resp.status_code == 204
    cal = await client.get("/v1/me/calendar", headers=bearer(login.user))
    plot = next(p for p in cal.json()["plots"] if p["crop_plot_id"] == str(login.plot.id))
    by_key = {t["task_key"]: t for t in plot["tasks"]}
    assert dropped["task_key"] not in by_key
    assert (
        by_key[target["task_key"]]["due_date"]
        == (login.plot.sowing_date + timedelta(days=target["day_offset"] + 3)).isoformat()
    )
    # stale version
    stale = await client.patch(
        f"/v1/calendar/templates/{target['id']}",
        json={"sort_order": 1, "version": target["version"]},
        headers=bearer(agronomist),
    )
    assert stale.status_code == 409 and stale.json()["code"] == "version_conflict"


async def test_template_create_rules(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, world: World
) -> None:
    agronomist = world.a.user(UserRole.AGRONOMIST)
    body = {
        "crop_id": str(login.crop.id),
        "season": "rabi",
        "task_key": f"{login.crop.code}.rabi_extra_irrigation",
        "task_type": "irrigate",
        "day_offset": 12,
        "titles": {"en": "Extra irrigation", "te": "అదనపు నీరు"},
        "instructions": {"en": "Rabi only."},
    }
    resp = await client.post("/v1/calendar/templates", json=body, headers=bearer(agronomist))
    assert resp.status_code == 201, resp.text
    assert resp.json()["season"] == "rabi"
    dup = await client.post("/v1/calendar/templates", json=body, headers=bearer(agronomist))
    assert dup.status_code == 409 and dup.json()["code"] == "template_exists"
    no_en = await client.post(
        "/v1/calendar/templates",
        json={**body, "task_key": "x.no_english", "titles": {"te": "..."}},
        headers=bearer(agronomist),
    )
    assert no_en.status_code == 422
    bad_crop = await client.post(
        "/v1/calendar/templates",
        json={**body, "task_key": "x.bad", "crop_id": str(uuid.uuid4())},
        headers=bearer(agronomist),
    )
    assert bad_crop.status_code == 404


async def test_season_template_overrides_the_default(
    db_session: AsyncSession, login: FarmerLogin
) -> None:
    from farmerapp.advisory.calendar import effective_templates

    base = await effective_templates(
        db_session, login.plot.tenant_id, login.plot.crop_id, login.plot.season
    )
    first = base[0]
    db_session.add(
        CropTaskTemplate(
            tenant_id=first.tenant_id,
            crop_id=first.crop_id,
            season=login.plot.season,
            task_key=first.task_key,
            task_type=first.task_type,
            day_offset=first.day_offset + 5,
            duration_days=1,
            titles={"en": "Season specific"},
            instructions={},
        )
    )
    await db_session.flush()
    again = await effective_templates(
        db_session, login.plot.tenant_id, login.plot.crop_id, login.plot.season
    )
    assert len(again) == len(base)
    chosen = next(t for t in again if t.task_key == first.task_key)
    assert chosen.season == login.plot.season and chosen.day_offset == first.day_offset + 5


async def test_task_update_scope_and_version(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, db_session: AsyncSession, world: World
) -> None:
    await ensure_calendar(db_session, login.plot)
    task = (await plot_tasks(db_session, login.plot.id))[0]
    stale = await client.patch(
        f"/v1/calendar/tasks/{task.id}",
        json={"status": "done", "version": task.version + 5},
        headers=bearer(login.user),
    )
    assert stale.status_code == 409 and stale.json()["code"] == "version_conflict"
    empty = await client.patch(f"/v1/calendar/tasks/{task.id}", json={}, headers=bearer(login.user))
    assert empty.status_code == 422
    # another tenant's officer never sees it
    foreign = world.b.user(UserRole.FIELD_OFFICER)
    resp = await client.patch(
        f"/v1/calendar/tasks/{task.id}", json={"status": "done"}, headers=bearer(foreign)
    )
    assert resp.status_code == 404
    # undo
    await client.patch(
        f"/v1/calendar/tasks/{task.id}", json={"status": "done"}, headers=bearer(login.user)
    )
    undone = await client.patch(
        f"/v1/calendar/tasks/{task.id}", json={"status": "pending"}, headers=bearer(login.user)
    )
    assert undone.json()["status"] == "pending" and undone.json()["done_at"] is None


async def test_officer_reads_a_farmers_calendar(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, world: World
) -> None:
    officer = next(u for u in world.a.everyone if u.id == login.farmer.registered_by)
    resp = await client.get(
        f"/v1/farmers/{login.farmer.id}/calendar",
        params={"crop_plot_id": str(login.plot.id)},
        headers=bearer(officer),
    )
    assert resp.status_code == 200, resp.text
    assert [p["crop_plot_id"] for p in resp.json()["plots"]] == [str(login.plot.id)]
    other = world.b.user(UserRole.OWNER)
    assert (
        await client.get(f"/v1/farmers/{login.farmer.id}/calendar", headers=bearer(other))
    ).status_code == 404


async def test_deleting_the_plot_removes_pending_tasks(
    db_session: AsyncSession, login: FarmerLogin
) -> None:
    from farmerapp.farmers import service as farmers

    await ensure_calendar(db_session, login.plot)
    tasks = await plot_tasks(db_session, login.plot.id)
    tasks[0].status = "done"
    tasks[0].done_at = datetime.now(UTC)
    await db_session.flush()
    await farmers.delete_crop_plot(db_session, login.plot)
    left = await plot_tasks(db_session, login.plot.id)
    assert [t.id for t in left] == [tasks[0].id]


# ------------------------------------------------------------------ reminders
IST_07_30 = datetime(2026, 9, 21, 2, 0, tzinfo=UTC)  # 07:30 IST, a Monday


async def _due_today(session: AsyncSession, login: FarmerLogin, now: datetime) -> CropPlotTask:
    today = (now + timedelta(hours=5, minutes=30)).date()
    template = PILOT_CALENDARS[login.crop.code][2]
    login.plot.sowing_date = today - timedelta(days=template.day_offset)
    await session.flush()
    await ensure_calendar(session, login.plot, now=now)
    task = next(
        t
        for t in await plot_tasks(session, login.plot.id)
        if t.task_key == f"{login.crop.code}.{template.key}"
    )
    assert task.due_date == today
    return task


async def _reminders(session: AsyncSession) -> list[Notification]:
    return list(
        (
            await session.execute(
                select(Notification).where(Notification.kind == "crop_task_reminder")
            )
        ).scalars()
    )


async def test_reminders_are_written_once_for_tasks_due_today(
    db_session: AsyncSession, login: FarmerLogin, world: World
) -> None:
    task = await _due_today(db_session, login, IST_07_30)
    report = await calendar_reminders(db_session, tenant_id=world.a.tenant.id, now=IST_07_30)
    assert report.state == "sent" and task.id in report.reminded
    notes = [n for n in await _reminders(db_session) if n.data["task_id"] == str(task.id)]
    assert len(notes) == 1 and notes[0].user_id == login.user.id
    assert notes[0].title_key == "notification.crop_task_reminder.title"
    assert notes[0].data["due_date"] == task.due_date.isoformat()
    assert task.reminded_at == IST_07_30
    again = await calendar_reminders(
        db_session, tenant_id=world.a.tenant.id, now=IST_07_30 + timedelta(hours=1)
    )
    assert task.id not in again.reminded
    assert len([n for n in await _reminders(db_session) if n.data["task_id"] == str(task.id)]) == 1


async def test_reminders_respect_quiet_hours_start_time_and_the_switch(
    db_session: AsyncSession, login: FarmerLogin, world: World
) -> None:
    task = await _due_today(db_session, login, IST_07_30)
    night = datetime(2026, 9, 20, 17, 0, tzinfo=UTC)  # 22:30 IST
    quiet = await calendar_reminders(db_session, tenant_id=world.a.tenant.id, now=night)
    assert quiet.state == "quiet_hours" and quiet.reminded == []
    tenant = await db_session.get_one(Tenant, world.a.tenant.id)
    tenant.settings = {
        **(tenant.settings or {}),
        "quiet_hours": {"start": "22:00", "end": "06:00"},
        "calendar_reminders": {"local_time": "08:00", "lookback_days": 2},
    }
    await db_session.flush()
    early = await calendar_reminders(db_session, tenant_id=world.a.tenant.id, now=IST_07_30)
    assert early.state == "too_early"
    task.reminder_enabled = False
    await db_session.flush()
    later = await calendar_reminders(
        db_session, tenant_id=world.a.tenant.id, now=IST_07_30 + timedelta(hours=1)
    )
    assert later.state == "sent" and task.id not in later.reminded


async def test_quiet_hours_window_maths() -> None:
    from datetime import time

    from farmerapp.tenants.settings import QuietHours

    wrap = QuietHours(start="21:00", end="07:00")
    assert wrap.contains(time(22, 0)) and wrap.contains(time(6, 59))
    assert not wrap.contains(time(7, 0)) and not wrap.contains(time(12, 0))
    day = QuietHours(start="13:00", end="15:00")
    assert day.contains(time(14, 0)) and not day.contains(time(15, 0))
    assert not QuietHours(start="10:00", end="10:00").contains(time(10, 0))


async def test_the_job_generates_calendars_for_every_active_plot(
    db_session: AsyncSession, world: World
) -> None:
    before = await db_session.scalar(select(func.count()).select_from(CropPlotTask))
    assert before == 0
    report = await calendar_reminders(db_session, tenant_id=world.a.tenant.id, now=IST_07_30)
    plots = await db_session.scalar(
        select(func.count()).select_from(CropPlot).where(CropPlot.tenant_id == world.a.tenant.id)
    )
    assert report.plots_checked > 0 and report.plots_checked <= (plots or 0)
    assert report.tasks_generated == await db_session.scalar(
        select(func.count()).select_from(CropPlotTask)
    )


# ------------------------------------------------------------------ sync
async def test_sync_update_marks_a_task_done_and_create_is_rejected(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, db_session: AsyncSession
) -> None:
    await ensure_calendar(db_session, login.plot)
    task = (await plot_tasks(db_session, login.plot.id))[0]
    ops = [
        {
            "op_id": str(uuid.uuid4()),
            "entity": "crop_plot_task",
            "action": "update",
            "entity_id": str(task.id),
            "base_version": 1,
            "client_ts": datetime.now(UTC).isoformat(),
            "payload": {"status": "done", "reminder_enabled": False, "due_date": "2000-01-01"},
        },
        {
            "op_id": str(uuid.uuid4()),
            "entity": "crop_plot_task",
            "action": "create",
            "entity_id": str(uuid.uuid4()),
            "base_version": 0,
            "client_ts": datetime.now(UTC).isoformat(),
            "payload": {},
        },
    ]
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "farmer-phone", "cursor": None, "ops": ops},
        headers=bearer(login.user),
    )
    assert resp.status_code == 200, resp.text
    results = resp.json()["results"]
    assert results[0]["status"] == "applied", results[0]
    assert results[0]["server"]["status"] == "done"
    assert results[0]["server"]["reminder_enabled"] is False
    assert results[0]["server"]["due_date"] != "2000-01-01"  # server-owned field dropped
    assert results[1]["status"] == "rejected"
    feed = resp.json()["changes"]
    assert any(c["entity"] == "crop_plot_task" for c in feed)


def test_today_boundary_is_ist() -> None:
    from farmerapp.advisory.calendar import today_ist

    assert today_ist(datetime(2026, 9, 20, 19, 0, tzinfo=UTC)) == date(2026, 9, 21)


@pytest.mark.parametrize("code", sorted(PILOT_CALENDARS))
def test_pilot_calendars_are_well_formed(code: str) -> None:
    tasks = PILOT_CALENDARS[code]
    keys = [t.key for t in tasks]
    assert len(keys) == len(set(keys))
    assert {t.task_type.value for t in tasks} >= {"sow", "fertilise", "harvest"}
    assert all(1 <= t.duration_days <= 60 for t in tasks)
    assert max(t.day_offset for t in tasks) == next(
        t.day_offset for t in tasks if t.task_type.value == "harvest"
    )
