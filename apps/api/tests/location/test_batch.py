"""FA-010 / VV-001 / VV-002 location batch ingest: points are stored only inside a duty
session's window (nothing before start, nothing after end), every stored point carries the
VV-002 metadata with the server-computed clock drift, duplicates and future points are
refused, and a batch replay (sync ``op_id`` or ``Idempotency-Key``) stores nothing twice."""

from __future__ import annotations

import uuid
from datetime import timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.location.models import LocationPoint
from tests.duty.conftest import DEVICE, DutyCtx, point, point_count, start_duty
from tests.sync.conftest import op, sync


async def _rows(session: AsyncSession, officer_id: uuid.UUID, since: object) -> list[LocationPoint]:
    rows = await session.execute(
        select(LocationPoint)
        .where(LocationPoint.officer_id == officer_id, LocationPoint.ts >= since)
        .order_by(LocationPoint.ts)
    )
    return list(rows.scalars())


# ------------------------------------------------------------------ FA-010: on duty only
async def test_no_points_are_stored_without_a_duty_session(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    before = await point_count(db_session, accepted.officer.id)
    body = accepted.batch_body(uuid.uuid4(), [point(accepted.now - timedelta(minutes=1))])
    resp = await client.post("/v1/location/batch", json=body, headers=accepted.headers)
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    result = await sync(
        client, accepted.ctx, [op("location_batch", "create", body)], headers=accepted.headers
    )
    assert result["results"][0]["status"] == "rejected"
    assert result["results"][0]["error"]["code"] == "not_found"
    assert await point_count(db_session, accepted.officer.id) == before


async def test_points_before_start_and_after_end_are_rejected_off_duty(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    start = accepted.now - timedelta(hours=1)
    started = await start_duty(client, accepted, start_at=start.isoformat())
    before = await point_count(db_session, accepted.officer.id)

    early = [
        point(start - timedelta(minutes=30)),
        point(start - timedelta(minutes=3)),
        point(start - timedelta(minutes=1)),  # inside the 2-minute slack
        point(start + timedelta(minutes=10)),
    ]
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], early),
        headers=accepted.headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["accepted"] == 2
    assert resp.json()["rejected"] == [
        {"index": 0, "reason": "off_duty"},
        {"index": 1, "reason": "off_duty"},
    ]
    assert await point_count(db_session, accepted.officer.id) == before + 2

    end_at = accepted.now
    resp = await client.post("/v1/duty/end", json=accepted.end_body(), headers=accepted.headers)
    assert resp.status_code == 200, resp.text
    accepted.clock.advance(timedelta(minutes=20))  # the app flushes its buffer later
    late = [
        point(end_at + timedelta(minutes=1)),  # inside the slack after the end
        point(end_at + timedelta(minutes=3)),
        point(end_at + timedelta(minutes=15)),
        point(start + timedelta(minutes=20)),  # a late sample from inside the session
    ]
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], late),
        headers=accepted.headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["accepted"] == 2
    assert resp.json()["rejected"] == [
        {"index": 1, "reason": "off_duty"},
        {"index": 2, "reason": "off_duty"},
    ]
    assert await point_count(db_session, accepted.officer.id) == before + 4
    # An all-off-duty batch is applied (idempotent) and stores nothing.
    body = await sync(
        client,
        accepted.ctx,
        [
            op(
                "location_batch",
                "create",
                accepted.batch_body(
                    started["id"],
                    [point(end_at + timedelta(minutes=10)), point(end_at + timedelta(hours=1))],
                ),
            )
        ],
        headers=accepted.headers,
    )
    assert body["results"][0]["status"] == "applied"
    assert body["results"][0]["server"]["accepted"] == 0
    assert body["results"][0]["server"]["rejected"] == [
        {"index": 0, "reason": "off_duty"},
        {"index": 1, "reason": "future"},  # an hour past the server clock: never stored either
    ]
    assert await point_count(db_session, accepted.officer.id) == before + 4


