"""M4 event rules on the duty / location write paths (SPEC 6.1): ``POST /v1/duty/start`` with
FA-028 integrity issues raises VA-E01 in the same transaction, a location batch with an
impossible jump raises VA-E02 (and a mock point VA-E01, deduped per officer and day), a
replayed batch raises nothing, and a failing rule never breaks the ingest."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.flags.models import Flag
from farmerapp.location import events as location_events
from farmerapp.rules import registry
from farmerapp.visits.events import EventBus
from tests.duty.conftest import DutyCtx, point, start_duty


async def _flags(session: AsyncSession, dctx: DutyCtx, rule_id: str) -> list[Flag]:
    async with tenant_scope(session, dctx.tenant_id):
        rows = await session.execute(
            select(Flag)
            .where(Flag.rule_id == rule_id, Flag.subject_id == dctx.officer.id)
            .order_by(Flag.created_at)
        )
        return list(rows.scalars())


async def test_duty_start_with_a_rooted_phone_raises_va_e01(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    started = await start_duty(
        client,
        accepted,
        integrity={"is_mock": False, "is_rooted": True, "clock_drift_s": -420},
    )
    [flag] = await _flags(db_session, accepted, "VA-E01")
    assert flag.raised_by_mode == "event" and flag.severity == "high"
    assert flag.owner_role == UserRole.CLUSTER_HEAD.value and flag.watchers
    assert flag.evidence["metrics"]["reasons"] == ["clock_drift", "rooted_device"]
    assert {"type": "duty_session", "id": started["id"]} in flag.evidence["records"]


async def test_location_batch_raises_va_e02_and_dedupes_va_e01(
    client: AsyncClient, accepted: DutyCtx, db_session: AsyncSession
) -> None:
    started = await start_duty(client, accepted)
    assert await _flags(db_session, accepted, "VA-E01") == []  # a clean start
    now = accepted.now
    points = [
        point(now - timedelta(minutes=30)),
        point(now - timedelta(minutes=29), east_m=100),
        point(now - timedelta(minutes=24), east_m=12_000),  # 11.9 km in 5 min
        point(now - timedelta(minutes=20), east_m=12_100, is_mock=True),
    ]
    body = accepted.batch_body(started["id"], points)
    headers = {**accepted.headers, "Idempotency-Key": str(uuid.uuid4())}
    resp = await client.post("/v1/location/batch", json=body, headers=headers)
    assert resp.status_code == 200 and resp.json()["accepted"] == 4, resp.text

    [travel] = await _flags(db_session, accepted, "VA-E02")
    assert travel.evidence["metrics"]["speed_kmh"] > 90
    assert len(travel.evidence["map"]["points"]) == 2
    [integrity] = await _flags(db_session, accepted, "VA-E01")
    assert integrity.evidence["metrics"]["reasons"] == ["mock_location"]

    # the replay stores nothing and raises nothing
    resp = await client.post("/v1/location/batch", json=body, headers=headers)
    assert resp.status_code == 200
    # a later batch the same day: the open flags are not duplicated (one per officer-day)
    later = [point(now - timedelta(minutes=10), east_m=40_000, is_rooted=True)]
    resp = await client.post(
        "/v1/location/batch",
        json=accepted.batch_body(started["id"], later),
        headers=accepted.headers,
    )
    assert resp.status_code == 200 and resp.json()["accepted"] == 1
    assert len(await _flags(db_session, accepted, "VA-E02")) == 1
    assert len(await _flags(db_session, accepted, "VA-E01")) == 1


async def test_a_failing_rule_never_breaks_the_batch(
    client: AsyncClient,
    accepted: DutyCtx,
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def boom(_ctx: registry.RuleContext) -> list[registry.Finding]:
        raise RuntimeError("rule bug")

    monkeypatch.setitem(registry._REGISTRY, "VA-E02", boom)
    started = await start_duty(client, accepted)
    now = accepted.now
    body = accepted.batch_body(
        started["id"],
        [point(now - timedelta(minutes=5)), point(now - timedelta(minutes=4), east_m=9_000)],
    )
    resp = await client.post("/v1/location/batch", json=body, headers=accepted.headers)
    assert resp.status_code == 200 and resp.json()["accepted"] == 2
    assert await _flags(db_session, accepted, "VA-E02") == []


async def test_async_subscriber_failures_are_isolated(db_session: AsyncSession) -> None:
    bus = EventBus()
    seen: list[object] = []

    async def failing(_session: AsyncSession, _event: object) -> None:
        raise RuntimeError("subscriber bug")

    async def working(_session: AsyncSession, event: object) -> None:
        seen.append(event)

    bus.subscribe_async(location_events.DutyStarted, failing)
    bus.subscribe_async(location_events.DutyStarted, working)
    bus.subscribe_async(location_events.DutyStarted, working)  # once
    bus.subscribe(location_events.DutyStarted, seen.append)
    event = location_events.DutyStarted(
        tenant_id=uuid.uuid4(),
        duty_session_id=uuid.uuid4(),
        officer_id=uuid.uuid4(),
        at=datetime.now(UTC),
    )
    assert await bus.dispatch(db_session, event) == 2 and seen == [event, event]
    bus.unsubscribe_async(location_events.DutyStarted, failing)
    bus.unsubscribe_async(location_events.DutyStarted, failing)  # unknown: no-op
    assert await bus.dispatch(db_session, event) == 2
