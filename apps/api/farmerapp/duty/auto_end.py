"""VV-007 auto end of duty and OPS-006 sync silence — the two scheduled duty jobs.

``auto-end-duty`` (Cloud Scheduler every 10 min, per tenant) closes every open session that

* is past the tenant's ``auto_duty_end_local_time`` (IST; default 20:00) — ended *at* that
  time with ``end_reason = auto_time`` (the first auto-end instant after ``start_at``, so a
  session that started after 20:00 runs until the next evening); or
* has been idle at home for ``idle_end_minutes`` (default 60): the kept points of the last
  ``idle_end_minutes`` all lie within 100 m of the first of them, the window is covered by
  data (first point within one stationary interval + 5 min of the window start, last one
  as close to now), and their centroid is within 200 m of the officer's ``home_point``
  (fallback: their store's location) — ended at the first idle point with ``auto_idle``.

Both write a ``notification`` row for the officer (``duty_auto_ended``) so the app can
prompt (FA-007 delivers it). After the end, ``farmerapp.location.ingest`` rejects every
point past ``end_at + 2 min``: no tracking beyond auto end.

``officer-sync-silence`` flags officers on duty whose last location batch arrived more than
two hours ago (``received_at``; the session start counts as the first contact) with a
``notification`` to the cluster head(s) of their cluster, once per session.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta, timezone

from sqlalchemy import cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.geo import haversine_m
from farmerapp.db.session import job_session
from farmerapp.duty.service import close_session, session_points
from farmerapp.duty.track import MAX_ACCURACY_M, TrackPoint
from farmerapp.location.models import _POINT_GEOM, DutyEndReason, DutySession, LocationPoint
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.policies.service import settings_for
from farmerapp.tenants.models import Store
from farmerapp.tenants.settings import TenantSettings

log = get_logger("farmerapp.duty.auto_end")

IST = timezone(timedelta(hours=5, minutes=30), "IST")
IDLE_RADIUS_M = 100.0
HOME_RADIUS_M = 200.0
IDLE_COVERAGE_SLACK = timedelta(minutes=5)
SYNC_SILENCE = timedelta(hours=2)

TITLE_AUTO_ENDED = "notification.duty_auto_ended.title"
BODY_AUTO_ENDED = "notification.duty_auto_ended.body."  # + end_reason
TITLE_SYNC_SILENCE = "notification.officer_sync_silence.title"
BODY_SYNC_SILENCE = "notification.officer_sync_silence.body"


@dataclass(frozen=True)
class AutoEndResult:
    tenant_id: uuid.UUID
    duty_session_id: uuid.UUID
    officer_id: uuid.UUID
    end_reason: str
    end_at: datetime


@dataclass(frozen=True)
class SilenceResult:
    tenant_id: uuid.UUID
    duty_session_id: uuid.UUID
    officer_id: uuid.UUID
    last_contact_at: datetime
    notified: list[uuid.UUID]  # cluster heads


def auto_time_cutoff(start_at: datetime, end_time: time, tz: timezone = IST) -> datetime:
    """The first ``end_time`` (local) strictly after ``start_at``."""
    local = start_at.astimezone(tz)
    cutoff = datetime.combine(local.date(), end_time, tzinfo=tz)
    if cutoff <= start_at:
        cutoff += timedelta(days=1)
    return cutoff.astimezone(UTC)


async def home_of(session: AsyncSession, officer: User) -> tuple[float, float] | None:
    """``(lat, lon)`` of the officer's home point, else their store, else ``None``."""
    home = (
        await session.execute(
            select(
                func.ST_Y(cast(User.home_point, _POINT_GEOM)),
                func.ST_X(cast(User.home_point, _POINT_GEOM)),
            ).where(User.id == officer.id, User.home_point.is_not(None))
        )
    ).first()
    if home is not None:
        return float(home[0]), float(home[1])
    if officer.store_id is None:
        return None
    store = (
        await session.execute(
            select(
                func.ST_Y(cast(Store.location, _POINT_GEOM)),
                func.ST_X(cast(Store.location, _POINT_GEOM)),
            ).where(Store.id == officer.store_id)
        )
    ).first()
    return (float(store[0]), float(store[1])) if store is not None else None


