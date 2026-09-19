"""FM-007 crop calendar: generation per crop plot, reads, task updates, reminders.

Generation
----------
``ensure_calendar(session, plot)`` materialises the calendar of one crop plot from the
effective templates of its crop and season (season-specific templates override the
season-less ones with the same ``task_key``): ``due_date = sowing_date + day_offset``,
``end_date = due_date + duration - 1``. Every task records its basis (sowing date, crop,
template hash). When the plot's sowing date or crop, or the crop's templates, change, the
**pending** tasks are brought in line in place (dates, texts, basis; ``reminded_at`` reset
when the date moved; the farmer's ``reminder_enabled`` kept), tasks whose template is gone are
soft-deleted and new templates add tasks. **Done tasks are never touched.** A deleted plot
soft-deletes its pending tasks.

The calendar is materialised on read (``GET /v1/me/calendar``, officer reads), after a crop
plot update (``farmerapp.farmers.service.update_crop_plot`` calls ``on_plot_changed``) and by
the daily ``calendar-reminders`` job for every active plot, so seeded or synced plots get
theirs too. Every write is audited (FA-006 listener) and lands in the sync change feed
(entity ``crop_plot_task``).

Reminders
---------
``run_calendar_reminders`` (daily, Cloud Scheduler 07:00 IST): per tenant, outside the
tenant's ``quiet_hours`` and not before ``calendar_reminders.local_time``, one
``crop_task_reminder`` notification to the farmer's login for every pending task with its
reminder on that is due today (or up to ``lookback_days`` ago and never reminded);
``reminded_at`` makes it once. Farmers without an app login get none (SMS is a follow-up).
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.models import CropPlotTask, CropTaskTemplate, TaskStatus
from farmerapp.api.errors import ConflictError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import farmer_filters
from farmerapp.catalog.crops import Crop
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.farmers.models import CropPlot, CropStage, Farm, Farmer
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.payments.config import IST
from farmerapp.tenants.settings import get_tenant_settings

log = get_logger("farmerapp.advisory.calendar")

#: Plots sown longer ago than this are finished: no generation, not in the calendar.
ACTIVE_PLOT_DAYS = 400


def today_ist(now: datetime) -> date:
    return now.astimezone(IST).date()


# --------------------------------------------------------------------------- templates
async def effective_templates(
    session: AsyncSession, tenant_id: uuid.UUID, crop_id: uuid.UUID, season: str | None
) -> list[CropTaskTemplate]:
    """The active templates of a crop for a season: a season row wins over the season-less
    row with the same key."""
    rows = (
        (
            await session.execute(
                select(CropTaskTemplate)
                .where(
                    CropTaskTemplate.tenant_id == tenant_id,
                    CropTaskTemplate.crop_id == crop_id,
                    CropTaskTemplate.deleted_at.is_(None),
                    (CropTaskTemplate.season.is_(None)) | (CropTaskTemplate.season == season),
                )
                .order_by(CropTaskTemplate.sort_order, CropTaskTemplate.task_key)
            )
        )
        .scalars()
        .all()
    )
    by_key: dict[str, CropTaskTemplate] = {}
    for row in rows:
        current = by_key.get(row.task_key)
        if current is None or (current.season is None and row.season is not None):
            by_key[row.task_key] = row
    return sorted(
        (t for t in by_key.values() if t.active), key=lambda t: (t.sort_order, t.task_key)
    )


def template_hash(templates: Sequence[CropTaskTemplate]) -> str:
    payload = [
        [
            t.task_key,
            t.season,
            t.task_type,
            t.day_offset,
            t.duration_days,
            t.stage,
            t.titles,
            t.instructions,
            t.product_category,
            t.sort_order,
        ]
        for t in templates
    ]
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


# --------------------------------------------------------------------------- generation
@dataclass
class GenerationResult:
    created: int = 0
    updated: int = 0
    removed: int = 0

    @property
    def changed(self) -> bool:
        return bool(self.created or self.updated or self.removed)


async def _plot_farmer_id(session: AsyncSession, plot: CropPlot) -> uuid.UUID:
    farmer_id = await session.scalar(select(Farm.farmer_id).where(Farm.id == plot.farm_id))
    if farmer_id is None:  # pragma: no cover - FK
        raise NotFoundError("Farm not found.")
    return farmer_id


async def plot_tasks(session: AsyncSession, plot_id: uuid.UUID) -> list[CropPlotTask]:
    return list(
        (
            await session.execute(
                select(CropPlotTask)
                .where(CropPlotTask.crop_plot_id == plot_id, CropPlotTask.deleted_at.is_(None))
                .order_by(CropPlotTask.due_date, CropPlotTask.sort_order, CropPlotTask.task_key)
            )
        )
        .scalars()
        .all()
    )


def _is_finished(plot: CropPlot, today: date) -> bool:
    return (
        plot.deleted_at is not None
        or plot.stage == CropStage.HARVESTED.value
        or (today - plot.sowing_date).days > ACTIVE_PLOT_DAYS
    )


async def ensure_calendar(
    session: AsyncSession,
    plot: CropPlot,
    *,
    now: datetime | None = None,
    farmer_id: uuid.UUID | None = None,
) -> GenerationResult:
    """Bring the plot's tasks in line with its sowing date, crop and templates (idempotent)."""
    now = now or datetime.now(UTC)
    result = GenerationResult()
    existing = await plot_tasks(session, plot.id)
    if plot.deleted_at is not None:
        for task in existing:
            if task.status == TaskStatus.PENDING.value:
                task.deleted_at = now
                result.removed += 1
        if result.changed:
            await session.flush()
        return result
    templates = await effective_templates(session, plot.tenant_id, plot.crop_id, plot.season)
    digest = template_hash(templates)
    if existing and all(
        t.status == TaskStatus.DONE.value
        or (
            t.basis_sowing_date == plot.sowing_date
            and t.basis_crop_id == plot.crop_id
            and t.basis_hash == digest
        )
        for t in existing
    ):
        return result  # up to date (the common read path: one query)
    if not existing and not templates:
        return result
    farmer_id = farmer_id or await _plot_farmer_id(session, plot)
    by_key = {t.task_key: t for t in existing}
    wanted = {t.task_key for t in templates}
    for template in templates:
        due = plot.sowing_date + timedelta(days=template.day_offset)
        fields = {
            "template_id": template.id,
            "task_type": template.task_type,
            "stage": template.stage,
            "due_date": due,
            "end_date": due + timedelta(days=template.duration_days - 1),
            "titles": dict(template.titles),
            "instructions": dict(template.instructions),
            "product_category": template.product_category,
            "sort_order": template.sort_order,
            "basis_sowing_date": plot.sowing_date,
            "basis_crop_id": plot.crop_id,
            "basis_hash": digest,
        }
        current = by_key.get(template.task_key)
        if current is None:
            session.add(
                CropPlotTask(
                    tenant_id=plot.tenant_id,
                    crop_plot_id=plot.id,
                    farmer_id=farmer_id,
                    task_key=template.task_key,
                    **fields,
                )
            )
            result.created += 1
            continue
        if current.status == TaskStatus.DONE.value:
            continue  # completed tasks are history
        changes = {k: v for k, v in fields.items() if getattr(current, k) != v}
        if not changes:
            continue
        if "due_date" in changes:
            changes["reminded_at"] = None  # a moved task is reminded again
        for key, value in changes.items():
            setattr(current, key, value)
        result.updated += 1
    for task in existing:
        if task.task_key not in wanted and task.status == TaskStatus.PENDING.value:
            task.deleted_at = now
            result.removed += 1
    if result.changed:
        await session.flush()
        log.info(
            "crop_calendar_generated",
            crop_plot_id=str(plot.id),
            created=result.created,
            updated=result.updated,
            removed=result.removed,
        )
    return result


