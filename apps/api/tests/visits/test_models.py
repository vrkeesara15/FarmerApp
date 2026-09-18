"""M2 entities at the ORM level (SPEC 8.2): duty_session, visit (VV-002 / VV-004 / VV-005
fields, generated duration), visit_photo, visit_confirmation, append-only policy_acceptance
(FA-011 / VV-010), village meeting-point radius (VV-003), sync change rows and RLS on every
new table."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.geo import point_wkt
from farmerapp.db.models import AuditLog
from farmerapp.db.rls import APPEND_ONLY_TABLES
from farmerapp.db.session import clear_tenant, tenant_scope
from farmerapp.jobs.seed import SMALL, demo_tenant_id, seed_demo
from farmerapp.location.models import (
    LOCATION_POLICY_KEY,
    DutyEndReason,
    DutySession,
    PolicyAcceptance,
)
from farmerapp.sync.models import SYNC_ENTITIES, SyncChange
from farmerapp.tenants.models import Village
from farmerapp.visits.models import (
    ConfirmationChannel,
    GeofenceResult,
    Visit,
    VisitConfirmation,
    VisitPhoto,
    VisitPurpose,
    VisitStatus,
)
from tests.farmers.conftest import Graph
from tests.visits.conftest import M2_TABLES

T0 = datetime(2026, 9, 18, 4, 30, tzinfo=UTC)  # 10:00 IST
DEVICE = "device-m2-test"


def _visit(graph: Graph, **overrides: object) -> Visit:
    values: dict[str, object] = {
        "tenant_id": graph.tenant_id,
        "officer_id": graph.officer.id,
        "farmer_id": graph.farmer.id,
        "farm_id": graph.farm.id,
        "village_id": graph.village.id,
        "purpose": VisitPurpose.ADVISORY,
        "checkin_at": T0,
        "checkin_point": point_wkt(79.55, 18.02),
        "checkin_accuracy_m": 9.5,
        "geofence_result": GeofenceResult.INSIDE,
        "device_integrity": {"is_mock": False, "is_rooted": False, "clock_drift_s": 3},
    }
    values.update(overrides)
    return Visit(**values)


async def test_duty_session_round_trip(db_session: AsyncSession, graph: Graph) -> None:
    session = DutySession(
        tenant_id=graph.tenant_id,
        officer_id=graph.officer.id,
        start_at=T0,
        start_point=point_wkt(79.5941, 17.9689),
        policy_version="2026-09-v1",
        device_id=DEVICE,
        app_version="0.2.0",
    )
    db_session.add(session)
    await db_session.flush()
    assert session.end_at is None and session.end_reason is None and session.km is None
    assert session.stops == []
    session.end_at = T0 + timedelta(hours=8)
    session.end_point = point_wkt(79.5941, 17.9689)
    session.end_reason = DutyEndReason.AUTO_TIME
    session.km = Decimal("42.5")
    session.stops = [{"lat": 18.02, "lon": 79.55, "start": T0.isoformat(), "minutes": 25}]
    await db_session.flush()
    loaded = (
        await db_session.execute(select(DutySession).where(DutySession.id == session.id))
    ).scalar_one()
    assert loaded.version == 2 and loaded.km == Decimal("42.50")
    assert loaded.end_reason == "auto_time" and loaded.stops[0]["minutes"] == 25
    assert loaded.start_lat is not None and loaded.start_lon is not None
    assert abs(loaded.start_lat - 17.9689) < 1e-6 and abs(loaded.start_lon - 79.5941) < 1e-6
    assert loaded.end_lat is not None and loaded.end_lon is not None
    assert loaded.duration_s == 8 * 3600


@pytest.mark.parametrize(
    "bad",
    [
        {"end_at": T0 - timedelta(minutes=1), "end_reason": "manual"},  # ends before it starts
        {"end_at": T0 + timedelta(hours=1)},  # ended without a reason
        {"end_reason": "manual"},  # reason without an end
        {"end_at": T0 + timedelta(hours=1), "end_reason": "because"},  # unknown reason
    ],
)
async def test_duty_session_check_constraints(
    db_session: AsyncSession, graph: Graph, bad: dict[str, object]
) -> None:
    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            db_session.add(
                DutySession(
                    tenant_id=graph.tenant_id,
                    officer_id=graph.officer.id,
                    start_at=T0,
                    policy_version="2026-09-v1",
                    **bad,
                )
            )
            await db_session.flush()


async def test_visit_fields_and_generated_duration(db_session: AsyncSession, graph: Graph) -> None:
    """VV-002 / VV-004 / VV-005 / FA-028: every field the scoring and the checks need."""
    visit = _visit(graph, notes="Leaf curl on chilli", crop_stage="flowering")
    db_session.add(visit)
    await db_session.flush()
    await db_session.refresh(visit)  # column properties (lat / lon) load with a SELECT
    assert visit.status == VisitStatus.OPEN and visit.confirmation_channel == "none"
    assert visit.checkout_at is None and visit.duration_s is None and visit.score is None
    assert abs(visit.checkin_lat - 18.02) < 1e-6 and abs(visit.checkin_lon - 79.55) < 1e-6
    assert visit.checkout_lat is None

    visit.checkout_at = T0 + timedelta(minutes=17, seconds=30)
    visit.checkout_point = point_wkt(79.5502, 18.0201)
    visit.score = 80
    visit.score_components = {
        "geofence": 30,
        "confirmation": 30,
        "photo": 0,
        "duration": 10,
        "integrity": 10,
    }
    visit.status = VisitStatus.VERIFIED
    visit.confirmation_channel = ConfirmationChannel.SMS_OTP
    visit.confirmed_at = T0 + timedelta(minutes=5)
    await db_session.flush()
    loaded = (await db_session.execute(select(Visit).where(Visit.id == visit.id))).scalar_one()
    assert loaded.duration_s == 17 * 60 + 30  # generated by the database
    assert loaded.version == 2 and loaded.status == "verified"
    assert loaded.device_integrity == {"is_mock": False, "is_rooted": False, "clock_drift_s": 3}
    assert loaded.score_components is not None and loaded.score_components["geofence"] == 30
    assert loaded.checkout_lat is not None and loaded.checkout_lon is not None
    columns = {
        r[0]
        for r in await db_session.execute(
            text("SELECT column_name FROM information_schema.columns WHERE table_name = 'visit'")
        )
    }
    assert columns >= {
        "officer_id", "farmer_id", "farm_id", "village_id", "purpose", "checkin_at",
        "checkout_at", "checkin_point", "checkin_accuracy_m", "checkout_point",
        "geofence_result", "override_note", "override_approved_by", "notes", "crop_stage",
        "duration_s", "score", "score_components", "status", "confirmation_channel",
        "confirmed_at", "device_integrity", "client_visit_id",
    }  # fmt: skip


@pytest.mark.parametrize(
    "bad",
    [
        {"purpose": "picnic"},
        {"geofence_result": "nearby"},
        {"status": "great"},
        {"confirmation_channel": "carrier_pigeon"},
        {"crop_stage": "ripe"},
        {"checkout_at": T0 - timedelta(minutes=1)},
        {"score": 101},
        {"score": -1},
        {"geofence_result": "override"},  # FA-014: an override needs a note
    ],
)
async def test_visit_check_constraints(
    db_session: AsyncSession, graph: Graph, bad: dict[str, object]
) -> None:
    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            db_session.add(_visit(graph, **bad))
            await db_session.flush()


async def test_override_with_note_and_approver(db_session: AsyncSession, graph: Graph) -> None:
    visit = _visit(
        graph,
        geofence_result=GeofenceResult.OVERRIDE,
        override_note="Farmer met at the canal, farm flooded",
        override_approved_by=graph.officer.id,
    )
    db_session.add(visit)
    await db_session.flush()
    assert visit.override_approved_by == graph.officer.id


async def test_client_visit_id_is_unique_per_tenant(db_session: AsyncSession, graph: Graph) -> None:
    client_id = uuid.uuid4()
    db_session.add(_visit(graph, client_visit_id=client_id))
    await db_session.flush()
    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            db_session.add(_visit(graph, client_visit_id=client_id))
            await db_session.flush()


async def test_visit_photo_and_confirmation(db_session: AsyncSession, graph: Graph) -> None:
    visit = _visit(graph)
    db_session.add(visit)
    await db_session.flush()
    photo = VisitPhoto(
        tenant_id=graph.tenant_id,
        visit_id=visit.id,
        blob_uri=f"gs://farmerapp-local-photos/{graph.tenant_id}/visit_photo/{'a' * 64}",
        sha256="a" * 64,
        phash="c3e1f0b5a9d2c4e8",
        exif_time=T0 + timedelta(minutes=2),
        exif_point=point_wkt(79.5501, 18.0201),
        taken_in_app=True,
        device_time=T0 + timedelta(minutes=2),
        server_time=T0 + timedelta(minutes=40),
    )
    confirmation = VisitConfirmation(
        tenant_id=graph.tenant_id,
        visit_id=visit.id,
        channel=ConfirmationChannel.SMS_OTP,
        farmer_phone_last4="0001",
        confirmed_at=T0 + timedelta(minutes=6),
        confirmed_via_device_id=DEVICE,
    )
    db_session.add_all([photo, confirmation])
    await db_session.flush()
    loaded_photo = (
        await db_session.execute(select(VisitPhoto).where(VisitPhoto.visit_id == visit.id))
    ).scalar_one()
    assert loaded_photo.taken_in_app is True and loaded_photo.phash == "c3e1f0b5a9d2c4e8"
    assert loaded_photo.exif_lat is not None and loaded_photo.exif_lon is not None
    assert (
        abs(loaded_photo.exif_lat - 18.0201) < 1e-6 and abs(loaded_photo.exif_lon - 79.5501) < 1e-6
    )
    loaded_conf = (
        await db_session.execute(
            select(VisitConfirmation).where(VisitConfirmation.visit_id == visit.id)
        )
    ).scalar_one()
    assert loaded_conf.rating is None and loaded_conf.otp_challenge_id is None
    loaded_conf.rating, loaded_conf.rating_reason = 5, "helpful"  # FM-011 later
    await db_session.flush()
    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            db_session.add(
                VisitConfirmation(
                    tenant_id=graph.tenant_id,
                    visit_id=visit.id,
                    channel="none",  # a confirmation always names a real channel
                    confirmed_at=T0,
                )
            )
            await db_session.flush()
    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            loaded_conf.rating = 6
            await db_session.flush()
    db_session.expire(loaded_conf)
    # Photos go with their visit (FK cascade).
    await db_session.delete(visit)
    await db_session.flush()
    assert (
        await db_session.scalar(
            select(func.count()).select_from(VisitPhoto).where(VisitPhoto.visit_id == visit.id)
        )
        == 0
    )


async def test_policy_acceptance_is_append_only(db_session: AsyncSession, graph: Graph) -> None:
    """FA-011 / VV-010: the acceptance record keeps version + timestamp and is never edited."""
    assert "policy_acceptance" in APPEND_ONLY_TABLES
    row = PolicyAcceptance(
        tenant_id=graph.tenant_id,
        user_id=graph.officer.id,
        version="2026-09-v1",
        accepted_at=T0,
        device_id=DEVICE,
        app_version="0.2.0",
        text_hash="b" * 64,
    )
    db_session.add(row)
    await db_session.flush()
    assert row.policy_key == LOCATION_POLICY_KEY == "location_policy"
    for statement in (
        "UPDATE policy_acceptance SET version = 'x' WHERE id = :i",
        "DELETE FROM policy_acceptance WHERE id = :i",
    ):
        with pytest.raises(DBAPIError, match="permission denied"):
            async with db_session.begin_nested():
                await db_session.execute(text(statement), {"i": row.id})
    # A newer policy is a new row; the latest per (user, key) is the accepted version.
    db_session.add(
        PolicyAcceptance(
            tenant_id=graph.tenant_id,
            user_id=graph.officer.id,
            version="2026-12-v2",
            accepted_at=T0 + timedelta(days=90),
        )
    )
    await db_session.flush()
    latest = await db_session.scalar(
        select(PolicyAcceptance.version)
        .where(PolicyAcceptance.user_id == graph.officer.id)
        .order_by(PolicyAcceptance.accepted_at.desc())
        .limit(1)
    )
    assert latest == "2026-12-v2"


async def test_village_meeting_point_radius(db_session: AsyncSession, graph: Graph) -> None:
    """VV-003: per-village radius, NULL means the tenant's ``geofence_radius_m``."""
    assert graph.village.meeting_point_radius_m is None
    graph.village.meeting_point = point_wkt(79.551, 18.021)
    graph.village.meeting_point_radius_m = 250
    await db_session.flush()
    value = await db_session.scalar(
        select(Village.meeting_point_radius_m).where(Village.id == graph.village.id)
    )
    assert value == 250
    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            graph.village.meeting_point_radius_m = 0
            await db_session.flush()
    db_session.expire(graph.village)