def idle_since(
    points: list[TrackPoint],
    *,
    now: datetime,
    idle: timedelta,
    stationary_s: int,
    home: tuple[float, float],
) -> datetime | None:
    """When the officer became idle at home, if the last ``idle`` window proves it."""
    window_start = now - idle
    coverage = timedelta(seconds=stationary_s) + IDLE_COVERAGE_SLACK
    window = [p for p in points if window_start <= p.ts <= now and p.accuracy_m <= MAX_ACCURACY_M]
    if len(window) < 2:
        return None
    if window[0].ts > window_start + coverage or window[-1].ts < now - coverage:
        return None  # not enough data across the window to call it idle
    first = window[0]
    if any(haversine_m(first.lat, first.lon, p.lat, p.lon) >= IDLE_RADIUS_M for p in window):
        return None  # moved
    lat = sum(p.lat for p in window) / len(window)
    lon = sum(p.lon for p in window) / len(window)
    if haversine_m(lat, lon, home[0], home[1]) > HOME_RADIUS_M:
        return None  # idle, but not at home (a long meeting is still duty)
    return first.ts


def _notify(session: AsyncSession, duty: DutySession, end_at: datetime, reason: str) -> None:
    session.add(
        Notification(
            tenant_id=duty.tenant_id,
            user_id=duty.officer_id,
            kind=NotificationKind.DUTY_AUTO_ENDED,
            title_key=TITLE_AUTO_ENDED,
            body_key=BODY_AUTO_ENDED + reason,
            data={
                "duty_session_id": str(duty.id),
                "end_reason": reason,
                "end_at": end_at.isoformat(),
            },
        )
    )


async def _open_sessions(session: AsyncSession, tenant_id: uuid.UUID) -> list[DutySession]:
    stmt = (
        select(DutySession)
        .where(
            DutySession.tenant_id == tenant_id,
            DutySession.end_at.is_(None),
            DutySession.deleted_at.is_(None),
        )
        .order_by(DutySession.start_at)
    )
    return list((await session.execute(stmt)).scalars().all())


async def _end_one(
    session: AsyncSession,
    duty: DutySession,
    settings: TenantSettings,
    now: datetime,
    officers: dict[uuid.UUID, User],
) -> AutoEndResult | None:
    cutoff = auto_time_cutoff(duty.start_at, settings.auto_duty_end_time())
    if now >= cutoff:
        await close_session(session, duty, end_at=cutoff, end_reason=DutyEndReason.AUTO_TIME)
        _notify(session, duty, cutoff, DutyEndReason.AUTO_TIME)
        return AutoEndResult(
            duty.tenant_id, duty.id, duty.officer_id, DutyEndReason.AUTO_TIME, cutoff
        )
    officer = officers.get(duty.officer_id)
    if officer is None:
        return None
    home = await home_of(session, officer)
    if home is None:
        return None
    became_idle = idle_since(
        await session_points(session, duty, until=now),
        now=now,
        idle=timedelta(minutes=settings.idle_end_minutes),
        stationary_s=settings.sampling.stationary_s,
        home=home,
    )
    if became_idle is None:
        return None
    await close_session(session, duty, end_at=became_idle, end_reason=DutyEndReason.AUTO_IDLE)
    _notify(session, duty, became_idle, DutyEndReason.AUTO_IDLE)
    return AutoEndResult(
        duty.tenant_id, duty.id, duty.officer_id, DutyEndReason.AUTO_IDLE, became_idle
    )


async def auto_end_duty(
    session: AsyncSession, *, tenant_id: uuid.UUID, now: datetime | None = None
) -> list[AutoEndResult]:
    """One pass over the tenant's open sessions (the session is bound to ``tenant_id``)."""
    now = now or datetime.now(UTC)
    settings = await settings_for(session, tenant_id)
    open_sessions = await _open_sessions(session, tenant_id)
    if not open_sessions:
        return []
    officers = {
        u.id: u
        for u in (
            await session.execute(
                select(User).where(User.id.in_({d.officer_id for d in open_sessions}))
            )
        ).scalars()
    }
    results: list[AutoEndResult] = []
    for duty in open_sessions:
        result = await _end_one(session, duty, settings, now, officers)
        if result is not None:
            results.append(result)
    await session.flush()
    log.info(
        "duty_auto_end",
        tenant_id=str(tenant_id),
        open_sessions=len(open_sessions),
        ended=len(results),
        auto_time=sum(r.end_reason == DutyEndReason.AUTO_TIME for r in results),
        auto_idle=sum(r.end_reason == DutyEndReason.AUTO_IDLE for r in results),
    )
    return results


