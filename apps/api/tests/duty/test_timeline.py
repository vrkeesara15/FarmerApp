"""VV-008: the officer's own day timeline and km; a gap reason is stored and shown to the
cluster head (console day replay). VV-006 at duty end: km / stops / gaps stored per session."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.geo import offset
from farmerapp.duty.models import TrackGap, gap_id
from farmerapp.duty.processing import process_session
from farmerapp.duty.service import close_session
from farmerapp.location.models import DutySession
from farmerapp.sync.models import SyncChange
from tests.analytics.builders import Mini, ist
from tests.authz.conftest import Bearer
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


DAY = date(2026, 8, 12)
FARM = (79.50, 17.90)


@pytest.fixture
async def mini(db_session: AsyncSession) -> Mini:
    return await Mini.create(db_session)


async def gap_day(m: Mini, officer: str = "o1", *, end: datetime | None = None) -> DutySession:
    """09:00-10:00 driving, stop at the farm until 10:20, no signal 10:20-11:10, driving on."""
    points: list[tuple[datetime, float, float]] = []
    for i in range(31):
        lon, lat = offset(FARM[0], FARM[1], -1_800 + 60 * i, 0)
        points.append((ist(DAY, 9) + timedelta(minutes=2 * i), lat, lon))
    for i in range(1, 11):
        points.append((ist(DAY, 10, 2 * i), FARM[1], FARM[0]))
    for i in range(23):
        lon, lat = offset(FARM[0], FARM[1], 500 + 300 * i, 200)
        points.append((ist(DAY, 11, 10) + timedelta(minutes=5 * i), lat, lon))
    return await m.duty(officer, ist(DAY, 9), end, km="0", points=points)


async def test_duty_end_processes_the_track(db_session: AsyncSession, mini: Mini) -> None:
    duty = await gap_day(mini)
    await close_session(db_session, duty, end_at=ist(DAY, 13), end_reason="manual")
    assert duty.processed_at is not None and duty.km_source == "haversine"
    assert duty.km is not None and Decimal("1.5") < duty.km < Decimal("10")
    assert duty.km_raw is not None and duty.km <= duty.km_raw
    assert len(duty.stops) == 1
    gaps = (
        (await db_session.execute(select(TrackGap).where(TrackGap.duty_session_id == duty.id)))
        .scalars()
        .all()
    )
    assert len(gaps) == 1
    gap = gaps[0]
    assert gap.id == gap_id(duty.id, ist(DAY, 10, 20))
    assert gap.start_at == ist(DAY, 10, 20) and gap.end_at == ist(DAY, 11, 10)
    assert gap.duration_s == 50 * 60 and gap.reason is None


async def test_officer_sees_the_day_and_explains_a_gap(
    client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    duty = await gap_day(mini, end=None)
    await close_session(db_session, duty, end_at=ist(DAY, 13), end_reason="manual")
    o1 = mini.user("o1")
    resp = await client.get("/v1/me/day", params={"date": str(DAY)}, headers=bearer(o1))
    assert resp.status_code == 200, resp.text
    day = resp.json()
    assert day["officer_id"] == str(o1.id)
    assert day["km"] == pytest.approx(float(duty.km or 0))  # the processed km
    assert len(day["stops"]) == 1
    assert [g["reason"] for g in day["gaps"]] == [None]
    gid = day["gaps"][0]["id"]
    assert {e["type"] for e in day["timeline"]} >= {"duty_start", "duty_end", "gap_start"}
    assert day["travel"]["sessions"] == 1
    assert day["travel"]["ta_paise"] == round(float(duty.km or 0) * 300)

    resp = await client.post(
        f"/v1/me/gaps/{gid}/reason",
        json={"reason": "network", "note": "No signal near the canal"},
        headers=bearer(o1),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["reason"] == "network"

    # The cluster head (and the owner) see it in the console day replay.
    for viewer in ("cluster_head", "owner"):
        replay = await client.get(
            f"/v1/analytics/officers/{o1.id}/day-replay",
            params={"date": str(DAY)},
            headers=bearer(mini.user(viewer)),
        )
        assert replay.status_code == 200, replay.text
        gap = replay.json()["gaps"][0]
        assert gap["id"] == gid
        assert gap["reason"] == "network" and gap["note"] == "No signal near the canal"

    # The reason is a sync change for the officer (offline timeline).
    change = await db_session.scalar(
        select(SyncChange).where(
            SyncChange.entity == "track_gap", SyncChange.entity_id == uuid.UUID(gid)
        )
    )
    assert change is not None

    # A reason can be corrected; another officer cannot touch it.
    resp = await client.post(
        f"/v1/me/gaps/{gid}/reason", json={"reason": "vehicle"}, headers=bearer(o1)
    )
    assert resp.json()["reason"] == "vehicle" and resp.json()["note"] is None
    resp = await client.post(
        f"/v1/me/gaps/{gid}/reason", json={"reason": "other"}, headers=bearer(mini.user("o2"))
    )
    assert resp.status_code == 404


async def test_a_gap_of_an_open_session_can_be_explained(
    client: AsyncClient, bearer: Bearer, mini: Mini, app: object, db_session: AsyncSession
) -> None:
    from farmerapp.auth.clock import FakeClock

    duty = await gap_day(mini, end=None)  # still on duty at 12:00
    app.state.auth.clock = FakeClock(ist(DAY, 12))  # type: ignore[attr-defined]
    o1 = mini.user("o1")
    target = gap_id(duty.id, ist(DAY, 10, 20))
    assert await db_session.get(TrackGap, target) is None
    resp = await client.post(
        f"/v1/me/gaps/{target}/reason", json={"reason": "personal_break"}, headers=bearer(o1)
    )
    assert resp.status_code == 200, resp.text
    row = await db_session.get_one(TrackGap, target)
    assert row.reason == "personal_break" and row.start_at == ist(DAY, 10, 20)

    # A made-up id is a 404.
    resp = await client.post(
        f"/v1/me/gaps/{uuid.uuid4()}/reason", json={"reason": "network"}, headers=bearer(o1)
    )
    assert resp.status_code == 404
    # Processing at duty end keeps the reason.
    await close_session(db_session, duty, end_at=ist(DAY, 13), end_reason="manual")
    await db_session.refresh(row)
    assert row.reason == "personal_break" and row.end_at == ist(DAY, 11, 10)


async def test_reprocessing_drops_vanished_gaps_but_keeps_explained_ones(
    db_session: AsyncSession, mini: Mini
) -> None:
    duty = await gap_day(mini)
    await close_session(db_session, duty, end_at=ist(DAY, 13), end_reason="manual")
    ghost = TrackGap(
        id=gap_id(duty.id, ist(DAY, 12)),
        tenant_id=mini.tid,
        duty_session_id=duty.id,
        officer_id=duty.officer_id,
        start_at=ist(DAY, 12),
        end_at=ist(DAY, 12, 40),
        duration_s=2400,
    )
    kept = TrackGap(
        id=gap_id(duty.id, ist(DAY, 12, 45)),
        tenant_id=mini.tid,
        duty_session_id=duty.id,
        officer_id=duty.officer_id,
        start_at=ist(DAY, 12, 45),
        end_at=ist(DAY, 13, 30),
        duration_s=2700,
        reason="other",
        reason_at=ist(DAY, 14),
    )
    await mini.add(ghost, kept)
    await process_session(db_session, duty)
    ids = set(
        (
            await db_session.execute(select(TrackGap.id).where(TrackGap.duty_session_id == duty.id))
        ).scalars()
    )
    assert ghost.id not in ids and kept.id in ids and gap_id(duty.id, ist(DAY, 10, 20)) in ids


async def test_me_day_roles(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    resp = await client.get(
        "/v1/me/day", params={"date": str(DAY)}, headers=bearer(mini.user("cluster_head"))
    )
    assert resp.status_code == 200  # cluster heads go on duty too
    for role in ("store_manager", "owner", "farmer_user"):
        resp = await client.get(
            "/v1/me/day", params={"date": str(DAY)}, headers=bearer(mini.user(role))
        )
        assert resp.status_code == 403, role
