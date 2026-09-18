"""M2 demo seed: for ``fcc``, 5 officers x last 7 days of duty sessions 09:00-18:00 IST with
location points every 2-10 minutes along a plausible path, 4-7 visits a day with photos,
confirmations for ~60 %, VV-004 scores and VV-005 statuses, and a policy acceptance per
officer (VV-010). Idempotent and under 30 s together with the M1 seed."""

from __future__ import annotations

import time
import uuid
from collections import Counter
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.jobs.seed import FULL, SEED_TODAY, SEEDED_TABLES, SMALL, demo_tenant_id, seed_demo
from farmerapp.jobs.seed_m2 import IST
from farmerapp.location.models import DutySession, LocationPoint, PolicyAcceptance
from farmerapp.visits.models import Visit, VisitConfirmation, VisitPhoto
from farmerapp.visits.scoring import score_visit_row, status_for

FCC = demo_tenant_id("fcc")
GFL = demo_tenant_id("gfl")


async def _count(session: AsyncSession, model: type) -> int:
    return int(await session.scalar(select(func.count()).select_from(model)) or 0)


def _ist(ts: datetime) -> datetime:
    return ts.astimezone(IST)


async def test_full_seed_m2_counts_and_duration(db_session: AsyncSession) -> None:
    started = time.perf_counter()
    result = await seed_demo(db_session, FULL)
    elapsed = time.perf_counter() - started
    assert elapsed < 30, f"seed took {elapsed:.1f}s"
    for table in ("duty_session", "location_point", "visit", "visit_photo", "visit_confirmation",
                  "policy_acceptance"):  # fmt: skip
        assert table in SEEDED_TABLES and result.created[table] == result.totals[table] > 0

    async with tenant_scope(db_session, FCC):
        officers = (
            (await db_session.execute(select(User).where(User.role == UserRole.FIELD_OFFICER)))
            .scalars()
            .all()
        )
        assert len(officers) == 5
        sessions = (await db_session.execute(select(DutySession))).scalars().all()
        assert len(sessions) == 5 * 7
        per_officer = Counter(s.officer_id for s in sessions)
        assert set(per_officer.values()) == {7}
        days = {_ist(s.start_at).date() for s in sessions}
        assert days == {SEED_TODAY - timedelta(days=i) for i in range(7)}
        for s in sessions:
            assert s.end_at is not None and s.end_reason is not None
            start, end = _ist(s.start_at), _ist(s.end_at)
            assert (8, 45) <= (start.hour, start.minute) <= (9, 15), start
            assert 17 <= end.hour <= 20, end
            assert s.km is not None and 5 <= float(s.km) <= 250
            assert s.policy_version == "2026-09-v1" and s.device_id and s.app_version
            assert isinstance(s.stops, list) and s.stops
        assert {s.end_reason for s in sessions} >= {"manual", "auto_time"}

        points = await _count(db_session, LocationPoint)
        assert 5 * 7 * 100 <= points <= 5 * 7 * 400, points
        per_day = (
            await db_session.execute(
                select(LocationPoint.duty_session_id, func.count()).group_by(
                    LocationPoint.duty_session_id
                )
            )
        ).all()
        assert len(per_day) == 35 and all(80 <= n <= 400 for _, n in per_day)
        # VV-001 cadence: consecutive points are 2-10 minutes apart within a session.
        gaps = (
            await db_session.execute(
                text(
                    "SELECT max(gap), min(gap) FROM (SELECT extract(epoch FROM ts - lag(ts) OVER "
                    "(PARTITION BY duty_session_id ORDER BY ts)) AS gap FROM location_point) g "
                    "WHERE gap IS NOT NULL"
                )
            )
        ).one()
        assert gaps[1] >= 60 and gaps[0] <= 11 * 60
        # VV-002 / VA-E02: metadata present, plausible speeds, a few flagged devices.
        stats = (
            await db_session.execute(
                select(
                    func.max(LocationPoint.speed_mps),
                    func.min(LocationPoint.accuracy_m),
                    func.max(LocationPoint.accuracy_m),
                    func.min(LocationPoint.battery_pct),
                    func.max(LocationPoint.battery_pct),
                    func.bool_or(LocationPoint.is_mock),
                    func.count().filter(LocationPoint.received_at < LocationPoint.ts),
                )
            )
        ).one()
        assert stats[0] is not None and stats[0] < 25  # 90 km/h
        assert stats[1] >= 3 and stats[2] <= 60
        assert stats[3] >= 20 and stats[4] <= 100
        assert stats[5] is True and stats[6] == 0
        all_points = await db_session.scalar(
            select(func.count()).select_from(LocationPoint).where(LocationPoint.provider == "fused")
        )
        assert all_points == points
        # Every point sits inside its duty session window (FA-010: nothing off duty).
        off_duty = await db_session.scalar(
            text(
                "SELECT count(*) FROM location_point p "
                "JOIN duty_session d ON d.id = p.duty_session_id "
                "WHERE p.ts < d.start_at OR p.ts > d.end_at"
            )
        )
        assert off_duty == 0

        visits = (await db_session.execute(select(Visit))).scalars().all()
        assert 5 * 7 * 4 <= len(visits) <= 5 * 7 * 7
        by_day = Counter((v.officer_id, _ist(v.checkin_at).date()) for v in visits)
        assert len(by_day) == 35 and all(4 <= n <= 7 for n in by_day.values())
        geofence = Counter(v.geofence_result for v in visits)
        assert geofence["inside"] + geofence["meeting_point"] > 0.6 * len(visits)
        assert geofence["outside"] > 0 and geofence["override"] > 0
        assert all(
            v.override_note and v.override_approved_by
            for v in visits
            if v.geofence_result == "override"
        )
        assert all(
            v.farm_id is None and v.village_id is not None
            for v in visits
            if v.geofence_result == "meeting_point"
        )
        confirmed = [v for v in visits if v.confirmed_at is not None]
        assert 0.45 * len(visits) <= len(confirmed) <= 0.75 * len(visits)
        assert all(v.confirmation_channel != "none" for v in confirmed)
        assert all(v.confirmation_channel == "none" for v in visits if v.confirmed_at is None)
        assert {v.purpose for v in visits} >= {
            "advisory",
            "scouting",
            "demo",
            "collection",
            "sale",
            "meeting",
        }
        assert all(
            set(v.device_integrity) == {"is_mock", "is_rooted", "clock_drift_s"} for v in visits
        )
        assert any(v.device_integrity["is_mock"] for v in visits)
        closed = [v for v in visits if v.checkout_at is not None]
        open_visits = [v for v in visits if v.checkout_at is None]
        assert closed and len(open_visits) <= 5
        assert all(v.status == "open" and v.score is None for v in open_visits)
        assert all(v.duration_s is not None and 60 <= v.duration_s <= 3 * 3600 for v in closed)
        assert any(
            v.duration_s is not None and v.duration_s < 300 for v in closed
        )  # VA-E04 material
        statuses = Counter(v.status for v in closed)
        assert statuses["verified"] > statuses["partial"] > 0 and statuses["unverified"] > 0
        assert all(v.status == status_for(v.score) for v in closed if v.score is not None)

        photos = (await db_session.execute(select(VisitPhoto))).scalars().all()
        assert len(visits) <= len(photos) <= 3 * len(visits)
        assert all(
            p.blob_uri.startswith(f"gs://farmerapp-local-photos/{FCC}/visit_photo/") for p in photos
        )
        assert all(p.sha256 and len(p.sha256) == 64 and p.phash and p.exif_time for p in photos)
        assert all(p.server_time >= p.device_time for p in photos if p.device_time)
        assert any(not p.taken_in_app for p in photos)

        confirmations = (await db_session.execute(select(VisitConfirmation))).scalars().all()
        assert len(confirmations) == len(confirmed)
        assert {c.channel for c in confirmations} == {"sms_otp", "app_push", "qr"}
        assert all(c.farmer_phone_last4 and c.confirmed_via_device_id for c in confirmations)

        acceptances = (await db_session.execute(select(PolicyAcceptance))).scalars().all()
        assert {a.user_id for a in acceptances} == {o.id for o in officers}
        assert all(
            a.version == "2026-09-v1" and a.policy_key == "location_policy" for a in acceptances
        )
        assert all(a.text_hash and a.device_id and a.app_version for a in acceptances)
        assert all(
            a.accepted_at <= min(s.start_at for s in sessions if s.officer_id == a.user_id)
            for a in acceptances
        )

    async with tenant_scope(db_session, GFL):
        assert await _count(db_session, DutySession) == 7
        assert await _count(db_session, Visit) >= 4 * 7
        assert await _count(db_session, PolicyAcceptance) == 1


