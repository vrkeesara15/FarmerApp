"""WC-013 request / response models (console C100)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from farmerapp.exports import cron
from farmerapp.exports.models import ExportFormat, ExportJob, ReportSchedule
from farmerapp.tenants.settings import Email

CronText = Annotated[str, StringConstraints(min_length=9, max_length=64)]


def _cron(value: str | None) -> str | None:
    if value is None:
        return value
    try:
        return cron.validate(value)
    except cron.CronError as exc:
        raise ValueError(str(exc)) from exc


class ExportIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    resource: Annotated[str, StringConstraints(min_length=1, max_length=32)] = Field(
        description="`farmers`, `orders`, `payments`, `visits`, `flags`, `stock`, "
        "`audit_logs`, `consent_records` (NF-013), `tally`, `tally_xml`, `zoho` (ST-008)."
    )
    filters: dict[str, Any] = Field(
        default_factory=dict, description="The list endpoint's filters as a JSON object."
    )
    format: ExportFormat = ExportFormat.CSV


class ExportOut(BaseModel):
    id: uuid.UUID
    resource: str
    format: str
    filters: dict[str, Any]
    status: str
    rows: int
    size_bytes: int
    filename: str | None
    created_at: datetime
    url: str | None = Field(description="15-minute signed URL (null in listings).")
    url_expires_at: datetime | None

    @classmethod
    def from_row(cls, job: ExportJob, *, url: str | None, expires_at: datetime | None) -> ExportOut:
        return cls(
            id=job.id,
            resource=job.resource,
            format=job.format,
            filters=dict(job.filters or {}),
            status=job.status,
            rows=job.rows,
            size_bytes=job.size_bytes,
            filename=job.filename,
            created_at=job.created_at,
            url=url,
            url_expires_at=expires_at,
        )


class ExportPage(BaseModel):
    items: list[ExportOut]
    next_cursor: str | None = None


class ResourceOut(BaseModel):
    name: str
    formats: list[str]
    columns: list[str]
    filters: list[str]
    description: str


class ResourcesOut(BaseModel):
    items: list[ResourceOut]


class ScheduleIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, StringConstraints(min_length=1, max_length=120)]
    resource: Annotated[str, StringConstraints(min_length=1, max_length=32)]
    filters: dict[str, Any] = Field(default_factory=dict)
    format: ExportFormat = ExportFormat.XLSX
    recipients: list[Email] = Field(min_length=1, max_length=20)
    cron: CronText = Field(
        default=cron.WEEKLY_MONDAY_0800,
        description="minute hour day month weekday, in IST (`0 8 * * 1` = Monday 08:00).",
    )
    active: bool = True

    _cron = field_validator("cron")(_cron)


class SchedulePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, StringConstraints(min_length=1, max_length=120)] | None = None
    resource: Annotated[str, StringConstraints(min_length=1, max_length=32)] | None = None
    filters: dict[str, Any] | None = None
    format: ExportFormat | None = None
    recipients: list[Email] | None = Field(default=None, min_length=1, max_length=20)
    cron: CronText | None = None
    active: bool | None = None

    _cron = field_validator("cron")(_cron)


class ScheduleOut(BaseModel):
    id: uuid.UUID
    name: str
    resource: str
    format: str
    filters: dict[str, Any]
    recipients: list[str]
    cron: str
    timezone: str = "Asia/Kolkata"
    active: bool
    owner_id: uuid.UUID
    next_run_at: datetime | None
    last_run_at: datetime | None
    last_status: str | None
    created_at: datetime

    @classmethod
    def from_row(cls, s: ReportSchedule) -> ScheduleOut:
        return cls(
            id=s.id,
            name=s.name,
            resource=s.resource,
            format=s.format,
            filters=dict(s.filters or {}),
            recipients=list(s.recipients or []),
            cron=s.cron,
            active=s.active,
            owner_id=s.owner_id,
            next_run_at=s.next_run_at,
            last_run_at=s.last_run_at,
            last_status=s.last_status,
            created_at=s.created_at,
        )


class ScheduleList(BaseModel):
    items: list[ScheduleOut]


__all__ = [
    "ExportIn",
    "ExportOut",
    "ExportPage",
    "ResourceOut",
    "ResourcesOut",
    "ScheduleIn",
    "ScheduleList",
    "ScheduleOut",
    "SchedulePatch",
]
