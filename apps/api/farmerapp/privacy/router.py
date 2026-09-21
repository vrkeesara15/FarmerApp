"""Data-principal requests (FM-015 API half; NF-013 groundwork).

* ``POST /v1/me/deletion-request {reason?}`` (any signed-in user; the farmer app's
  "Delete account and data" in settings) -> ``201 {ticket_id, status: "received", due_by}``,
  due in 30 days; tenant admins are notified (``data_request_received``). While one is open
  a repeat returns it (``200``) instead of a second ticket.
* ``GET /v1/me/deletion-request`` -> the caller's latest deletion request (404 if none).
* ``GET /v1/admin/data-requests`` (owner, tenant admin) — every request of the tenant,
  filters ``type`` / ``status``, oldest due first.
* ``PATCH /v1/admin/data-requests/{id} {status, note?}`` (owner, tenant admin) —
  ``received -> in_progress -> completed | rejected`` with ``handled_by`` / ``handled_at``.

The erasure itself stays a reviewed, manual operation (financial records are retained 8
years, NF-012) — the ticket is the auditable commitment and its deadline.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime, timedelta
from typing import Annotated, Any, get_args

from fastapi import APIRouter, Query, Response
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, NotFoundError, problem_responses
from farmerapp.api.pagination import Page, PageOut
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.policy import PUBLIC, Role, require_roles
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.db import audit
from farmerapp.farmers.models import Farmer, LandOwnership
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.privacy.erasure import ErasureReport, erase_principal, retained_classes
from farmerapp.privacy.export import build_export, resolve_farmer
from farmerapp.privacy.models import (
    DATA_REQUEST_TRANSITIONS,
    DUE_DAYS,
    OPEN_STATUSES,
    DataRequest,
    DataRequestStatus,
    DataRequestType,
)
from farmerapp.tenants.settings import Language

log = get_logger("farmerapp.privacy")

ALL_ROLES = tuple(Role)
ADMIN_ROLES = (Role.OWNER, Role.TENANT_ADMIN)

me_router = APIRouter(prefix="/me", tags=["privacy"])
admin_router = APIRouter(prefix="/admin/data-requests", tags=["privacy"])
public_router = APIRouter(prefix="/privacy", tags=["privacy"])

#: NF-013 correction: the fields a data principal may ask to have corrected about themselves.
#: Anything else (role, status, village, ids, money) is not theirs to change through this
#: channel — a correction ticket is not an authorisation to edit the database.
CORRECTABLE_FARMER_FIELDS = frozenset({"name", "phone", "landmark", "language", "land_ownership"})
CORRECTABLE_USER_FIELDS = frozenset({"name", "language"})
CORRECTABLE_FIELDS = CORRECTABLE_FARMER_FIELDS | CORRECTABLE_USER_FIELDS

#: Correctable fields whose column is a closed set. Checked when the *request* is made, so a
#: value that would trip a CHECK constraint is a 422 to the principal rather than a 500 to the
#: admin who applies it.
CORRECTABLE_VALUES: dict[str, frozenset[str]] = {
    "language": frozenset(get_args(Language)),
    "land_ownership": frozenset(v.value for v in LandOwnership),
}
#: FA-001 / FA-012 use the same shape: +91 and ten digits starting 6-9.
PHONE_RE = re.compile(r"^\+91[6-9]\d{9}$")


class InvalidDataRequestTransitionError(AppError):
    status = 409
    code = "invalid_transition"


class DeletionRequestIn(BaseModel):
    reason: str | None = Field(default=None, max_length=2000)


class DeletionRequestOut(BaseModel):
    ticket_id: uuid.UUID
    type: DataRequestType
    status: DataRequestStatus
    due_by: datetime
    created_at: datetime

    @classmethod
    def from_row(cls, row: DataRequest) -> DeletionRequestOut:
        return cls(
            ticket_id=row.id,
            type=DataRequestType(row.type),
            status=DataRequestStatus(row.status),
            due_by=row.due_by,
            created_at=row.created_at,
        )


class DataRequestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    type: DataRequestType
    status: DataRequestStatus
    user_id: uuid.UUID
    farmer_id: uuid.UUID | None
    reason: str | None
    subject: str | None = None
    message: str | None = None
    requested_changes: dict[str, str] | None = None
    erasure_report: dict[str, Any] | None = None
    due_by: datetime
    overdue: bool = False
    handled_by: uuid.UUID | None
    handled_at: datetime | None
    resolution_note: str | None
    created_at: datetime
    updated_at: datetime
    version: int


class CorrectionRequestIn(BaseModel):
    """NF-013: ``{field: new value}``, restricted to the principal's own fields (SEC-022)."""

    model_config = ConfigDict(extra="forbid")

    changes: dict[str, str] = Field(min_length=1, max_length=len(CORRECTABLE_FIELDS))
    reason: str | None = Field(default=None, max_length=2000)

    @field_validator("changes")
    @classmethod
    def _allowed(cls, changes: dict[str, str]) -> dict[str, str]:
        unknown = sorted(set(changes) - CORRECTABLE_FIELDS)
        if unknown:
            raise ValueError(
                f"{', '.join(unknown)} cannot be corrected here "
                f"(allowed: {', '.join(sorted(CORRECTABLE_FIELDS))})"
            )
        cleaned: dict[str, str] = {}
        for name, raw in changes.items():
            value = raw.strip()
            if not value or len(value) > 200:
                raise ValueError(f"{name} must be 1-200 characters")
            # The value is applied verbatim to a column with a CHECK constraint or a format,
            # so the closed sets are validated here rather than failing at flush time.
            allowed = CORRECTABLE_VALUES.get(name)
            if allowed is not None and value not in allowed:
                raise ValueError(f"{name} must be one of {', '.join(sorted(allowed))}")
            if name == "phone" and not PHONE_RE.match(value):
                raise ValueError("phone must be an Indian mobile number (+91 and 10 digits)")
            cleaned[name] = value
        return cleaned


class GrievanceIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subject: str = Field(min_length=3, max_length=200)
    message: str = Field(min_length=3, max_length=4000)


class GrievanceContactOut(BaseModel):
    """NF-013: who to complain to, shown in the apps and the console."""

    officer_name: str
    email: str
    phone: str
    response_days: int
    rights: list[str]


class CorrectionAppliedOut(BaseModel):
    applied: dict[str, str]
    request: DataRequestOut


class ErasureOut(BaseModel):
    erased: list[str]
    retained: list[dict[str, Any]]
    already_erased: bool
    request: DataRequestOut


class DataRequestPage(PageOut[DataRequestOut]):
    pass


class DataRequestUpdate(BaseModel):
    status: DataRequestStatus
    note: str | None = Field(default=None, max_length=2000)


async def _notify_admins(session: AsyncSession, row: DataRequest) -> int:
    admins = (
        await session.execute(
            select(User.id).where(
                User.tenant_id == row.tenant_id,
                User.role == UserRole.TENANT_ADMIN.value,
                User.status == UserStatus.ACTIVE.value,
                User.deleted_at.is_(None),
            )
        )
    ).scalars()
    count = 0
    for admin_id in admins:
        session.add(
            Notification(
                tenant_id=row.tenant_id,
                user_id=admin_id,
                kind=NotificationKind.DATA_REQUEST_RECEIVED.value,
                title_key=f"notification.{NotificationKind.DATA_REQUEST_RECEIVED.value}.title",
                body_key=f"notification.{NotificationKind.DATA_REQUEST_RECEIVED.value}.body",
                data={
                    "data_request_id": str(row.id),
                    "type": row.type,
                    "due_by": row.due_by.isoformat(),
                },
            )
        )
        count += 1
    return count


async def _latest(
    session: AsyncSession,
    actor: User,
    kind: DataRequestType = DataRequestType.DELETION,
) -> DataRequest | None:
    return (
        await session.execute(
            select(DataRequest)
            .where(
                DataRequest.tenant_id == actor.tenant_id,
                DataRequest.user_id == actor.id,
                DataRequest.type == kind.value,
                DataRequest.deleted_at.is_(None),
            )
            .order_by(DataRequest.created_at.desc(), DataRequest.id.desc())
            .limit(1)
        )
    ).scalar_one_or_none()


async def _own_farmer_id(session: AsyncSession, actor: User) -> uuid.UUID | None:
    if UserRole(actor.role) != UserRole.FARMER:
        return None
    found: uuid.UUID | None = await session.scalar(
        select(Farmer.id).where(Farmer.tenant_id == actor.tenant_id, Farmer.user_id == actor.id)
    )
    return found


