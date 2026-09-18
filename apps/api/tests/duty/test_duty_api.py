"""FA-010 duty start / end (REST twins and ``duty_session`` sync ops), FA-011 / VV-010 gate
at start, VV-001 sampling policy, SPEC 2.6 scope (store managers never, officers own)."""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.geo import point_wkt
from farmerapp.location.models import DutyEndReason, DutySession
from farmerapp.tenants.settings import DEFAULT_LOCATION_POLICY_VERSION
from tests.duty.conftest import (
    BASE_LAT,
    BASE_LON,
    DEVICE,
    DutyCtx,
    accept_policy,
    point,
    set_tenant_settings,
    start_duty,
)
from tests.sync.conftest import op, sync

NEW_VERSION = "2026-10-v2"


# ------------------------------------------------------------------ FA-011 / VV-010 gate
async def test_start_is_rejected_until_the_current_policy_is_accepted(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    await set_tenant_settings(db_session, dctx.tenant, location_policy_version=NEW_VERSION)
    resp = await client.post("/v1/duty/start", json=dctx.start_body(), headers=dctx.headers)
    assert resp.status_code == 422, resp.text
    body = resp.json()
    assert body["code"] == "policy_not_accepted" and body["required_version"] == NEW_VERSION
    assert (
        await db_session.scalar(
            select(DutySession).where(
                DutySession.officer_id == dctx.officer.id, DutySession.end_at.is_(None)
            )
        )
        is None
    )
    # Accept the new version (the app fetched it again), then start with it.
    accepted = await accept_policy(client, dctx)
    assert accepted["version"] == NEW_VERSION
    started = await start_duty(client, dctx, policy_version=NEW_VERSION)
    assert started["policy_version"] == NEW_VERSION


async def test_start_with_a_stale_app_policy_version_is_rejected(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    resp = await client.post(
        "/v1/duty/start",
        json=accepted.start_body(policy_version="2025-01-v0"),
        headers=accepted.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "policy_not_accepted"


# ------------------------------------------------------------------ start / current / end
async def test_start_stores_the_session_and_current_reports_it(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    before = await client.get("/v1/duty/current", headers=accepted.headers)
    assert before.status_code == 200 and before.json()["session"] is None
    assert before.json()["policy_accepted"] is True
    assert before.json()["policy_version"] == DEFAULT_LOCATION_POLICY_VERSION

    started = await start_duty(client, accepted, integrity={"is_mock": True, "clock_drift_s": 400})
    assert started["officer_id"] == str(accepted.officer.id)
    assert started["tenant_id"] == str(accepted.tenant_id)
    assert started["end_at"] is None and started["end_reason"] is None
    assert started["km"] is None and started["stops"] == []
    assert started["start_point"] == {"lat": BASE_LAT, "lon": BASE_LON}
    assert started["policy_version"] == DEFAULT_LOCATION_POLICY_VERSION
    assert started["device_id"] == DEVICE and started["app_version"] == "0.2.0"
    assert started["device_integrity"] == {
        "is_mock": True,
        "is_rooted": False,
        "clock_drift_s": 400,
    }
    assert started["version"] == 1 and started["duration_s"] is None

    current = await client.get("/v1/duty/current", headers=accepted.headers)
    assert current.json()["session"]["id"] == started["id"]
    row = await db_session.get(DutySession, uuid.UUID(started["id"]))
    assert row is not None and row.start_at == accepted.now - timedelta(hours=1)


async def test_second_start_is_rejected_while_a_session_is_active(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    started = await start_duty(client, accepted)
    resp = await client.post("/v1/duty/start", json=accepted.start_body(), headers=accepted.headers)
    assert resp.status_code == 409, resp.text
    assert resp.json()["code"] == "duty_already_active"
    assert resp.json()["duty_session_id"] == started["id"]


async def test_a_stale_open_session_is_forced_closed_by_a_new_start(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    stale = DutySession(
        tenant_id=accepted.tenant_id,
        officer_id=accepted.officer.id,
        start_at=accepted.now - timedelta(hours=25),
        start_point=point_wkt(BASE_LON, BASE_LAT),
        policy_version=DEFAULT_LOCATION_POLICY_VERSION,
    )
    db_session.add(stale)
    await db_session.flush()
    started = await start_duty(client, accepted)
    await db_session.refresh(stale)
    assert stale.end_reason == DutyEndReason.FORCED
    assert stale.end_at is not None and stale.end_at <= accepted.now - timedelta(hours=1)
    assert stale.km == Decimal("0.00")
    assert started["id"] != str(stale.id) and started["end_at"] is None


async def test_start_in_the_future_is_clamped_to_now(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    started = await start_duty(
        client, accepted, start_at=(accepted.now + timedelta(hours=2)).isoformat()
    )
    assert started["start_at"] == (accepted.now + timedelta(minutes=2)).isoformat().replace(
        "+00:00", "Z"
    )


async def test_end_computes_km_and_stops_from_the_points(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    started = await start_duty(client, accepted)
    start = accepted.now - timedelta(hours=1)
    points: list[dict[str, Any]] = [
        point(start + timedelta(minutes=i * 3), east_m=i * 1000) for i in range(5)
    ]  # 4 km at 20 km/h
    points += [
        point(start + timedelta(minutes=14), east_m=4000 + 5),
        point(start + timedelta(minutes=17), east_m=4000 + 8),
        point(start + timedelta(minutes=20), east_m=4000 + 3),
    ]  # a 6-minute stop
    points.append(point(start + timedelta(minutes=21), east_m=50_000, accuracy_m=500.0))  # ignored
    points.append(point(start + timedelta(minutes=22), east_m=100_000))  # implausible jump
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], points),
        headers=accepted.headers,
    )
    assert resp.status_code == 200 and resp.json()["accepted"] == 10, resp.text

    resp = await client.post(
        "/v1/duty/end",
        json=accepted.end_body(end_point={"lat": BASE_LAT, "lon": BASE_LON + 0.01}),
        headers=accepted.headers,
    )
    assert resp.status_code == 200, resp.text
    ended = resp.json()
    assert ended["id"] == started["id"] and ended["end_reason"] == "manual"
    assert ended["end_at"] == accepted.now.isoformat().replace("+00:00", "Z")
    assert ended["duration_s"] == 3600
    assert Decimal("3.99") <= Decimal(ended["km"]) <= Decimal("4.05")
    assert len(ended["stops"]) == 1
    stop = ended["stops"][0]  # the run starts at the last road point (12 min) and lasts 8 min
    assert stop["duration_s"] == 480 and stop["points"] == 4
    assert stop["start"] == (start + timedelta(minutes=12)).isoformat()
    assert stop["end"] == (start + timedelta(minutes=20)).isoformat()
    assert abs(ended["end_point"]["lon"] - (BASE_LON + 0.01)) < 1e-6
    assert ended["version"] == 2

    current = await client.get("/v1/duty/current", headers=accepted.headers)
    assert current.json()["session"] is None


async def test_end_without_an_active_session_is_409(client: AsyncClient, accepted: DutyCtx) -> None:
    resp = await client.post("/v1/duty/end", json=accepted.end_body(), headers=accepted.headers)
    assert resp.status_code == 409 and resp.json()["code"] == "no_active_duty"


async def test_end_reported_by_the_device_as_auto_keeps_its_reason(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    await start_duty(client, accepted)
    resp = await client.post(
        "/v1/duty/end",
        json=accepted.end_body(end_reason="auto_idle", end_point=None),
        headers=accepted.headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["end_reason"] == "auto_idle" and resp.json()["end_point"] is None


async def test_start_replay_with_idempotency_key_returns_the_same_session(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    headers = {**accepted.headers, "Idempotency-Key": "duty-start-1"}
    first = await client.post("/v1/duty/start", json=accepted.start_body(), headers=headers)
    second = await client.post("/v1/duty/start", json=accepted.start_body(), headers=headers)
    assert first.status_code == 201 and second.status_code == 201
    assert first.json()["id"] == second.json()["id"]


# ------------------------------------------------------------------ VV-001 sampling policy
async def test_duty_policy_comes_from_the_tenant_settings(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    resp = await client.get("/v1/duty/policy", headers=dctx.headers)
    assert resp.status_code == 200, resp.text
    assert resp.json() == {
        "moving_interval_s": 120,
        "stationary_interval_s": 600,
        "upload_interval_s": 900,
        "upload_on_wifi_or_charging": True,
    }
    await set_tenant_settings(
        db_session, dctx.tenant, sampling={"moving_s": 60, "stationary_s": 300, "upload_s": 600}
    )
    resp = await client.get("/v1/duty/policy", headers=dctx.head_headers)
    assert resp.json()["moving_interval_s"] == 60 and resp.json()["upload_interval_s"] == 600


# ------------------------------------------------------------------ SPEC 2.6 scope
@pytest.mark.parametrize(
    "role",
    [UserRole.STORE_MANAGER, UserRole.ACCOUNTANT, UserRole.AGRONOMIST, UserRole.FARMER],
)
async def test_non_duty_roles_are_forbidden_on_every_duty_and_track_route(
    client: AsyncClient, dctx: DutyCtx, bearer: Any, role: UserRole
) -> None:
    headers = bearer(dctx.world.a.user(role))
    for method, path, body in (
        ("GET", "/v1/duty/current", None),
        ("GET", "/v1/duty/policy", None),
        ("POST", "/v1/duty/start", dctx.start_body()),
        ("POST", "/v1/duty/end", dctx.end_body()),
        ("POST", "/v1/location/batch", dctx.batch_body(uuid.uuid4(), [point(dctx.now)])),
        ("GET", "/v1/duty-sessions", None),
        ("GET", f"/v1/officers/{dctx.officer.id}/track?day=2026-09-21", None),
    ):
        resp = await client.request(method, path, json=body, headers=headers)
        assert resp.status_code == 403, (role, method, path, resp.text)
        assert resp.json()["code"] == "forbidden"


async def test_an_officer_sees_only_their_own_session(
    client: AsyncClient, accepted: DutyCtx
) -> None:
    started = await start_duty(client, accepted)
    mine = await client.get("/v1/duty-sessions", params={"limit": 100}, headers=accepted.headers)
    assert started["id"] in {s["id"] for s in mine.json()["items"]}
    assert {s["officer_id"] for s in mine.json()["items"]} == {str(accepted.officer.id)}
    theirs = await client.get(
        "/v1/duty-sessions", params={"limit": 100}, headers=accepted.other_headers
    )
    assert started["id"] not in {s["id"] for s in theirs.json()["items"]}
    other_current = await client.get("/v1/duty/current", headers=accepted.other_headers)
    assert other_current.json()["session"] is None
    # The cluster head of the officer's cluster sees it in the listing.
    if accepted.officer.cluster_id == accepted.cluster_head.cluster_id:
        head = await client.get(
            "/v1/duty-sessions", params={"limit": 100}, headers=accepted.head_headers
        )
        assert started["id"] in {s["id"] for s in head.json()["items"]}


# ------------------------------------------------------------------ sync ops
async def test_sync_duty_session_create_replay_conflict_and_end(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    duty_id = uuid.uuid4()
    create = op("duty_session", "create", accepted.start_body(), entity_id=duty_id)
    body = await sync(client, accepted.ctx, [create], headers=accepted.headers)
    result = body["results"][0]
    assert result["status"] == "applied" and result["version"] == 1, result
    assert result["server"]["id"] == str(duty_id) and result["server"]["end_at"] is None
    # The feed carries the new session for its owner.
    assert ("duty_session", str(duty_id)) in {
        (c["entity"], c["entity_id"]) for c in body["changes"]
    }

    replay = await sync(client, accepted.ctx, [create], headers=accepted.headers)
    assert replay["results"][0]["status"] == "duplicate"
    assert replay["results"][0]["server"]["id"] == str(duty_id)

    again = op("duty_session", "create", accepted.start_body(), entity_id=duty_id)
    conflict = await sync(client, accepted.ctx, [again], headers=accepted.headers)
    assert conflict["results"][0]["status"] == "conflict"
    assert conflict["results"][0]["server"]["id"] == str(duty_id)

    # Points, then the end op: km is server-owned and computed from them.
    start = accepted.now - timedelta(hours=1)
    batch = op(
        "location_batch",
        "create",
        accepted.batch_body(
            duty_id, [point(start + timedelta(minutes=i * 3), east_m=i * 1000) for i in range(3)]
        ),
    )
    end = op(
        "duty_session",
        "update",
        {**accepted.end_body(), "km": 999, "stops": [{"fake": True}]},
        entity_id=duty_id,
        base_version=1,
    )
    body = await sync(client, accepted.ctx, [batch, end], headers=accepted.headers)
    assert body["results"][0]["status"] == "applied"
    assert body["results"][0]["server"]["accepted"] == 3
    ended = body["results"][1]
    assert ended["status"] == "applied" and ended["version"] == 2, ended
    assert ended["server"]["end_reason"] == "manual"
    assert Decimal("1.99") <= Decimal(ended["server"]["km"]) <= Decimal("2.01")
    assert ended["server"]["stops"] == []

    # Ending again: the session is closed, the device adopts the server state.
    body = await sync(
        client,
        accepted.ctx,
        [op("duty_session", "update", accepted.end_body(), entity_id=duty_id, base_version=2)],
        headers=accepted.headers,
    )
    assert body["results"][0]["status"] == "conflict"
    assert body["results"][0]["server"]["version"] == 2


async def test_sync_duty_create_needs_the_policy_and_a_colleague_cannot_end_it(
    client: AsyncClient, dctx: DutyCtx, db_session: AsyncSession
) -> None:
    await set_tenant_settings(db_session, dctx.tenant, location_policy_version=NEW_VERSION)
    duty_id = uuid.uuid4()
    body = await sync(
        client,
        dctx.ctx,
        [op("duty_session", "create", dctx.start_body(), entity_id=duty_id)],
        headers=dctx.headers,
    )
    rejected = body["results"][0]
    assert rejected["status"] == "rejected" and rejected["error"]["code"] == "policy_not_accepted"
    assert rejected["error"]["status"] == 422
    assert await db_session.get(DutySession, duty_id) is None

    await accept_policy(client, dctx)
    body = await sync(
        client,
        dctx.ctx,
        [
            op(
                "duty_session",
                "create",
                dctx.start_body(policy_version=NEW_VERSION),
                entity_id=duty_id,
            )
        ],
        headers=dctx.headers,
    )
    assert body["results"][0]["status"] == "applied"
    body = await sync(
        client,
        dctx.ctx,
        [op("duty_session", "update", dctx.end_body(), entity_id=duty_id, base_version=1)],
        headers=dctx.other_headers,
    )
    assert body["results"][0]["status"] == "rejected"
    assert body["results"][0]["error"]["code"] == "not_found"
    row = await db_session.get(DutySession, duty_id)
    assert row is not None and row.end_at is None


async def test_sync_end_after_a_server_auto_end_keeps_the_server_end(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    from farmerapp.duty.service import close_session

    started = await start_duty(client, accepted)
    duty = await db_session.get_one(DutySession, uuid.UUID(started["id"]))
    auto_end_at = accepted.now - timedelta(minutes=30)
    await close_session(db_session, duty, end_at=auto_end_at, end_reason=DutyEndReason.AUTO_TIME)
    body = await sync(
        client,
        accepted.ctx,
        [op("duty_session", "update", accepted.end_body(), entity_id=duty.id, base_version=1)],
        headers=accepted.headers,
    )
    result = body["results"][0]
    assert result["status"] == "conflict"
    assert result["server"]["end_reason"] == "auto_time"
    assert result["server"]["end_at"] == auto_end_at.isoformat().replace("+00:00", "Z")
    await db_session.refresh(duty)
    assert duty.end_at == auto_end_at and duty.end_reason == DutyEndReason.AUTO_TIME
