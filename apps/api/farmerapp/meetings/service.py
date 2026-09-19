"""FA-027 farmer meetings: geofenced creation, attendance by OTP or QR, the attendance list.

* **Create** — the officer checks in at the village's registered meeting point: the point is
  evaluated like a visit with purpose ``meeting`` (VV-003, ``farmerapp.visits.geofence``):
  within the meeting point radius, else ``422 outside_geofence`` with the distance (a village
  without a meeting point cannot host one).
* **Attendance by OTP** — ``attendance/otp`` sends a code to the farmer's phone through the
  FA-001 OTP machinery (purpose ``meeting_attendance``, same limits and lockout); the officer
  types the code the farmer reads out (``method = otp``). Needs connectivity, like FA-016.
* **Attendance by QR** — the farmer app shows ``GET /v1/me/attendance-qr``: a short-lived
  HS256 token (``typ = meeting_attendance``, tenant + farmer, ``MEETING_QR_TTL_SECONDS``,
  default 5 min). The officer's app scans it (offline too: validated when the op syncs,
  against the scan time).
* A farmer attends a meeting once (unique): a second record is a replay of the first.
  Attendance is recorded on open meetings of the officer only.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

import jwt
from sqlalchemy import ColumnElement, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ConflictError, NotFoundError
from farmerapp.api.pagination import PageRequest
from farmerapp.auth.field_scope import staff_ids
from farmerapp.auth.models import OtpPurpose, User
from farmerapp.auth.providers import mask_phone
from farmerapp.db.geo import point_wkt
from farmerapp.farmers.models import Farmer
from farmerapp.meetings.models import (
    AttendanceMethod,
    FarmerMeeting,
    MeetingAttendance,
    MeetingStatus,
)
from farmerapp.meetings.schemas import (
    AttendanceIn,
    AttendanceOtpOut,
    AttendanceOut,
    AttendanceQrOut,
    MeetingCreate,
    MeetingDetailOut,
    MeetingOut,
    MeetingPage,
)
from farmerapp.settings import Settings
from farmerapp.tenants.settings import get_tenant_settings
from farmerapp.visits import geofence
from farmerapp.visits.errors import OutsideGeofenceError

if TYPE_CHECKING:
    from farmerapp.auth.deps import AuthServices

QR_TYP = "meeting_attendance"
OTP_PURPOSE = OtpPurpose.MEETING_ATTENDANCE


class MeetingClosedError(ConflictError):
    code = "meeting_closed"


class AttendanceTokenInvalidError(AppError):
    status = 422
    code = "attendance_token_invalid"


class FarmerProfileMissingError(NotFoundError):
    code = "farmer_profile_not_found"


def meeting_filters(actor: User) -> list[ColumnElement[bool]]:
    return [
        FarmerMeeting.tenant_id == actor.tenant_id,
        FarmerMeeting.deleted_at.is_(None),
        FarmerMeeting.officer_id.in_(staff_ids(actor)),
    ]


async def visible_meeting(
    session: AsyncSession, actor: User, meeting_id: uuid.UUID
) -> FarmerMeeting:
    row = (
        await session.execute(
            select(FarmerMeeting).where(FarmerMeeting.id == meeting_id, *meeting_filters(actor))
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Meeting not found.")
    return row


async def own_meeting(session: AsyncSession, actor: User, meeting_id: uuid.UUID) -> FarmerMeeting:
    row = await visible_meeting(session, actor, meeting_id)
    if row.officer_id != actor.id:
        raise NotFoundError("Meeting not found.")
    return row


async def create_meeting(
    session: AsyncSession, actor: User, body: MeetingCreate
) -> tuple[FarmerMeeting, bool]:
    if body.id is not None:
        existing = await session.get(FarmerMeeting, body.id)
        if existing is not None:
            return await own_meeting(session, actor, existing.id), False
    village = await geofence.village_of(session, actor.tenant_id, body.village_id)
    if village is None:
        raise NotFoundError("Village not found.")
    settings = await get_tenant_settings(session, actor.tenant_id)
    point = body.checkin_point
    check = await geofence.evaluate(
        session,
        lat=point.lat,
        lon=point.lon,
        farm=None,
        village=village,
        default_radius_m=settings.geofence_radius_m,
        meeting_point_radius_m=settings.meeting_point_radius_m,
    )
    if not check.allowed:
        raise OutsideGeofenceError(
            "Hold the meeting at the village meeting point.",
            extra={
                "distance_m": check.distance_m,
                "target": check.target,
                "radius_m": check.radius_m,
            },
        )
    row = FarmerMeeting(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        officer_id=actor.id,
        village_id=village.id,
        topic=body.topic,
        held_at=body.held_at,
        checkin_point=point_wkt(point.lon, point.lat),
        checkin_accuracy_m=point.accuracy_m,
        geofence_result=check.result.value,
        distance_m=check.distance_m,
    )
    session.add(row)
    await session.flush()
    await session.refresh(row)
    return row, True


async def _tenant_farmer(session: AsyncSession, tenant_id: uuid.UUID, farmer_id: Any) -> Farmer:
    try:
        fid = uuid.UUID(str(farmer_id))
    except ValueError as exc:
        raise NotFoundError("Farmer not found.") from exc
    farmer = await session.get(Farmer, fid)
    if farmer is None or farmer.tenant_id != tenant_id or farmer.deleted_at is not None:
        raise NotFoundError("Farmer not found.")
    return farmer


async def send_attendance_otp(
    session: AsyncSession,
    actor: User,
    meeting: FarmerMeeting,
    farmer_id: uuid.UUID,
    *,
    services: AuthServices,
    device_id: str | None,
) -> AttendanceOtpOut:
    if meeting.status != MeetingStatus.OPEN:
        raise MeetingClosedError("The meeting is closed.")
    farmer = await _tenant_farmer(session, actor.tenant_id, farmer_id)
    sent = await services.otp.send(
        session,
        phone=farmer.phone,
        purpose=OTP_PURPOSE,
        tenant_id=actor.tenant_id,
        device_id=device_id,
    )
    settings = services.settings
    return AttendanceOtpOut(
        farmer_id=farmer.id,
        phone_masked=mask_phone(farmer.phone),
        expires_in=settings.otp_ttl_seconds,
        resend_after=settings.otp_resend_after_seconds,
        resends_left=sent.resends_left,
    )


def issue_qr(settings: Settings, farmer: Farmer, *, now: datetime) -> AttendanceQrOut:
    expires = now + timedelta(seconds=settings.meeting_qr_ttl_seconds)
    claims = {
        "iss": settings.jwt_issuer,
        "typ": QR_TYP,
        "tid": str(farmer.tenant_id),
        "fid": str(farmer.id),
        "iat": int(now.timestamp()),
        "exp": int(expires.timestamp()),
        "jti": uuid.uuid4().hex,
    }
    token = jwt.encode(claims, settings.jwt_signing_key, algorithm=settings.jwt_algorithm)
    return AttendanceQrOut(token=token, farmer_id=farmer.id, expires_at=expires)


async def my_attendance_qr(
    session: AsyncSession, actor: User, settings: Settings, *, now: datetime
) -> AttendanceQrOut:
    farmer = (
        await session.execute(
            select(Farmer).where(
                Farmer.tenant_id == actor.tenant_id,
                Farmer.user_id == actor.id,
                Farmer.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if farmer is None:
        raise FarmerProfileMissingError("No farmer profile for this account.")
    return issue_qr(settings, farmer, now=now)


def decode_qr(settings: Settings, token: str, *, tenant_id: uuid.UUID, at: datetime) -> str:
    """The farmer id of a valid attendance QR (not expired at ``at``)."""
    try:
        claims: dict[str, Any] = jwt.decode(
            token,
            settings.jwt_signing_key,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            options={"verify_exp": False, "verify_iat": False, "require": ["exp", "fid", "tid"]},
        )
    except jwt.PyJWTError as exc:
        raise AttendanceTokenInvalidError("Invalid attendance QR.") from exc
    if claims.get("typ") != QR_TYP or claims.get("tid") != str(tenant_id):
        raise AttendanceTokenInvalidError("Invalid attendance QR.")
    if int(claims["exp"]) < int(at.timestamp()):
        raise AttendanceTokenInvalidError("The QR expired; ask the farmer to refresh it.")
    return str(claims["fid"])


async def record_attendance(
    session: AsyncSession,
    actor: User,
    meeting: FarmerMeeting,
    body: AttendanceIn,
    *,
    services: AuthServices,
    now: datetime,
) -> tuple[MeetingAttendance, bool]:
    if body.id is not None:
        existing = await session.get(MeetingAttendance, body.id)
        if existing is not None:
            if existing.tenant_id != actor.tenant_id or existing.meeting_id != meeting.id:
                raise NotFoundError("Attendance not found.")
            return existing, False
    if meeting.status != MeetingStatus.OPEN:
        raise MeetingClosedError("The meeting is closed.")
    at = min(body.recorded_at or now, now)
    challenge_id: uuid.UUID | None = None
    if body.method == AttendanceMethod.OTP.value:
        farmer = await _tenant_farmer(session, actor.tenant_id, body.farmer_id)
        challenge = await services.otp.verify(
            session,
            phone=farmer.phone,
            code=body.code or "",
            purpose=OTP_PURPOSE,
            tenant_id=actor.tenant_id,
        )
        challenge_id = challenge.id
    else:
        fid = decode_qr(services.settings, body.token or "", tenant_id=actor.tenant_id, at=at)
        farmer = await _tenant_farmer(session, actor.tenant_id, fid)
    already = (
        await session.execute(
            select(MeetingAttendance).where(
                MeetingAttendance.meeting_id == meeting.id,
                MeetingAttendance.farmer_id == farmer.id,
            )
        )
    ).scalar_one_or_none()
    if already is not None:
        return already, False
    row = MeetingAttendance(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        meeting_id=meeting.id,
        farmer_id=farmer.id,
        method=body.method,
        recorded_at=at,
        recorded_by=actor.id,
        otp_challenge_id=challenge_id,
    )
    session.add(row)
    await session.flush()
    await session.refresh(row)
    return row, True


async def close_meeting(session: AsyncSession, meeting: FarmerMeeting, *, now: datetime) -> None:
    if meeting.status == MeetingStatus.CLOSED:
        return
    meeting.status = MeetingStatus.CLOSED.value
    meeting.closed_at = now
    await session.flush()
    await session.refresh(meeting)


async def attendee_count(
    session: AsyncSession, meeting_ids: list[uuid.UUID]
) -> dict[uuid.UUID, int]:
    if not meeting_ids:
        return {}
    rows = await session.execute(
        select(MeetingAttendance.meeting_id, func.count())
        .where(
            MeetingAttendance.meeting_id.in_(meeting_ids), MeetingAttendance.deleted_at.is_(None)
        )
        .group_by(MeetingAttendance.meeting_id)
    )
    return {r[0]: int(r[1]) for r in rows}


async def detail(session: AsyncSession, meeting: FarmerMeeting) -> MeetingDetailOut:
    rows = (
        await session.execute(
            select(MeetingAttendance, Farmer.name)
            .join(Farmer, Farmer.id == MeetingAttendance.farmer_id)
            .where(
                MeetingAttendance.meeting_id == meeting.id,
                MeetingAttendance.deleted_at.is_(None),
            )
            .order_by(MeetingAttendance.recorded_at, MeetingAttendance.id)
        )
    ).all()
    base = MeetingOut.from_row(meeting, attendees=len(rows))
    return MeetingDetailOut(
        **base.model_dump(),
        attendance=[AttendanceOut.from_row(a, name) for a, name in rows],
    )


async def list_meetings(
    session: AsyncSession, actor: User, page: PageRequest, *, village_id: uuid.UUID | None
) -> MeetingPage:
    stmt = select(FarmerMeeting).where(*meeting_filters(actor))
    if village_id is not None:
        stmt = stmt.where(FarmerMeeting.village_id == village_id)
    keyset = page.after(FarmerMeeting.created_at, FarmerMeeting.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(FarmerMeeting.created_at, FarmerMeeting.id).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    counts = await attendee_count(session, [m.id for m in items])
    return MeetingPage(
        items=[MeetingOut.from_row(m, counts.get(m.id, 0)) for m in items], next_cursor=cursor
    )


__all__ = [
    "QR_TYP",
    "AttendanceTokenInvalidError",
    "MeetingClosedError",
    "close_meeting",
    "create_meeting",
    "decode_qr",
    "detail",
    "issue_qr",
    "list_meetings",
    "meeting_filters",
    "my_attendance_qr",
    "own_meeting",
    "record_attendance",
    "send_attendance_otp",
    "visible_meeting",
]
