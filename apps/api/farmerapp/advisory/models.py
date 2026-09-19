"""Farmer advisory data model (M7 farmer P1; Alembic ``0032_farmer_p1``).

* ``crop_task_template`` — FM-007: the agronomist-maintained calendar of a crop (optionally
  per season): one row per task with a stable ``task_key``, its type (sow, irrigate,
  fertilise, spray, harvest), the day offset from sowing and duration, the crop stage, the
  localized titles and short instructions (``{"en": ..., "te": ...}``) and an optional
  product category the app can link to (never a SKU: DX-007 recommendations stay with the
  diagnosis engine). Templates of a crop with ``season`` NULL apply to every season; a
  season-specific template with the same ``task_key`` wins.
* ``crop_plot_task`` — FM-007: the calendar generated for one crop plot from its sowing date
  (``due_date = sowing_date + day_offset``). Titles and instructions are copied from the
  template so the task is self-contained offline (sync entity ``crop_plot_task``).
  ``basis_sowing_date`` / ``basis_crop_id`` / ``basis_hash`` record what the task was
  generated from: a change of the sowing date, the crop or the crop's templates regenerates
  the pending tasks (done tasks are kept). ``reminder_enabled`` is the farmer's switch;
  ``reminded_at`` is set once the reminder notification was written.
* ``outbreak_alert`` — DX-013 / FM-009: one row per district x crop x problem x ISO week in
  which the outbreak rule fired (count vs trailing mean, tenant settings ``outbreak``), with
  the numbers that made it fire and whom it notified.

Enumerations are CHECK constraints on short strings (expand-only when a value is added).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import ProductCategory, sql_in
from farmerapp.db.base import Base, BaseColumns
from farmerapp.farmers.models import CropStage, Season


class TaskType(StrEnum):
    SOW = "sow"
    IRRIGATE = "irrigate"
    FERTILISE = "fertilise"
    SPRAY = "spray"
    HARVEST = "harvest"


class TaskStatus(StrEnum):
    PENDING = "pending"
    DONE = "done"


class OutbreakStatus(StrEnum):
    ACTIVE = "active"
    CLOSED = "closed"


class CropTaskTemplate(Base, BaseColumns):
    __tablename__ = "crop_task_template"
    __table_args__ = (
        CheckConstraint(f"task_type IN ({sql_in(TaskType)})", name="task_type"),
        CheckConstraint(f"season IS NULL OR season IN ({sql_in(Season)})", name="season"),
        CheckConstraint(f"stage IS NULL OR stage IN ({sql_in(CropStage)})", name="stage"),
        CheckConstraint(
            f"product_category IS NULL OR product_category IN ({sql_in(ProductCategory)})",
            name="product_category",
        ),
        CheckConstraint("day_offset BETWEEN -60 AND 400", name="day_offset"),
        CheckConstraint("duration_days BETWEEN 1 AND 60", name="duration_days"),
        CheckConstraint("task_key ~ '^[a-z0-9_.-]{2,64}$'", name="task_key"),
        Index(
            "uq_crop_task_template_key",
            "tenant_id",
            "crop_id",
            text("coalesce(season, '')"),
            "task_key",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_crop_task_template_crop", "tenant_id", "crop_id"),
    )

    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    season: Mapped[str | None] = mapped_column(String(8), nullable=True)
    task_key: Mapped[str] = mapped_column(String(64), nullable=False)
    task_type: Mapped[str] = mapped_column(String(16), nullable=False)
    day_offset: Mapped[int] = mapped_column(Integer, nullable=False)
    duration_days: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="1", default=1
    )
    stage: Mapped[str | None] = mapped_column(String(16), nullable=True)
    #: {"en": "Basal fertiliser", "te": "...", "hi": ...} — the app falls back to "en"
    titles: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    instructions: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    product_category: Mapped[str | None] = mapped_column(String(16), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true"), default=True
    )
    source: Mapped[str | None] = mapped_column(String(200), nullable=True)
    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )


class CropPlotTask(Base, BaseColumns):
    __tablename__ = "crop_plot_task"
    __table_args__ = (
        CheckConstraint(f"task_type IN ({sql_in(TaskType)})", name="task_type"),
        CheckConstraint(f"status IN ({sql_in(TaskStatus)})", name="status"),
        CheckConstraint("status <> 'done' OR done_at IS NOT NULL", name="done_at"),
        CheckConstraint("end_date >= due_date", name="dates"),
        Index(
            "uq_crop_plot_task_key",
            "crop_plot_id",
            "task_key",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_crop_plot_task_farmer_due", "tenant_id", "farmer_id", "due_date"),
        Index(
            "ix_crop_plot_task_reminder_due",
            "tenant_id",
            "due_date",
            postgresql_where=text(
                "deleted_at IS NULL AND status = 'pending' AND reminder_enabled "
                "AND reminded_at IS NULL"
            ),
        ),
        Index("ix_crop_plot_task_crop_plot_id", "crop_plot_id"),
    )

    crop_plot_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop_plot.id", ondelete="CASCADE"), nullable=False
    )
    #: denormalised for the farmer's calendar, the sync scope and reminders
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=False
    )
    template_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("crop_task_template.id", ondelete="SET NULL"), nullable=True
    )
    task_key: Mapped[str] = mapped_column(String(64), nullable=False)
    task_type: Mapped[str] = mapped_column(String(16), nullable=False)
    stage: Mapped[str | None] = mapped_column(String(16), nullable=True)
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    titles: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    instructions: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    product_category: Mapped[str | None] = mapped_column(String(16), nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    status: Mapped[str] = mapped_column(
        String(8), nullable=False, server_default=text("'pending'"), default=TaskStatus.PENDING
    )
    done_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    done_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    reminder_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true"), default=True
    )
    reminded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    basis_sowing_date: Mapped[date] = mapped_column(Date, nullable=False)
    basis_crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    #: sha256 (16 hex) of the crop's active templates when generated
    basis_hash: Mapped[str] = mapped_column(String(16), nullable=False)


class OutbreakAlert(Base, BaseColumns):
    __tablename__ = "outbreak_alert"
    __table_args__ = (
        CheckConstraint(f"status IN ({sql_in(OutbreakStatus)})", name="status"),
        CheckConstraint("case_count >= 0", name="case_count"),
        Index(
            "uq_outbreak_alert_cell",
            "tenant_id",
            "district",
            "crop_id",
            "problem_id",
            "week_start",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_outbreak_alert_district_week", "tenant_id", "district", "week_start"),
    )

    district: Mapped[str] = mapped_column(String(80), nullable=False)
    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    problem_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("corpus_problem.id", ondelete="RESTRICT"), nullable=False
    )
    #: Monday (IST) of the ISO week
    week_start: Mapped[date] = mapped_column(Date, nullable=False)
    iso_year: Mapped[int] = mapped_column(Integer, nullable=False)
    iso_week: Mapped[int] = mapped_column(Integer, nullable=False)
    case_count: Mapped[int] = mapped_column(Integer, nullable=False)
    farmers_affected: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    baseline_mean: Mapped[Decimal] = mapped_column(Numeric(8, 2), nullable=False)
    #: the rule in force when it fired: {"min_cases", "ratio", "baseline_weeks", ...}
    rule: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    status: Mapped[str] = mapped_column(
        String(8), nullable=False, server_default=text("'active'"), default=OutbreakStatus.ACTIVE
    )
    notified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    #: {"farmers": n, "officers": n, "agronomists": n}
    notified: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)


__all__ = [
    "CropPlotTask",
    "CropTaskTemplate",
    "OutbreakAlert",
    "OutbreakStatus",
    "TaskStatus",
    "TaskType",
]
