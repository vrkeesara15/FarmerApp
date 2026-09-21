"""``/v1/farmers``, ``/v1/farms``, ``/v1/crop-plots`` — directory, farmer 360 and the
FA-012 / FA-013 write endpoints.

Row scope follows SPEC 2.6 through ``farmerapp.auth.scope.farmer_filters``: owner / director
/ auditor / tenant_admin see the tenant, a cluster head their cluster (village -> store ->
cluster), a store manager their store (village -> store), a field officer the farmers they
registered, an agronomist crop data (phone masked, landmark hidden), a farmer their own
record. Writes go through ``farmerapp.farmers.service`` (shared with ``POST /v1/sync``) and
every POST honours ``Idempotency-Key`` (``farmerapp.api.idempotency``).
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Request, Response, status
from sqlalchemy import select

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.providers import mask_phone
from farmerapp.auth.scope import farmer_filters
from farmerapp.farmers import service
from farmerapp.farmers.models import Farmer
from farmerapp.farmers.officer import officer_out
from farmerapp.farmers.phone_verify import PURPOSE, issue_token
from farmerapp.farmers.schemas import (
    ConsentCreate,
    ConsentRecordOut,
    CropPlotCreate,
    CropPlotOut,
    CropPlotUpdate,
    FarmCreate,
    FarmerCreate,
    FarmerDetailOut,
    FarmerOut,
    FarmerPage,
    FarmerUpdate,
    FarmOut,
    FarmUpdate,
    PhoneVerificationTokenOut,
    PhoneVerifyCodeRequest,
    PhoneVerifyConfirmRequest,
    PhoneVerifySendRequest,
    PhoneVerifySendResponse,
)
from farmerapp.uploads.router import get_blob_store

router = APIRouter(prefix="/farmers", tags=["farmers"])
farm_router = APIRouter(prefix="/farms", tags=["farmers"])
plot_router = APIRouter(prefix="/crop-plots", tags=["farmers"])

LIST_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.AGRONOMIST,
)
READ_ROLES = (*LIST_ROLES, Role.FARMER)
#: FA-012 registration and edits (SPEC 2.6 "Farmer profile": create / update).
WRITE_ROLES = (Role.FIELD_OFFICER, Role.STORE_MANAGER, Role.CLUSTER_HEAD, Role.TENANT_ADMIN)
#: Edits of an existing record: the staff above plus the farmer on their own record.
EDIT_ROLES = (*WRITE_ROLES, Role.FARMER)

#: Roles that read crop data, not the person (SPEC 2.6 "Read (crop data)").
PII_REDACTED_ROLES = frozenset({UserRole.AGRONOMIST})

_OTP_PROBLEMS = ((423, "otp_locked"), (429, "otp_rate_limited"))
_VERIFY_PROBLEMS = (
    (401, "otp_invalid"),
    (401, "otp_expired"),
    (404, "otp_not_found"),
    (423, "otp_locked"),
)
_WRITE_PROBLEMS = (
    (404, "not_found"),
    (409, "farmer_phone_exists"),
    (409, "plan_limit_exceeded"),  # WC-014
    (409, "version_conflict"),
    (422, "farm_boundary_invalid"),
    (422, "farmer_phone_is_staff"),
    (422, "phone_verification_invalid"),
    (422, "idempotency_key_reuse"),
)


def _redact(actor: User) -> bool:
    return UserRole(actor.role) in PII_REDACTED_ROLES


# --------------------------------------------------------------------------- reads
@router.get(
    "",
    operation_id="listFarmers",
    summary="Farmers visible to the caller (tenant, cluster, store or own), oldest first",
    response_model=FarmerPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_farmers(
    actor: Annotated[User, require_roles(*LIST_ROLES)],
    session: DbSession,
    page: Page,
    village_id: Annotated[uuid.UUID | None, Query()] = None,
    registered_by: Annotated[uuid.UUID | None, Query(description="Officer user id.")] = None,
) -> FarmerPage:
    stmt = select(Farmer).where(Farmer.deleted_at.is_(None), *farmer_filters(actor))
    if village_id is not None:
        stmt = stmt.where(Farmer.village_id == village_id)
    if registered_by is not None:
        stmt = stmt.where(Farmer.registered_by == registered_by)
    after = page.after(Farmer.created_at, Farmer.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Farmer.created_at, Farmer.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    redact = _redact(actor)
    return FarmerPage(
        items=[FarmerOut.from_row(f, redact_pii=redact) for f in items], next_cursor=next_cursor
    )


# --------------------------------------------------------------------------- phone verification
@router.post(
    "/phone/verify/send",
    operation_id="sendFarmerPhoneOtp",
    summary="Send an OTP to a farmer's phone before registration (VA-F01)",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=PhoneVerifySendResponse,
    responses=problem_responses(*_OTP_PROBLEMS),
)
async def send_phone_otp(
    body: PhoneVerifySendRequest,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> PhoneVerifySendResponse:
    return await _send_otp(session, services, actor, body.phone)


async def _send_otp(
    session: DbSession, services: Services, actor: User, phone: str
) -> PhoneVerifySendResponse:
    result = await services.otp.send(
        session, phone=phone, purpose=PURPOSE, tenant_id=actor.tenant_id, device_id=actor.device_id
    )
    settings = services.settings
    return PhoneVerifySendResponse(
        challenge_id=result.challenge.id,
        phone_masked=mask_phone(phone),
        channel=result.challenge.channel,
        expires_in=settings.otp_ttl_seconds,
        resend_after=settings.otp_resend_after_seconds,
        resends_left=result.resends_left,
    )


@router.post(
    "/phone/verify/confirm",
    operation_id="confirmFarmerPhoneOtp",
    summary="Confirm the farmer's OTP; returns a 30-minute phone_verification_token",
    response_model=PhoneVerificationTokenOut,
    responses=problem_responses(*_VERIFY_PROBLEMS),
)
async def confirm_phone_otp(
    body: PhoneVerifyConfirmRequest,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> PhoneVerificationTokenOut:
    await services.otp.verify(
        session, phone=body.phone, code=body.code, purpose=PURPOSE, tenant_id=actor.tenant_id
    )
    token = issue_token(
        services.settings, tenant_id=actor.tenant_id, phone=body.phone, now=services.clock.now()
    )
    return PhoneVerificationTokenOut(
        phone_verification_token=token,
        expires_in=services.settings.phone_verification_ttl_seconds,
    )


@router.post(
    "/{id}/phone/verify/send",
    operation_id="sendFarmerRecordPhoneOtp",
    summary="Send an OTP to verify the phone of an already registered farmer",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=PhoneVerifySendResponse,
    responses=problem_responses((404, "not_found"), *_OTP_PROBLEMS),
)
async def send_record_phone_otp(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
    services: Services,
) -> PhoneVerifySendResponse:
    farmer = await service.visible_farmer(session, actor, id)
    return await _send_otp(session, services, actor, farmer.phone)


@router.post(
    "/{id}/phone/verify/confirm",
    operation_id="confirmFarmerRecordPhoneOtp",
    summary="Confirm the OTP and mark the farmer's phone as verified",
    response_model=FarmerOut,
    responses=problem_responses((404, "not_found"), *_VERIFY_PROBLEMS),
)
async def confirm_record_phone_otp(
    id: uuid.UUID,
    body: PhoneVerifyCodeRequest,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
    services: Services,
) -> FarmerOut:
    farmer = await service.visible_farmer(session, actor, id)
    await services.otp.verify(
        session, phone=farmer.phone, code=body.code, purpose=PURPOSE, tenant_id=actor.tenant_id
    )
    return await service.mark_phone_verified(session, farmer)


# --------------------------------------------------------------------------- farmer writes
@router.post(
    "",
    operation_id="createFarmer",
    summary="Register a farmer with farms, crop plots and consent (FA-012, FA-013)",
    status_code=status.HTTP_201_CREATED,
    response_model=FarmerDetailOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_farmer(
    request: Request,
    body: FarmerCreate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> FarmerDetailOut:
    return await service.create_farmer(
        session,
        actor,
        body,
        settings=services.settings,
        now=services.clock.now(),
        blobs=get_blob_store(request),
    )


@router.get(
    "/{id}",
    operation_id="getFarmer",
    summary="One farmer with farms, crop plots and consent history",
    response_model=FarmerDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_farmer(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
) -> FarmerDetailOut:
    farmer = await service.visible_farmer(session, actor, id)
    detail = await service.farmer_detail(session, farmer, redact_pii=_redact(actor))
    detail.officer = await officer_out(session, farmer, actor)
    return detail


@router.patch(
    "/{id}",
    operation_id="updateFarmer",
    summary="Change name, village, landmark, language or land ownership",
    response_model=FarmerOut,
    responses=problem_responses((404, "not_found"), (409, "version_conflict")),
)
async def update_farmer(
    id: uuid.UUID,
    body: FarmerUpdate,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> FarmerOut:
    farmer = await service.visible_farmer(session, actor, id)
    return await service.update_farmer(session, actor, farmer, body)


@router.post(
    "/{id}/farms",
    operation_id="createFarm",
    summary="Add a farm (with crop plots and photos) to a farmer",
    status_code=status.HTTP_201_CREATED,
    response_model=FarmOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_farm(
    request: Request,
    id: uuid.UUID,
    body: FarmCreate,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> FarmOut:
    farmer = await service.visible_farmer(session, actor, id)
    return await service.add_farm(session, actor, farmer, body, blobs=get_blob_store(request))


@router.post(
    "/{id}/consents",
    operation_id="createConsent",
    summary="Append a consent grant or withdrawal (FM-002)",
    status_code=status.HTTP_201_CREATED,
    response_model=ConsentRecordOut,
    responses=problem_responses((404, "not_found"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_consent(
    request: Request,
    id: uuid.UUID,
    body: ConsentCreate,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> ConsentRecordOut:
    farmer = await service.visible_farmer(session, actor, id)
    return await service.add_consent(session, actor, farmer, body)


# --------------------------------------------------------------------------- farms
@farm_router.patch(
    "/{id}",
    operation_id="updateFarm",
    summary="Change a farm (boundary re-checked, photos replaced when given)",
    response_model=FarmOut,
    responses=problem_responses(
        (404, "not_found"), (409, "version_conflict"), (422, "farm_boundary_invalid")
    ),
)
async def update_farm(
    request: Request,
    id: uuid.UUID,
    body: FarmUpdate,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> FarmOut:
    farm = await service.visible_farm(session, actor, id)
    return await service.update_farm(session, actor, farm, body, blobs=get_blob_store(request))


@farm_router.delete(
    "/{id}",
    operation_id="deleteFarm",
    summary="Soft-delete a farm and its crop plots",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=problem_responses((404, "not_found")),
)
async def delete_farm(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> Response:
    farm = await service.visible_farm(session, actor, id)
    await service.delete_farm(session, farm)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@farm_router.post(
    "/{id}/crop-plots",
    operation_id="createCropPlot",
    summary="Add a crop plot to a farm (FA-013)",
    status_code=status.HTTP_201_CREATED,
    response_model=CropPlotOut,
    responses=problem_responses((404, "not_found"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_crop_plot(
    request: Request,
    id: uuid.UUID,
    body: CropPlotCreate,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> CropPlotOut:
    farm = await service.visible_farm(session, actor, id)
    return await service.add_crop_plot(session, farm, body)


# --------------------------------------------------------------------------- crop plots
@plot_router.patch(
    "/{id}",
    operation_id="updateCropPlot",
    summary="Change a crop plot",
    response_model=CropPlotOut,
    responses=problem_responses((404, "not_found"), (409, "version_conflict")),
)
async def update_crop_plot(
    id: uuid.UUID,
    body: CropPlotUpdate,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> CropPlotOut:
    plot = await service.visible_crop_plot(session, actor, id)
    return await service.update_crop_plot(session, plot, body)


@plot_router.delete(
    "/{id}",
    operation_id="deleteCropPlot",
    summary="Soft-delete a crop plot",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=problem_responses((404, "not_found")),
)
async def delete_crop_plot(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*EDIT_ROLES)],
    session: DbSession,
) -> Response:
    plot = await service.visible_crop_plot(session, actor, id)
    await service.delete_crop_plot(session, plot)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


__all__ = [
    "EDIT_ROLES",
    "LIST_ROLES",
    "READ_ROLES",
    "WRITE_ROLES",
    "farm_router",
    "plot_router",
    "router",
]
