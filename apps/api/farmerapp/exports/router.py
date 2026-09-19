"""``/v1/exports`` and ``/v1/report-schedules`` — WC-013 (console C100), NF-013, ST-008.

* ``POST /v1/exports {resource, filters, format}`` generates the file synchronously (at most
  100,000 rows), stores it in the exports bucket and answers with a 15-minute signed URL.
  **Step-up required** (SEC-028) and audited (``export.create``). The route admits every
  staff role that may export something; the resource's own roles (the list endpoint's) are
  checked inside (403 ``forbidden``), and the rows are the caller's list scope.
* ``GET /v1/exports`` lists the caller's recent exports; ``GET /v1/exports/{id}`` returns a
  fresh signed URL for one of them.
* ``/v1/report-schedules``: recurring exports emailed by the ``run-report-schedules`` job,
  cron in IST (``0 8 * * 1`` = Monday 08:00). Creating or changing a schedule is an export
  decision: step-up required. Admin roles see every schedule of the tenant, others their own.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Request, status
from sqlalchemy import select

from farmerapp.api.errors import ForbiddenError, NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import require_roles
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.exports import service
from farmerapp.exports.models import ExportFormat, ExportJob, ReportSchedule
from farmerapp.exports.resources import EXPORT_ROLES, RESOURCES, TENANT_ADMINS
from farmerapp.exports.schemas import (
    ExportIn,
    ExportOut,
    ExportPage,
    ResourceOut,
    ResourcesOut,
    ScheduleIn,
    ScheduleList,
    ScheduleOut,
    SchedulePatch,
)
from farmerapp.uploads.blobstore import BlobStore

router = APIRouter(prefix="/exports", tags=["exports"])
schedules_router = APIRouter(prefix="/report-schedules", tags=["exports"])

SCHEDULE_ROLES = tuple(
    r
    for r in EXPORT_ROLES
    if r not in (UserRole.FIELD_OFFICER, UserRole.AGRONOMIST, UserRole.FARMER)
)
_EXPORT_PROBLEMS = (
    (401, "step_up_required"),
    (404, "not_found"),
    (422, "export_resource_unknown"),
    (422, "export_filters_invalid"),
    (422, "export_format_unsupported"),
)


def get_exports_store(request: Request) -> BlobStore:
    store: BlobStore = request.app.state.exports
    return store


async def _out(
    job: ExportJob, store: BlobStore, services: Services, *, signed: bool = True
) -> ExportOut:
    url = expires = None
    if signed and job.blob_uri:
        link = await store.signed_url(
            job.blob_uri,
            ttl=timedelta(seconds=services.settings.signed_url_ttl_seconds),
            now=services.clock.now(),
        )
        url, expires = link.url, link.expires_at
    return ExportOut.from_row(job, url=url, expires_at=expires)


@router.get(
    "/resources",
    operation_id="listExportResources",
    summary="Resources the caller may export, with their columns and formats",
    response_model=ResourcesOut,
)
async def list_resources(
    actor: Annotated[User, require_roles(*EXPORT_ROLES)],
) -> ResourcesOut:
    role = UserRole(actor.role)
    return ResourcesOut(
        items=[
            ResourceOut(
                name=r.name,
                formats=sorted(r.formats),
                columns=list(r.columns),
                filters=sorted(r.filters.model_json_schema(by_alias=True).get("properties", {})),
                description=r.description,
            )
            for r in RESOURCES.values()
            if role in r.roles
        ]
    )


@router.post(
    "",
    operation_id="createExport",
    summary="Export a list view as CSV / XLSX (step-up; audited); returns a signed URL",
    status_code=status.HTTP_201_CREATED,
    response_model=ExportOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(*_EXPORT_PROBLEMS),
)
async def create_export(
    body: ExportIn,
    request: Request,
    actor: Annotated[User, require_roles(*EXPORT_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> ExportOut:
    store = get_exports_store(request)
    job, _ = await service.generate(
        session,
        actor,
        resource_name=body.resource,
        fmt=body.format,
        raw_filters=body.filters,
        store=store,
        now=services.clock.now(),
    )
    return await _out(job, store, services)


@router.get(
    "",
    operation_id="listExports",
    summary="The caller's exports, newest first (no URLs; fetch one for a fresh link)",
    response_model=ExportPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_exports(
    actor: Annotated[User, require_roles(*EXPORT_ROLES)],
    session: DbSession,
    page: Page,
) -> ExportPage:
    stmt = select(ExportJob).where(
        ExportJob.tenant_id == actor.tenant_id,
        ExportJob.requested_by == actor.id,
        ExportJob.deleted_at.is_(None),
    )
    keyset = page.before(ExportJob.created_at, ExportJob.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(ExportJob.created_at.desc(), ExportJob.id.desc()).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    return ExportPage(
        items=[ExportOut.from_row(j, url=None, expires_at=None) for j in items],
        next_cursor=cursor,
    )


@router.get(
    "/{id}",
    operation_id="getExport",
    summary="One of the caller's exports with a fresh 15-minute signed URL",
    response_model=ExportOut,
    responses=problem_responses((404, "not_found")),
)
async def get_export(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*EXPORT_ROLES)],
    session: DbSession,
    services: Services,
) -> ExportOut:
    job = (
        await session.execute(
            select(ExportJob).where(
                ExportJob.id == id,
                ExportJob.tenant_id == actor.tenant_id,
                ExportJob.requested_by == actor.id,
                ExportJob.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if job is None:
        raise NotFoundError("Export not found.")
    return await _out(job, get_exports_store(request), services)


# --------------------------------------------------------------------------- schedules
def _is_admin(actor: User) -> bool:
    return UserRole(actor.role) in TENANT_ADMINS


async def _schedule(session: DbSession, actor: User, schedule_id: uuid.UUID) -> ReportSchedule:
    stmt = select(ReportSchedule).where(
        ReportSchedule.id == schedule_id,
        ReportSchedule.tenant_id == actor.tenant_id,
        ReportSchedule.deleted_at.is_(None),
    )
    if not _is_admin(actor):
        stmt = stmt.where(ReportSchedule.owner_id == actor.id)
    row = (await session.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Report schedule not found.")
    return row


@schedules_router.get(
    "",
    operation_id="listReportSchedules",
    summary="Scheduled reports (admins: the tenant's; others: their own)",
    response_model=ScheduleList,
)
async def list_schedules(
    actor: Annotated[User, require_roles(*SCHEDULE_ROLES)], session: DbSession
) -> ScheduleList:
    stmt = select(ReportSchedule).where(
        ReportSchedule.tenant_id == actor.tenant_id, ReportSchedule.deleted_at.is_(None)
    )
    if not _is_admin(actor):
        stmt = stmt.where(ReportSchedule.owner_id == actor.id)
    rows = (await session.execute(stmt.order_by(ReportSchedule.created_at))).scalars()
    return ScheduleList(items=[ScheduleOut.from_row(r) for r in rows])


@schedules_router.post(
    "",
    operation_id="createReportSchedule",
    summary="Schedule a recurring export emailed to recipients (cron in IST; step-up)",
    status_code=status.HTTP_201_CREATED,
    response_model=ScheduleOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(*_EXPORT_PROBLEMS, (422, "cron_invalid")),
)
async def create_schedule(
    body: ScheduleIn,
    actor: Annotated[User, require_roles(*SCHEDULE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> ScheduleOut:
    _, filters = service.check_request(actor, body.resource, body.format, body.filters)
    expr = " ".join(body.cron.split())
    row = ReportSchedule(
        tenant_id=actor.tenant_id,
        name=body.name,
        resource=body.resource,
        format=body.format.value,
        filters=filters.model_dump(mode="json", by_alias=True, exclude_none=True),
        recipients=list(body.recipients),
        cron=expr,
        active=body.active,
        owner_id=actor.id,
        next_run_at=service.next_run(expr, services.clock.now()),
    )
    session.add(row)
    await session.flush()
    return ScheduleOut.from_row(row)


@schedules_router.patch(
    "/{id}",
    operation_id="updateReportSchedule",
    summary="Change a scheduled report (step-up)",
    response_model=ScheduleOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(*_EXPORT_PROBLEMS, (422, "cron_invalid")),
)
async def update_schedule(
    id: uuid.UUID,
    body: SchedulePatch,
    actor: Annotated[User, require_roles(*SCHEDULE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> ScheduleOut:
    row = await _schedule(session, actor, id)
    changes = body.model_dump(exclude_unset=True)
    owner = await session.get(User, row.owner_id)
    if owner is None:  # pragma: no cover - FK
        raise NotFoundError("Report schedule not found.")
    resource = changes.get("resource", row.resource)
    fmt = ExportFormat(changes.get("format", row.format))
    raw_filters = changes.get("filters", row.filters)
    if owner.id != actor.id and "resource" in changes:
        raise ForbiddenError("Only the owner of a schedule may change what it exports.")
    _, filters = service.check_request(owner, resource, fmt, raw_filters)
    row.resource = resource
    row.format = fmt.value
    row.filters = filters.model_dump(mode="json", by_alias=True, exclude_none=True)
    for key in ("name", "active"):
        if key in changes:
            setattr(row, key, changes[key])
    if "recipients" in changes:
        row.recipients = list(changes["recipients"])
    if "cron" in changes:
        row.cron = " ".join(str(changes["cron"]).split())
    if "cron" in changes or "active" in changes:
        row.next_run_at = service.next_run(row.cron, services.clock.now())
    await session.flush()
    return ScheduleOut.from_row(row)


@schedules_router.delete(
    "/{id}",
    operation_id="deleteReportSchedule",
    summary="Stop and remove a scheduled report",
    status_code=status.HTTP_204_NO_CONTENT,
    responses=problem_responses((404, "not_found")),
)
async def delete_schedule(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*SCHEDULE_ROLES)],
    session: DbSession,
    services: Services,
) -> None:
    row = await _schedule(session, actor, id)
    row.active = False
    row.deleted_at = services.clock.now()
    await session.flush()


__all__ = ["SCHEDULE_ROLES", "get_exports_store", "router", "schedules_router"]
