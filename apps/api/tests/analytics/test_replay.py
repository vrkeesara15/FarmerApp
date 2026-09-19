"""AN-003 / WC-002 officer day replay: "replay shows track, visits and gaps"."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import to_ist_date
from farmerapp.analytics.replay import Kept, find_gaps, proof_items, split_lines, usable
from farmerapp.auth.models import UserRole
from farmerapp.db.geo import offset
from farmerapp.location.models import DutySession, LocationPoint
from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.authz.conftest import Bearer, World

DAY = date(2026, 8, 12)
FARM = (79.50, 17.90)  # lon, lat


async def build(m: Mini) -> None:
    """O1 on 12 Aug: drives 09:00-10:00, stops at a farm 10:00-10:20 (visit), no signal
    10:20-11:10 (50-minute gap), then drives on until 13:00 (a partial visit at 11:30)."""
    points: list[tuple[datetime, float, float]] = []
    t = ist(DAY, 9)
    for i in range(31):  # 09:00 .. 10:00 every 2 min, 60 m east each time
        lon, lat = offset(FARM[0], FARM[1], -1_800 + 60 * i, 0)
        points.append((t + timedelta(minutes=2 * i), lat, lon))
    for i in range(1, 11):  # 10:02 .. 10:20 at the farm
        points.append((ist(DAY, 10, 2 * i), FARM[1], FARM[0]))
    for i in range(23):  # 11:10 .. 13:00 every 5 min
        lon, lat = offset(FARM[0], FARM[1], 500 + 300 * i, 200)
        points.append((ist(DAY, 11, 10) + timedelta(minutes=5 * i), lat, lon))
    await m.duty("o1", ist(DAY, 9), ist(DAY, 13), km="99", points=points)
    good = await m.visit(
        "o1", "f1", ist(DAY, 10, 2), minutes=16, score=80, confirmed=True,
        components={
            "geofence": 30, "confirmation": 30, "photo": 0, "duration": 10, "integrity": 10,
        },
        lat=FARM[1], lon=FARM[0],
    )  # fmt: skip
    await m.photo(good)
    await m.visit(
        "o1", "f2", ist(DAY, 11, 30), minutes=10, score=45,
        components={"geofence": 30, "confirmation": 0, "photo": 0, "duration": 5, "integrity": 10},
    )  # fmt: skip
    await m.session.flush()


async def test_replay_shows_track_visits_and_gaps(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    o1 = mini.user("o1")
    resp = await get(client, bearer, mini.user("owner"), f"/officers/{o1.id}/day-replay", date=DAY)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["date"] == "2026-08-12"
    assert body["officer_name"] == "User o1"
    assert "filters" in body

    # Track: two line strings (broken at the gap), every kept point for playback.
    assert body["track"]["type"] == "MultiLineString"
    assert len(body["track"]["coordinates"]) == 2
    assert len(body["points"]) == 31 + 10 + 23
    assert 1.5 < body["km"] < 10.0  # recomputed from the points, not the stored 99 km
    assert body["duty_sessions"][0]["km"] == pytest.approx(body["km"])

    # Gap: 10:20 -> 11:10 while on duty, no reason recorded yet (VV-008).
    assert len(body["gaps"]) == 1
    gap = body["gaps"][0]
    assert datetime.fromisoformat(gap["start"]) == ist(DAY, 10, 20)
    assert datetime.fromisoformat(gap["end"]) == ist(DAY, 11, 10)
    assert gap["duration_s"] == 50 * 60
    assert gap["reason"] is None

    # Stop at the farm (>= 5 min within 100 m).
    assert any(s["duration_s"] >= 18 * 60 for s in body["stops"])

    # Visits: pins with status colours, score components and proof rows.
    v1, v2 = body["visits"]
    assert (v1["status"], v1["colour"], v1["score"]) == ("verified", "green", 80)
    assert (v2["status"], v2["colour"]) == ("partial", "amber")
    assert v1["lat"] == pytest.approx(FARM[1]) and v1["lon"] == pytest.approx(FARM[0])
    assert v1["photos"] == 1 and v1["confirmed_at"] is not None
    proof = {p["kind"]: p for p in v1["proof"]}
    assert proof["geofence"]["satisfied"] and not proof["photo"]["satisfied"]
    assert proof["duration"] == {
        "kind": "duration",
        "satisfied": True,
        "points": 10,
        "max_points": 10,
    }
    assert {p["kind"]: p["satisfied"] for p in v2["proof"]}["confirmation"] is False

    # Timeline sorted by time, with every kind of event.
    times = [e["ts"] for e in body["timeline"]]
    assert times == sorted(times)
    kinds = [e["type"] for e in body["timeline"]]
    assert kinds[0] == "duty_start" and kinds[-1] == "duty_end"
    assert {"visit_checkin", "visit_checkout", "stop", "gap_start", "gap_end"} <= set(kinds)


@pytest.mark.parametrize(
    ("role", "status"),
    [
        ("owner", 200),
        ("director", 200),
        ("auditor", 200),
        ("tenant_admin", 200),
        ("cluster_head", 200),  # O1 is in the north cluster
        ("o1", 200),  # own day
        ("o2", 404),  # another officer
        ("store_manager", 403),  # SPEC 2.6: never store managers
        ("accountant", 403),
        ("agronomist", 403),
        ("farmer_user", 403),
    ],
)
async def test_replay_roles(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, status: int
) -> None:
    o1 = mini.user("o1")
    resp = await get(client, bearer, mini.user(role), f"/officers/{o1.id}/day-replay", date=DAY)
    assert resp.status_code == status, resp.text


async def test_cluster_head_cannot_replay_another_cluster(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    o2 = mini.user("o2")
    resp = await get(
        client, bearer, mini.user("cluster_head"), f"/officers/{o2.id}/day-replay", date=DAY
    )
    assert resp.status_code == 404


async def test_replay_requires_a_date(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    resp = await get(
        client, bearer, mini.user("owner"), f"/officers/{mini.user('o1').id}/day-replay"
    )
    assert resp.status_code == 422


async def test_empty_day(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    resp = await get(
        client, bearer, mini.user("owner"), f"/officers/{mini.user('o1').id}/day-replay", date=DAY
    )
    body = resp.json()
    assert body["track"]["coordinates"] == [] and body["visits"] == [] and body["gaps"] == []
    assert body["km"] == 0


async def test_seeded_day_with_an_injected_gap(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    """The seeded officer's duty day, with 90 minutes of points removed mid-session."""
    officer = world.a.user(UserRole.FIELD_OFFICER)
    ds = (
        await db_session.execute(
            select(DutySession).where(DutySession.officer_id == officer.id).limit(1)
        )
    ).scalar_one()
    day = to_ist_date(ds.start_at)
    owner = world.a.owner
    path = f"/officers/{officer.id}/day-replay"
    before = (await get(client, bearer, owner, path, date=day)).json()
    assert before["track"]["coordinates"], "the seed must have a track"
    assert len(before["visits"]) == 2  # SMALL: one verified + one partial per officer
    assert {v["colour"] for v in before["visits"]} == {"green", "amber"}

    cut_from = ds.start_at + timedelta(hours=2)
    cut_to = cut_from + timedelta(minutes=90)
    await db_session.execute(
        delete(LocationPoint).where(
            LocationPoint.officer_id == officer.id,
            LocationPoint.ts >= cut_from,
            LocationPoint.ts < cut_to,
        )
    )
    after = (await get(client, bearer, owner, path, date=day)).json()
    injected = [
        g
        for g in after["gaps"]
        if datetime.fromisoformat(g["start"]) <= cut_from
        and datetime.fromisoformat(g["end"]) >= cut_to
    ]
    assert len(injected) == 1
    assert injected[0]["duration_s"] >= 90 * 60
    assert injected[0]["duty_session_id"] == str(ds.id)
    assert injected[0]["reason"] is None
    assert len(after["gaps"]) >= len(before["gaps"])
    assert len(after["points"]) < len(before["points"])
    assert len(after["visits"]) == 2
    assert "gap_start" in [e["type"] for e in after["timeline"]]