# ------------------------------------------------------------------ VV-002 metadata
async def test_every_stored_point_has_the_vv002_fields_and_the_server_clock_drift(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    start = accepted.now - timedelta(hours=1)
    started = await start_duty(client, accepted, start_at=start.isoformat())
    sent_at = accepted.now + timedelta(seconds=37)  # the device clock runs 37 s ahead
    points = [
        point(
            start + timedelta(minutes=5),
            speed_mps=0.0,
            battery_pct=91,
            bearing=None,
            provider="gps",
        ),
        point(
            start + timedelta(minutes=7),
            speed_mps=8.4,
            battery_pct=90,
            is_mock=True,
            is_rooted=True,
        ),
        point(start + timedelta(minutes=9), battery_pct=None, speed_mps=None, provider=None),
    ]
    body = accepted.batch_body(started["id"], points, sent_at=sent_at.isoformat())
    resp = await client.post("/v1/location/batch", json=body, headers=accepted.headers)
    assert resp.status_code == 200, resp.text
    out = resp.json()
    assert out["accepted"] == 3 and out["rejected"] == []
    assert out["clock_drift_s"] == 37
    assert out["received_at"] == accepted.now.isoformat().replace("+00:00", "Z")

    rows = await _rows(db_session, accepted.officer.id, start)
    assert len(rows) == 3
    for row in rows:
        assert row.tenant_id == accepted.tenant_id
        assert row.duty_session_id == uuid.UUID(started["id"])
        assert row.accuracy_m == 8.0
        assert row.clock_drift_s == 37
        assert row.received_at == accepted.now
        assert isinstance(row.is_mock, bool) and isinstance(row.is_rooted, bool)
        assert abs(row.lat - 18.02) < 1e-6 and abs(row.lon - 79.55) < 1e-6
    first, second, third = rows
    assert (first.speed_mps, first.battery_pct, first.bearing, first.provider) == (
        0.0,
        91,
        None,
        "gps",
    )
    assert (second.speed_mps, second.battery_pct, second.bearing) == (8.4, 90, 90.0)
    assert second.is_mock is True and second.is_rooted is True and first.is_mock is False
    assert (third.speed_mps, third.battery_pct, third.provider) == (None, None, None)

    # A device clock behind the server gives a negative drift.
    body = accepted.batch_body(
        started["id"],
        [point(start + timedelta(minutes=11))],
        sent_at=(accepted.now - timedelta(seconds=400)).isoformat(),
    )
    resp = await client.post("/v1/location/batch", json=body, headers=accepted.headers)
    assert resp.json()["clock_drift_s"] == -400
    assert (await _rows(db_session, accepted.officer.id, start))[-1].clock_drift_s == -400

    track = await client.get(
        f"/v1/officers/{accepted.officer.id}/track",
        params={"day": "2026-09-21"},
        headers=accepted.headers,
    )
    assert track.status_code == 200 and track.json()["count"] == 4
    assert {p["clock_drift_s"] for p in track.json()["points"]} == {37, -400}


# ------------------------------------------------------------------ future / duplicates
async def test_future_and_duplicate_points_are_rejected(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    start = accepted.now - timedelta(hours=1)
    started = await start_duty(client, accepted, start_at=start.isoformat())
    before = await point_count(db_session, accepted.officer.id)
    t1 = start + timedelta(minutes=5)
    points = [
        point(accepted.now + timedelta(minutes=5)),  # future
        point(accepted.now + timedelta(minutes=1)),  # within the 2-minute future slack
        point(t1),
        point(t1, east_m=50),  # same ts in the same batch
    ]
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], points),
        headers=accepted.headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["accepted"] == 2
    assert resp.json()["rejected"] == [
        {"index": 0, "reason": "future"},
        {"index": 3, "reason": "duplicate"},
    ]
    # The same ts again in a later batch (the device re-sent an old buffer).
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], [point(t1), point(t1 + timedelta(minutes=1))]),
        headers=accepted.headers,
    )
    assert resp.json()["accepted"] == 1
    assert resp.json()["rejected"] == [{"index": 0, "reason": "duplicate"}]
    assert await point_count(db_session, accepted.officer.id) == before + 3


