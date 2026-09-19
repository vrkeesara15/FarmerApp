"""SPEC 6.1 runners: inline (FA-012 write paths), event (in-process + Pub/Sub worker) and batch
(job + CLI); a failing rule never breaks the write or the other rules."""

from __future__ import annotations

import base64
import contextlib
import json
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typer.testing import CliRunner

from farmerapp.db.geo import ACRE_M2, offset
from farmerapp.db.session import tenant_scope
from farmerapp.flags.models import Flag
from farmerapp.jobs.cli import cli
from farmerapp.payments.events import PaymentCaptured
from farmerapp.rules import events, jobs, registry
from farmerapp.rules.engine import run_batch, run_rules
from farmerapp.rules.loader import DEFAULT_RULES_DIR, load_rules
from farmerapp.rules.schema import Mode
from farmerapp.worker.messages import PubSubMessage
from tests.authz.conftest import Bearer
from tests.rules.harness import (
    DEFAULT_NOW,
    VILLAGE_LAT,
    VILLAGE_LON,
    BaseWorld,
    add_farmer,
    base_world,
    load_fixture,
    run_fixture,
)

RULES = load_rules(DEFAULT_RULES_DIR)


def _square(east_m: float, acres: float = 1.0) -> dict[str, Any]:
    side = (acres * ACRE_M2) ** 0.5
    corners = [(east_m, 0.0), (east_m + side, 0.0), (east_m + side, side), (east_m, side)]
    ring = [list(offset(VILLAGE_LON, VILLAGE_LAT, e, n)) for e, n in corners]
    return {"type": "Polygon", "coordinates": [[*ring, ring[0]]]}


def _farmer_body(world: BaseWorld, phone: str, name: str, **extra: Any) -> dict[str, Any]:
    return {"phone": phone, "name": name, "village_id": str(world.refs["v1"]), **extra}


async def _flags(session: AsyncSession, world: BaseWorld, rule_id: str | None = None) -> list[Flag]:
    stmt = select(Flag).where(Flag.tenant_id == world.tenant_id)
    if rule_id:
        stmt = stmt.where(Flag.rule_id == rule_id)
    return list((await session.execute(stmt.order_by(Flag.created_at))).scalars())


@pytest.fixture
async def world(db_session: AsyncSession) -> BaseWorld:
    return await base_world(db_session)