async def test_m2_writes_are_audited_and_fed_to_sync(
    db_session: AsyncSession, graph: Graph
) -> None:
    assert {"visit", "visit_photo", "duty_session", "policy_acceptance"} <= set(SYNC_ENTITIES)
    visit = _visit(graph)
    duty = DutySession(
        tenant_id=graph.tenant_id,
        officer_id=graph.officer.id,
        start_at=T0,
        policy_version="2026-09-v1",
    )
    db_session.add_all([visit, duty])
    await db_session.flush()
    visit.notes = "updated"
    await db_session.flush()
    audits = (
        await db_session.execute(
            select(AuditLog.action).where(AuditLog.entity.in_(["visit", "duty_session"]))
        )
    ).scalars()
    assert sorted(audits) == ["duty_session.create", "visit.create", "visit.update"]
    changes = (
        await db_session.execute(
            select(SyncChange.entity, SyncChange.action, SyncChange.version)
            .where(SyncChange.entity.in_(["visit", "duty_session"]))
            .order_by(SyncChange.seq)
        )
    ).all()
    assert [tuple(c) for c in changes] == [
        ("visit", "create", 1),
        ("duty_session", "create", 1),
        ("visit", "update", 2),
    ]


# ------------------------------------------------------------------ RLS on every M2 table
@pytest.mark.parametrize("table", M2_TABLES)
async def test_rls_hides_other_tenants_on_every_m2_table(
    db_session: AsyncSession, table: str
) -> None:
    await seed_demo(db_session, SMALL)
    fcc, gfl = demo_tenant_id("fcc"), demo_tenant_id("gfl")
    if table == "location_daily_agg":  # written by the purge job, not the seed
        for tid in (fcc, gfl):
            async with tenant_scope(db_session, tid):
                officer = await db_session.scalar(select(DutySession.officer_id).limit(1))
                await db_session.execute(
                    text(
                        "INSERT INTO location_daily_agg (tenant_id, officer_id, day, km, points, "
                        "first_ts, last_ts) VALUES (:t, :o, '2026-01-01', 1, 1, now(), now())"
                    ),
                    {"t": tid, "o": officer},
                )
    async with tenant_scope(db_session, fcc):
        rows = (await db_session.execute(text(f'SELECT tenant_id FROM "{table}"'))).all()
        assert rows and {r[0] for r in rows} == {fcc}
    async with tenant_scope(db_session, gfl):
        rows = (await db_session.execute(text(f'SELECT tenant_id FROM "{table}"'))).all()
        assert rows and {r[0] for r in rows} == {gfl}
    await clear_tenant(db_session)
    assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0


async def test_foreign_tenant_visit_is_rejected(db_session: AsyncSession, graph: Graph) -> None:
    with pytest.raises(DBAPIError, match="row-level security"):
        async with db_session.begin_nested():
            db_session.add(_visit(graph, tenant_id=graph.other_tenant_id))
            await db_session.flush()


async def test_seed_m2_writes_are_attributed_to_the_system(db_session: AsyncSession) -> None:
    result = await seed_demo(db_session, SMALL)
    async with tenant_scope(db_session, result.tenant_id):
        rows = (
            await db_session.execute(
                select(AuditLog.entity, AuditLog.actor_role, func.count())
                .where(AuditLog.action.like("%.create"))
                .group_by(AuditLog.entity, AuditLog.actor_role)
            )
        ).all()
    by_entity = {entity: (role, n) for entity, role, n in rows}
    for table in (
        "duty_session",
        "visit",
        "visit_photo",
        "visit_confirmation",
        "policy_acceptance",
    ):
        role, n = by_entity[table]
        assert role == audit.SYSTEM_ROLE and n >= 1, table
    assert "location_point" not in by_entity  # high-volume telemetry is not audited