async def on_plot_changed(session: AsyncSession, plot: CropPlot) -> GenerationResult:
    """Hook for crop plot writes: regenerate only a calendar that exists already (new plots
    get theirs on first read or from the daily job)."""
    has_tasks = await session.scalar(
        select(CropPlotTask.id)
        .where(CropPlotTask.crop_plot_id == plot.id, CropPlotTask.deleted_at.is_(None))
        .limit(1)
    )
    if has_tasks is None:
        return GenerationResult()
    return await ensure_calendar(session, plot)


# --------------------------------------------------------------------------- reads
@dataclass(frozen=True)
class PlotCalendar:
    plot: CropPlot
    crop: Crop
    tasks: list[CropPlotTask]


async def farmer_calendar(
    session: AsyncSession,
    farmer: Farmer,
    *,
    now: datetime,
    crop_plot_id: uuid.UUID | None = None,
) -> list[PlotCalendar]:
    today = today_ist(now)
    stmt = (
        select(CropPlot, Crop)
        .join(Farm, Farm.id == CropPlot.farm_id)
        .join(Crop, Crop.id == CropPlot.crop_id)
        .where(
            Farm.farmer_id == farmer.id,
            Farm.deleted_at.is_(None),
            CropPlot.deleted_at.is_(None),
        )
        .order_by(CropPlot.sowing_date, CropPlot.id)
    )
    if crop_plot_id is not None:
        stmt = stmt.where(CropPlot.id == crop_plot_id)
    out: list[PlotCalendar] = []
    for plot, crop in (await session.execute(stmt)).tuples():
        if _is_finished(plot, today) and crop_plot_id is None:
            continue
        await ensure_calendar(session, plot, now=now, farmer_id=farmer.id)
        out.append(PlotCalendar(plot=plot, crop=crop, tasks=await plot_tasks(session, plot.id)))
    return out


