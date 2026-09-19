"""OPS-007 ``store-day-watch``: zero sales on a working day and a day not closed by 22:00
IST notify the store manager and the cluster head, once per store, day and kind."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typer.testing import CliRunner

from farmerapp.auth.models import User, UserRole
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.jobs.cli import cli
from farmerapp.notifications.models import Notification
from farmerapp.ops import store_watch
from farmerapp.ops.store_watch import StoreDayAlertKind, run_store_day_watch, store_day_watch
from farmerapp.orders.models import Order
from farmerapp.payments.config import IST
from farmerapp.payments.models import DayClose
from farmerapp.tenants.models import Store
from tests.authz.conftest import World

MONDAY = date(2026, 10, 5)
SUNDAY = date(2026, 10, 4)


def ist(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime.combine(day, time(hour, minute), tzinfo=IST).astimezone(UTC)


async def _stores(session: AsyncSession) -> dict[str, Store]:
    return {s.code: s for s in (await session.execute(select(Store))).scalars()}


async def _sale(session: AsyncSession, world: World, store: Store, at: datetime) -> None:
    session.add(
        Order(
            tenant_id=world.a.tenant.id,
            farmer_id=world.a.farmer.id,
            store_id=store.id,
            channel="pos",
            status="handed_over",
            fulfilment="pickup",
            subtotal_paise=10_000,
            discount_paise=0,
            tax_paise=0,
            total_paise=10_000,
            placed_by=world.a.user(UserRole.STORE_MANAGER).id,
            placed_at=at,
        )
    )
    await session.flush()


async def _close(
    session: AsyncSession, world: World, store: Store, day: date, at: datetime, status: str
) -> None:
    session.add(
        DayClose(
            tenant_id=world.a.tenant.id,
            store_id=store.id,
            business_date=day,
            cash_expected_paise=0,
            cash_counted_paise=0,
            variance_paise=0,
            closed_by=world.a.user(UserRole.STORE_MANAGER).id,
            closed_at=at,
            status=status,
        )
    )
    await session.flush()


async def _alerts(session: AsyncSession, user: User) -> list[tuple[str, str]]:
    rows = await session.execute(
        select(Notification.kind, Notification.data["store_code"].astext).where(
            Notification.user_id == user.id,
            Notification.kind.in_([k.value for k in StoreDayAlertKind]),
        )
    )
    return sorted((str(kind), str(code)) for kind, code in rows.tuples())


async def test_zero_sales_and_unclosed_days_alert_the_manager_and_cluster_head(
    world: World, db_session: AsyncSession
) -> None:
    tid = world.a.tenant.id
    manager = world.a.user(UserRole.STORE_MANAGER)
    head = world.a.user(UserRole.CLUSTER_HEAD)
    async with tenant_scope(db_session, tid):
        stores = await _stores(db_session)
        wgl = next(s for s in stores.values() if s.id == manager.store_id)
        knr = next(s for s in stores.values() if s.cluster_id == head.cluster_id and s != wgl)
        # WGL sold and closed at 21:30: fine. KNR sold, never closed. The rest: nothing.
        await _sale(db_session, world, wgl, ist(MONDAY, 11))
        await _close(db_session, world, wgl, MONDAY, ist(MONDAY, 21, 30), "closed")
        await _sale(db_session, world, knr, ist(MONDAY, 12))

        early = await store_day_watch(db_session, tenant_id=tid, now=ist(MONDAY, 21, 59))
        assert not early.checked and early.alerts == []

        report = await store_day_watch(db_session, tenant_id=tid, now=ist(MONDAY, 22, 15))
        assert report.checked and report.working_day and report.stores == len(stores)
        by_store = {(a.store_code, a.kind) for a in report.alerts}
        assert (wgl.code, StoreDayAlertKind.ZERO_SALES) not in by_store
        assert (wgl.code, StoreDayAlertKind.NOT_CLOSED) not in by_store
        assert (knr.code, StoreDayAlertKind.NOT_CLOSED) in by_store
        assert (knr.code, StoreDayAlertKind.ZERO_SALES) not in by_store
        idle = [s for s in stores.values() if s not in (wgl, knr)]
        for store in idle:
            assert (store.code, StoreDayAlertKind.ZERO_SALES) in by_store
            assert (store.code, StoreDayAlertKind.NOT_CLOSED) in by_store
        knr_alert = next(a for a in report.alerts if a.store_code == knr.code)
        assert head.id in knr_alert.notified  # cluster head of KNR's cluster
        assert manager.id not in knr_alert.notified  # WGL's manager is not KNR's
        assert await _alerts(db_session, manager) == []
        head_alerts = await _alerts(db_session, head)
        assert ("store_day_not_closed", knr.code) in head_alerts

        # Re-run (the scheduler retries, or a late re-check): nothing new.
        again = await store_day_watch(db_session, tenant_id=tid, now=ist(MONDAY, 23))
        assert again.alerts == [] and await _alerts(db_session, head) == head_alerts


async def test_manager_is_notified_for_their_store(world: World, db_session: AsyncSession) -> None:
    tid = world.a.tenant.id
    manager = world.a.user(UserRole.STORE_MANAGER)
    async with tenant_scope(db_session, tid):
        wgl = next(s for s in (await _stores(db_session)).values() if s.id == manager.store_id)
        # Closed, but after the deadline, then reopened: still "not closed by 22:00".
        await _sale(db_session, world, wgl, ist(MONDAY, 10))
        await _close(db_session, world, wgl, MONDAY, ist(MONDAY, 21), "reopened")
        report = await store_day_watch(db_session, tenant_id=tid, now=ist(MONDAY, 22, 30))
        mine = [a for a in report.alerts if a.store_code == wgl.code]
        assert [a.kind for a in mine] == [StoreDayAlertKind.NOT_CLOSED]
        assert manager.id in mine[0].notified
        note = (
            await db_session.execute(
                select(Notification).where(
                    Notification.user_id == manager.id,
                    Notification.kind == "store_day_not_closed",
                )
            )
        ).scalar_one()
        assert note.title_key == "notification.store_day_not_closed.title"
        assert note.data == {"store_id": str(wgl.id), "store_code": wgl.code, "day": "2026-10-05"}


async def test_sundays_and_holidays_are_not_working_days(
    world: World, db_session: AsyncSession
) -> None:
    tid = world.a.tenant.id
    async with tenant_scope(db_session, tid):
        sunday = await store_day_watch(db_session, tenant_id=tid, now=ist(SUNDAY, 23))
        assert not sunday.working_day and sunday.alerts == []
        tenant = await db_session.get_one(Tenant, tid)
        tenant.settings = {
            **(tenant.settings or {}),
            "holidays": [MONDAY.isoformat()],
            "working_days": [1, 2, 3, 4, 5, 6, 7],
        }
        await db_session.flush()
        holiday = await store_day_watch(db_session, tenant_id=tid, now=ist(MONDAY, 23))
        assert not holiday.working_day and holiday.alerts == []
        sunday_now = await store_day_watch(db_session, tenant_id=tid, now=ist(SUNDAY, 23))
        assert sunday_now.working_day and sunday_now.alerts  # Sunday trades for this tenant
        # A custom deadline.
        tenant.settings = {**tenant.settings, "day_close_deadline_local_time": "23:30"}
        await db_session.flush()
        tuesday = MONDAY + timedelta(days=1)
        late = await store_day_watch(db_session, tenant_id=tid, now=ist(tuesday, 23))
        assert not late.checked


async def test_job_wrapper_binds_each_tenant(world: World) -> None:
    """Committed sessions: the test's rows are invisible, the tenant binding is the point."""
    reports = await run_store_day_watch([world.a.tenant.id, world.b.tenant.id], now=ist(SUNDAY, 23))
    assert [r.tenant_id for r in reports] == [world.a.tenant.id, world.b.tenant.id]
    assert all(not r.working_day for r in reports)


def test_store_day_watch_command(monkeypatch: pytest.MonkeyPatch) -> None:
    tenant = uuid.uuid4()

    async def fake_run(tenant_ids: Any, *, now: Any = None, day: Any = None) -> list[Any]:
        report = store_watch.StoreDayReport(tenant_id=tenant_ids[0], day=day, stores=5)
        report.alerts.append(
            store_watch.StoreDayAlert(
                tenant, uuid.uuid4(), "WGL", day, StoreDayAlertKind.ZERO_SALES, [uuid.uuid4()]
            )
        )
        off = store_watch.StoreDayReport(tenant_id=tenant, day=day, working_day=False)
        early = store_watch.StoreDayReport(tenant_id=tenant, day=day, checked=False)
        return [report, off, early]

    monkeypatch.setattr(store_watch, "run_store_day_watch", fake_run)
    result = CliRunner().invoke(
        cli, ["store-day-watch", "--tenant-id", str(tenant), "--date", "2026-10-05"]
    )
    assert result.exit_code == 0, result.output
    assert f"tenant={tenant} date=2026-10-05 checked stores=5 alerts=1" in result.output
    assert "WGL store_zero_sales notified=1" in result.output
    assert "not a working day" in result.output and "before the deadline" in result.output
