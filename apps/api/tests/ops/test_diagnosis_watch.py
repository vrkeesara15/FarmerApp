"""OPS-009 / DX-006: queue-age alert at 18 h (once), stale queued re-delivery, daily LLM
fallback rate with the 40 % alert."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.diagnosis.encoder import FakeEncoder
from farmerapp.diagnosis.llm import FakeLlmDiagnosisClient
from farmerapp.diagnosis.models import Diagnosis
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.notifications.models import Notification
from farmerapp.ops.diagnosis_watch import (
    LLM_RATE_ALERT,
    diagnosis_watch,
    run_diagnosis_watch,
)
from farmerapp.payments.publisher import RecordingPublisher
from farmerapp.settings import get_settings
from farmerapp.uploads.blobstore import LocalBlobStore
from tests.authz.conftest import World
from tests.logcontract import assert_fields, capture, one_event

NOW = datetime(2026, 9, 19, 12, 0, tzinfo=UTC)


async def _diagnosis(
    session: AsyncSession,
    world: World,
    *,
    status: str,
    age: timedelta,
    llm_used: bool = False,
    answered: bool = True,
) -> Diagnosis:
    farmer = world.a.farmer
    row = Diagnosis(
        tenant_id=world.a.tenant.id,
        subject="officer",
        farmer_id=farmer.id,
        requested_by=world.a.user(UserRole.FIELD_OFFICER).id,
        images=[],
        status=status,
        model_versions={},
        llm_used=llm_used,
        answered_at=NOW - age if answered else None,
        created_at=NOW - age,
    )
    session.add(row)
    await session.flush()
    return row


async def test_queue_age_alerts_once_per_diagnosis(
    db_session: AsyncSession, world: World, caplog: pytest.LogCaptureFixture
) -> None:
    capture(caplog)
    old = await _diagnosis(db_session, world, status="provisional", age=timedelta(hours=19))
    await _diagnosis(db_session, world, status="out_of_scope", age=timedelta(hours=2))
    await _diagnosis(db_session, world, status="answered", age=timedelta(hours=30))
    report = await diagnosis_watch(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert report.queue == 2 and report.overdue == 1 and report.alerted == [old.id]
    assert report.oldest_hours == pytest.approx(19.0)
    assert report.notified == [world.a.user(UserRole.AGRONOMIST).id]
    note = (
        await db_session.execute(
            select(Notification).where(Notification.kind == "diagnosis_queue_aged")
        )
    ).scalar_one()
    assert note.data["count"] == 1 and note.data["oldest_diagnosis_id"] == str(old.id)
    line = one_event(caplog, "diagnosis_queue_aged")
    assert_fields(line, tenant_id=str, newly_overdue=int, overdue=int, notified=int)
    snapshot = one_event(caplog, "diagnosis_queue_snapshot")
    assert_fields(snapshot, tenant_id=str, queue=int, overdue=int)
    # a second run does not alert again
    again = await diagnosis_watch(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert again.alerted == [] and again.overdue == 1
    count = await db_session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.kind == "diagnosis_queue_aged")
    )
    assert count == 1


async def test_llm_fallback_rate_alerts_above_40_percent_once_a_day(
    db_session: AsyncSession, world: World, caplog: pytest.LogCaptureFixture
) -> None:
    capture(caplog)
    for i in range(6):
        await _diagnosis(
            db_session,
            world,
            status="provisional" if i < 3 else "answered",
            age=timedelta(minutes=10 + i),
            llm_used=i < 3,
        )
    report = await diagnosis_watch(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert report.answered == 6 and report.llm_fallbacks == 3
    assert report.llm_rate == 0.5 > LLM_RATE_ALERT and report.llm_alert
    rate = one_event(caplog, "diagnosis_llm_fallback_rate")
    assert_fields(rate, tenant_id=str, answered=int, llm_fallbacks=int, rate=float)
    alert = one_event(caplog, "diagnosis_llm_fallback_alert")
    assert alert["level"] == "warning"
    recipients = set(
        (
            await db_session.execute(
                select(Notification.user_id).where(Notification.kind == "diagnosis_llm_rate")
            )
        ).scalars()
    )
    assert recipients == {world.a.user(UserRole.AGRONOMIST).id, world.a.owner.id}
    await diagnosis_watch(db_session, tenant_id=world.a.tenant.id, now=NOW)
    count = await db_session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.kind == "diagnosis_llm_rate")
    )
    assert count == 2  # not repeated the same day


async def test_low_rate_and_small_sample_do_not_alert(
    db_session: AsyncSession, world: World, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO)
    await _diagnosis(
        db_session, world, status="provisional", age=timedelta(minutes=5), llm_used=True
    )
    small = await diagnosis_watch(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert small.llm_rate == 1.0 and not small.llm_alert  # below the minimum sample
    for i in range(9):
        await _diagnosis(db_session, world, status="answered", age=timedelta(minutes=6 + i))
    low = await diagnosis_watch(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert low.llm_rate == 0.1 and not low.llm_alert
    empty = await diagnosis_watch(
        db_session, tenant_id=world.a.tenant.id, now=NOW, day=NOW.date() - timedelta(days=3)
    )
    assert empty.llm_rate is None and empty.answered == 0


async def test_stale_queued_diagnoses_are_delivered_again(
    db_session: AsyncSession, world: World, tmp_path: object
) -> None:
    stale = await _diagnosis(
        db_session, world, status="queued", age=timedelta(minutes=40), answered=False
    )
    await _diagnosis(db_session, world, status="queued", age=timedelta(minutes=2), answered=False)
    publisher = RecordingPublisher()
    services = DiagnosisServices(
        settings=get_settings(),
        encoder=FakeEncoder(),
        llm=FakeLlmDiagnosisClient(),
        blobs=LocalBlobStore(str(tmp_path)),
        publisher=publisher,
    )
    report = await diagnosis_watch(
        db_session, tenant_id=world.a.tenant.id, now=NOW, services=services
    )
    assert report.redelivered == [stale.id]
    assert publisher.messages[0][1]["diagnosis_id"] == str(stale.id)


async def test_the_job_entry_point_binds_each_tenant(monkeypatch: pytest.MonkeyPatch) -> None:
    import contextlib

    from farmerapp.ops import diagnosis_watch as mod

    seen: list[uuid.UUID] = []

    @contextlib.asynccontextmanager
    async def fake_session(tenant_id: uuid.UUID):  # type: ignore[no-untyped-def]
        seen.append(tenant_id)
        yield object()

    async def fake_watch(session: object, **kwargs: object) -> str:
        return f"report {kwargs['tenant_id']}"

    monkeypatch.setattr(mod, "job_session", fake_session)
    monkeypatch.setattr(mod, "diagnosis_watch", fake_watch)
    tenants = [uuid.uuid4(), uuid.uuid4()]
    reports = await run_diagnosis_watch(tenants, now=NOW)
    assert seen == tenants and reports == [f"report {t}" for t in tenants]  # type: ignore[comparison-overlap]