async def own_farmer(session: AsyncSession, actor: User) -> Farmer:
    """The farmer record of a farmer login (FM-001: ``farmer.user_id``)."""
    farmer = await session.scalar(
        select(Farmer)
        .where(
            Farmer.tenant_id == actor.tenant_id,
            Farmer.user_id == actor.id,
            Farmer.deleted_at.is_(None),
        )
        .order_by(Farmer.created_at)
        .limit(1)
    )
    if farmer is None:
        raise NotFoundError("No farmer profile is linked to this login.")
    return farmer


# --------------------------------------------------------------------------- writes
async def visible_task(session: AsyncSession, actor: User, task_id: uuid.UUID) -> CropPlotTask:
    task = await session.scalar(
        select(CropPlotTask)
        .join(Farmer, Farmer.id == CropPlotTask.farmer_id)
        .where(
            CropPlotTask.id == task_id,
            CropPlotTask.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            *farmer_filters(actor),
        )
    )
    if task is None:
        raise NotFoundError("Calendar task not found.")
    return task


async def update_task(
    session: AsyncSession,
    actor: User,
    task: CropPlotTask,
    *,
    status: TaskStatus | None,
    reminder_enabled: bool | None,
    expected_version: int | None,
    now: datetime,
) -> CropPlotTask:
    if expected_version is not None and expected_version != task.version:
        raise ConflictError(
            "The task changed since you loaded it.",
            code="version_conflict",
            extra={"current_version": task.version},
        )
    if status is not None and status.value != task.status:
        task.status = status.value
        task.done_at = now if status == TaskStatus.DONE else None
        task.done_by = actor.id if status == TaskStatus.DONE else None
    if reminder_enabled is not None:
        task.reminder_enabled = reminder_enabled
    await session.flush()
    await session.refresh(task)
    return task


# --------------------------------------------------------------------------- reminders
@dataclass
class ReminderReport:
    tenant_id: uuid.UUID
    day: date
    state: str = "sent"  # sent | quiet_hours | too_early
    plots_checked: int = 0
    tasks_generated: int = 0
    reminded: list[uuid.UUID] = field(default_factory=list)
    no_login: int = 0


async def _active_plots(
    session: AsyncSession, tenant_id: uuid.UUID, today: date
) -> list[tuple[CropPlot, uuid.UUID]]:
    rows = await session.execute(
        select(CropPlot, Farm.farmer_id)
        .join(Farm, Farm.id == CropPlot.farm_id)
        .join(Farmer, Farmer.id == Farm.farmer_id)
        .where(
            CropPlot.tenant_id == tenant_id,
            CropPlot.deleted_at.is_(None),
            Farm.deleted_at.is_(None),
            Farmer.deleted_at.is_(None),
            CropPlot.sowing_date >= today - timedelta(days=ACTIVE_PLOT_DAYS),
        )
        .order_by(CropPlot.id)
    )
    return [(plot, farmer_id) for plot, farmer_id in rows.tuples()]