# ------------------------------------------------------------------ idempotent replay
async def test_batch_replay_by_op_id_and_idempotency_key_stores_nothing_twice(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    start = accepted.now - timedelta(hours=1)
    started = await start_duty(client, accepted, start_at=start.isoformat())
    before = await point_count(db_session, accepted.officer.id)
    batch_id = uuid.uuid4()
    body = accepted.batch_body(
        started["id"], [point(start + timedelta(minutes=m)) for m in (3, 6, 9)], id=str(batch_id)
    )
    batch_op = op("location_batch", "create", body, entity_id=batch_id)
    first = await sync(client, accepted.ctx, [batch_op], headers=accepted.headers)
    second = await sync(client, accepted.ctx, [batch_op], headers=accepted.headers)
    assert first["results"][0]["status"] == "applied"
    assert first["results"][0]["server"]["accepted"] == 3
    assert first["results"][0]["entity_id"] == str(batch_id)
    assert second["results"][0]["status"] == "duplicate"
    assert second["results"][0]["server"] == first["results"][0]["server"]
    assert await point_count(db_session, accepted.officer.id) == before + 3
    # No change-feed row for a batch (points are never in the feed).
    assert not [c for c in first["changes"] if c["entity"] == "location_batch"]

    rest = accepted.batch_body(
        started["id"], [point(start + timedelta(minutes=m)) for m in (12, 15)]
    )
    headers = {**accepted.headers, "Idempotency-Key": "batch-1"}
    r1 = await client.post("/v1/location/batch", json=rest, headers=headers)
    r2 = await client.post("/v1/location/batch", json=rest, headers=headers)
    assert r1.status_code == 200 and r2.status_code == 200 and r1.json() == r2.json()
    assert r1.json()["accepted"] == 2
    assert await point_count(db_session, accepted.officer.id) == before + 5
    # Same key, different body: refused.
    r3 = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], [point(start + timedelta(minutes=18))]),
        headers=headers,
    )
    assert r3.status_code == 422 and r3.json()["code"] == "idempotency_key_reuse"


# ------------------------------------------------------------------ validation / scope
async def test_batch_size_and_point_validation(client: AsyncClient, accepted: DutyCtx) -> None:
    started = await start_duty(client, accepted)
    start = accepted.now - timedelta(hours=1)
    too_many = [point(start + timedelta(seconds=i)) for i in range(501)]
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], too_many),
        headers=accepted.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "validation_error"
    resp = await client.post(
        "/v1/location/batch", json=accepted.batch_body(started["id"], []), headers=accepted.headers
    )
    assert resp.status_code == 422
    bad = point(start, accuracy_m=-1)
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], [bad]),
        headers=accepted.headers,
    )
    assert resp.status_code == 422
    bad = point(start, provider="wifi")
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], [bad]),
        headers=accepted.headers,
    )
    assert resp.status_code == 422
    exactly = [point(start + timedelta(seconds=i)) for i in range(500)]
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], exactly),
        headers=accepted.headers,
    )
    assert resp.status_code == 200 and resp.json()["accepted"] == 500


async def test_a_colleague_cannot_upload_into_another_officers_session(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    started = await start_duty(client, accepted)
    before = await point_count(db_session, accepted.other_officer.id)
    body = accepted.batch_body(started["id"], [point(accepted.now - timedelta(minutes=5))])
    resp = await client.post("/v1/location/batch", json=body, headers=accepted.other_headers)
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    result = await sync(
        client, accepted.ctx, [op("location_batch", "create", body)], headers=accepted.other_headers
    )
    assert result["results"][0]["status"] == "rejected"
    assert await point_count(db_session, accepted.other_officer.id) == before
    # ... and nothing landed in the owner's session either.
    rows = await _rows(db_session, accepted.officer.id, accepted.now - timedelta(minutes=6))
    assert rows == []
    assert body["device_id"] == DEVICE