async def _open_ticket(
    session: AsyncSession,
    actor: User,
    services: Services,
    *,
    kind: DataRequestType,
    reason: str | None = None,
    subject: str | None = None,
    message: str | None = None,
    requested_changes: dict[str, str] | None = None,
) -> DataRequest:
    """Create a data-principal ticket of any type, notify the admins, return the row."""
    now = services.clock.now()
    row = DataRequest(
        tenant_id=actor.tenant_id,
        type=kind.value,
        user_id=actor.id,
        farmer_id=await _own_farmer_id(session, actor),
        reason=reason,
        subject=subject,
        message=message,
        requested_changes=requested_changes,
        status=DataRequestStatus.RECEIVED.value,
        due_by=now + timedelta(days=DUE_DAYS),
    )
    session.add(row)
    await session.flush()
    notified = await _notify_admins(session, row)
    await session.flush()
    await session.refresh(row)
    log.info(
        "data_request_received",
        tenant_id=str(actor.tenant_id),
        data_request_id=str(row.id),
        type=row.type,
        role=str(actor.role),
        notified=notified,
    )
    return row


@me_router.post(
    "/deletion-request",
    operation_id="requestAccountDeletion",
    summary="FM-015: ask to delete my account and data (a ticket due in 30 days)",
    status_code=201,
    response_model=DeletionRequestOut,
)
async def request_deletion(
    body: DeletionRequestIn,
    response: Response,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> DeletionRequestOut:
    latest = await _latest(session, actor)
    if latest is not None and DataRequestStatus(latest.status) in OPEN_STATUSES:
        response.status_code = 200
        return DeletionRequestOut.from_row(latest)
    now = services.clock.now()
    farmer_id = None
    if UserRole(actor.role) == UserRole.FARMER:
        farmer_id = await session.scalar(
            select(Farmer.id).where(Farmer.tenant_id == actor.tenant_id, Farmer.user_id == actor.id)
        )
    row = DataRequest(
        tenant_id=actor.tenant_id,
        type=DataRequestType.DELETION.value,
        user_id=actor.id,
        farmer_id=farmer_id,
        reason=body.reason,
        status=DataRequestStatus.RECEIVED.value,
        due_by=now + timedelta(days=DUE_DAYS),
    )
    session.add(row)
    await session.flush()
    notified = await _notify_admins(session, row)
    await session.flush()
    await session.refresh(row)
    log.info(
        "data_request_received",
        tenant_id=str(actor.tenant_id),
        data_request_id=str(row.id),
        type=row.type,
        role=str(actor.role),
        notified=notified,
    )
    return DeletionRequestOut.from_row(row)


@me_router.get(
    "/deletion-request",
    operation_id="getAccountDeletionRequest",
    summary="FM-015: my latest deletion request",
    response_model=DeletionRequestOut,
    responses=problem_responses((404, "not_found")),
)
async def get_deletion_request(
    actor: Annotated[User, require_roles(*ALL_ROLES)], session: DbSession
) -> DeletionRequestOut:
    latest = await _latest(session, actor)
    if latest is None:
        raise NotFoundError("No deletion request.")
    return DeletionRequestOut.from_row(latest)


def _out(row: DataRequest, now: datetime) -> DataRequestOut:
    out = DataRequestOut.model_validate(row)
    out.overdue = DataRequestStatus(row.status) in OPEN_STATUSES and row.due_by < now
    return out


@admin_router.get(
    "",
    operation_id="listDataRequests",
    summary="NF-013 / FM-015: data-principal requests of the tenant, oldest due first",
    response_model=DataRequestPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_data_requests(
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    session: DbSession,
    services: Services,
    page: Page,
    type: Annotated[DataRequestType | None, Query()] = None,
    status: Annotated[list[DataRequestStatus] | None, Query()] = None,
) -> DataRequestPage:
    stmt = select(DataRequest).where(
        DataRequest.tenant_id == actor.tenant_id, DataRequest.deleted_at.is_(None)
    )
    if type is not None:
        stmt = stmt.where(DataRequest.type == type.value)
    if status:
        stmt = stmt.where(DataRequest.status.in_([s.value for s in status]))
    keyset = page.after(DataRequest.created_at, DataRequest.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(DataRequest.created_at, DataRequest.id).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    now = services.clock.now()
    return DataRequestPage(items=[_out(r, now) for r in items], next_cursor=cursor)


@admin_router.patch(
    "/{id}",
    operation_id="updateDataRequest",
    summary="Move a data request: received -> in_progress -> completed / rejected",
    response_model=DataRequestOut,
    responses=problem_responses((404, "not_found"), (409, "invalid_transition")),
)
async def update_data_request(
    id: uuid.UUID,
    body: DataRequestUpdate,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    session: DbSession,
    services: Services,
) -> DataRequestOut:
    row = (
        await session.execute(
            select(DataRequest)
            .where(
                DataRequest.id == id,
                DataRequest.tenant_id == actor.tenant_id,
                DataRequest.deleted_at.is_(None),
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Data request not found.")
    current = DataRequestStatus(row.status)
    if body.status not in DATA_REQUEST_TRANSITIONS[current]:
        raise InvalidDataRequestTransitionError(
            f"Cannot move a {current.value} request to {body.status.value}."
        )
    now = services.clock.now()
    row.status = body.status.value
    row.handled_by = actor.id
    if body.status in (DataRequestStatus.COMPLETED, DataRequestStatus.REJECTED):
        row.handled_at = now
    if body.note is not None:
        row.resolution_note = body.note
    await session.flush()
    await session.refresh(row)
    return _out(row, now)


# --------------------------------------------------------------------------- NF-013 rights
@public_router.get(
    "/contact",
    operation_id="getGrievanceContact",
    dependencies=[PUBLIC],
    summary="NF-013: the grievance-redressal contact and the rights a data principal has",
    response_model=GrievanceContactOut,
)
async def grievance_contact(services: Services) -> GrievanceContactOut:
    settings = services.settings
    return GrievanceContactOut(
        officer_name=settings.grievance_officer_name,
        email=settings.grievance_officer_email,
        phone=settings.grievance_officer_phone,
        response_days=settings.grievance_response_days,
        rights=["access", "correction", "erasure", "grievance"],
    )


@me_router.get(
    "/data-export",
    operation_id="exportMyData",
    summary="NF-013 right of access: everything this company holds about me, as JSON",
    response_model=dict,
)
async def export_my_data(
    actor: Annotated[User, require_roles(*ALL_ROLES)], session: DbSession, services: Services
) -> dict[str, Any]:
    farmer = await resolve_farmer(session, actor)
    document = await build_export(session, user=actor, farmer=farmer, now=services.clock.now())
    audit.record(
        session,
        action="privacy.access_export",
        entity="user",
        entity_id=actor.id,
        after={"sections": len(document.get("counts", {}))},
    )
    await session.flush()
    return document


@me_router.get(
    "/data-requests",
    operation_id="listMyDataRequests",
    summary="NF-013: my own access / correction / erasure / grievance tickets",
    response_model=list[DeletionRequestOut],
)
async def list_my_data_requests(
    actor: Annotated[User, require_roles(*ALL_ROLES)], session: DbSession
) -> list[DeletionRequestOut]:
    rows = (
        (
            await session.execute(
                select(DataRequest)
                .where(
                    DataRequest.tenant_id == actor.tenant_id,
                    DataRequest.user_id == actor.id,
                    DataRequest.deleted_at.is_(None),
                )
                .order_by(DataRequest.created_at.desc(), DataRequest.id.desc())
                .limit(100)
            )
        )
        .scalars()
        .all()
    )
    return [DeletionRequestOut.from_row(row) for row in rows]


@me_router.post(
    "/correction-request",
    operation_id="requestCorrection",
    summary="NF-013 right to correction: ask for my own details to be corrected",
    status_code=201,
    response_model=DeletionRequestOut,
)
async def request_correction(
    body: CorrectionRequestIn,
    response: Response,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> DeletionRequestOut:
    latest = await _latest(session, actor, DataRequestType.CORRECTION)
    if latest is not None and DataRequestStatus(latest.status) in OPEN_STATUSES:
        response.status_code = 200
        return DeletionRequestOut.from_row(latest)
    row = await _open_ticket(
        session,
        actor,
        services,
        kind=DataRequestType.CORRECTION,
        reason=body.reason,
        requested_changes=body.changes,
    )
    return DeletionRequestOut.from_row(row)


@me_router.post(
    "/grievance",
    operation_id="raiseGrievance",
    summary="NF-013 grievance redressal: raise a complaint about how my data is handled",
    status_code=201,
    response_model=DeletionRequestOut,
)
async def raise_grievance(
    body: GrievanceIn,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> DeletionRequestOut:
    row = await _open_ticket(
        session,
        actor,
        services,
        kind=DataRequestType.GRIEVANCE,
        subject=body.subject,
        message=body.message,
    )
    return DeletionRequestOut.from_row(row)


async def _load_for_admin(session: AsyncSession, actor: User, id: uuid.UUID) -> DataRequest:
    row = (
        await session.execute(
            select(DataRequest)
            .where(
                DataRequest.id == id,
                DataRequest.tenant_id == actor.tenant_id,
                DataRequest.deleted_at.is_(None),
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Data request not found.")
    return row


async def _principal(session: AsyncSession, row: DataRequest) -> tuple[User, Farmer | None]:
    user = await session.get(User, row.user_id)
    if user is None:
        raise NotFoundError("The data principal's account no longer exists.")
    farmer = None
    if row.farmer_id is not None:
        farmer = await session.get(Farmer, row.farmer_id)
    if farmer is None:
        farmer = await resolve_farmer(session, user)
    return user, farmer


@admin_router.get(
    "/{id}/export",
    operation_id="exportDataRequestSubject",
    summary="NF-013: the access-right document for the principal of this ticket",
    response_model=dict,
    responses=problem_responses((404, "not_found")),
)
async def export_data_request_subject(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    session: DbSession,
    services: Services,
) -> dict[str, Any]:
    row = await _load_for_admin(session, actor, id)
    user, farmer = await _principal(session, row)
    document = await build_export(session, user=user, farmer=farmer, now=services.clock.now())
    audit.record(
        session,
        action="privacy.access_export",
        entity="data_request",
        entity_id=row.id,
        after={"subject_user_id": str(user.id), "by": str(actor.id)},
    )
    await session.flush()
    return document


@admin_router.post(
    "/{id}/apply-correction",
    operation_id="applyDataRequestCorrection",
    summary="NF-013: apply a correction request to the principal's record (step-up; audited)",
    response_model=CorrectionAppliedOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        (404, "not_found"), (409, "invalid_transition"), (401, "step_up_required")
    ),
)
async def apply_correction(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> CorrectionAppliedOut:
    row = await _load_for_admin(session, actor, id)
    if DataRequestType(row.type) != DataRequestType.CORRECTION:
        raise InvalidDataRequestTransitionError("This ticket is not a correction request.")
    if DataRequestStatus(row.status) not in OPEN_STATUSES:
        raise InvalidDataRequestTransitionError("This request is already closed.")
    user, farmer = await _principal(session, row)
    changes = dict(row.requested_changes or {})
    applied: dict[str, str] = {}
    for field, value in changes.items():
        if farmer is not None and field in CORRECTABLE_FARMER_FIELDS:
            setattr(farmer, field, value)
            applied[field] = value
        elif field in CORRECTABLE_USER_FIELDS:
            setattr(user, field, value)
            applied[field] = value
    now = services.clock.now()
    row.status = DataRequestStatus.COMPLETED.value
    row.handled_by = actor.id
    row.handled_at = now
    row.resolution_note = f"Applied: {', '.join(sorted(applied)) or 'nothing applicable'}"
    # FA-006 already audits the farmer / user diffs; this line records *why* they changed.
    audit.record(
        session,
        action="privacy.correction_applied",
        entity="data_request",
        entity_id=row.id,
        after={"applied": sorted(applied), "subject_user_id": str(user.id)},
    )
    await session.flush()
    await session.refresh(row)
    log.info(
        "data_request_correction_applied",
        tenant_id=str(actor.tenant_id),
        data_request_id=str(row.id),
        fields=sorted(applied),
    )
    return CorrectionAppliedOut(applied=applied, request=_out(row, now))


@admin_router.post(
    "/{id}/erase",
    operation_id="eraseDataRequestSubject",
    summary="NF-013: anonymise the principal, keeping what NF-012 requires (step-up; audited)",
    response_model=ErasureOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        (404, "not_found"), (409, "invalid_transition"), (401, "step_up_required")
    ),
)
async def erase_data_request_subject(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> ErasureOut:
    row = await _load_for_admin(session, actor, id)
    if DataRequestType(row.type) != DataRequestType.DELETION:
        raise InvalidDataRequestTransitionError("This ticket is not a deletion request.")
    if DataRequestStatus(row.status) not in OPEN_STATUSES:
        raise InvalidDataRequestTransitionError("This request is already closed.")
    user, farmer = await _principal(session, row)
    now = services.clock.now()
    report: ErasureReport = await erase_principal(session, user=user, farmer=farmer, now=now)
    row.status = DataRequestStatus.COMPLETED.value
    row.handled_by = actor.id
    row.handled_at = now
    row.erasure_report = report.as_json()
    row.resolution_note = (
        "Anonymised. Kept: " + ", ".join(r.record_class for r in report.retained) + "."
    )
    await session.flush()
    await session.refresh(row)
    return ErasureOut(
        erased=report.erased,
        retained=[r.__dict__ for r in report.retained],
        already_erased=report.already_erased,
        request=_out(row, now),
    )


@admin_router.get(
    "/retention-exceptions",
    operation_id="listRetentionExceptions",
    summary="NF-012 / NF-013: what an erasure must keep, and for how long",
    response_model=list[dict[str, Any]],
)
async def list_retention_exceptions(
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
) -> list[dict[str, Any]]:
    _ = actor
    return [r.__dict__ for r in retained_classes()]


__all__ = ["admin_router", "me_router", "public_router"]
