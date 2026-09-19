"""Duty start / end (FA-010) shared by the REST twins and the ``duty_session`` sync ops.

Rules, in one place:

* **Start** needs an acceptance of the tenant's current ``location_policy_version``
  (FA-011 / VV-010 — ``policy_not_accepted`` otherwise, also when the app sends another
  version), and no other open session: an open session younger than 24 h is
  ``duty_already_active``; an older one is a stale toggle (phone died) and is closed
  ``forced`` at the new start before the new session opens.
* **End** closes the officer's open session with the device's ``end_at`` / ``end_point`` /
  ``end_reason`` (``manual``, or ``auto_time`` / ``auto_idle`` when the app ended it) and
  computes ``km`` / ``stops`` from the stored points (``farmerapp.duty.track``). A session
  the server already ended keeps its end (server-owned, ``SERVER_OWNED_FIELDS``).
* Points are only ever stored inside a session's window (``farmerapp.location.ingest``), so
  "no location while off duty" (FA-010) is a property of the data, not of the client.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User
from farmerapp.db.geo import point_wkt
from farmerapp.duty.errors import DutyAlreadyActiveError, NoActiveDutyError
from farmerapp.duty.processing import apply_processing
from farmerapp.duty.schemas import DutyEndIn, DutyPolicyOut, DutyStartIn, DutyStatusOut
from farmerapp.duty.track import TrackPoint
from farmerapp.location import events as location_events
from farmerapp.location.models import DutyEndReason, DutySession, LocationPoint
from farmerapp.location.schemas import DutySessionOut
from farmerapp.logging import get_logger
from farmerapp.policies import service as policies
from farmerapp.policies.errors import PolicyNotAcceptedError
from farmerapp.tenants.settings import TenantSettings

log = get_logger("farmerapp.duty")

#: An open session older than this is a stale toggle, closed ``forced`` when a new one starts.
STALE_SESSION_AFTER = timedelta(hours=24)
#: Points up to this long before the start / after the end still belong to the session
#: (the app samples a first fix before the toggle lands and a last one after).
WINDOW_SLACK = timedelta(minutes=2)


def aware(ts: datetime) -> datetime:
    return ts if ts.tzinfo is not None else ts.replace(tzinfo=UTC)


def session_window(duty: DutySession, now: datetime) -> tuple[datetime, datetime]:
    """``[start - slack, end (or now) + slack]``: the only time points may be stored."""
    upper = duty.end_at if duty.end_at is not None else now
    return duty.start_at - WINDOW_SLACK, upper + WINDOW_SLACK


async def open_session(
    session: AsyncSession, tenant_id: uuid.UUID, officer_id: uuid.UUID
) -> DutySession | None:
    stmt = (
        select(DutySession)
        .where(
            DutySession.tenant_id == tenant_id,
            DutySession.officer_id == officer_id,
            DutySession.end_at.is_(None),
            DutySession.deleted_at.is_(None),
        )
        .order_by(DutySession.start_at.desc())
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def own_session(session: AsyncSession, actor: User, duty_id: uuid.UUID) -> DutySession:
    """The actor's own session by id (a colleague's is a 404)."""
    duty = await session.get(DutySession, duty_id)
    if (
        duty is None
        or duty.tenant_id != actor.tenant_id
        or duty.officer_id != actor.id
        or duty.deleted_at is not None
    ):
        raise NotFoundError("Duty session not found.")
    return duty


async def session_points(
    session: AsyncSession, duty: DutySession, *, until: datetime
) -> list[TrackPoint]:
    """The stored points of a session inside its window (partition-pruned by ``ts``)."""
    lower, upper = session_window(duty, until)
    stmt = (
        select(LocationPoint)
        .where(
            LocationPoint.tenant_id == duty.tenant_id,
            LocationPoint.duty_session_id == duty.id,
            LocationPoint.ts >= lower,
            LocationPoint.ts <= upper,
        )
        .order_by(LocationPoint.ts)
    )
    rows = (await session.execute(stmt)).scalars().all()
    return [TrackPoint(ts=r.ts, lat=r.lat, lon=r.lon, accuracy_m=r.accuracy_m) for r in rows]


async def close_session(
    session: AsyncSession,
    duty: DutySession,
    *,
    end_at: datetime,
    end_reason: DutyEndReason | str,
    end_point: tuple[float, float] | None = None,
) -> DutySession:
    """Set the end fields and the km / stops computed from the points up to ``end_at``."""
    end_at = max(aware(end_at), duty.start_at)
    points = await session_points(session, duty, until=end_at)
    duty.end_at = end_at
    duty.end_reason = str(end_reason)
    if end_point is not None:
        duty.end_point = point_wkt(end_point[1], end_point[0])
    elif points:
        last = points[-1]
        duty.end_point = point_wkt(last.lon, last.lat)
    # VV-006: km (jitter-filtered; road snapping runs later in the process-tracks job),
    # stops and gaps (track_gap rows) at the end of duty — one update of the session row.
    summary = await apply_processing(session, duty, points, end=end_at)
    await session.flush()
    await session.refresh(duty)
    log.info(
        "duty_ended",
        duty_session_id=str(duty.id),
        officer_id=str(duty.officer_id),
        end_reason=duty.end_reason,
        km=str(summary.km),
        stops=len(summary.stops),
        gaps=len(summary.gaps),
        points=summary.kept,
    )
    return duty


async def start_duty(
    session: AsyncSession, actor: User, body: DutyStartIn, *, now: datetime
) -> DutySessionOut:
    settings = await policies.settings_for(session, actor.tenant_id)
    required = settings.location_policy_version
    await policies.require_accepted(session, actor, required)
    if body.policy_version != required:
        raise PolicyNotAcceptedError(
            f"The app holds policy {body.policy_version}; {required} must be accepted.",
            extra={"required_version": required},
        )
    start_at = min(aware(body.start_at), now + WINDOW_SLACK)
    current = await open_session(session, actor.tenant_id, actor.id)
    if current is not None:
        if now - current.start_at <= STALE_SESSION_AFTER:
            raise DutyAlreadyActiveError(
                "A duty session is already active.", extra={"duty_session_id": str(current.id)}
            )
        await close_session(
            session, current, end_at=min(start_at, now), end_reason=DutyEndReason.FORCED
        )
    duty = DutySession(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        officer_id=actor.id,
        start_at=start_at,
        start_point=point_wkt(body.start_point.lon, body.start_point.lat),
        policy_version=required,
        device_id=body.device_id,
        app_version=body.app_version,
        device_integrity=body.integrity.model_dump(),
    )
    session.add(duty)
    await session.flush()
    await session.refresh(duty)
    log.info(
        "duty_started",
        duty_session_id=str(duty.id),
        officer_id=str(actor.id),
        device_id=body.device_id,
        is_mock=body.integrity.is_mock,
        is_rooted=body.integrity.is_rooted,
        clock_drift_s=body.integrity.clock_drift_s,
    )
    await location_events.bus.dispatch(  # M4: VA-E01 on the start's integrity flags
        session,
        location_events.DutyStarted(
            tenant_id=actor.tenant_id, duty_session_id=duty.id, officer_id=actor.id, at=now
        ),
    )
    return DutySessionOut.from_row(duty)


async def end_duty(
    session: AsyncSession,
    actor: User,
    body: DutyEndIn,
    *,
    now: datetime,
    duty: DutySession | None = None,
) -> DutySessionOut:
    """End ``duty`` (default: the actor's open session) with the device's end fields."""
    if duty is None:
        duty = await open_session(session, actor.tenant_id, actor.id)
        if duty is None:
            raise NoActiveDutyError("No duty session is active.")
    end_point = (body.end_point.lat, body.end_point.lon) if body.end_point else None
    await close_session(
        session,
        duty,
        end_at=min(aware(body.end_at), now + WINDOW_SLACK),
        end_reason=body.end_reason,
        end_point=end_point,
    )
    return DutySessionOut.from_row(duty)


async def status(session: AsyncSession, actor: User) -> DutyStatusOut:
    settings = await policies.settings_for(session, actor.tenant_id)
    current = await open_session(session, actor.tenant_id, actor.id)
    return DutyStatusOut(
        session=DutySessionOut.from_row(current) if current is not None else None,
        policy_version=settings.location_policy_version,
        policy_accepted=await policies.has_accepted(
            session, actor, settings.location_policy_version
        ),
    )


def sampling_policy(settings: TenantSettings) -> DutyPolicyOut:
    return DutyPolicyOut(
        moving_interval_s=settings.sampling.moving_s,
        stationary_interval_s=settings.sampling.stationary_s,
        upload_interval_s=settings.sampling.upload_s,
        upload_on_wifi_or_charging=True,
    )


def as_decimal(value: Any) -> Decimal | None:
    return None if value is None else Decimal(str(value))


__all__ = [
    "STALE_SESSION_AFTER",
    "WINDOW_SLACK",
    "aware",
    "close_session",
    "end_duty",
    "open_session",
    "own_session",
    "sampling_policy",
    "session_points",
    "session_window",
    "start_duty",
    "status",
]
