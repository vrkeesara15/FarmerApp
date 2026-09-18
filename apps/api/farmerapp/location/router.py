"""``/v1/duty-sessions`` and ``/v1/officers/{id}/track`` — read endpoints (M2-KICKOFF).

SPEC 2.6 "Officer location track": owner / director / auditor (and tenant admin) read
everything, a cluster head their own cluster, a field officer themselves only. Store
managers, accountants, agronomists and farmers are not on the routes at all (403), and
an officer asking for a colleague's track gets 404 (``officer_filters``). The duty toggle
and point upload (FA-010, VV-001) are the loop's write endpoints.

A track day is a local (IST) calendar day: officers work IST days and ``location_point``
is partitioned on UTC days, so a day's points span at most two partitions.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import duty_session_filters, officer_filters
from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.location.schemas import (
    DutySessionOut,
    DutySessionPage,
    LocationPointOut,
    TrackOut,
)

duty_router = APIRouter(prefix="/duty-sessions", tags=["duty"])
officer_router = APIRouter(prefix="/officers", tags=["duty"])

#: SPEC 2.6 "Officer location track" column: never store managers or other officers.
TRACK_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.FIELD_OFFICER,
)

IST = timezone(timedelta(hours=5, minutes=30), "IST")
MAX_TRACK_POINTS = 5000  # ~7 points a minute for an 11-hour day; a day is never paginated


def day_bounds(day: date, tz: timezone = IST) -> tuple[datetime, datetime]:
    """``[start, end)`` of a local calendar day as aware datetimes."""
    start = datetime(day.year, day.month, day.day, tzinfo=tz)
    return start, start + timedelta(days=1)


async def visible_officer(session: AsyncSession, actor: User, officer_id: uuid.UUID) -> User:
    """A field officer of the tenant within the actor's track scope, else 404."""
    stmt = select(User).where(
        User.id == officer_id,
        User.role == UserRole.FIELD_OFFICER,
        User.deleted_at.is_(None),
        *officer_filters(actor),
    )
    officer = (await session.execute(stmt)).scalar_one_or_none()
    if officer is None:
        raise NotFoundError("Officer not found.")
    return officer


@duty_router.get(
    "",
    operation_id="listDutySessions",
    summary="Duty sessions of the officers the caller may see (own for officers), oldest first",
    response_model=DutySessionPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_duty_sessions(
    actor: Annotated[User, require_roles(*TRACK_ROLES)],
    session: DbSession,
    page: Page,
    officer_id: Annotated[uuid.UUID | None, Query(description="Officer user id.")] = None,
    from_: Annotated[
        datetime | None, Query(alias="from", description="Started at or after (RFC 3339).")
    ] = None,
    to: Annotated[datetime | None, Query(description="Started before (RFC 3339).")] = None,
) -> DutySessionPage:
    stmt = select(DutySession).where(DutySession.deleted_at.is_(None), *duty_session_filters(actor))
    if officer_id is not None:
        stmt = stmt.where(DutySession.officer_id == officer_id)
    if from_ is not None:
        stmt = stmt.where(DutySession.start_at >= from_)
    if to is not None:
        stmt = stmt.where(DutySession.start_at < to)
    after = page.after(DutySession.created_at, DutySession.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(DutySession.created_at, DutySession.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return DutySessionPage(
        items=[DutySessionOut.from_row(s) for s in items], next_cursor=next_cursor
    )


@officer_router.get(
    "/{id}/track",
    operation_id="getOfficerTrack",
    summary="An officer's location points for one IST day (own day for officers)",
    response_model=TrackOut,
    responses=problem_responses((404, "not_found")),
)
async def get_officer_track(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*TRACK_ROLES)],
    session: DbSession,
    day: Annotated[date, Query(description="Local (IST) calendar day, YYYY-MM-DD.")],
) -> TrackOut:
    officer = await visible_officer(session, actor, id)
    lower, upper = day_bounds(day)
    stmt = (
        select(LocationPoint)
        .where(
            LocationPoint.tenant_id == actor.tenant_id,
            LocationPoint.officer_id == officer.id,
            LocationPoint.ts >= lower,
            LocationPoint.ts < upper,
        )
        .order_by(LocationPoint.ts, LocationPoint.id)
        .limit(MAX_TRACK_POINTS)
    )
    rows = (await session.execute(stmt)).scalars().all()
    points = [LocationPointOut.from_row(p) for p in rows]
    return TrackOut(officer_id=officer.id, day=day, count=len(points), points=points)


__all__ = [
    "IST",
    "MAX_TRACK_POINTS",
    "TRACK_ROLES",
    "day_bounds",
    "duty_router",
    "officer_router",
    "visible_officer",
]
