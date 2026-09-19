"""VV-006 track processing: km (road-snapped when enabled), stops and gaps per duty session.

For one duty session:

* **filter** — accuracy <= 100 m, strictly increasing time, no jump faster than 90 km/h
  (``farmerapp.duty.track``, the same filter the console replay draws);
* **km** — the length of the path the ``RoadSnapper`` returns (``farmerapp.duty.roads``):
  the jitter-filtered fixes by default (``haversine``), the Roads API's snapped and
  interpolated path when ``ROAD_SNAPPER=google`` (falls back to the filter on any failure).
  ``km_raw`` keeps the plain haversine sum of the kept fixes for comparison;
* **stops** — at least 5 minutes within 100 m (``summarise``);
* **gaps** — more than 30 minutes without a kept point while on duty (``find_gaps``), stored
  as ``track_gap`` rows with deterministic ids (``gap_id``) so a VV-008 reason given before
  (or while the session was open) survives re-processing. A gap that no longer exists after
  re-processing is deleted unless the officer already explained it.

Runs at duty end (``farmerapp.duty.service.close_session``, the filter only: no network call
in the request) and in the ``process-tracks`` job, which (re-)processes ended sessions not yet
processed with the configured snapper. FA-023 travel allowance reads the stored ``km``.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from itertools import pairwise
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.duty.models import TrackGap, gap_id
from farmerapp.duty.roads import FilterSnapper, RoadSnapError, RoadSnapper, path_m
from farmerapp.duty.track import TrackPoint, _usable, summarise
from farmerapp.location.models import DutySession
from farmerapp.logging import get_logger

log = get_logger("farmerapp.duty.processing")

GAP_MIN = timedelta(minutes=30)


@dataclass(frozen=True)
class GapSpan:
    start: datetime
    end: datetime

    @property
    def duration_s(self) -> int:
        return int((self.end - self.start).total_seconds())


@dataclass(frozen=True)
class ProcessedTrack:
    km: Decimal
    km_raw: Decimal
    km_source: str
    stops: list[dict[str, Any]]
    gaps: list[GapSpan]
    kept: int


def _km(metres: float) -> Decimal:
    return (Decimal(metres) / Decimal(1000)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def find_gaps(
    session_start: datetime, session_end: datetime, times: Sequence[datetime]
) -> list[GapSpan]:
    """Spans over 30 minutes without a point between ``session_start`` and ``session_end``."""
    if session_end <= session_start:
        return []
    marks = [session_start, *[t for t in times if session_start <= t <= session_end], session_end]
    return [GapSpan(a, b) for a, b in pairwise(sorted(marks)) if b - a > GAP_MIN]


async def process_points(
    points: Sequence[TrackPoint],
    *,
    start: datetime,
    end: datetime,
    snapper: RoadSnapper | None = None,
) -> ProcessedTrack:
    """The VV-006 figures of one session's points (pure apart from the snapper call)."""
    kept = _usable(points)
    summary = summarise(kept)
    snapper = snapper or FilterSnapper()
    source = snapper.name
    try:
        path = await snapper.snap(kept)
    except RoadSnapError as exc:
        log.warning("road_snap_failed", snapper=snapper.name, error=str(exc))
        path = await FilterSnapper().snap(kept)
        source = FilterSnapper.name
    return ProcessedTrack(
        km=_km(path_m(path)),
        km_raw=summary.km,
        km_source=source,
        stops=summary.stops,
        gaps=find_gaps(start, end, [p.ts for p in kept]),
        kept=len(kept),
    )


async def store_gaps(
    session: AsyncSession, duty: DutySession, gaps: Sequence[GapSpan]
) -> list[TrackGap]:
    """Upsert the session's gaps by id; drop vanished ones the officer did not explain."""
    existing = {
        g.id: g
        for g in (
            await session.execute(select(TrackGap).where(TrackGap.duty_session_id == duty.id))
        ).scalars()
    }
    out: list[TrackGap] = []
    seen: set[uuid.UUID] = set()
    for span in gaps:
        gid = gap_id(duty.id, span.start)
        seen.add(gid)
        row = existing.get(gid)
        if row is None:
            row = TrackGap(
                id=gid,
                tenant_id=duty.tenant_id,
                duty_session_id=duty.id,
                officer_id=duty.officer_id,
                start_at=span.start,
                end_at=span.end,
                duration_s=span.duration_s,
            )
            session.add(row)
        elif row.end_at != span.end:
            row.end_at = span.end
            row.duration_s = span.duration_s
        out.append(row)
    for gid, row in existing.items():
        if gid not in seen and row.reason is None and row.deleted_at is None:
            await session.delete(row)
    await session.flush()
    return out


async def apply_processing(
    session: AsyncSession,
    duty: DutySession,
    points: Sequence[TrackPoint],
    *,
    end: datetime,
    snapper: RoadSnapper | None = None,
    now: datetime | None = None,
) -> ProcessedTrack:
    """Process ``points`` and store km / stops / gaps on the (ended) session."""
    result = await process_points(points, start=duty.start_at, end=end, snapper=snapper)
    duty.km = result.km
    duty.km_raw = result.km_raw
    duty.km_source = result.km_source
    duty.stops = result.stops
    duty.processed_at = now or datetime.now(UTC)
    await store_gaps(session, duty, result.gaps)
    return result


async def process_session(
    session: AsyncSession,
    duty: DutySession,
    *,
    snapper: RoadSnapper | None = None,
    now: datetime | None = None,
) -> ProcessedTrack:
    """(Re-)process an ended session from its stored points (the ``process-tracks`` job)."""
    from farmerapp.duty.service import session_points  # local: service imports this module

    if duty.end_at is None:
        raise ValueError("only ended duty sessions are processed")
    points = await session_points(session, duty, until=duty.end_at)
    result = await apply_processing(
        session, duty, points, end=duty.end_at, snapper=snapper, now=now
    )
    await session.flush()
    log.info(
        "track_processed",
        duty_session_id=str(duty.id),
        officer_id=str(duty.officer_id),
        km=str(result.km),
        km_raw=str(result.km_raw),
        km_source=result.km_source,
        stops=len(result.stops),
        gaps=len(result.gaps),
        points=result.kept,
    )
    return result


@dataclass(frozen=True)
class ProcessReport:
    tenant_id: uuid.UUID
    processed: int
    km_source: str


async def process_tracks(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    snapper: RoadSnapper,
    since: datetime,
    now: datetime | None = None,
    limit: int = 500,
) -> ProcessReport:
    """Every ended session of the tenant since ``since`` not yet processed with ``snapper``."""
    rows = (
        (
            await session.execute(
                select(DutySession)
                .where(
                    DutySession.tenant_id == tenant_id,
                    DutySession.deleted_at.is_(None),
                    DutySession.end_at.is_not(None),
                    DutySession.end_at >= since,
                    (DutySession.processed_at.is_(None))
                    | (DutySession.km_source.is_distinct_from(snapper.name)),
                )
                .order_by(DutySession.end_at)
                .limit(limit)
            )
        )
        .scalars()
        .all()
    )
    for duty in rows:
        await process_session(session, duty, snapper=snapper, now=now)
    return ProcessReport(tenant_id=tenant_id, processed=len(rows), km_source=snapper.name)


__all__ = [
    "GAP_MIN",
    "GapSpan",
    "ProcessReport",
    "ProcessedTrack",
    "apply_processing",
    "find_gaps",
    "process_points",
    "process_session",
    "process_tracks",
    "store_gaps",
]
