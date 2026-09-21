"""NF-012 sweep on real fixtures: dry run by default, purge on --apply, never the 8-year floor.

The seeded world (``world`` fixture, SMALL profile) gives real visits, orders, payments and
audit rows in tenant A. Each test ages the rows it cares about with one UPDATE and then asks
the sweep what it would do — which is exactly what an operator does before a retention run.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.session import set_tenant
from farmerapp.retention import POLICY, RetentionAction, policy_for, sweep
from tests.authz.conftest import World, world  # noqa: F401  (fixture re-exported)

NOW = datetime(2026, 9, 19, 12, 0, tzinfo=UTC)
_ = World


async def _age(session: AsyncSession, table: str, column: str, days: int) -> int:
    """Date every row of ``table`` exactly ``days`` before NOW. Returns how many were moved."""
    result = await session.execute(
        text(f'UPDATE "{table}" SET {column} = :ts'), {"ts": NOW - timedelta(days=days)}
    )
    await session.flush()
    return int(getattr(result, "rowcount", 0) or 0)


async def _count(session: AsyncSession, table: str) -> int:
    return int((await session.scalar(text(f'SELECT count(*) FROM "{table}"'))) or 0)


# --------------------------------------------------------------------------- dry run
async def test_a_fresh_tenant_has_nothing_due(db_session: AsyncSession, world: World) -> None:  # noqa: F811
    report = await sweep(db_session, tenant_id=world.a.tenant.id, now=NOW)
    assert report.due == 0
    assert report.deleted == 0
    assert {c.name for c in report.classes} == {c.name for c in POLICY}


async def test_dry_run_is_the_default_and_deletes_nothing(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    moved = await _age(db_session, "visit", "created_at", 8 * 365)
    assert moved, "the seeded world has visits"
    before = await _count(db_session, "visit")

    report = await sweep(db_session, tenant_id=world.a.tenant.id, now=NOW)
    visits = next(c for c in report.classes if c.name == "visit_records")
    assert visits.due == moved
    assert visits.deleted == 0
    assert visits.applied is False
    assert await _count(db_session, "visit") == before


# --------------------------------------------------------------------------- purge
async def test_apply_purges_visit_records_past_seven_years(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    aged = await _age(db_session, "visit", "created_at", 7 * 365 + 1)
    before = await _count(db_session, "visit")
    assert aged == before

    report = await sweep(
        db_session, tenant_id=world.a.tenant.id, now=NOW, apply=True, classes=("visit_records",)
    )
    entry = next(c for c in report.classes if c.name == "visit_records")
    assert entry.applied is True
    assert entry.deleted == aged
    assert await _count(db_session, "visit") == 0


async def test_a_visit_one_day_inside_the_window_survives(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    await _age(db_session, "visit", "created_at", 7 * 365 - 1)
    before = await _count(db_session, "visit")
    report = await sweep(
        db_session, tenant_id=world.a.tenant.id, now=NOW, apply=True, classes=("visit_records",)
    )
    assert report.due == 0 and report.deleted == 0
    assert await _count(db_session, "visit") == before


# --------------------------------------------------------------------------- the floor
async def test_financial_records_are_never_deleted_even_with_apply(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    """NF-012's 8 years is a floor, and DPDP erasure yields to it (docs/dpdp.md)."""
    await _age(db_session, "order", "created_at", 9 * 365)
    await _age(db_session, "payment", "created_at", 9 * 365)
    orders, payments = await _count(db_session, "order"), await _count(db_session, "payment")
    assert orders and payments

    report = await sweep(db_session, tenant_id=world.a.tenant.id, now=NOW, apply=True)
    entry = next(c for c in report.classes if c.name == "financial_records")
    assert entry.action is RetentionAction.RETAIN
    assert entry.due >= orders + payments
    assert entry.deleted == 0
    assert entry.applied is False
    assert "floor" in entry.deferred_to
    assert await _count(db_session, "order") == orders
    assert await _count(db_session, "payment") == payments


# --------------------------------------------------------------------------- deferred classes
async def test_audit_logs_are_counted_but_left_to_the_migrate_role(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    # audit_log is append-only: the app role may not even UPDATE it, so the rows are aged by
    # moving *now* instead — which is what a year of running does anyway.
    before = await _count(db_session, "audit_log")
    assert before, "the seed writes audit rows"
    later = NOW + timedelta(days=500)
    report = await sweep(db_session, tenant_id=world.a.tenant.id, now=later, apply=True)
    entry = next(c for c in report.classes if c.name == "audit_logs")
    assert entry.due == before
    assert entry.deleted == 0
    assert "migrate role" in entry.deferred_to
    assert "purge-audit-logs" in entry.deferred_to
    assert await _count(db_session, "audit_log") == before


async def test_location_points_name_their_own_job(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    report = await sweep(
        db_session, tenant_id=world.a.tenant.id, now=NOW, apply=True, classes=("location_points",)
    )
    entry = report.classes[0]
    assert entry.days == 180
    assert "purge-location-points" in entry.deferred_to
    assert entry.deleted == 0


async def test_photos_are_archived_by_the_bucket_not_by_the_sweep(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    await _age(db_session, "farm_photo", "created_at", 4 * 365)
    before = await _count(db_session, "farm_photo")
    report = await sweep(
        db_session, tenant_id=world.a.tenant.id, now=NOW, apply=True, classes=("photos",)
    )
    entry = report.classes[0]
    assert entry.action is RetentionAction.ARCHIVE
    assert entry.deleted == 0
    assert "lifecycle" in entry.deferred_to or "GCS" in entry.deferred_to
    assert await _count(db_session, "farm_photo") == before, "the row outlives the hot object"


# --------------------------------------------------------------------------- scoping
async def test_the_sweep_never_reaches_another_tenant(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    await _age(db_session, "visit", "created_at", 8 * 365)
    in_a = await _count(db_session, "visit")
    assert in_a

    report = await sweep(
        db_session, tenant_id=world.b.tenant.id, now=NOW, apply=True, classes=("visit_records",)
    )
    # RLS keeps the session on tenant A's rows; asking for B's sweep must not delete A's.
    assert report.classes[0].deleted == 0, "tenant B's sweep must not see tenant A's rows"
    await set_tenant(db_session, world.a.tenant.id)
    assert await _count(db_session, "visit") == in_a


async def test_an_unknown_class_is_a_clear_error(
    db_session: AsyncSession,
    world: World,  # noqa: F811
) -> None:
    with pytest.raises(KeyError, match="unknown retention class"):
        await sweep(db_session, tenant_id=uuid.uuid4(), now=NOW, classes=("nonsense",))


def test_every_class_reports_a_cutoff_that_matches_its_window() -> None:
    for entry in POLICY:
        assert policy_for(entry.name) is entry
        assert NOW - timedelta(days=entry.days) < NOW