async def _last_contact(session: AsyncSession, duty: DutySession) -> datetime:
    last = await session.scalar(
        select(func.max(LocationPoint.received_at)).where(
            LocationPoint.tenant_id == duty.tenant_id,
            LocationPoint.duty_session_id == duty.id,
            LocationPoint.ts >= duty.start_at - timedelta(minutes=2),
        )
    )
    return max(last, duty.start_at) if last is not None else duty.start_at


async def _already_flagged(session: AsyncSession, duty: DutySession) -> bool:
    stmt = select(Notification.id).where(
        Notification.tenant_id == duty.tenant_id,
        Notification.kind == NotificationKind.OFFICER_SYNC_SILENCE,
        Notification.data["duty_session_id"].astext == str(duty.id),
    )
    return (await session.execute(stmt.limit(1))).first() is not None


async def officer_sync_silence(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime | None = None,
    silence: timedelta = SYNC_SILENCE,
) -> list[SilenceResult]:
    """Notify cluster heads of officers on duty with no location batch for ``silence``."""
    now = now or datetime.now(UTC)
    results: list[SilenceResult] = []
    for duty in await _open_sessions(session, tenant_id):
        last = await _last_contact(session, duty)
        if now - last < silence or await _already_flagged(session, duty):
            continue
        officer = await session.get(User, duty.officer_id)
        heads: list[User] = []
        if officer is not None and officer.cluster_id is not None:
            heads = list(
                (
                    await session.execute(
                        select(User).where(
                            User.tenant_id == tenant_id,
                            User.role == UserRole.CLUSTER_HEAD,
                            User.cluster_id == officer.cluster_id,
                            User.status == UserStatus.ACTIVE,
                            User.deleted_at.is_(None),
                        )
                    )
                ).scalars()
            )
        for head in heads:
            session.add(
                Notification(
                    tenant_id=tenant_id,
                    user_id=head.id,
                    kind=NotificationKind.OFFICER_SYNC_SILENCE,
                    title_key=TITLE_SYNC_SILENCE,
                    body_key=BODY_SYNC_SILENCE,
                    data={
                        "duty_session_id": str(duty.id),
                        "officer_id": str(duty.officer_id),
                        "last_contact_at": last.isoformat(),
                        "silent_minutes": int((now - last).total_seconds() // 60),
                    },
                )
            )
        results.append(
            SilenceResult(tenant_id, duty.id, duty.officer_id, last, [h.id for h in heads])
        )
    await session.flush()
    log.info(
        "officer_sync_silence",
        tenant_id=str(tenant_id),
        silent=len(results),
        notified=sum(len(r.notified) for r in results),
    )
    return results


# --------------------------------------------------------------------------- jobs
async def run_auto_end(
    tenant_ids: list[uuid.UUID], *, now: datetime | None = None
) -> list[AutoEndResult]:
    results: list[AutoEndResult] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                results.extend(await auto_end_duty(session, tenant_id=tenant_id, now=now))
    return results


async def run_sync_silence(
    tenant_ids: list[uuid.UUID], *, now: datetime | None = None
) -> list[SilenceResult]:
    results: list[SilenceResult] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                results.extend(await officer_sync_silence(session, tenant_id=tenant_id, now=now))
    return results


__all__ = [
    "HOME_RADIUS_M",
    "IDLE_RADIUS_M",
    "IST",
    "SYNC_SILENCE",
    "AutoEndResult",
    "SilenceResult",
    "auto_end_duty",
    "auto_time_cutoff",
    "home_of",
    "idle_since",
    "officer_sync_silence",
    "run_auto_end",
    "run_sync_silence",
]