async def calendar_reminders(
    session: AsyncSession, *, tenant_id: uuid.UUID, now: datetime | None = None
) -> ReminderReport:
    now = now or datetime.now(UTC)
    local = now.astimezone(IST)
    report = ReminderReport(tenant_id=tenant_id, day=local.date())
    settings = await get_tenant_settings(session, tenant_id)
    if settings.quiet_hours.contains(local.time().replace(tzinfo=None)):
        report.state = "quiet_hours"
        return report
    hour, minute = settings.calendar_reminders.local_time.split(":")
    if (local.hour, local.minute) < (int(hour), int(minute)):
        report.state = "too_early"
        return report
    for plot, farmer_id in await _active_plots(session, tenant_id, report.day):
        if _is_finished(plot, report.day):
            continue
        report.plots_checked += 1
        generated = await ensure_calendar(session, plot, now=now, farmer_id=farmer_id)
        report.tasks_generated += generated.created
    since = report.day - timedelta(days=settings.calendar_reminders.lookback_days)
    due = (
        await session.execute(
            select(CropPlotTask, Farmer.user_id)
            .join(Farmer, Farmer.id == CropPlotTask.farmer_id)
            .join(CropPlot, CropPlot.id == CropPlotTask.crop_plot_id)
            .where(
                CropPlotTask.tenant_id == tenant_id,
                CropPlotTask.deleted_at.is_(None),
                CropPlotTask.status == TaskStatus.PENDING.value,
                CropPlotTask.reminder_enabled.is_(True),
                CropPlotTask.reminded_at.is_(None),
                CropPlotTask.due_date >= since,
                CropPlotTask.due_date <= report.day,
                CropPlot.deleted_at.is_(None),
            )
            .order_by(CropPlotTask.due_date, CropPlotTask.id)
        )
    ).tuples()
    for task, user_id in due:
        if user_id is None:
            report.no_login += 1
            continue
        session.add(
            Notification(
                tenant_id=tenant_id,
                user_id=user_id,
                kind=NotificationKind.CROP_TASK_REMINDER.value,
                title_key=f"notification.{NotificationKind.CROP_TASK_REMINDER.value}.title",
                body_key=f"notification.{NotificationKind.CROP_TASK_REMINDER.value}.body",
                data={
                    "task_id": str(task.id),
                    "crop_plot_id": str(task.crop_plot_id),
                    "farmer_id": str(task.farmer_id),
                    "task_key": task.task_key,
                    "task_type": task.task_type,
                    "due_date": task.due_date.isoformat(),
                },
            )
        )
        task.reminded_at = now
        report.reminded.append(task.id)
    await session.flush()
    log.info(
        "crop_calendar_reminders",
        tenant_id=str(tenant_id),
        state=report.state,
        plots=report.plots_checked,
        generated=report.tasks_generated,
        reminded=len(report.reminded),
        no_login=report.no_login,
    )
    return report


async def run_calendar_reminders(
    tenant_ids: Iterable[uuid.UUID], *, now: datetime | None = None
) -> list[ReminderReport]:
    reports: list[ReminderReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(await calendar_reminders(session, tenant_id=tenant_id, now=now))
    return reports


#: Roles that may change a task (the farmer on their own, the officer for their farmers).
TASK_WRITE_ROLES = (UserRole.FARMER, UserRole.FIELD_OFFICER)

__all__ = [
    "ACTIVE_PLOT_DAYS",
    "TASK_WRITE_ROLES",
    "GenerationResult",
    "PlotCalendar",
    "ReminderReport",
    "calendar_reminders",
    "effective_templates",
    "ensure_calendar",
    "farmer_calendar",
    "on_plot_changed",
    "own_farmer",
    "plot_tasks",
    "run_calendar_reminders",
    "template_hash",
    "today_ist",
    "update_task",
    "visible_task",
]
