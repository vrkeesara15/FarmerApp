"""``/v1/meetings`` — FA-027 farmer meetings; ``GET /v1/me/attendance-qr`` for farmers.

Writes (create, attendance, close): the field officer holding the meeting. Reads: the officer,
cluster head (own cluster), owner, director, tenant admin, auditor. The attendance QR: the
farmer role only (their own farmer record).
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.meetings import service
from farmerapp.meetings.schemas import (
    AttendanceIn,
    AttendanceOtpIn,
    AttendanceOtpOut,
    AttendanceOut,
    AttendanceQrOut,
    MeetingCreate,
    MeetingDetailOut,
    MeetingOut,
    MeetingPage,
)

router = APIRouter(prefix="/meetings", tags=["meetings"])
me_router = APIRouter(prefix="/me", tags=["meetings"])

WRITE_ROLES = (Role.FIELD_OFFICER,)
READ_ROLES = (
    Role.FIELD_OFFICER,
    Role.CLUSTER_HEAD,
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
)


@router.post(
    "",
    operation_id="createMeeting",
    summary="Start a farmer meeting at a village meeting point (geofenced like a visit)",
    status_code=201,
    response_model=MeetingOut,
    responses=problem_responses(
        (404, "not_found"), (422, "outside_geofence"), (422, "idempotency_key_reuse")
    ),
)
@idempotent(status_code=201)
async def create_meeting(
    request: Request,
    body: MeetingCreate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> MeetingOut:
    row, _ = await service.create_meeting(session, actor, body)
    return MeetingOut.from_row(row)


@router.get(
    "",
    operation_id="listMeetings",
    summary="Meetings the caller may see, oldest first (cursor)",
    response_model=MeetingPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_meetings(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    village_id: Annotated[uuid.UUID | None, Query()] = None,
) -> MeetingPage:
    return await service.list_meetings(session, actor, page, village_id=village_id)


@router.get(
    "/{id}",
    operation_id="getMeeting",
    summary="A meeting with its attendance list (linked to farmers)",
    response_model=MeetingDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_meeting(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> MeetingDetailOut:
    return await service.detail(session, await service.visible_meeting(session, actor, id))


@router.post(
    "/{id}/attendance/otp",
    operation_id="sendMeetingAttendanceOtp",
    summary="Send an attendance code to a farmer's phone (purpose meeting_attendance)",
    response_model=AttendanceOtpOut,
    responses=problem_responses(
        (404, "not_found"), (409, "meeting_closed"), (429, "otp_resend_limit")
    ),
)
async def send_attendance_otp(
    request: Request,
    id: uuid.UUID,
    body: AttendanceOtpIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> AttendanceOtpOut:
    meeting = await service.own_meeting(session, actor, id)
    return await service.send_attendance_otp(
        session,
        actor,
        meeting,
        body.farmer_id,
        services=services,
        device_id=getattr(request.state, "device_id", None),
    )


@router.post(
    "/{id}/attendance",
    operation_id="recordMeetingAttendance",
    summary="Record a farmer's attendance by OTP code or the farmer app's QR",
    status_code=201,
    response_model=AttendanceOut,
    responses=problem_responses(
        (401, "otp_invalid"),
        (404, "not_found"),
        (409, "meeting_closed"),
        (422, "attendance_token_invalid"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=201)
async def record_attendance(
    request: Request,
    id: uuid.UUID,
    body: AttendanceIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> AttendanceOut:
    meeting = await service.own_meeting(session, actor, id)
    row, _ = await service.record_attendance(
        session, actor, meeting, body, services=services, now=services.clock.now()
    )
    return AttendanceOut.from_row(row)


@router.post(
    "/{id}/close",
    operation_id="closeMeeting",
    summary="Close the meeting (no more attendance)",
    response_model=MeetingDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def close_meeting(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> MeetingDetailOut:
    meeting = await service.own_meeting(session, actor, id)
    await service.close_meeting(session, meeting, now=services.clock.now())
    return await service.detail(session, meeting)


@me_router.get(
    "/attendance-qr",
    operation_id="getMyAttendanceQr",
    summary="Farmer app: a short-lived signed QR token proving the farmer's presence",
    response_model=AttendanceQrOut,
    responses=problem_responses((404, "farmer_profile_not_found")),
)
async def get_attendance_qr(
    actor: Annotated[User, require_roles(Role.FARMER)], session: DbSession, services: Services
) -> AttendanceQrOut:
    return await service.my_attendance_qr(
        session, actor, services.settings, now=services.clock.now()
    )


__all__ = ["me_router", "router"]
