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

import uuid
from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Query, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, NotFoundError, problem_responses
from farmerapp.api.pagination import Page, PageOut
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.policy import Role, require_roles
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.privacy.models import (
    DATA_REQUEST_TRANSITIONS,
    DUE_DAYS,
    OPEN_STATUSES,
    DataRequest,
    DataRequestStatus,
    DataRequestType,
)

log = get_logger("farmerapp.privacy")

ALL_ROLES = tuple(Role)
ADMIN_ROLES = (Role.OWNER, Role.TENANT_ADMIN)

me_router = APIRouter(prefix="/me", tags=["privacy"])
admin_router = APIRouter(prefix="/admin/data-requests", tags=["privacy"])


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
    due_by: datetime
    overdue: bool = False
    handled_by: uuid.UUID | None
    handled_at: datetime | None
    resolution_note: str | None
    created_at: datetime
    updated_at: datetime
    version: int


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


async def _latest(session: AsyncSession, actor: User) -> DataRequest | None:
    return (
        await session.execute(
            select(DataRequest)
            .where(
                DataRequest.tenant_id == actor.tenant_id,
                DataRequest.user_id == actor.id,
                DataRequest.type == DataRequestType.DELETION.value,
                DataRequest.deleted_at.is_(None),
            )
            .order_by(DataRequest.created_at.desc(), DataRequest.id.desc())
            .limit(1)
        )
    ).scalar_one_or_none()


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


__all__ = ["admin_router", "me_router"]
