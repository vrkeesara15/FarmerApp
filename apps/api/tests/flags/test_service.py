"""VA-003 routing, VA-002 dedupe and OPS-010 SLA escalation."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole, UserStatus
from farmerapp.flags import service
from farmerapp.flags.models import Flag, FlagEvent, FlagStatus
from farmerapp.flags.routing import ladder_level, next_level, route, subject_scope
from farmerapp.notifications.models import Notification
from farmerapp.rules.registry import Evidence, Finding
from farmerapp.rules.schema import Mode, Subject
from tests.flags.conftest import RULES, Flagged, make_flag
from tests.logcontract import assert_fields, capture, json_events, one_event
from tests.rules.harness import DEFAULT_NOW, add_user, base_world


async def test_routing_employee_and_farmer_flags(
    flagged: Flagged, db_session: AsyncSession
) -> None:
    world = flagged.world
    burst = flagged.one("officer")
    assert burst.owner_id == world.refs["cluster_head"] and burst.owner_role == "cluster_head"
    assert burst.watchers == [world.refs["auditor"]]
    assert burst.scope_cluster_id == world.refs["c1"] and burst.scope_store_id == world.refs["s1"]
    farm = flagged.one("left")
    assert farm.owner_id == world.refs["store_manager"] and farm.watchers == []
    assert farm.sla_due_at == farm.created_at + timedelta(hours=72)

    notes = (
        (
            await db_session.execute(
                select(Notification.user_id).where(
                    Notification.kind == "flag_assigned",
                    Notification.data["flag_id"].astext == str(burst.id),
                )
            )
        )
        .scalars()
        .all()
    )
    assert sorted(map(str, notes)) == sorted(
        [str(world.refs["cluster_head"]), str(world.refs["auditor"])]
    )


async def test_routing_falls_back_up_the_ladder(db_session: AsyncSession) -> None:
    world = await base_world(db_session)
    farmer = await make_flag(db_session, world, "officer", subject=Subject.FARMER, rule_id="VA-F03")
    # a "farmer" id that is not a farmer: no scope -> no store manager / cluster head
    assert farmer.owner_role == "auditor"

    world.users["store_manager"].status = UserStatus.DISABLED.value
    await db_session.flush()
    from tests.rules.harness import add_farmer

    f = await add_farmer(db_session, world, {"ref": "f1"}, DEFAULT_NOW)
    target = await route(
        db_session,
        tenant_id=world.tenant_id,
        subject_type=Subject.FARMER,
        subject_id=f.id,
        owner_role="store_manager",
        severity="low",
    )
    assert target.owner_id == world.refs["cluster_head"] and target.watchers == []

    loose = await add_user(db_session, world, "loose", UserRole.FIELD_OFFICER, store="s1")
    scope = await subject_scope(db_session, Subject.EMPLOYEE, loose.id)
    assert scope.cluster_id == world.refs["c1"]  # through the store
    assert (await subject_scope(db_session, Subject.EMPLOYEE, uuid.uuid4())).cluster_id is None
    assert (
        await subject_scope(db_session, Subject.STORE, world.refs["s1"])
    ).cluster_id == world.refs["c1"]
    visit_scope = await subject_scope(db_session, Subject.VISIT, uuid.uuid4())
    assert visit_scope.cluster_id is None and visit_scope.store_id is None

    assert ladder_level(None) == -1
    assert ladder_level("director") == 3
    assert ladder_level("owner") == 3
    scope = await subject_scope(db_session, Subject.FARMER, f.id)
    assert await next_level(db_session, world.tenant_id, scope, "owner") is None


async def test_dedupe_and_rule_versions(db_session: AsyncSession) -> None:
    world = await base_world(db_session)
    rule = RULES.get("VA-F06")
    finding = Finding(
        subject_type=Subject.EMPLOYEE,
        subject_id=world.refs["officer"],
        key="burst:2026-09-18",
        title="Burst",
        evidence=Evidence(),
    )
    kwargs = {
        "tenant_id": world.tenant_id,
        "finding": finding,
        "mode": Mode.BATCH,
        "now": DEFAULT_NOW,
    }
    first = await service.raise_flag(db_session, rule=rule, **kwargs)  # type: ignore[arg-type]
    assert first is not None
    assert await service.raise_flag(db_session, rule=rule, **kwargs) is None  # type: ignore[arg-type]

    first.status = FlagStatus.RESOLVED_VALID.value
    first.resolved_at = DEFAULT_NOW
    await db_session.flush()
    # reviewed under this version: not raised again
    assert await service.raise_flag(db_session, rule=rule, **kwargs) is None  # type: ignore[arg-type]
    bumped = rule.model_copy(update={"version": rule.version + 1})
    second = await service.raise_flag(db_session, rule=bumped, **kwargs)  # type: ignore[arg-type]
    assert second is not None and second.rule_version == rule.version + 1


async def test_dedupe_race_hits_the_unique_index(
    db_session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    world = await base_world(db_session)
    finding = Finding(
        subject_type=Subject.EMPLOYEE, subject_id=world.refs["officer"], key="x", title="t"
    )
    kwargs = {
        "tenant_id": world.tenant_id,
        "finding": finding,
        "mode": Mode.EVENT,
        "now": DEFAULT_NOW,
    }
    rule = RULES.get("VA-F06")
    assert await service.raise_flag(db_session, rule=rule, **kwargs) is not None  # type: ignore[arg-type]

    async def never(*_args: object) -> bool:
        return False

    monkeypatch.setattr(service, "_already_known", never)
    assert await service.raise_flag(db_session, rule=rule, **kwargs) is None  # type: ignore[arg-type]
    rows = (
        await db_session.execute(select(Flag.id).where(Flag.tenant_id == world.tenant_id))
    ).all()
    assert len(rows) == 1


async def test_sla_escalation_climbs_the_ladder(flagged: Flagged, db_session: AsyncSession) -> None:
    world = flagged.world
    burst = flagged.one("officer")
    farm = flagged.one("left")
    later = DEFAULT_NOW + timedelta(hours=49)  # past the 48 h VA-F06 SLA, not the 72 h VA-F03
    moved = await service.escalate_overdue(
        db_session, world.tenant_id, now=later, sla_hours={"VA-F06": 48}
    )
    assert {m.flag_id for m in moved} == {burst.id, flagged.one("officer2").id}
    await db_session.refresh(burst)
    assert burst.owner_id == world.refs["auditor"] and burst.escalation_level == 1
    assert burst.sla_due_at == later + timedelta(hours=48)
    assert burst.status == FlagStatus.OPEN.value  # the SLA job never changes the status
    event = (
        await db_session.execute(
            select(FlagEvent).where(
                FlagEvent.flag_id == burst.id, FlagEvent.kind == "sla_escalated"
            )
        )
    ).scalar_one()
    assert event.from_owner_id == world.refs["cluster_head"]
    assert event.to_owner_id == world.refs["auditor"]

    much_later = later + timedelta(days=3)
    await service.escalate_overdue(db_session, world.tenant_id, now=much_later)
    await db_session.refresh(burst)
    await db_session.refresh(farm)
    assert burst.owner_id == world.refs["owner"] and burst.escalation_level == 2
    assert farm.owner_id == world.refs["cluster_head"]  # store manager -> cluster head
    assert burst.sla_due_at == much_later + timedelta(hours=service.DEFAULT_SLA_HOURS)

    top = await service.escalate_overdue(
        db_session, world.tenant_id, now=much_later + timedelta(days=9)
    )
    assert burst.id not in {m.flag_id for m in top}  # the owner is the top of the ladder


async def test_flag_raised_log_contract(
    db_session: AsyncSession, caplog: pytest.LogCaptureFixture
) -> None:
    """``farmerapp_flags_raised{rule_id}``: logged on insert, not on a deduped re-raise."""
    capture(caplog)
    world = await base_world(db_session)
    flag = await make_flag(db_session, world, "officer", key="log-contract")
    line = one_event(caplog, "flag_raised")
    assert_fields(line, tenant_id=str, rule_id=str, flag_id=str, flag_severity=str)
    assert line["rule_id"] == "VA-F06" and line["flag_id"] == str(flag.id)
    assert line["tenant_id"] == str(world.tenant_id)
    before = len(json_events(caplog, "flag_raised"))
    rule = RULES.get("VA-F06")
    again = await service.raise_flag(
        db_session,
        tenant_id=world.tenant_id,
        rule=rule,
        finding=Finding(
            subject_type=Subject.EMPLOYEE,
            subject_id=world.refs["officer"],
            key="log-contract",
            title="Test flag",
        ),
        mode=Mode.BATCH,
        now=DEFAULT_NOW,
    )
    assert again is None and len(json_events(caplog, "flag_raised")) == before


async def test_sla_escalation_notifies_the_new_owner_and_skips_resolved_or_due_flags(
    flagged: Flagged, db_session: AsyncSession
) -> None:
    """OPS-010: one level up per pass, a ``flag_escalated`` notification to the new owner;
    resolved flags and flags still inside their SLA are left alone."""
    world = flagged.world
    burst, shared = flagged.one("officer"), flagged.one("officer2")
    farm = flagged.one("left")
    shared.status = FlagStatus.RESOLVED_VALID.value
    shared.resolved_at = DEFAULT_NOW
    await db_session.flush()
    later = DEFAULT_NOW + timedelta(hours=49)  # VA-F06 (48 h) overdue, VA-F03 (72 h) not
    moved = await service.escalate_overdue(db_session, world.tenant_id, now=later)
    assert [m.flag_id for m in moved] == [burst.id]
    assert moved[0].to_role == "auditor" and moved[0].to_owner_id == world.refs["auditor"]
    await db_session.refresh(farm)
    assert farm.escalation_level == 0 and farm.owner_id == world.refs["store_manager"]
    notes = (
        (
            await db_session.execute(
                select(Notification).where(
                    Notification.kind == "flag_escalated",
                    Notification.data["flag_id"].astext == str(burst.id),
                )
            )
        )
        .scalars()
        .all()
    )
    assert [n.user_id for n in notes] == [world.refs["auditor"]]
    assert notes[0].title_key == "notification.flag_escalated.title"
    assert notes[0].data["rule_id"] == "VA-F06"
    # A second pass within the fresh SLA moves nothing.
    assert await service.escalate_overdue(db_session, world.tenant_id, now=later) == []
