"""Daily partitions of ``location_point`` and the SPEC 2.6 retention (180 days).

Two ``SECURITY DEFINER`` SQL functions installed by migration 0007 (owned by the migrating
role, which owns the parent table; the app role may only EXECUTE them — DDL stays denied,
SEC-011):

* ``ensure_location_partitions(from_day, to_day)`` / ``ensure_location_partitions(days_ahead)``
  create the missing ``location_point_pYYYYMMDD`` tables (UTC days) **with RLS enabled,
  forced and both policies installed** on each child, and return the names created.
  ``jobs ensure-partitions`` runs it daily (yesterday .. today + 7); the seed calls it for its
  own window. There is no DEFAULT partition: a point for a day without a partition is a
  loud insert error, never a silent catch-all.
* ``purge_location_points(retention_days, dry_run)`` lists the partitions whose day is
  older than ``retention_days`` (never below 180) and, unless ``dry_run``, folds each into
  ``location_daily_agg`` (km from consecutive-point distances, count, first / last ts per
  officer) and drops it. ``jobs purge-location-points`` is dry run unless ``--apply``.

The Python helpers here call those functions; nothing in this module needs the migrate role.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, date, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.session import get_session_factory
from farmerapp.location.models import LOCATION_RETENTION_DAYS, PARTITION_PREFIX
from farmerapp.logging import get_logger

log = get_logger("farmerapp.location.partitions")

DEFAULT_DAYS_AHEAD = 7
_NAME_RE = re.compile(rf"^{PARTITION_PREFIX}(\d{{4}})(\d{{2}})(\d{{2}})$")

_ENSURE = text("SELECT ensure_location_partitions(:from_day, :to_day)")
_ENSURE_AHEAD = text("SELECT ensure_location_partitions(:days_ahead)")
_LIST = text(
    "SELECT c.relname FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid "
    "WHERE i.inhparent = 'public.location_point'::regclass ORDER BY c.relname"
)
_PURGE = text("SELECT * FROM purge_location_points(:retention_days, :dry_run)")


def partition_name(day: date) -> str:
    return f"{PARTITION_PREFIX}{day:%Y%m%d}"


def partition_day(name: str) -> date:
    match = _NAME_RE.match(name)
    if match is None:
        raise ValueError(f"not a location_point partition name: {name!r}")
    year, month, day = (int(g) for g in match.groups())
    return date(year, month, day)


@dataclass(frozen=True)
class PartitionInfo:
    name: str
    day: date

    @property
    def lower(self) -> datetime:
        return datetime(self.day.year, self.day.month, self.day.day, tzinfo=UTC)

    @property
    def upper(self) -> datetime:
        nxt = date.fromordinal(self.day.toordinal() + 1)
        return datetime(nxt.year, nxt.month, nxt.day, tzinfo=UTC)


@dataclass(frozen=True)
class PurgeRow:
    partition: str
    day: date
    points: int
    officer_days: int  # ``location_daily_agg`` rows written (0 on a dry run)
    dropped: bool
    dry_run: bool


async def ensure_partitions(session: AsyncSession, *, from_day: date, to_day: date) -> list[str]:
    """Create the missing daily partitions for ``from_day .. to_day`` (inclusive); names created."""
    rows = await session.execute(_ENSURE, {"from_day": from_day, "to_day": to_day})
    return [str(r[0]) for r in rows]


async def ensure_partitions_ahead(
    session: AsyncSession, days_ahead: int = DEFAULT_DAYS_AHEAD
) -> list[str]:
    """Yesterday .. today + ``days_ahead`` (the daily job)."""
    rows = await session.execute(_ENSURE_AHEAD, {"days_ahead": days_ahead})
    return [str(r[0]) for r in rows]


async def list_partitions(session: AsyncSession) -> list[PartitionInfo]:
    rows = await session.execute(_LIST)
    return [PartitionInfo(name=str(r[0]), day=partition_day(str(r[0]))) for r in rows]


async def purge_location_points(
    session: AsyncSession,
    *,
    retention_days: int = LOCATION_RETENTION_DAYS,
    apply: bool = False,
) -> list[PurgeRow]:
    """Partitions older than ``retention_days``; aggregated + dropped only when ``apply``."""
    if retention_days < LOCATION_RETENTION_DAYS:
        raise ValueError(
            f"retention_days={retention_days} is below the SPEC 2.6 minimum of "
            f"{LOCATION_RETENTION_DAYS} days"
        )
    rows = await session.execute(_PURGE, {"retention_days": retention_days, "dry_run": not apply})
    report = [
        PurgeRow(
            partition=str(r.partition_name),
            day=r.day,
            points=int(r.points),
            officer_days=int(r.officer_days),
            dropped=bool(r.dropped),
            dry_run=not apply,
        )
        for r in rows
    ]
    log.info(
        "location_purge",
        retention_days=retention_days,
        dry_run=not apply,
        partitions=len(report),
        points=sum(r.points for r in report),
        dropped=sum(r.dropped for r in report),
    )
    return report


# --------------------------------------------------------------------------- jobs
async def run_ensure_partitions(days_ahead: int = DEFAULT_DAYS_AHEAD) -> list[str]:
    factory = get_session_factory()
    async with factory() as session, session.begin():
        created = await ensure_partitions_ahead(session, days_ahead)
    log.info("location_partitions_ensured", days_ahead=days_ahead, created=created)
    return created


async def run_purge(
    *, retention_days: int = LOCATION_RETENTION_DAYS, apply: bool = False
) -> list[PurgeRow]:
    factory = get_session_factory()
    async with factory() as session, session.begin():
        return await purge_location_points(session, retention_days=retention_days, apply=apply)


__all__ = [
    "DEFAULT_DAYS_AHEAD",
    "PartitionInfo",
    "PurgeRow",
    "ensure_partitions",
    "ensure_partitions_ahead",
    "list_partitions",
    "partition_day",
    "partition_name",
    "purge_location_points",
    "run_ensure_partitions",
    "run_purge",
]