async def test_seed_scores_match_the_scoring_function(db_session: AsyncSession) -> None:
    await seed_demo(db_session, SMALL)
    async with tenant_scope(db_session, FCC):
        visits = (
            (await db_session.execute(select(Visit).where(Visit.checkout_at.is_not(None))))
            .scalars()
            .all()
        )
        assert visits
        for visit in visits:
            photos = (
                (
                    await db_session.execute(
                        select(VisitPhoto).where(VisitPhoto.visit_id == visit.id)
                    )
                )
                .scalars()
                .all()
            )
            expected = score_visit_row(visit, photos, min_duration_s=300)
            assert (visit.score, visit.status) == (expected.score, expected.status), visit.id
            assert visit.score_components == expected.components


async def test_m2_seed_is_idempotent_and_small_profile(db_session: AsyncSession) -> None:
    first = await seed_demo(db_session, SMALL)
    assert SMALL.duty_days == 1 and SMALL.visits_per_day == (2, 2)  # cheap fixtures
    assert first.totals["duty_session"] == 6
    assert first.totals["visit"] == 12 and first.totals["visit_confirmation"] == 6
    assert first.totals["policy_acceptance"] == 6
    assert 6 * 15 <= first.totals["location_point"] <= 6 * 45
    async with tenant_scope(db_session, FCC):
        statuses = Counter((await db_session.execute(select(Visit.status))).scalars().all())
        assert statuses == {"verified": 5, "partial": 5}  # one of each per officer
    second = await seed_demo(db_session, SMALL)
    assert all(n == 0 for n in second.created.values()), second.created
    assert second.totals == first.totals
    third = await seed_demo(db_session, FULL)
    assert third.totals["duty_session"] == (5 + 1) * 7
    assert third.created["duty_session"] == (5 + 1) * (7 - SMALL.duty_days)
    # The small profile's rows are a subset of the full ones (same ids).
    fourth = await seed_demo(db_session, FULL)
    assert all(n == 0 for n in fourth.created.values())


