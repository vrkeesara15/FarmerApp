"""``location_point`` is declaratively partitioned by day (SPEC 8.2): partitions are created
by ``ensure_location_partitions`` (migration 0007 + ``jobs ensure-partitions``), RLS is
enforced on the parent *and* on every child, and ``purge-location-points`` aggregates days
older than 180 days into ``location_daily_agg`` before dropping their partition (SPEC 2.6),
dry run by default."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession
from typer.testing import CliRunner

from farmerapp.auth.models import User, UserRole
from farmerapp.db.geo import offset, point_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.rls import rls_violations
from farmerapp.db.session import clear_tenant, set_tenant, tenant_scope
from farmerapp.jobs.cli import cli
from farmerapp.location import partitions
from farmerapp.location.models import (
    LOCATION_RETENTION_DAYS,
    PARTITION_PREFIX,
    LocationDailyAgg,
    LocationPoint,
)

DAY = date(2025, 1, 15)  # far from today: never overlaps the migration's own partitions
OLD_DAY = date(2025, 1, 1)


def _ts(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=UTC)


async def _tenant_with_officer(session: AsyncSession, label: str) -> tuple[uuid.UUID, User]:
    tid = uuid.uuid4()
    async with tenant_scope(session, tid):
        session.add(Tenant(id=tid, name=f"Part {label}", slug=f"part-{label}-{tid.hex[:6]}"))
        await session.flush()
        officer = User(
            tenant_id=tid,
            phone=f"+9190000{uuid.uuid4().int % 100000:05d}",
            name=f"Officer {label}",
            role=UserRole.FIELD_OFFICER,
        )
        session.add(officer)
        await session.flush()
    return tid, officer


def _point(tid: uuid.UUID, officer: User, ts: datetime, east_m: float = 0.0) -> LocationPoint:
    lon, lat = offset(79.55, 18.02, east_m, 0)
    return LocationPoint(
        tenant_id=tid,
        officer_id=officer.id,
        ts=ts,
        point=point_wkt(lon, lat),
        accuracy_m=8.0,
        speed_mps=1.2,
        battery_pct=80,
        provider="fused",
        received_at=ts + timedelta(minutes=15),
    )


async def _partitions(session: AsyncSession) -> list[str]:
    return [p.name for p in await partitions.list_partitions(session)]


# ------------------------------------------------------------------ creation
async def test_migration_created_the_parent_and_the_current_window(
    db_session: AsyncSession,
) -> None:
    kind = await db_session.scalar(
        text("SELECT relkind::text FROM pg_class WHERE relname = 'location_point'")
    )
    assert kind == "p"  # declaratively partitioned parent
    strategy = await db_session.scalar(
        text(
            "SELECT partstrat::text FROM pg_partitioned_table "
            "WHERE partrelid = 'location_point'::regclass"
        )
    )
    assert strategy == "r"  # RANGE (ts)
    names = await _partitions(db_session)
    today = datetime.now(UTC).date()
    assert partitions.partition_name(today) in names
    assert partitions.partition_name(today + timedelta(days=7)) in names
    assert partitions.partition_name(today - timedelta(days=1)) in names


async def test_ensure_creates_missing_daily_partitions_idempotently(
    db_session: AsyncSession,
) -> None:
    created = await partitions.ensure_partitions(
        db_session, from_day=DAY, to_day=DAY + timedelta(days=2)
    )
    assert created == [partitions.partition_name(DAY + timedelta(days=i)) for i in range(3)]
    assert created[0] == f"{PARTITION_PREFIX}20250115"
    again = await partitions.ensure_partitions(
        db_session, from_day=DAY, to_day=DAY + timedelta(days=3)
    )
    assert again == [partitions.partition_name(DAY + timedelta(days=3))]
    infos = {p.name: p for p in await partitions.list_partitions(db_session)}
    info = infos[created[0]]
    assert info.day == DAY
    assert info.lower == _ts(DAY, 0) and info.upper == _ts(DAY + timedelta(days=1), 0)


async def test_ensure_ahead_covers_yesterday_to_today_plus_days(db_session: AsyncSession) -> None:
    await db_session.execute(text("SELECT ensure_location_partitions(9)"))
    names = await _partitions(db_session)
    today = datetime.now(UTC).date()
    for delta in range(-1, 10):
        assert partitions.partition_name(today + timedelta(days=delta)) in names


async def test_ensure_rejects_bad_ranges(db_session: AsyncSession) -> None:
    with pytest.raises(DBAPIError, match="from_day"):
        async with db_session.begin_nested():
            await partitions.ensure_partitions(
                db_session, from_day=DAY, to_day=DAY - timedelta(days=1)
            )
    with pytest.raises(DBAPIError, match="at most"):
        async with db_session.begin_nested():
            await partitions.ensure_partitions(
                db_session, from_day=DAY, to_day=DAY + timedelta(days=500)
            )


async def test_app_role_cannot_create_partitions_directly(db_session: AsyncSession) -> None:
    """The SECURITY DEFINER function is the only way; plain DDL stays denied (SEC-011)."""
    with pytest.raises(DBAPIError, match=r"must be owner|permission denied"):
        async with db_session.begin_nested():
            await db_session.execute(
                text(
                    "CREATE TABLE location_point_pxxxx PARTITION OF location_point "
                    "FOR VALUES FROM ('2024-01-01') TO ('2024-01-02')"
                )
            )


# ------------------------------------------------------------------ routing + RLS
async def test_points_route_to_their_day_and_need_a_partition(db_session: AsyncSession) -> None:
    tid, officer = await _tenant_with_officer(db_session, "route")
    await partitions.ensure_partitions(db_session, from_day=DAY, to_day=DAY + timedelta(days=1))
    await set_tenant(db_session, tid)
    db_session.add_all(
        [
            _point(tid, officer, _ts(DAY, 4)),
            _point(tid, officer, _ts(DAY, 23, 59)),
            _point(tid, officer, _ts(DAY + timedelta(days=1), 0)),
        ]
    )
    await db_session.flush()
    first = await db_session.scalar(
        text(f"SELECT count(*) FROM ONLY {partitions.partition_name(DAY)}")
    )
    second = await db_session.scalar(
        text(f"SELECT count(*) FROM ONLY {partitions.partition_name(DAY + timedelta(days=1))}")
    )
    assert (first, second) == (2, 1)
    assert await db_session.scalar(select(func.count()).select_from(LocationPoint)) == 3
    with pytest.raises(DBAPIError, match="no partition of relation"):
        async with db_session.begin_nested():
            db_session.add(_point(tid, officer, _ts(DAY + timedelta(days=5), 9)))
            await db_session.flush()


async def test_rls_is_forced_on_parent_and_children(
    db_session: AsyncSession, migrate_engine: AsyncEngine
) -> None:
    tid_a, officer_a = await _tenant_with_officer(db_session, "a")
    tid_b, officer_b = await _tenant_with_officer(db_session, "b")
    names = await partitions.ensure_partitions(db_session, from_day=DAY, to_day=DAY)
    child = names[0]
    async with tenant_scope(db_session, tid_a):
        db_session.add_all(
            [_point(tid_a, officer_a, _ts(DAY, 5)), _point(tid_a, officer_a, _ts(DAY, 6))]
        )
        await db_session.flush()
    async with tenant_scope(db_session, tid_b):
        db_session.add(_point(tid_b, officer_b, _ts(DAY, 5)))
        await db_session.flush()

    # Through the parent (the policy on the parent applies to every partition).
    async with tenant_scope(db_session, tid_a):
        rows = (await db_session.execute(select(LocationPoint.tenant_id))).scalars().all()
        assert rows and set(rows) == {tid_a} and len(rows) == 2
        # ... and directly on the child (its own policy, installed by the function).
        direct = (await db_session.execute(text(f"SELECT tenant_id FROM {child}"))).scalars().all()
        assert set(direct) == {tid_a} and len(direct) == 2
    async with tenant_scope(db_session, tid_b):
        assert await db_session.scalar(select(func.count()).select_from(LocationPoint)) == 1
        assert await db_session.scalar(text(f"SELECT count(*) FROM {child}")) == 1
    await clear_tenant(db_session)
    assert await db_session.scalar(select(func.count()).select_from(LocationPoint)) == 0
    assert await db_session.scalar(text(f"SELECT count(*) FROM {child}")) == 0

    # Foreign tenant insert through the parent and through the child are both rejected.
    await set_tenant(db_session, tid_a)
    with pytest.raises(DBAPIError, match="row-level security"):
        async with db_session.begin_nested():
            db_session.add(_point(tid_b, officer_b, _ts(DAY, 7)))
            await db_session.flush()
    with pytest.raises(DBAPIError, match="row-level security"):
        async with db_session.begin_nested():
            await db_session.execute(
                text(
                    f"INSERT INTO {child} (id, tenant_id, officer_id, ts, point, accuracy_m) "
                    "VALUES (gen_random_uuid(), :t, :o, :ts, "
                    "ST_GeogFromText('SRID=4326;POINT(79 18)'), 5)"
                ),
                {"t": tid_b, "o": officer_b.id, "ts": _ts(DAY, 8)},
            )
    # Catalogue: the child passes the same meta-check as every model table. The child only
    # exists inside this test's transaction, so check it on the same connection.
    conn = await db_session.connection()
    problems = await conn.run_sync(rls_violations, ["location_point", child])
    assert problems == []
    forced = (
        await db_session.execute(
            text(
                "SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class "
                "WHERE relname IN ('location_point', :c)"
            ),
            {"c": child},
        )
    ).all()
    assert len(forced) == 2 and all(r[1] and r[2] for r in forced)
    del migrate_engine  # fixture kept for symmetry with tests/rls (owner connection unused)


async def test_location_point_is_not_audited_and_not_in_the_sync_feed(
    db_session: AsyncSession,
) -> None:
    from farmerapp.db.audit import is_audited
    from farmerapp.db.models import AuditLog
    from farmerapp.sync.models import SYNC_ENTITIES, SYNC_EXCLUDED_ENTITIES, SyncChange

    assert LocationPoint.__audit__ is False
    assert "location_point" in SYNC_EXCLUDED_ENTITIES and "location_point" not in SYNC_ENTITIES
    tid, officer = await _tenant_with_officer(db_session, "audit")
    await partitions.ensure_partitions(db_session, from_day=DAY, to_day=DAY)
    await set_tenant(db_session, tid)
    row = _point(tid, officer, _ts(DAY, 5))
    assert not is_audited(row)
    db_session.add(row)
    await db_session.flush()
    audits = await db_session.scalar(
        select(func.count()).select_from(AuditLog).where(AuditLog.entity == "location_point")
    )
    changes = await db_session.scalar(
        select(func.count()).select_from(SyncChange).where(SyncChange.entity == "location_point")
    )
    assert (audits, changes) == (0, 0)


async def test_point_metadata_fields_are_present(db_session: AsyncSession) -> None:
    """VV-002 / FA-028: accuracy, speed, battery, mock, rooted and clock drift on every point."""
    tid, officer = await _tenant_with_officer(db_session, "meta")
    await partitions.ensure_partitions(db_session, from_day=DAY, to_day=DAY)
    await set_tenant(db_session, tid)
    row = _point(tid, officer, _ts(DAY, 5))
    row.is_mock, row.is_rooted, row.clock_drift_s, row.bearing = True, False, 420, 270.5
    db_session.add(row)
    await db_session.flush()
    loaded = (
        await db_session.execute(select(LocationPoint).where(LocationPoint.id == row.id))
    ).scalar_one()
    assert loaded.ts == _ts(DAY, 5) and loaded.received_at == _ts(DAY, 5, 15)
    assert (loaded.accuracy_m, loaded.speed_mps, loaded.battery_pct) == (8.0, 1.2, 80)
    assert (loaded.is_mock, loaded.is_rooted, loaded.clock_drift_s) == (True, False, 420)
    assert loaded.bearing == 270.5 and loaded.provider == "fused"
    assert abs(loaded.lat - 18.02) < 1e-6 and abs(loaded.lon - 79.55) < 1e-6
    columns = {
        r[0]
        for r in await db_session.execute(
            text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_name = 'location_point'"
            )
        )
    }
    assert columns >= {
        "id", "tenant_id", "officer_id", "duty_session_id", "ts", "point", "accuracy_m",
        "speed_mps", "bearing", "battery_pct", "is_mock", "is_rooted", "clock_drift_s",
        "provider", "received_at",
    }  # fmt: skip


# ------------------------------------------------------------------ purge + aggregate
async def _old_track(db_session: AsyncSession) -> tuple[uuid.UUID, User, str]:
    tid, officer = await _tenant_with_officer(db_session, "purge")
    names = await partitions.ensure_partitions(db_session, from_day=OLD_DAY, to_day=OLD_DAY)
    await set_tenant(db_session, tid)
    # Five points 1 km apart east -> 4 km walked.
    db_session.add_all(
        [_point(tid, officer, _ts(OLD_DAY, 4, 10 * i), east_m=1000 * i) for i in range(5)]
    )
    await db_session.flush()
    await clear_tenant(db_session)
    return tid, officer, names[0]


async def test_purge_dry_run_reports_and_drops_nothing(db_session: AsyncSession) -> None:
    tid, _officer, child = await _old_track(db_session)
    report = await partitions.purge_location_points(db_session, retention_days=180)
    mine = [r for r in report if r.partition == child]
    assert len(mine) == 1
    row = mine[0]
    assert row.day == OLD_DAY and row.points == 5 and row.dropped is False
    assert row.officer_days == 0 and row.dry_run is True
    assert child in await _partitions(db_session)
    async with tenant_scope(db_session, tid):
        assert await db_session.scalar(select(func.count()).select_from(LocationDailyAgg)) == 0
    # Recent partitions are never listed.
    assert not any(r.day >= datetime.now(UTC).date() - timedelta(days=180) for r in report)


async def test_purge_apply_aggregates_then_drops(db_session: AsyncSession) -> None:
    tid, officer, child = await _old_track(db_session)
    report = await partitions.purge_location_points(db_session, retention_days=180, apply=True)
    row = next(r for r in report if r.partition == child)
    assert row.dropped is True and row.points == 5 and row.officer_days == 1
    assert child not in await _partitions(db_session)
    async with tenant_scope(db_session, tid):
        agg = (await db_session.execute(select(LocationDailyAgg))).scalar_one()
        assert agg.officer_id == officer.id and agg.day == OLD_DAY
        assert agg.points == 5
        assert 3.9 <= float(agg.km) <= 4.1
        assert agg.first_ts == _ts(OLD_DAY, 4) and agg.last_ts == _ts(OLD_DAY, 4, 40)
        assert await db_session.scalar(select(func.count()).select_from(LocationPoint)) == 0
    # Running it again finds nothing to do.
    again = await partitions.purge_location_points(db_session, retention_days=180, apply=True)
    assert not [r for r in again if r.partition == child]


async def test_purge_refuses_retention_below_180_days(db_session: AsyncSession) -> None:
    assert LOCATION_RETENTION_DAYS == 180
    with pytest.raises(ValueError, match="180"):
        await partitions.purge_location_points(db_session, retention_days=90)
    with pytest.raises(DBAPIError, match="180"):
        async with db_session.begin_nested():
            await db_session.execute(text("SELECT * FROM purge_location_points(30, true)"))


async def test_daily_agg_is_isolated_per_tenant(db_session: AsyncSession) -> None:
    tid_a, officer_a = await _tenant_with_officer(db_session, "agg-a")
    tid_b, _ = await _tenant_with_officer(db_session, "agg-b")
    async with tenant_scope(db_session, tid_a):
        db_session.add(
            LocationDailyAgg(
                tenant_id=tid_a,
                officer_id=officer_a.id,
                day=OLD_DAY,
                km=12.5,
                points=200,
                first_ts=_ts(OLD_DAY, 3),
                last_ts=_ts(OLD_DAY, 12),
            )
        )
        await db_session.flush()
        assert await db_session.scalar(select(func.count()).select_from(LocationDailyAgg)) == 1
    async with tenant_scope(db_session, tid_b):
        assert await db_session.scalar(select(func.count()).select_from(LocationDailyAgg)) == 0


# ------------------------------------------------------------------ jobs CLI
def test_cli_ensure_partitions(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[int] = []

    async def fake(days_ahead: int = 7) -> list[str]:
        calls.append(days_ahead)
        return ["location_point_p20260925"]

    monkeypatch.setattr(partitions, "run_ensure_partitions", fake)
    result = CliRunner().invoke(cli, ["ensure-partitions", "--days-ahead", "9"])
    assert result.exit_code == 0, result.output
    assert calls == [9] and "location_point_p20260925" in result.output
    assert CliRunner().invoke(cli, ["ensure-partitions"]).exit_code == 0
    assert calls[-1] == 7


def test_cli_purge_is_dry_run_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[dict[str, Any]] = []

    async def fake(*, retention_days: int, apply: bool) -> list[partitions.PurgeRow]:
        calls.append({"retention_days": retention_days, "apply": apply})
        return [
            partitions.PurgeRow(
                partition="location_point_p20260101",
                day=date(2026, 1, 1),
                points=321,
                officer_days=0 if not apply else 4,
                dropped=apply,
                dry_run=not apply,
            )
        ]

    monkeypatch.setattr(partitions, "run_purge", fake)
    runner = CliRunner()
    result = runner.invoke(cli, ["purge-location-points"])
    assert result.exit_code == 0, result.output
    assert calls == [{"retention_days": 180, "apply": False}]
    assert "dry-run" in result.output and "321" in result.output
    result = runner.invoke(cli, ["purge-location-points", "--apply", "--retention-days", "365"])
    assert result.exit_code == 0, result.output
    assert calls[-1] == {"retention_days": 365, "apply": True}
    assert "dropped" in result.output
