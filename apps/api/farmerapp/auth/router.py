"""``/v1/auth/*`` and ``/v1/me``."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Request, Response, status

from farmerapp.api.errors import problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.errors import UserDisabledError, UserNotFoundError
from farmerapp.auth.models import OtpPurpose, User, UserStatus
from farmerapp.auth.otp import find_user_by_phone
from farmerapp.auth.policy import PUBLIC, Role, require_roles
from farmerapp.auth.providers import mask_phone
from farmerapp.auth.schemas import (
    LogoutRequest,
    OtpSendRequest,
    OtpSendResponse,
    OtpVerifyRequest,
    RefreshRequest,
    TokenResponse,
    UserOut,
)
from farmerapp.db import audit
from farmerapp.db.session import set_tenant

router = APIRouter(prefix="/auth", tags=["auth"])
me_router = APIRouter(tags=["me"])


@router.post(
    "/otp/send",
    operation_id="sendOtp",
    dependencies=[PUBLIC],
    summary="Send a 6-digit login code by SMS (WhatsApp fallback after 30 s)",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=OtpSendResponse,
    responses=problem_responses(
        (404, "user_not_found"),
        (403, "user_disabled"),
        (423, "otp_locked"),
        (429, "otp_rate_limited"),
    ),
)
async def send_otp(body: OtpSendRequest, session: DbSession, services: Services) -> OtpSendResponse:
    result = await services.otp.send(
        session, phone=body.phone, purpose=OtpPurpose(body.purpose), device_id=body.device_id
    )
    settings = services.settings
    return OtpSendResponse(
        challenge_id=result.challenge.id,
        phone_masked=mask_phone(body.phone),
        channel=result.challenge.channel,
        expires_in=settings.otp_ttl_seconds,
        resend_after=settings.otp_resend_after_seconds,
        resends_left=result.resends_left,
    )


@router.post(
    "/otp/verify",
    operation_id="verifyOtp",
    dependencies=[PUBLIC],
    summary="Verify the code; returns access + refresh tokens and the user profile",
    response_model=TokenResponse,
    responses=problem_responses(
        (401, "otp_invalid"),
        (401, "otp_expired"),
        (404, "otp_not_found"),
        (404, "user_not_found"),
        (403, "user_disabled"),
        (423, "otp_locked"),
    ),
)
async def verify_otp(
    request: Request, body: OtpVerifyRequest, session: DbSession, services: Services
) -> TokenResponse:
    challenge = await services.otp.verify(session, phone=body.phone, code=body.code)
    user: User | None = None
    if challenge.user_id is not None:
        await set_tenant(session, challenge.tenant_id)
        user = await session.get(User, challenge.user_id)
        if user is not None and user.deleted_at is not None:
            user = None
    if user is None:
        user = await find_user_by_phone(session, body.phone)
    if user is None:
        raise UserNotFoundError("No account for this number.")
    if user.status != UserStatus.ACTIVE:
        raise UserDisabledError("This account is disabled.")
    # FA-006: from here on the user is the actor (device binding, refresh token, login event).
    audit.bind_actor(audit.actor_from_request(request, user, device_id=body.device_id))
    if body.device_id:
        user.device_id = body.device_id
    issued = await services.tokens.issue_for_login(
        session, user, device_id=body.device_id, device_name=body.device_name
    )
    audit.record(
        session,
        action="auth.login",
        entity="user",
        entity_id=user.id,
        tenant_id=user.tenant_id,
        after={"device_id": body.device_id, "channel": challenge.channel},
    )
    await session.flush()
    return TokenResponse(
        access_token=issued.access_token,
        refresh_token=issued.refresh_token,
        expires_in=issued.expires_in,
        user=UserOut.from_user(user),
    )


@router.post(
    "/refresh",
    operation_id="refreshToken",
    dependencies=[PUBLIC],
    summary="Rotate the refresh token and issue a new access token",
    response_model=TokenResponse,
    responses=problem_responses(
        (401, "refresh_invalid"),
        (401, "refresh_expired"),
        (401, "refresh_reused"),
        (401, "refresh_device_mismatch"),
        (403, "user_disabled"),
    ),
)
async def refresh_token(
    body: RefreshRequest, session: DbSession, services: Services
) -> TokenResponse:
    issued = await services.tokens.rotate(session, body.refresh_token, device_id=body.device_id)
    return TokenResponse(
        access_token=issued.access_token,
        refresh_token=issued.refresh_token,
        expires_in=issued.expires_in,
        user=UserOut.from_user(issued.user),
    )


@router.post(
    "/logout",
    operation_id="logout",
    dependencies=[PUBLIC],
    summary="Revoke the refresh token family (idempotent)",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def logout(
    request: Request, body: LogoutRequest, session: DbSession, services: Services
) -> Response:
    row = await services.tokens.revoke(session, body.refresh_token)
    if row is not None:
        user = await session.get(User, row.user_id)  # tenant bound by the token lookup
        if user is not None:
            audit.bind_actor(audit.actor_from_request(request, user, device_id=row.device_id))
            audit.record(
                session,
                action="auth.logout",
                entity="user",
                entity_id=user.id,
                tenant_id=user.tenant_id,
                after={"family_id": row.family_id, "device_id": row.device_id},
            )
            await session.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@me_router.get(
    "/me",
    operation_id="getMe",
    summary="Profile of the authenticated user",
    response_model=UserOut,
)
async def get_me(user: Annotated[User, require_roles(*Role)]) -> UserOut:
    return UserOut.from_user(user)