# --------------------------------------------------------------------------- inline
async def test_registration_raises_inline_flags_next_to_warnings(
    client: AsyncClient, bearer: Bearer, world: BaseWorld, db_session: AsyncSession
) -> None:
    headers = bearer(world.users["officer"])
    first = await client.post(
        "/v1/farmers",
        json=_farmer_body(
            world,
            "+919012300001",
            "Mallesh Goud",
            farms=[{"area_acres": "1.0", "boundary": _square(0)}],
        ),
        headers=headers,
    )
    assert first.status_code == 201, first.text
    assert await _flags(db_session, world) == []

    second = await client.post(
        "/v1/farmers",
        json=_farmer_body(
            world,
            "+919012300002",
            "Malesh Goud",
            farms=[{"area_acres": "1.0", "boundary": _square(20)}],
        ),
        headers=headers,
    )
    assert second.status_code == 201, second.text
    assert "farm_overlap" in second.json()["warnings"]  # FA-012 response unchanged
    new_id = second.json()["id"]
    flags = await _flags(db_session, world)
    assert {(f.rule_id, str(f.subject_id), f.raised_by_mode) for f in flags} == {
        ("VA-F02", new_id, "inline"),
        ("VA-F03", new_id, "inline"),
    }
    duplicate = next(f for f in flags if f.rule_id == "VA-F02")
    assert duplicate.owner_id == world.refs["store_manager"]
    assert {r["id"] for r in duplicate.evidence["records"]} >= {new_id, first.json()["id"]}

    # Editing the farm to a sane, separate boundary is re-checked; the open flag is not duplicated.
    farm_id = second.json()["farms"][0]["id"]
    resp = await client.patch(
        f"/v1/farms/{farm_id}", json={"boundary": _square(500)}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    resp = await client.patch(
        f"/v1/farmers/{new_id}", json={"name": "Malesh Goud S"}, headers=headers
    )
    assert resp.status_code == 200
    resp = await client.post(
        f"/v1/farmers/{new_id}/farms",
        json={"area_acres": "1.0", "boundary": _square(1000, acres=2.5)},
        headers=headers,
    )
    assert resp.status_code == 201 and resp.json()["warnings"] == ["area_mismatch"]
    f03 = await _flags(db_session, world, "VA-F03")
    assert len(f03) == 2  # the overlap flag stays open for review; one for the new farm


async def test_registration_burst_is_an_event_flag(
    client: AsyncClient, bearer: Bearer, world: BaseWorld, db_session: AsyncSession
) -> None:
    headers = {**bearer(world.users["officer"]), "X-Device-Id": "tablet-1"}
    for i in range(9):
        resp = await client.post(
            "/v1/farmers",
            json=_farmer_body(world, f"+91902340{i:04d}", f"Farmer Number {i}"),
            headers=headers,
        )
        assert resp.status_code == 201, resp.text
    flags = await _flags(db_session, world, "VA-F06")
    assert [(f.subject_id, f.raised_by_mode, f.severity) for f in flags] == [
        (world.refs["officer"], "event", "high")
    ]
    assert flags[0].owner_id == world.refs["cluster_head"]
    assert flags[0].watchers == [world.refs["auditor"]]

    # the same tablet used by a second officer: a shared-device flag
    resp = await client.post(
        "/v1/farmers",
        json=_farmer_body(world, "+919023409999", "Another Farmer"),
        headers={**bearer(world.users["officer2"]), "X-Device-Id": "tablet-1"},
    )
    assert resp.status_code == 201
    reasons = sorted(
        f.evidence["metrics"]["reason"] for f in await _flags(db_session, world, "VA-F06")
    )
    assert reasons == ["registration_burst", "shared_device"]


async def test_a_failing_rule_never_breaks_the_write(
    client: AsyncClient,
    bearer: Bearer,
    world: BaseWorld,
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def boom(_ctx: registry.RuleContext) -> list[registry.Finding]:
        raise RuntimeError("rule bug")

    monkeypatch.setitem(registry._REGISTRY, "VA-F01", boom)
    resp = await client.post(
        "/v1/farmers",
        json=_farmer_body(
            world,
            "+919012399999",
            "Ravi",
            farms=[{"area_acres": "1.0", "boundary": _square(0, 2.5)}],
        ),
        headers=bearer(world.users["officer"]),
    )
    assert resp.status_code == 201, resp.text
    assert [f.rule_id for f in await _flags(db_session, world)] == ["VA-F03"]

    report = await run_batch(db_session, world.tenant_id, now=DEFAULT_NOW, rule_set=RULES)
    assert report.failed == ["VA-F01"]
    assert "VA-F03" in report.rules_run


async def test_rule_without_implementation_is_reported(
    db_session: AsyncSession, world: BaseWorld, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delitem(registry._REGISTRY, "VA-F02")
    report = await run_rules(
        db_session, world.tenant_id, Mode.BATCH, rule_ids=["VA-F02"], rule_set=RULES
    )
    assert report.failed == ["VA-F02"] and report.rules_run == []


# --------------------------------------------------------------------------- event (worker)
def _message(payload: dict[str, Any]) -> PubSubMessage:
    return PubSubMessage(
        data=base64.b64encode(json.dumps(payload).encode()).decode(), messageId="m"
    )


def _provider(session: AsyncSession) -> Any:
    @contextlib.asynccontextmanager
    async def provide(tenant_id: uuid.UUID) -> AsyncIterator[AsyncSession]:
        async with tenant_scope(session, tenant_id):
            yield session

    return provide


async def test_worker_runs_event_rules(db_session: AsyncSession, world: BaseWorld) -> None:
    data = load_fixture("VA-F06", "positive")
    data = {**data, "seed": {"farmers": data["seed"]["farmers"][:9]}}  # the burst only
    now = datetime.now(UTC)
    for spec in data["seed"]["farmers"]:
        await add_farmer(db_session, world, spec, now)
    msg = _message({"tenant_id": str(world.tenant_id), "farmer_id": str(world.refs["b9"])})
    report = await events.handle_event_message(
        "farmer.registered", msg, session_provider=_provider(db_session), rule_set=RULES, now=now
    )
    assert report is not None and report.total_raised == 1
    again = await events.handle_event_message(
        "farmer.registered", msg, session_provider=_provider(db_session), rule_set=RULES, now=now
    )
    assert again is not None and again.total_raised == 0  # redelivery is a no-op

    assert (
        await events.handle_event_message(
            "farmer.registered", _message({"x": 1}), session_provider=_provider(db_session)
        )
        is None
    )
    assert (
        await events.handle_event_message(
            "payment.webhook", msg, session_provider=_provider(db_session), rule_set=RULES
        )
        is None  # no event rule on the topic yet: no database work
    )


async def test_payment_subscriber_is_a_noop_without_rules(db_session: AsyncSession) -> None:
    events.register()
    event = PaymentCaptured(
        tenant_id=uuid.uuid4(),
        payment_id=uuid.uuid4(),
        order_id=uuid.uuid4(),
        store_id=uuid.uuid4(),
        farmer_id=None,
        mode="cash",
        amount_paise=100,
        provider_event_id=None,
        at=DEFAULT_NOW,
    )
    await events._on_payment_captured(db_session, event)


async def test_payment_subscriber_runs_subscribed_rules(
    db_session: AsyncSession, world: BaseWorld, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen: list[Any] = []

    async def fake_emit(
        session: AsyncSession, tenant_id: uuid.UUID, topic: str, ids: Any, **kw: Any
    ) -> None:
        seen.append((tenant_id, topic, list(ids)))

    class Rules:
        def for_mode(self, mode: Mode, *, trigger: str | None = None) -> list[str]:
            return ["VA-E10"]

    monkeypatch.setattr(events, "get_rule_set", lambda: Rules())
    monkeypatch.setattr(events, "emit", fake_emit)
    payment = uuid.uuid4()
    await events._on_payment_captured(
        db_session,
        PaymentCaptured(
            tenant_id=world.tenant_id,
            payment_id=payment,
            order_id=uuid.uuid4(),
            store_id=world.refs["s1"],
            farmer_id=None,
            mode="upi_qr",
            amount_paise=100,
            provider_event_id="evt",
            at=DEFAULT_NOW,
        ),
    )
    assert seen == [(world.tenant_id, "payment.captured", [payment])]


# --------------------------------------------------------------------------- batch (job + CLI)
async def test_batch_job_is_idempotent(db_session: AsyncSession, world: BaseWorld) -> None:
    data = load_fixture("VA-F03", "positive")
    await run_fixture(db_session, "VA-F03", {**data, "mode": "batch"}, rule_set=RULES, world=world)
    before = len(await _flags(db_session, world))
    reports = await jobs.run_rules_job(
        [world.tenant_id], session_provider=_provider(db_session), rule_set=RULES, now=DEFAULT_NOW
    )
    assert reports[0].mode == Mode.BATCH and reports[0].total_raised == 0
    assert set(reports[0].rules_run) == {
        "VA-F01",
        "VA-F02",
        "VA-F03",
        "VA-F06",
        "VA-E03",
        "VA-E04",
        "VA-E05",
    }  # the nightly batch rules; event-only rules (VA-F08, VA-E01/E02/E08) never run here
    assert len(await _flags(db_session, world)) == before

    sla = await jobs.run_sla_escalation(
        [world.tenant_id],
        session_provider=_provider(db_session),
        rule_set=RULES,
        now=datetime(2030, 1, 1, tzinfo=UTC),
    )
    assert len(sla[0].escalations) == before


def test_resolve_tenant() -> None:
    from farmerapp.jobs.seed import DEMO_TENANTS

    fcc = next(t for t in DEMO_TENANTS if t.slug == "fcc")
    assert jobs.resolve_tenant("fcc") == fcc.id
    tid = uuid.uuid4()
    assert jobs.resolve_tenant(str(tid)) == tid
    with pytest.raises(jobs.UnknownTenantError):
        jobs.resolve_tenant("nope")


def test_cli_run_rules_and_sla(monkeypatch: pytest.MonkeyPatch) -> None:
    from collections import Counter

    from farmerapp.flags.service import Escalation
    from farmerapp.rules.engine import RunReport

    calls: list[Any] = []
    tid = uuid.uuid4()

    async def fake_rules(tenants: Any, *, mode: Mode, rule_ids: Any) -> list[RunReport]:
        calls.append((list(tenants), mode, rule_ids))
        return [
            RunReport(
                tenant_id=tid,
                mode=mode,
                rules_run=["VA-F02"],
                findings=Counter({"VA-F02": 2}),
                raised=Counter({"VA-F02": 1}),
                failed=["VA-F01"],
            )
        ]

    async def fake_sla(tenants: Any) -> list[jobs.SlaReport]:
        return [
            jobs.SlaReport(
                tenant_id=tid,
                escalations=[Escalation(uuid.uuid4(), "VA-F06", None, uuid.uuid4(), "auditor")],
            )
        ]

    monkeypatch.setattr(jobs, "run_rules_job", fake_rules)
    monkeypatch.setattr(jobs, "run_sla_escalation", fake_sla)
    runner = CliRunner()
    result = runner.invoke(
        cli,
        [
            "run-rules",
            "--mode",
            "batch",
            "--tenant",
            "fcc",
            "--tenant",
            str(tid),
            "--rule",
            "VA-F02",
        ],
    )
    assert result.exit_code == 0, result.output
    assert "raised=1" in result.output and "VA-F01 FAILED" in result.output
    assert calls[0][1] == Mode.BATCH and calls[0][2] == ["VA-F02"] and calls[0][0][1] == tid

    result = runner.invoke(cli, ["flags-sla-escalation", "--tenant", str(tid)])
    assert result.exit_code == 0 and "escalated=1" in result.output and "auditor" in result.output

    assert runner.invoke(cli, ["run-rules", "--tenant", "nope"]).exit_code != 0
    assert runner.invoke(cli, ["run-rules", "--tenant", "fcc", "--mode", "hourly"]).exit_code != 0
    assert runner.invoke(cli, ["run-rules", "--tenant", "fcc", "--mode", "event"]).exit_code != 0
