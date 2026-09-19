"""VV-008: the officer's own day (timeline, km, stops, gaps, visits) and gap reasons.

``GET /v1/me/day?date=`` is the console day replay (``farmerapp.analytics.replay``) of the
caller — the officer sees exactly what their manager sees (SPEC 4.2) — plus the day's travel
allowance (FA-023). ``POST /v1/me/gaps/{gap_id}/reason`` stores the officer's reason for one
of their gaps (``network | personal_break | vehicle | other`` + note); it then shows in the
cluster head's replay. A gap id is stable (``gap_id``); a gap not stored yet (a session still
open, or processed before the reason) is found by recomputing the officer's recent sessions.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import FiltersOut
from farmerapp.analytics.replay import day_replay
from farmerapp.analytics.schemas import (
    DutySessionBrief,
    GapOut,
    GeoJsonMultiLineString,
    ReplayVisitOut,
    StopOut,
    TimelineEvent,
)
from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.duty.models import GapReason, TrackGap
from farmerapp.duty.models import gap_id as make_gap_id
from farmerapp.duty.processing import find_gaps
from farmerapp.duty.service import session_points
from farmerapp.duty.track import _usable
from farmerapp.location.models import DutySession
from farmerapp.travel.schemas import TravelDayOut
from farmerapp.travel.service import travel_day

router = APIRouter(prefix="/me", tags=["duty"])

DUTY_ROLES = (Role.FIELD_OFFICER, Role.CLUSTER_HEAD)
#: How far back a gap reason may be given (and gaps are recomputed to find an id).
REASON_WINDOW = timedelta(days=7)


class MeDayOut(BaseModel):
    date: date
    officer_id: uuid.UUID
    duty_sessions: list[DutySessionBrief]
    km: float = Field(description="The day's km (processed km of ended sessions, VV-006).")
    track: GeoJsonMultiLineString
    stops: list[StopOut]
    gaps: list[GapOut] = Field(description="Gaps > 30 min while on duty, with reasons.")
    visits: list[ReplayVisitOut]
    timeline: list[TimelineEvent]
    travel: TravelDayOut = Field(description="FA-023 travel allowance of the day.")


class GapReasonIn(BaseModel):
    reason: GapReason
    note: str | None = Field(default=None, max_length=500)


class GapOutRow(BaseModel):
    id: uuid.UUID
    duty_session_id: uuid.UUID
    start: datetime
    end: datetime
    duration_s: int
    reason: str | None
    note: str | None
    reason_at: datetime | None

    @classmethod
    def from_row(cls, row: TrackGap) -> GapOutRow:
        return cls(
            id=row.id,
            duty_session_id=row.duty_session_id,
            start=row.start_at,
            end=row.end_at,
            duration_s=row.duration_s,
            reason=row.reason,
            note=row.note,
            reason_at=row.reason_at,
        )


async def my_day(session: AsyncSession, actor: User, day: date, *, now: datetime) -> MeDayOut:
    replay = await day_replay(
        session,
        actor,
        day,
        FiltersOut(from_=day, to=day, days=1, scope="own"),
        now=now,
    )
    return MeDayOut(
        date=day,
        officer_id=actor.id,
        duty_sessions=replay.duty_sessions,
        km=replay.km,
        track=replay.track,
        stops=replay.stops,
        gaps=replay.gaps,
        visits=replay.visits,
        timeline=replay.timeline,
        travel=await travel_day(session, actor.tenant_id, actor.id, day),
    )


async def _find_gap(
    session: AsyncSession, actor: User, target: uuid.UUID, *, now: datetime
) -> TrackGap | None:
    """Recompute the officer's recent sessions' gaps and build the row with ``target`` id."""
    sessions = (
        (
            await session.execute(
                select(DutySession).where(
                    DutySession.tenant_id == actor.tenant_id,
                    DutySession.officer_id == actor.id,
                    DutySession.deleted_at.is_(None),
                    DutySession.start_at >= now - REASON_WINDOW,
                )
            )
        )
        .scalars()
        .all()
    )
    for duty in sessions:
        end = duty.end_at or now
        points = _usable(await session_points(session, duty, until=end))
        for span in find_gaps(duty.start_at, end, [p.ts for p in points]):
            if make_gap_id(duty.id, span.start) == target:
                return TrackGap(
                    id=target,
                    tenant_id=actor.tenant_id,
                    duty_session_id=duty.id,
                    officer_id=actor.id,
                    start_at=span.start,
                    end_at=span.end,
                    duration_s=span.duration_s,
                )
    return None


async def give_reason(
    session: AsyncSession, actor: User, gap: uuid.UUID, body: GapReasonIn, *, now: datetime
) -> GapOutRow:
    row = await session.get(TrackGap, gap)
    if row is not None and (
        row.tenant_id != actor.tenant_id or row.officer_id != actor.id or row.deleted_at
    ):
        raise NotFoundError("Gap not found.")
    if row is None:
        row = await _find_gap(session, actor, gap, now=now)
        if row is None:
            raise NotFoundError("Gap not found.")
        session.add(row)
    row.reason = body.reason.value
    row.note = body.note
    row.reason_at = now
    await session.flush()
    await session.refresh(row)
    return GapOutRow.from_row(row)


@router.get(
    "/day",
    operation_id="getMyDay",
    summary="The caller's day: duty sessions, km, stops, gaps (with reasons), visits, TA",
    response_model=MeDayOut,
)
async def get_my_day(
    actor: Annotated[User, require_roles(*DUTY_ROLES)],
    session: DbSession,
    services: Services,
    day: Annotated[date, Query(alias="date", description="The IST day (YYYY-MM-DD).")],
) -> MeDayOut:
    return await my_day(session, actor, day, now=services.clock.now())


@router.post(
    "/gaps/{gap_id}/reason",
    operation_id="setGapReason",
    summary="Explain a gap in the caller's track (shown to the cluster head)",
    response_model=GapOutRow,
    responses=problem_responses((404, "not_found")),
)
async def set_gap_reason(
    gap_id: uuid.UUID,
    body: GapReasonIn,
    actor: Annotated[User, require_roles(*DUTY_ROLES)],
    session: DbSession,
    services: Services,
) -> GapOutRow:
    return await give_reason(session, actor, gap_id, body, now=services.clock.now())


__all__ = ["GapOutRow", "GapReasonIn", "MeDayOut", "give_reason", "my_day", "router"]
