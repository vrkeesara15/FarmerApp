"""VA-E01 v2: a failed Play Integrity verdict on one of the officer's requests that day
(``audit_log.integrity``, SEC-024) is an integrity reason like mock location or root."""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models import AuditLog
from tests.rules.harness import DEFAULT_NOW, base_world, load_fixture, run_fixture, when


async def _audit(
    session: AsyncSession, tenant_id: uuid.UUID, actor: uuid.UUID, status: str, at: object
) -> None:
    session.add(
        AuditLog(
            tenant_id=tenant_id,
            actor_id=actor,
            actor_role="field_officer",
            action="payment.create",
            entity="payment",
            entity_id=uuid.uuid4(),
            integrity={"status": status, "actions": ["payment_collection"], "reasons": []},
            created_at=at,
        )
    )
    await session.flush()


async def test_failed_play_integrity_on_the_same_day_raises_the_flag(
    db_session: AsyncSession,
) -> None:
    data = load_fixture("VA-E01", "negative")  # clean duty, points and visit
    world = await base_world(db_session)
    now = when(data["now"], DEFAULT_NOW)
    officer = world.refs["officer"]
    await _audit(db_session, world.tenant_id, officer, "failed", now - timedelta(hours=1))
    await _audit(db_session, world.tenant_id, officer, "unavailable", now - timedelta(hours=1))
    other = world.refs["officer2"]
    await _audit(db_session, world.tenant_id, other, "failed", now - timedelta(hours=1))
    _, outcome = await run_fixture(db_session, "VA-E01", data, world=world)
    assert len(outcome.flags) == 1
    flag = outcome.flags[0]
    assert flag.subject_id == officer and flag.rule_version == 2
    metrics = flag.evidence["metrics"]
    assert metrics["reasons"] == ["play_integrity_failed"]
    assert metrics["play_integrity_failed"] == 1  # "unavailable" is recorded, not flagged
    assert any(r["type"] == "audit_log" for r in flag.evidence["records"])


async def test_unavailable_or_other_days_do_not_flag(db_session: AsyncSession) -> None:
    data = load_fixture("VA-E01", "negative")
    world = await base_world(db_session)
    now = when(data["now"], DEFAULT_NOW)
    officer = world.refs["officer"]
    await _audit(db_session, world.tenant_id, officer, "unavailable", now - timedelta(hours=1))
    await _audit(db_session, world.tenant_id, officer, "failed", now - timedelta(days=3))
    _, outcome = await run_fixture(db_session, "VA-E01", data, world=world)
    assert outcome.flags == []
