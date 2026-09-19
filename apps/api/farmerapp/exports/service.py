"""WC-013 export generation and scheduled report delivery.

``generate(...)`` streams a resource's scoped rows into a CSV / XLSX (or the resource's own
document format), stores it in the **exports bucket** through a ``BlobStore``
(``gs://<exports bucket>/<tenant>/exports/<resource>/<job id>.<ext>``), writes an
``export_job`` row and an ``export.create`` audit record (resource, format, filters, rows;
SEC-028 / NF-013) and returns the job; the router answers with a 15-minute signed URL.

``run_due_schedules(...)`` (job ``run-report-schedules``, every 15 minutes) runs every active
``report_schedule`` whose ``next_run_at`` has passed, **as its owner** (the export has exactly
the owner's role scope), emails the file to the recipients through the ``EmailSender`` and
moves ``next_run_at`` to the next cron fire (IST). A ``report_run`` per schedule and fire time
makes a re-run of the job a no-op.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import IO, Any

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ForbiddenError
from farmerapp.auth.models import User, UserStatus
from farmerapp.db import audit
from farmerapp.exports import cron
from farmerapp.exports.email import Attachment, Email, EmailError, EmailSender
from farmerapp.exports.models import (
    ExportFormat,
    ExportJob,
    ExportStatus,
    ReportKind,
    ReportRun,
    ReportSchedule,
    RunStatus,
)
from farmerapp.exports.resources import RESOURCES, Resource, allowed
from farmerapp.exports.writers import CSV_MEDIA_TYPE, XLSX_MEDIA_TYPE, CsvWriter, XlsxWriter
from farmerapp.logging import get_logger
from farmerapp.settings import Settings
from farmerapp.uploads.blobstore import (
    BlobStore,
    FakeGcsBlobStore,
    GcsBlobStore,
    IamBlobSigner,
    LocalBlobStore,
)

log = get_logger("farmerapp.exports")

MEDIA_TYPES = {
    ExportFormat.CSV: CSV_MEDIA_TYPE,
    ExportFormat.XLSX: XLSX_MEDIA_TYPE,
    ExportFormat.XML: "application/xml",
}


class UnknownResourceError(AppError):
    status = 422
    code = "export_resource_unknown"


class InvalidExportFiltersError(AppError):
    status = 422
    code = "export_filters_invalid"


class UnsupportedFormatError(AppError):
    status = 422
    code = "export_format_unsupported"


class InvalidCronError(AppError):
    status = 422
    code = "cron_invalid"


def build_exports_store(settings: Settings) -> BlobStore:
    """The exports bucket (``EXPORTS_BUCKET``) behind the same adapters as the photo store."""
    if settings.blob_store == "local":
        return LocalBlobStore(settings.blob_local_dir)
    if settings.blob_store == "gcs":  # pragma: no cover - needs Google credentials
        from farmerapp.gcp import GoogleAccessToken

        token = GoogleAccessToken()
        signer = IamBlobSigner(
            token,
            service_account=settings.gcs_signing_service_account,
            email_provider=token.service_account_email,
        )
        return GcsBlobStore(bucket=settings.exports_bucket, token=token, signer=signer)
    if not settings.storage_emulator_host:  # pragma: no cover - configuration
        raise ValueError("BLOB_STORE=fake_gcs needs STORAGE_EMULATOR_HOST")
    return FakeGcsBlobStore(settings.storage_emulator_host, bucket=settings.exports_bucket)


def resource_for(name: str) -> Resource:
    resource = RESOURCES.get(name)
    if resource is None:
        raise UnknownResourceError(
            f"Unknown export resource {name!r}.", extra={"resources": sorted(RESOURCES)}
        )
    return resource


def check_request(
    actor: User, resource_name: str, fmt: ExportFormat, raw_filters: dict[str, Any]
) -> tuple[Resource, Any]:
    """Resource known, role allowed (403 otherwise), format supported, filters valid."""
    resource = resource_for(resource_name)
    if not allowed(resource, actor):
        raise ForbiddenError("Your role cannot export this resource.")
    if fmt.value not in resource.formats:
        raise UnsupportedFormatError(
            f"{resource.name} exports as {', '.join(sorted(resource.formats))}.",
            extra={"formats": sorted(resource.formats)},
        )
    try:
        filters = resource.filters.model_validate(raw_filters or {})
    except ValidationError as exc:
        raise InvalidExportFiltersError(
            "The filters are not valid for this resource.",
            extra={"errors": [{"loc": list(e["loc"]), "msg": e["msg"]} for e in exc.errors()]},
        ) from exc
    return resource, filters


async def render(
    session: AsyncSession,
    actor: User,
    resource: Resource,
    filters: Any,
    fmt: ExportFormat,
    now: datetime,
) -> tuple[bytes, int]:
    if fmt.value in resource.render:
        return await resource.render[fmt.value](session, actor, filters, now)
    writer: CsvWriter | XlsxWriter = (
        XlsxWriter(resource.columns, sheet=resource.name)
        if fmt == ExportFormat.XLSX
        else CsvWriter(resource.columns)
    )
    async for row in resource.rows(session, actor, filters, now):
        writer.add(row)
    out: IO[bytes]
    out, count = writer.finish()
    with out:
        return out.read(), count


def filename_for(resource: Resource, fmt: ExportFormat, filters: Any, now: datetime) -> str:
    day = getattr(filters, "day", None) or now.astimezone(cron.IST).date()
    return f"{resource.name}-{day.isoformat()}.{fmt.value}"


async def generate(
    session: AsyncSession,
    actor: User,
    *,
    resource_name: str,
    fmt: ExportFormat,
    raw_filters: dict[str, Any],
    store: BlobStore,
    now: datetime,
    schedule_id: uuid.UUID | None = None,
    requested: bool = True,
) -> tuple[ExportJob, bytes]:
    resource, filters = check_request(actor, resource_name, fmt, raw_filters)
    data, rows = await render(session, actor, resource, filters, fmt, now)
    job = ExportJob(
        id=uuid.uuid4(),
        tenant_id=actor.tenant_id,
        resource=resource.name,
        format=fmt.value,
        filters=filters.model_dump(mode="json", by_alias=True, exclude_none=True),
        status=ExportStatus.DONE.value,
        rows=rows,
        size_bytes=len(data),
        filename=filename_for(resource, fmt, filters, now),
        requested_by=actor.id if requested else None,
        schedule_id=schedule_id,
    )
    key = f"{actor.tenant_id}/exports/{resource.name}/{job.id}.{fmt.value}"
    job.blob_uri = await store.put(key, data, content_type=MEDIA_TYPES[fmt])
    session.add(job)
    audit.record(
        session,
        action="export.create",
        entity="export_job",
        entity_id=job.id,
        tenant_id=actor.tenant_id,
        after={
            "resource": resource.name,
            "format": fmt.value,
            "filters": job.filters,
            "rows": rows,
            "schedule_id": str(schedule_id) if schedule_id else None,
        },
    )
    await session.flush()
    log.info(
        "export_created",
        tenant_id=str(actor.tenant_id),
        resource=resource.name,
        format=fmt.value,
        rows=rows,
        size_bytes=len(data),
    )
    return job, data


# --------------------------------------------------------------------------- report runs
async def claim_run(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    kind: ReportKind,
    dedupe_key: str,
    period: str,
    schedule_id: uuid.UUID | None = None,
    store_id: uuid.UUID | None = None,
) -> ReportRun | None:
    """Insert the run row first (unique per dedupe key); ``None`` when already delivered."""
    existing = await session.scalar(
        select(ReportRun.id).where(
            ReportRun.tenant_id == tenant_id, ReportRun.dedupe_key == dedupe_key
        )
    )
    if existing is not None:
        return None
    run = ReportRun(
        tenant_id=tenant_id,
        kind=kind.value,
        dedupe_key=dedupe_key,
        period=period,
        schedule_id=schedule_id,
        store_id=store_id,
        status=RunStatus.SENT.value,
        blob_uris=[],
        recipients=0,
    )
    try:
        async with session.begin_nested():
            session.add(run)
            await session.flush()
    except IntegrityError:  # pragma: no cover - a concurrent run claimed it
        return None
    return run


async def deliver(
    email: EmailSender, run: ReportRun, recipients: list[str], message: Email
) -> None:
    run.recipients = len(recipients)
    if not recipients:
        run.status = RunStatus.NO_RECIPIENTS.value
        return
    try:
        await email.send(message)
    except EmailError as exc:
        run.status = RunStatus.FAILED.value
        run.error = str(exc)[:200]
        log.warning("report_email_failed", kind=run.kind, period=run.period, error=run.error)
        return
    run.status = RunStatus.SENT.value


# --------------------------------------------------------------------------- schedules
def next_run(expr: str, after: datetime) -> datetime:
    try:
        return cron.next_fire(expr, after)
    except cron.CronError as exc:
        raise InvalidCronError(str(exc)) from exc


@dataclass
class ScheduleReport:
    tenant_id: uuid.UUID
    ran: list[uuid.UUID] = field(default_factory=list)
    failed: list[uuid.UUID] = field(default_factory=list)
    skipped: int = 0


async def run_due_schedules(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime,
    store: BlobStore,
    email: EmailSender,
) -> ScheduleReport:
    report = ScheduleReport(tenant_id=tenant_id)
    due = (
        (
            await session.execute(
                select(ReportSchedule)
                .where(
                    ReportSchedule.tenant_id == tenant_id,
                    ReportSchedule.deleted_at.is_(None),
                    ReportSchedule.active.is_(True),
                    ReportSchedule.next_run_at <= now,
                )
                .order_by(ReportSchedule.next_run_at, ReportSchedule.id)
                .with_for_update(skip_locked=True)
            )
        )
        .scalars()
        .all()
    )
    for schedule in due:
        fire = schedule.next_run_at or now
        schedule.next_run_at = next_run(schedule.cron, max(now, fire))
        schedule.last_run_at = now
        run = await claim_run(
            session,
            tenant_id=tenant_id,
            kind=ReportKind.SCHEDULE,
            dedupe_key=f"schedule:{schedule.id}:{fire.isoformat()}",
            period=fire.astimezone(cron.IST).strftime("%Y-%m-%d %H:%M"),
            schedule_id=schedule.id,
        )
        if run is None:
            report.skipped += 1
            continue
        owner = await session.get(User, schedule.owner_id)
        if owner is None or owner.status != UserStatus.ACTIVE or owner.deleted_at is not None:
            run.status = RunStatus.FAILED.value
            run.error = "schedule owner is no longer active"
            schedule.last_status = run.status
            report.failed.append(schedule.id)
            continue
        try:
            with audit.actor_scope(audit.system_actor(tenant_id)):
                job, data = await generate(
                    session,
                    owner,
                    resource_name=schedule.resource,
                    fmt=ExportFormat(schedule.format),
                    raw_filters=dict(schedule.filters or {}),
                    store=store,
                    now=now,
                    schedule_id=schedule.id,
                    requested=False,
                )
        except AppError as exc:
            run.status = RunStatus.FAILED.value
            run.error = f"{exc.code}: {exc.detail}"[:200]
            schedule.last_status = run.status
            report.failed.append(schedule.id)
            continue
        run.blob_uris = [job.blob_uri] if job.blob_uri else []
        await deliver(
            email,
            run,
            list(schedule.recipients or []),
            Email(
                to=tuple(schedule.recipients or []),
                subject=f"{schedule.name} — {run.period} IST",
                text=(
                    f"Scheduled report '{schedule.name}' ({schedule.resource}, {job.rows} rows) "
                    "is attached."
                ),
                attachments=(
                    Attachment(
                        job.filename or "report", data, MEDIA_TYPES[ExportFormat(job.format)]
                    ),
                ),
            ),
        )
        schedule.last_status = run.status
        (report.ran if run.status == RunStatus.SENT.value else report.failed).append(schedule.id)
    await session.flush()
    log.info(
        "report_schedules",
        tenant_id=str(tenant_id),
        ran=len(report.ran),
        failed=len(report.failed),
        skipped=report.skipped,
    )
    return report


__all__ = [
    "MEDIA_TYPES",
    "InvalidCronError",
    "InvalidExportFiltersError",
    "ScheduleReport",
    "UnknownResourceError",
    "UnsupportedFormatError",
    "build_exports_store",
    "check_request",
    "claim_run",
    "deliver",
    "generate",
    "next_run",
    "render",
    "resource_for",
    "run_due_schedules",
]
