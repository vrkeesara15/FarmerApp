"""VA-F06 times registrations by when the device captured them, not when they synced.

Officers capture farmers offline and sync them together; the server ``created_at`` values of
one sync batch are seconds apart. The sync ``farmer`` create stores the op's ``client_ts`` as
``farmer.captured_at`` (capped at the server time) and the burst window uses it.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.farmers.models import Farmer
from farmerapp.flags.models import Flag
from farmerapp.rules.engine import run_batch
from farmerapp.rules.loader import DEFAULT_RULES_DIR, RuleSet, load_rules
from tests.authz.conftest import Bearer
from tests.rules.harness import BaseWorld, add_farmer, base_world

RULES = load_rules(DEFAULT_RULES_DIR)


def _tuned(max_registrations: int) -> RuleSet:
    """The shipped rule set with a lower VA-F06 threshold (a YAML-only change, VA-001)."""
    f06 = RULES.get("VA-F06")
    params = {**f06.params, "max_registrations": max_registrations}
    return RuleSet(
        rules={**RULES.rules, "VA-F06": f06.model_copy(update={"params": params})},
        directory=RULES.directory,
    )


async def _f06(session: AsyncSession, world: BaseWorld) -> list[Flag]:
    stmt = select(Flag).where(Flag.tenant_id == world.tenant_id, Flag.rule_id == "VA-F06")
    return list((await session.execute(stmt)).scalars())


@pytest.fixture
async def world(db_session: AsyncSession) -> BaseWorld:
    return await base_world(db_session)


async def _seed_batch(
    session: AsyncSession, world: BaseWorld, now: datetime, captured: list[str | None]
) -> None:
    """Farmers that all reached the server a minute ago, captured at ``captured``."""
    for i, at in enumerate(captured):
        spec: dict[str, Any] = {"ref": f"f{i}", "registered_by": "officer", "at": "-1m"}
        if at is not None:
            spec["captured"] = at
        await add_farmer(session, world, spec, now)


async def test_five_captures_over_two_hours_synced_together_are_not_a_burst(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    now = datetime.now(UTC)
    rules = _tuned(4)  # more than 4 in under 30 minutes is a burst
    await _seed_batch(db_session, world, now, ["-120m", "-90m", "-60m", "-30m", "-2m"])
    report = await run_batch(db_session, world.tenant_id, now=now, rule_set=rules)
    assert "VA-F06" in report.rules_run
    assert await _f06(db_session, world) == []


async def test_without_capture_times_the_same_batch_is_a_burst(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    """Control: online registrations (no capture time) fall back to the server time."""
    now = datetime.now(UTC)
    await _seed_batch(db_session, world, now, [None] * 5)
    await run_batch(db_session, world.tenant_id, now=now, rule_set=_tuned(4))
    flags = await _f06(db_session, world)
    assert [f.evidence["metrics"]["reason"] for f in flags] == ["registration_burst"]


async def test_captures_inside_the_window_are_still_a_burst(
    db_session: AsyncSession, world: BaseWorld
) -> None:
    now = datetime.now(UTC)
    await _seed_batch(db_session, world, now, ["-3h", "-2.9h", "-2.8h", "-2.7h", "-2.6h"])
    await run_batch(db_session, world.tenant_id, now=now, rule_set=_tuned(4))
    flags = await _f06(db_session, world)
    assert len(flags) == 1
    first_at = datetime.fromisoformat(flags[0].evidence["metrics"]["first_at"])
    assert first_at == now - timedelta(hours=3)  # the capture time, not the sync time


def _create(world: BaseWorld, i: int, client_ts: datetime) -> dict[str, Any]:
    return {
        "op_id": str(uuid.uuid4()),
        "entity": "farmer",
        "action": "create",
        "entity_id": str(uuid.uuid4()),
        "base_version": 0,
        "payload": {
            "phone": f"+91903450{i:04d}",
            "name": f"Offline Farmer {i}",
            "village_id": str(world.refs["v1"]),
        },
        "client_ts": client_ts.isoformat(),
    }


async def _sync(client: AsyncClient, headers: dict[str, str], ops: list[dict[str, Any]]) -> None:
    resp = await client.post(
        "/v1/sync", json={"device_id": "tablet-f06", "cursor": None, "ops": ops}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    assert {r["status"] for r in resp.json()["results"]} == {"applied"}, resp.text


async def test_sync_stores_the_capture_time_and_one_batch_is_not_a_burst(
    client: AsyncClient, bearer: Bearer, world: BaseWorld, db_session: AsyncSession
) -> None:
    """Nine offline captures 15 minutes apart, synced in one request (default thresholds:
    more than 8 in under 30 minutes). Event mode runs on every ``farmer.registered``."""
    headers = {**bearer(world.users["officer"]), "X-Device-Id": "tablet-f06"}
    start = datetime.now(UTC) - timedelta(hours=2, minutes=10)
    ops = [_create(world, i, start + timedelta(minutes=15 * i)) for i in range(9)]
    future = _create(world, 99, datetime.now(UTC) + timedelta(days=1))  # a fast device clock
    await _sync(client, headers, [*ops, future])

    rows = {
        str(f.id): f
        for f in (
            await db_session.execute(select(Farmer).where(Farmer.tenant_id == world.tenant_id))
        ).scalars()
    }
    for i, op in enumerate(ops):
        farmer = rows[op["entity_id"]]
        assert farmer.captured_at == start + timedelta(minutes=15 * i)
        assert farmer.captured_at < farmer.created_at
    capped = rows[future["entity_id"]]
    assert capped.captured_at == capped.created_at  # never after the server received it
    assert await _f06(db_session, world) == []


async def test_sync_of_a_real_burst_is_still_flagged(
    client: AsyncClient, bearer: Bearer, world: BaseWorld, db_session: AsyncSession
) -> None:
    headers = {**bearer(world.users["officer"]), "X-Device-Id": "tablet-f06"}
    start = datetime.now(UTC) - timedelta(hours=1)
    await _sync(
        client, headers, [_create(world, i, start + timedelta(minutes=2 * i)) for i in range(9)]
    )
    flags = await _f06(db_session, world)
    assert [(f.subject_id, f.evidence["metrics"]["reason"]) for f in flags] == [
        (world.refs["officer"], "registration_burst")
    ]


async def test_online_registration_has_no_capture_time(
    client: AsyncClient, bearer: Bearer, world: BaseWorld, db_session: AsyncSession
) -> None:
    resp = await client.post(
        "/v1/farmers",
        json={"phone": "+919034599999", "name": "Online", "village_id": str(world.refs["v1"])},
        headers=bearer(world.users["officer"]),
    )
    assert resp.status_code == 201, resp.text
    farmer = await db_session.get(Farmer, uuid.UUID(resp.json()["id"]))
    assert farmer is not None and farmer.captured_at is None
