"""``/v1/visits`` — reads (M2-KICKOFF) and the FA-014 .. FA-017 write endpoints, the REST
twins of the ``POST /v1/sync`` ops (``farmerapp.visits.sync_ops``).

Row scope is ``farmerapp.auth.scope.visit_filters``: owner / director / tenant_admin /
auditor see the tenant, a cluster head the visits of the officers in their cluster, a store
manager those of their store's officers, a field officer their own, a farmer the visits made
to them. Agronomists and accountants have no visit access (SPEC 2.6). Writes are the
visiting officer's own (``own_visit``: 404 otherwise); the farmer-side confirmation is the
farmer's own visits; override decisions belong to the cluster head of the officer's cluster
(scope) and the tenant's owner / director / tenant admin.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Query, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import visit_filters
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.uploads.router import get_blob_store
from farmerapp.visits import service
from farmerapp.visits.errors import ConfirmationChannelInvalidError
from farmerapp.visits.models import ConfirmationChannel, Visit, VisitStatus
from farmerapp.visits.schemas import (
    ConfirmationRequest,
    ConfirmationRequestOut,
    ConfirmationSubmit,
    FarmerConfirm,
    OverrideDecisionIn,
    OverrideRequestOut,
    VisitCapture,
    VisitCheckIn,
    VisitCheckOut,
    VisitConfirmationOut,
    VisitDetailOut,
    VisitOut,
    VisitPage,
    VisitPhotoCreate,
    VisitPhotoOut,
)

router = APIRouter(prefix="/visits", tags=["visits"])

READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.FARMER,
)
#: Staff who make visits (the ``/v1/sync`` roles minus the farmer).
VISIT_ROLES = (Role.FIELD_OFFICER, Role.CLUSTER_HEAD, Role.STORE_MANAGER)
#: FA-014: who decides an override (cluster head of the officer's cluster; owners above).
APPROVER_ROLES = (Role.CLUSTER_HEAD, Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)

_OTP_PROBLEMS = ((423, "otp_locked"), (429, "otp_rate_limited"))
_VERIFY_PROBLEMS = (
    (401, "otp_invalid"),
    (401, "otp_expired"),
    (404, "otp_not_found"),
    (423, "otp_locked"),
)

visible_visit = service.visible_visit


async def visit_detail(
    session: AsyncSession,
    visit: Visit,
    *,
    blobs: BlobStore | None = None,
    now: datetime | None = None,
    signed_url_ttl_s: int = 900,
) -> VisitDetailOut:
    """The detail read model; with ``blobs`` every photo carries a signed read URL."""
    photos = []
    for photo in await service.photos_of(session, visit):
        url = expires = None
        if blobs is not None and now is not None:
            signed = await blobs.signed_url(
                photo.blob_uri, ttl=timedelta(seconds=signed_url_ttl_s), now=now
            )
            url, expires = signed.url, signed.expires_at
        photos.append(VisitPhotoOut.from_row(photo, signed_url=url, signed_url_expires_at=expires))
    confirmations = await service.confirmations_of(session, visit)
    override = await service.override_request_of(session, visit)
    return VisitDetailOut.from_rows(visit, photos, confirmations, override)


async def _detail(
    request: Request, services: Services, session: AsyncSession, visit: Visit
) -> VisitDetailOut:
    return await visit_detail(
        session,
        visit,
        blobs=get_blob_store(request),
        now=services.clock.now(),
        signed_url_ttl_s=services.settings.signed_url_ttl_seconds,
    )


# --------------------------------------------------------------------------- reads
@router.get(
    "",
    operation_id="listVisits",
    summary="Visits visible to the caller (tenant, cluster, store, own or to self), oldest first",
    response_model=VisitPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_visits(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    officer_id: Annotated[uuid.UUID | None, Query(description="Officer user id.")] = None,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
    from_: Annotated[
        datetime | None, Query(alias="from", description="Check-in at or after (RFC 3339).")
    ] = None,
    to: Annotated[datetime | None, Query(description="Check-in before (RFC 3339).")] = None,
    status: Annotated[VisitStatus | None, Query()] = None,
) -> VisitPage:
    stmt = select(Visit).where(Visit.deleted_at.is_(None), *visit_filters(actor))
    if officer_id is not None:
        stmt = stmt.where(Visit.officer_id == officer_id)
    if farmer_id is not None:
        stmt = stmt.where(Visit.farmer_id == farmer_id)
    if from_ is not None:
        stmt = stmt.where(Visit.checkin_at >= from_)
    if to is not None:
        stmt = stmt.where(Visit.checkin_at < to)
    if status is not None:
        stmt = stmt.where(Visit.status == status.value)
    after = page.after(Visit.created_at, Visit.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Visit.created_at, Visit.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return VisitPage(items=[VisitOut.from_row(v) for v in items], next_cursor=next_cursor)


# --------------------------------------------------------------------------- FA-014 check-in
@router.post(
    "/check-in",
    operation_id="checkInVisit",
    summary="Check in at a farm or a village meeting point (FA-014 geofence, FA-028 integrity)",
    status_code=status.HTTP_201_CREATED,
    response_model=VisitDetailOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "conflict"),
        (422, "outside_geofence"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def check_in(
    request: Request,
    body: VisitCheckIn,
    actor: Annotated[User, require_roles(*VISIT_ROLES)],
    session: DbSession,
    services: Services,
) -> VisitDetailOut:
    visit = await service.check_in(session, actor, body, now=services.clock.now())
    return await _detail(request, services, session, visit)


@router.get(
    "/{id}",
    operation_id="getVisit",
    summary="One visit with photos (signed URLs), confirmations, override request and score "
    "components",
    response_model=VisitDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_visit(
    request: Request,
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    services: Services,
) -> VisitDetailOut:
    visit = await service.visible_visit(session, actor, id)
    return await _detail(request, services, session, visit)


# --------------------------------------------------------------------------- FA-015 capture
@router.patch(
    "/{id}",
    operation_id="captureVisit",
    summary="Notes, crop stage and purpose of an open or closed visit (FA-015)",
    response_model=VisitDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def capture_visit(
    request: Request,
    id: uuid.UUID,
    body: VisitCapture,
    actor: Annotated[User, require_roles(*VISIT_ROLES)],
    session: DbSession,
    services: Services,
) -> VisitDetailOut:
    visit = await service.own_visit(session, actor, id)
    await service.capture(session, visit, body)
    return await _detail(request, services, session, visit)


@router.post(
    "/{id}/photos",
    operation_id="addVisitPhoto",
    summary="Attach an in-app photo from a completed upload (FA-015; EXIF and server time kept)",
    status_code=status.HTTP_201_CREATED,
    response_model=VisitPhotoOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "conflict"),
        (422, "gallery_not_allowed"),
        (422, "photo_sha_mismatch"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def add_visit_photo(
    request: Request,
    id: uuid.UUID,
    body: VisitPhotoCreate,
    actor: Annotated[User, require_roles(*VISIT_ROLES)],
    session: DbSession,
    services: Services,
) -> VisitPhotoOut:
    visit = await service.own_visit(session, actor, id)
    photo = await service.add_photo(
        session, actor, visit, body, blobs=get_blob_store(request), now=services.clock.now()
    )
    signed = await get_blob_store(request).signed_url(
        photo.blob_uri,
        ttl=timedelta(seconds=services.settings.signed_url_ttl_seconds),
        now=services.clock.now(),
    )
    return VisitPhotoOut.from_row(
        photo, signed_url=signed.url, signed_url_expires_at=signed.expires_at
    )


# --------------------------------------------------------------------------- FA-016 confirmation
@router.post(
    "/{id}/confirm/request",
    operation_id="requestVisitConfirmation",
    summary="Ask the farmer to confirm: SMS OTP, push prompt in the farmer app, or a QR token",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=ConfirmationRequestOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "visit_already_confirmed"),
        (422, "confirmation_channel_invalid"),
        *_OTP_PROBLEMS,
    ),
)
async def request_confirmation(
    id: uuid.UUID,
    body: ConfirmationRequest,
    actor: Annotated[User, require_roles(*VISIT_ROLES)],
    session: DbSession,
    services: Services,
) -> ConfirmationRequestOut:
    visit = await service.own_visit(session, actor, id)
    started = await service.request_confirmation(
        session, actor, visit, body.channel, services=services
    )
    return ConfirmationRequestOut(
        confirmation=VisitConfirmationOut.from_row(started.row),
        channel=body.channel,
        phone_masked=started.phone_masked,
        expires_in=started.expires_in,
        resend_after=started.resend_after,
        resends_left=started.resends_left,
        token=started.token,
    )


@router.post(
    "/{id}/confirm",
    operation_id="confirmVisit",
    summary="Officer-side completion: the SMS OTP the farmer read out (FA-016)",
    response_model=VisitDetailOut,
    responses=problem_responses(
        (404, "not_found"),
        (404, "confirmation_not_requested"),
        (409, "visit_already_confirmed"),
        (422, "confirmation_channel_invalid"),
        *_VERIFY_PROBLEMS,
    ),
)
async def confirm_visit(
    request: Request,
    id: uuid.UUID,
    body: ConfirmationSubmit,
    actor: Annotated[User, require_roles(*VISIT_ROLES)],
    session: DbSession,
    services: Services,
) -> VisitDetailOut:
    visit = await service.own_visit(session, actor, id)
    if body.channel != ConfirmationChannel.SMS_OTP.value:
        raise ConfirmationChannelInvalidError(
            "Push and QR confirmations are completed by the farmer's app "
            "(POST /v1/visits/{id}/farmer-confirm)."
        )
    if not body.code:
        raise ConfirmationChannelInvalidError("An SMS confirmation needs the code.")
    await service.confirm_with_otp(session, actor, visit, body.code, services=services)
    return await _detail(request, services, session, visit)


@router.post(
    "/{id}/farmer-confirm",
    operation_id="farmerConfirmVisit",
    summary="Farmer-side completion of a push or QR confirmation, with the FM-011 rating",
    response_model=VisitConfirmationOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "visit_already_confirmed"),
        (422, "confirmation_token_invalid"),
    ),
)
async def farmer_confirm_visit(
    id: uuid.UUID,
    body: FarmerConfirm,
    actor: Annotated[User, require_roles(Role.FARMER)],
    session: DbSession,
    services: Services,
) -> VisitConfirmationOut:
    visit = await service.visible_visit(session, actor, id)  # farmer scope: own visits
    row = await service.farmer_confirm(
        session, actor, visit, body, settings=services.settings, now=services.clock.now()
    )
    return VisitConfirmationOut.from_row(row)


# --------------------------------------------------------------------------- FA-017 check-out
@router.post(
    "/{id}/check-out",
    operation_id="checkOutVisit",
    summary="Check out: duration, VV-004 score and VV-005 status (short visits flagged)",
    response_model=VisitDetailOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "visit_already_checked_out"),
        (422, "checkout_before_checkin"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=status.HTTP_200_OK)
async def check_out_visit(
    request: Request,
    id: uuid.UUID,
    body: VisitCheckOut,
    actor: Annotated[User, require_roles(*VISIT_ROLES)],
    session: DbSession,
    services: Services,
) -> VisitDetailOut:
    visit = await service.own_visit(session, actor, id)
    await service.check_out(session, visit, body, now=services.clock.now())
    return await _detail(request, services, session, visit)


# --------------------------------------------------------------------------- FA-014 override
@router.post(
    "/{id}/override/approve",
    operation_id="approveVisitOverride",
    summary="Approve the pending geofence override (cluster head of the officer's cluster)",
    response_model=OverrideRequestOut,
    responses=problem_responses((404, "not_found"), (409, "override_not_pending")),
)
async def approve_override(
    id: uuid.UUID,
    body: OverrideDecisionIn,
    actor: Annotated[User, require_roles(*APPROVER_ROLES)],
    session: DbSession,
    services: Services,
) -> OverrideRequestOut:
    visit = await service.visible_visit(session, actor, id)
    request_row = await service.decide_override(
        session, actor, visit, approve=True, note=body.note, now=services.clock.now()
    )
    return OverrideRequestOut.from_row(request_row)


@router.post(
    "/{id}/override/reject",
    operation_id="rejectVisitOverride",
    summary="Reject the pending geofence override (the visit keeps no geofence credit)",
    response_model=OverrideRequestOut,
    responses=problem_responses((404, "not_found"), (409, "override_not_pending")),
)
async def reject_override(
    id: uuid.UUID,
    body: OverrideDecisionIn,
    actor: Annotated[User, require_roles(*APPROVER_ROLES)],
    session: DbSession,
    services: Services,
) -> OverrideRequestOut:
    visit = await service.visible_visit(session, actor, id)
    request_row = await service.decide_override(
        session, actor, visit, approve=False, note=body.note, now=services.clock.now()
    )
    return OverrideRequestOut.from_row(request_row)


__all__ = [
    "APPROVER_ROLES",
    "READ_ROLES",
    "VISIT_ROLES",
    "router",
    "visible_visit",
    "visit_detail",
]
