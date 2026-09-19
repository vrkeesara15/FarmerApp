"""VV-007 auto end of duty (20:00 IST, tenant-configurable; 60 min idle at home) with an
injected clock, the notification row for the app prompt, no points after the auto end, and
the OPS-006 sync-silence flag to the cluster head."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, time, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db.geo import haversine_m, offset, point_wkt
from farmerapp.duty.auto_end import (
    auto_end_duty,
    auto_time_cutoff,
    home_of,
    idle_since,
    officer_sync_silence,
    run_auto_end,
    run_sync_silence,
)
from farmerapp.duty.track import TrackPoint
from farmerapp.location.models import _POINT_GEOM, DutyEndReason, DutySession, LocationPoint
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.tenants.models import Store
from tests.duty.conftest import (
    BASE_LAT,
    BASE_LON,
    DAY,
    DutyCtx,
    ist,
    point,
    point_count,
    set_tenant_settings,
    start_duty,
)
from tests.logcontract import assert_fields, capture, one_event

IST = timedelta(hours=5, minutes=30)


async def _notifications(session: AsyncSession, user_id: uuid.UUID) -> list[Notification]:
    rows = await session.execute(
        select(Notification)
        .where(Notification.user_id == user_id)
        .order_by(Notification.created_at)
    )
    return list(rows.scalars())


async def _upload(
    client: AsyncClient, dctx: DutyCtx, duty_id: str, points: list[dict[str, object]]
) -> dict[str, object]:
    resp = await client.post(
        "/v1/location/batch", json=dctx.batch_body(duty_id, points), headers=dctx.headers
    )
    assert resp.status_code == 200, resp.text
    body: dict[str, object] = resp.json()
    return body


# ------------------------------------------------------------------ pure functions
def test_auto_time_cutoff_is_the_first_end_time_after_start() -> None:
    eight_pm = time(20, 0)
    assert auto_time_cutoff(ist(9, 0), eight_pm) == ist(20, 0)
    assert auto_time_cutoff(ist(19, 59), eight_pm) == ist(20, 0)
    assert auto_time_cutoff(ist(20, 0), eight_pm) == ist(20, 0, day=DAY + timedelta(days=1))
    assert auto_time_cutoff(ist(21, 30), eight_pm) == ist(20, 0, day=DAY + timedelta(days=1))
    assert auto_time_cutoff(ist(9, 0), time(18, 30)) == ist(18, 30)


def _tp(minutes: int, east_m: float = 0.0, acc: float = 8.0) -> TrackPoint:
    lon, lat = offset(BASE_LON, BASE_LAT, east_m, 0)
    return TrackPoint(ts=ist(10, 0) + timedelta(minutes=minutes), lat=lat, lon=lon, accuracy_m=acc)


def test_idle_since_rules() -> None:
    now = ist(11, 0)
    home = (BASE_LAT, BASE_LON)
    idle = timedelta(minutes=60)
    still = [_tp(m, east_m=(m % 3) * 5) for m in range(0, 61, 10)]
    assert idle_since(still, now=now, idle=idle, stationary_s=600, home=home) == ist(10, 0)
    # Started idling 20 minutes into the window: the window is not covered from its start.
    late = [_tp(m) for m in range(20, 61, 10)]
    assert idle_since(late, now=now, idle=idle, stationary_s=600, home=home) is None
    # No recent point (device silent for 30 min): no evidence of idling now.
    stale = [_tp(m) for m in range(0, 31, 10)]
    assert idle_since(stale, now=now, idle=idle, stationary_s=600, home=home) is None
    # Moved 150 m within the window.
    moved = [*still[:4], _tp(40, east_m=150), *still[5:]]
    assert idle_since(moved, now=now, idle=idle, stationary_s=600, home=home) is None
    # Idle, but 500 m from home (a long farm visit).
    far = (BASE_LAT, BASE_LON + 0.005)
    assert idle_since(still, now=now, idle=idle, stationary_s=600, home=far) is None
    # Inaccurate points do not count.
    fuzzy = [TrackPoint(p.ts, p.lat, p.lon, 300.0) for p in still]
    assert idle_since(fuzzy, now=now, idle=idle, stationary_s=600, home=home) is None
    assert idle_since([], now=now, idle=idle, stationary_s=600, home=home) is None


# ------------------------------------------------------------------ auto_time
async def test_duty_auto_ends_at_2000_ist_and_no_points_after(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    await _upload(
        client, accepted, started["id"], [point(ist(9, 30)), point(ist(9, 45), east_m=800)]
    )
    count = await point_count(db_session, accepted.officer.id)

    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(19, 59)) == []
    results = await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(20, 5))
    assert len(results) == 1
    result = results[0]
    assert result.duty_session_id == uuid.UUID(started["id"])
    assert result.end_reason == DutyEndReason.AUTO_TIME and result.end_at == ist(20, 0)
    duty = await db_session.get_one(DutySession, uuid.UUID(started["id"]))
    assert duty.end_at == ist(20, 0) and duty.end_reason == DutyEndReason.AUTO_TIME
    assert duty.km is not None and 0.75 <= float(duty.km) <= 0.85
    assert duty.auto_ended

    notes = await _notifications(db_session, accepted.officer.id)
    assert [n.kind for n in notes] == [NotificationKind.DUTY_AUTO_ENDED]
    note = notes[0]
    assert note.tenant_id == accepted.tenant_id
    assert note.title_key == "notification.duty_auto_ended.title"
    assert note.body_key == "notification.duty_auto_ended.body.auto_time"
    assert note.data["duty_session_id"] == started["id"] and note.data["end_reason"] == "auto_time"
    assert note.read_at is None

    # A second pass does nothing more.
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(20, 15)) == []

    # The app is still running: its next batch after the auto end stores nothing (FA-010).
    accepted.clock.advance(ist(20, 12) - accepted.now)
    late = await _upload(
        client,
        accepted,
        started["id"],
        [point(ist(20, 3)), point(ist(20, 10)), point(ist(19, 58))],
    )
    assert late["accepted"] == 1  # 19:58 is inside the window; 20:03 / 20:10 are off duty
    assert late["rejected"] == [
        {"index": 0, "reason": "off_duty"},
        {"index": 1, "reason": "off_duty"},
    ]
    assert await point_count(db_session, accepted.officer.id) == count + 1
    current = await client.get("/v1/duty/current", headers=accepted.headers)
    assert current.json()["session"] is None


async def test_auto_end_time_is_tenant_configurable(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    await set_tenant_settings(db_session, accepted.tenant, auto_duty_end_local_time="18:30")
    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(18, 29)) == []
    results = await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(18, 31))
    assert [(r.end_reason, r.end_at) for r in results] == [(DutyEndReason.AUTO_TIME, ist(18, 30))]
    duty = await db_session.get_one(DutySession, uuid.UUID(started["id"]))
    assert duty.end_at == ist(18, 30)


async def test_a_session_started_after_the_cutoff_runs_to_the_next_evening(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    accepted.clock.advance(ist(21, 0) - accepted.now)
    await start_duty(client, accepted, start_at=ist(21, 0).isoformat())
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(23, 30)) == []
    tomorrow = DAY + timedelta(days=1)
    assert (
        await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(19, 0, day=tomorrow))
        == []
    )
    results = await auto_end_duty(
        db_session, tenant_id=accepted.tenant_id, now=ist(20, 1, day=tomorrow)
    )
    assert [r.end_at for r in results] == [ist(20, 0, day=tomorrow)]


async def test_auto_end_only_touches_the_bound_tenant(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    other = accepted.world.b.tenant.id
    assert await auto_end_duty(db_session, tenant_id=other, now=ist(20, 5)) == []
    duty = await db_session.scalar(
        select(DutySession).where(
            DutySession.officer_id == accepted.officer.id, DutySession.end_at.is_(None)
        )
    )
    assert duty is not None


# ------------------------------------------------------------------ auto_idle
def _home_track(
    start: datetime, minutes: int, *, east_m: float = 0.0, step: int = 10
) -> list[dict[str, object]]:
    return [
        point(start + timedelta(minutes=m), east_m=east_m + (m % 3) * 4, north_m=(m % 2) * 3)
        for m in range(0, minutes + 1, step)
    ]


async def test_idle_at_home_for_60_minutes_ends_duty(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    accepted.officer.home_point = point_wkt(*offset(BASE_LON, BASE_LAT, 30, 20))
    await db_session.flush()
    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    accepted.clock.advance(ist(11, 6) - accepted.now)
    # Moving in the morning, then home from 10:00.
    await _upload(
        client,
        accepted,
        started["id"],
        [
            point(ist(9, 10), east_m=3000),
            point(ist(9, 30), east_m=6000),
            *_home_track(ist(10, 0), 65),
        ],
    )
    # Only 30 minutes idle so far: still on duty.
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(10, 30)) == []
    results = await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(11, 5))
    assert len(results) == 1
    assert results[0].end_reason == DutyEndReason.AUTO_IDLE
    assert results[0].end_at == ist(10, 10)  # the first point of the idle window [10:05, 11:05]
    duty = await db_session.get_one(DutySession, uuid.UUID(started["id"]))
    assert duty.end_reason == DutyEndReason.AUTO_IDLE and duty.end_at == ist(10, 10)
    assert duty.km is not None and 8.9 <= float(duty.km) <= 9.1  # 3 km out, 6 km back home
    notes = await _notifications(db_session, accepted.officer.id)
    assert [n.body_key for n in notes] == ["notification.duty_auto_ended.body.auto_idle"]
    # Nothing after the end is stored.
    late = await _upload(client, accepted, started["id"], [point(ist(11, 0)), point(ist(10, 11))])
    assert late["accepted"] == 1 and late["rejected"] == [{"index": 0, "reason": "off_duty"}]


async def test_idle_away_from_home_or_moving_keeps_duty(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    accepted.officer.home_point = point_wkt(BASE_LON, BASE_LAT)
    await db_session.flush()
    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    accepted.clock.advance(ist(11, 6) - accepted.now)
    # An hour still at a farm 2 km from home, then an hour of slow movement near home.
    await _upload(client, accepted, started["id"], _home_track(ist(9, 0), 60, east_m=2000))
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(10, 0)) == []
    walking = [point(ist(10, 0) + timedelta(minutes=m), east_m=m * 12) for m in range(5, 66, 10)]
    await _upload(client, accepted, started["id"], walking)
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(11, 5)) == []
    duty = await db_session.get_one(DutySession, uuid.UUID(started["id"]))
    assert duty.end_at is None
    assert await _notifications(db_session, accepted.officer.id) == []


async def test_home_falls_back_to_the_store_location(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    assert accepted.officer.home_point is None and accepted.officer.store_id is not None
    home = await home_of(db_session, accepted.officer)
    assert home is not None
    slat, slon = await _store_lat_lon(db_session, accepted.officer.store_id)
    lat, lon = home
    assert haversine_m(lat, lon, slat, slon) < 1.0

    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    accepted.clock.advance(ist(11, 6) - accepted.now)
    at_store = [
        {**point(ist(10, 0) + timedelta(minutes=m)), "lat": slat + (m % 2) * 0.00005, "lon": slon}
        for m in range(0, 66, 10)
    ]
    await _upload(client, accepted, started["id"], at_store)
    results = await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(11, 5))
    assert [r.end_reason for r in results] == [DutyEndReason.AUTO_IDLE]

    accepted.officer.store_id = None
    accepted.officer.home_point = None
    await db_session.flush()
    assert await home_of(db_session, accepted.officer) is None


async def _store_lat_lon(session: AsyncSession, store_id: uuid.UUID) -> tuple[float, float]:
    row = (
        await session.execute(
            select(
                func.ST_Y(cast(Store.location, _POINT_GEOM)),
                func.ST_X(cast(Store.location, _POINT_GEOM)),
            ).where(Store.id == store_id)
        )
    ).one()
    return float(row[0]), float(row[1])


async def test_idle_needs_the_window_covered_by_data(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    accepted.officer.home_point = point_wkt(BASE_LON, BASE_LAT)
    await db_session.flush()
    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    accepted.clock.advance(ist(11, 6) - accepted.now)
    await _upload(client, accepted, started["id"], [point(ist(10, 50)), point(ist(11, 0))])
    assert await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(11, 5)) == []


# ------------------------------------------------------------------ OPS-006 sync silence
async def test_sync_silence_notifies_the_cluster_head_once(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    head = accepted.cluster_head
    accepted.officer.cluster_id = head.cluster_id
    await db_session.flush()
    started = await start_duty(client, accepted, start_at=ist(7, 0).isoformat())
    # 90 minutes without a batch since the start: nothing yet.
    assert (
        await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(8, 30)) == []
    )
    results = await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(9, 1))
    assert len(results) == 1
    assert results[0].duty_session_id == uuid.UUID(started["id"])
    assert results[0].last_contact_at == ist(7, 0) and results[0].notified == [head.id]
    notes = await _notifications(db_session, head.id)
    assert [n.kind for n in notes] == [NotificationKind.OFFICER_SYNC_SILENCE]
    assert notes[0].data["officer_id"] == str(accepted.officer.id)
    assert notes[0].data["silent_minutes"] == 121
    assert notes[0].title_key == "notification.officer_sync_silence.title"
    # Flagged once per session.
    assert (
        await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(9, 30)) == []
    )
    assert len(await _notifications(db_session, head.id)) == 1

    # A batch counts as contact (received_at is the server time).
    accepted.clock.advance(ist(9, 40) - accepted.now)
    await _upload(client, accepted, started["id"], [point(ist(9, 35))])
    assert (
        await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(11, 30)) == []
    )


async def test_sync_silence_without_a_cluster_head_records_the_silence_only(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    accepted.officer.cluster_id = None
    await db_session.flush()
    await start_duty(client, accepted, start_at=ist(7, 0).isoformat())
    results = await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(9, 30))
    assert len(results) == 1 and results[0].notified == []
    heads = [u for u in accepted.world.a.everyone if u.role == UserRole.CLUSTER_HEAD]
    for head in heads:
        assert await _notifications(db_session, head.id) == []


# ------------------------------------------------------------------ job wrappers
async def test_job_wrappers_run_per_tenant_in_their_own_session(accepted: DutyCtx) -> None:
    """The wrappers open a committed session; the test's uncommitted rows are invisible to
    them, so they see no open sessions — the point is the tenant binding and actor scope."""
    from farmerapp.db import session as session_mod

    # The cached engine may still be the one built at import from the local .env (the dev
    # database, which may lag the migrations): use the test database, then reset.
    session_mod.get_engine.cache_clear()
    session_mod.get_session_factory.cache_clear()
    tenants = [accepted.tenant_id, accepted.world.b.tenant.id]
    try:
        assert await run_auto_end(tenants, now=datetime(2026, 9, 21, 15, 0, tzinfo=UTC)) == []
        assert await run_sync_silence(tenants, now=datetime(2026, 9, 21, 15, 0, tzinfo=UTC)) == []
    finally:
        await session_mod.get_engine().dispose()
        session_mod.get_engine.cache_clear()
        session_mod.get_session_factory.cache_clear()


async def test_location_points_stay_off_duty_free_after_every_auto_end(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    """Every stored point of the officer lies inside a duty window (FA-010 invariant)."""
    started = await start_duty(client, accepted, start_at=ist(9, 0).isoformat())
    await _upload(client, accepted, started["id"], [point(ist(9, 30))])
    accepted.clock.advance(ist(19, 59) - accepted.now)
    await _upload(client, accepted, started["id"], [point(ist(19, 58))])
    await auto_end_duty(db_session, tenant_id=accepted.tenant_id, now=ist(20, 5))
    accepted.clock.advance(ist(20, 30) - accepted.now)
    late = await _upload(client, accepted, started["id"], [point(ist(20, 20))])
    assert late["accepted"] == 0
    rows = (
        await db_session.execute(
            select(LocationPoint.ts, LocationPoint.duty_session_id).where(
                LocationPoint.officer_id == accepted.officer.id, LocationPoint.ts >= ist(0, 0)
            )
        )
    ).all()
    duty = await db_session.get_one(DutySession, uuid.UUID(started["id"]))
    assert duty.end_at is not None
    assert len(rows) == 2 and all(
        sid == duty.id
        and duty.start_at - timedelta(minutes=2) <= ts <= duty.end_at + timedelta(minutes=2)
        for ts, sid in rows
    )


# ------------------------------------------------------------------ OPS-006 more / ops_snapshot
async def test_sync_silence_only_notifies_active_heads_of_the_officers_cluster(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    head = accepted.cluster_head
    accepted.officer.cluster_id = head.cluster_id
    other_cluster = uuid.uuid4()
    others = [
        User(
            tenant_id=accepted.tenant_id,
            phone=phone,
            name=name,
            role=UserRole.CLUSTER_HEAD.value,
            cluster_id=cluster,
            status=status,
        )
        for phone, name, cluster, status in (
            ("+919811100001", "Other cluster head", other_cluster, UserStatus.ACTIVE.value),
            ("+919811100002", "Disabled head", head.cluster_id, UserStatus.DISABLED.value),
        )
    ]
    db_session.add_all(others)
    await db_session.flush()
    await start_duty(client, accepted, start_at=ist(7, 0).isoformat())
    results = await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(9, 5))
    assert [r.notified for r in results] == [[head.id]]
    for other in others:
        assert await _notifications(db_session, other.id) == []


async def test_sync_silence_ignores_ended_sessions(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    head = accepted.cluster_head
    accepted.officer.cluster_id = head.cluster_id
    await db_session.flush()
    await start_duty(client, accepted, start_at=ist(7, 0).isoformat())
    accepted.clock.advance(ist(8, 0) - accepted.now)
    resp = await client.post(
        "/v1/duty/end",
        json=accepted.end_body(end_at=ist(8, 0).isoformat()),
        headers=accepted.headers,
    )
    assert resp.status_code == 200, resp.text
    assert await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(11)) == []


async def test_ops_snapshot_log_contract(
    client: AsyncClient,
    accepted: DutyCtx,
    db_session: AsyncSession,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """``farmerapp_officers_on_duty`` / ``farmerapp_open_flags`` gauges, one line per tenant."""
    capture(caplog)
    await start_duty(client, accepted, start_at=ist(7, 0).isoformat())
    await officer_sync_silence(db_session, tenant_id=accepted.tenant_id, now=ist(7, 30))
    line = one_event(caplog, "ops_snapshot")
    assert_fields(line, tenant_id=str, officers_on_duty=int, open_flags=int)
    assert line["officers_on_duty"] == 1 and line["tenant_id"] == str(accepted.tenant_id)
    assert line["open_flags"] >= 0