def test_gap_and_line_helpers() -> None:
    t0 = datetime(2026, 8, 12, 4, tzinfo=UTC)
    times = [t0 + timedelta(minutes=m) for m in (0, 10, 50, 60)]
    # 10 -> 50 is 40 minutes; 60 -> end (100) is 40 minutes; exactly 30 is not a gap.
    gaps = find_gaps(t0, t0 + timedelta(minutes=100), times)
    assert gaps == [(times[1], times[2]), (times[3], t0 + timedelta(minutes=100))]
    assert find_gaps(t0, t0 + timedelta(minutes=30), []) == []
    pts = [Kept(t, 17.9, 79.5 + i * 0.001, 5.0) for i, t in enumerate(times)]
    assert [len(line) for line in split_lines(pts, gaps)] == [2, 2]
    # Inaccurate, duplicate and implausibly fast points are dropped.
    noisy = [
        Kept(t0, 17.9, 79.5, 5.0),
        Kept(t0, 17.9, 79.5, 5.0),
        Kept(t0 + timedelta(minutes=1), 17.9, 79.5, 500.0),
        Kept(t0 + timedelta(minutes=2), 18.9, 79.5, 5.0),
        Kept(t0 + timedelta(minutes=3), 17.9001, 79.5, 5.0),
    ]
    assert len(usable(noisy)) == 2
    assert [p.satisfied for p in proof_items(None)] == [False] * 5