async def test_seed_points_follow_the_visits(db_session: AsyncSession) -> None:
    """Around every check-in there is a location point within 100 m (the officer was there)."""
    await seed_demo(db_session, SMALL)
    async with tenant_scope(db_session, FCC):
        far = await db_session.scalar(
            text(
                "SELECT count(*) FROM visit v WHERE NOT EXISTS (SELECT 1 FROM location_point p "
                "WHERE p.officer_id = v.officer_id "
                "AND p.ts BETWEEN v.checkin_at - interval '12 min' "
                "AND v.checkin_at + interval '12 min' "
                "AND ST_DWithin(p.point, v.checkin_point, 100))"
            )
        )
        assert far == 0
        # Inside check-ins are within the 150 m geofence of the farm; outside ones are not.
        wrong = await db_session.scalar(
            text(
                "SELECT count(*) FROM visit v JOIN farm f ON f.id = v.farm_id WHERE "
                "(v.geofence_result = 'inside' "
                "AND NOT ST_DWithin(v.checkin_point, f.boundary, 150)) OR "
                "(v.geofence_result IN ('outside', 'override') "
                "AND ST_DWithin(v.checkin_point, f.boundary, 150))"
            )
        )
        assert wrong == 0
        meeting = await db_session.scalar(
            text(
                "SELECT count(*) FROM visit v JOIN village vl ON vl.id = v.village_id WHERE "
                "v.geofence_result = 'meeting_point' "
                "AND NOT ST_DWithin(v.checkin_point, vl.meeting_point, 150)"
            )
        )
        assert meeting == 0


def test_seed_today_is_fixed() -> None:
    assert date(2026, 9, 18) == SEED_TODAY
    assert isinstance(uuid.uuid4(), uuid.UUID)
    assert datetime(2026, 9, 18, 9, 0, tzinfo=IST).astimezone(UTC).hour == 3
