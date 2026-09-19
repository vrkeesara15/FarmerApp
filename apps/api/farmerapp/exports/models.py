"""Exports, scheduled reports and report deliveries (WC-013, AN-015, ST-008, NF-013;
migration 0031_growth).

* ``export_job`` — one generated export: the resource (a list view such as ``farmers`` or
  ``orders``, or an accounting / consent export), the format, the filters as requested, the
  row count and the blob in the exports bucket. ``requested_by`` is the user (NULL for a
  scheduled or system run, then ``schedule_id`` / the job says why). Audited: an export is a
  data egress (SEC-028 / NF-013).
* ``report_schedule`` — a recurring export emailed to a recipient list: resource, filters,
  format, recipients (email addresses), a five-field cron expression evaluated in IST
  (``0 8 * * 1`` = Monday 08:00), the user whose role scope the export runs under
  (``owner_id``), ``next_run_at`` (UTC) and the last outcome.
* ``report_run`` — one delivery of a recurring report (a schedule, the AN-015 weekly owner
  email, the ST-008 daily accounting export): unique ``dedupe_key`` per tenant so a re-run
  of a job for the same period never sends twice. Not audited (derived bookkeeping).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns


class ExportFormat(StrEnum):
    CSV = "csv"
    XLSX = "xlsx"
    XML = "xml"  # ST-008 Tally voucher XML only


class ExportStatus(StrEnum):
    DONE = "done"
    FAILED = "failed"


class ReportKind(StrEnum):
    SCHEDULE = "schedule"  # WC-013 report_schedule delivery
    WEEKLY_OWNER = "weekly_owner"  # AN-015
    ACCOUNTING = "accounting"  # ST-008 daily per store


class RunStatus(StrEnum):
    SENT = "sent"
    FAILED = "failed"
    NO_RECIPIENTS = "no_recipients"


class ExportJob(Base, BaseColumns):
    __tablename__ = "export_job"
    __table_args__ = (
        CheckConstraint(f"format IN ({sql_in(ExportFormat)})", name="format"),
        CheckConstraint(f"status IN ({sql_in(ExportStatus)})", name="status"),
        CheckConstraint("rows >= 0", name="rows"),
        Index("ix_export_job_requested", "tenant_id", "requested_by", "created_at"),
    )

    resource: Mapped[str] = mapped_column(String(32), nullable=False)
    format: Mapped[str] = mapped_column(String(8), nullable=False)
    filters: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    rows: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    blob_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)
    filename: Mapped[str | None] = mapped_column(String(200), nullable=True)
    requested_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    schedule_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    error: Mapped[str | None] = mapped_column(String(200), nullable=True)


class ReportSchedule(Base, BaseColumns):
    __tablename__ = "report_schedule"
    __table_args__ = (
        CheckConstraint(f"format IN ({sql_in(ExportFormat)})", name="format"),
        CheckConstraint("char_length(name) > 0 AND char_length(cron) > 0", name="names"),
        Index("ix_report_schedule_due", "tenant_id", "active", "next_run_at"),
    )

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    resource: Mapped[str] = mapped_column(String(32), nullable=False)
    format: Mapped[str] = mapped_column(String(8), nullable=False)
    filters: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    recipients: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    cron: Mapped[str] = mapped_column(String(64), nullable=False)
    active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    next_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_status: Mapped[str | None] = mapped_column(String(16), nullable=True)


class ReportRun(Base, BaseColumns):
    __tablename__ = "report_run"
    __table_args__ = (
        UniqueConstraint("tenant_id", "dedupe_key"),
        CheckConstraint(f"kind IN ({sql_in(ReportKind)})", name="kind"),
        CheckConstraint(f"status IN ({sql_in(RunStatus)})", name="status"),
        Index("ix_report_run_kind_created", "tenant_id", "kind", "created_at"),
    )
    __audit__ = False  # delivery bookkeeping

    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    dedupe_key: Mapped[str] = mapped_column(String(160), nullable=False)
    period: Mapped[str] = mapped_column(String(32), nullable=False)
    schedule_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    store_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    blob_uris: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    recipients: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error: Mapped[str | None] = mapped_column(String(200), nullable=True)


__all__ = [
    "ExportFormat",
    "ExportJob",
    "ExportStatus",
    "ReportKind",
    "ReportRun",
    "ReportSchedule",
    "RunStatus",
]
