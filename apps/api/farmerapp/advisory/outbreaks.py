"""DX-013 outbreak detection, FM-009 district alerts and the AN-006 crop health map.

Cases
-----
A **confirmed case** is a diagnosis with a final problem whose status is ``confirmed`` or
``corrected`` (agronomist) or, when ``outbreak.include_answered`` (default), ``answered``
(a corpus answer of high confidence) — the same definition as ``mart_crop_health_weekly``.
Its district is the diagnosis' district, else the farmer's village district; its week the ISO
week (Monday) of its IST request date.

Rule (tenant settings ``outbreak``)
-----------------------------------
A district x crop x problem x week **fires** when it has ``>= min_cases`` (3) cases **and**
``>= ratio`` (2x) the mean of the ``baseline_weeks`` (4) weeks before it (weeks without cases
count as zero, so a first cluster of 3 fires). ``outbreak-detection`` (daily) evaluates the
current and the previous week, writes one ``outbreak_alert`` per firing cell (idempotent:
the count is refreshed, never a second alert) and on creation notifies:

* the farmers of that district with an active plot of that crop and an app login — crop
  protection advisories, sent **without** marketing consent (FM-009 assumption for legal
  review, docs/prs/M7-farmer-p1-api.md; ``outbreak.farmer_alerts_enabled`` switches it off);
* the field officers of the district's stores and the officers who registered those farmers;
* the agronomists (the owners when the tenant has none).

District level only: no farm location or farmer identity is in an alert (AN-014).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.calendar import ACTIVE_PLOT_DAYS, today_ist
from farmerapp.advisory.models import OutbreakAlert, OutbreakStatus
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.models import CorpusProblem, Diagnosis, DiagnosisStatus
from farmerapp.farmers.models import CropPlot, CropStage, Farm, Farmer
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.payments.config import IST
from farmerapp.tenants.models import Store, Village
from farmerapp.tenants.settings import OutbreakSettings, get_tenant_settings

log = get_logger("farmerapp.advisory.outbreaks")

CellKey = tuple[str, uuid.UUID, uuid.UUID]  # district, crop_id, problem_id


def week_start(day: date) -> date:
    return day - timedelta(days=day.weekday())


def case_statuses(rule: OutbreakSettings) -> list[str]:
    statuses = [DiagnosisStatus.CONFIRMED.value, DiagnosisStatus.CORRECTED.value]
    if rule.include_answered:
        statuses.append(DiagnosisStatus.ANSWERED.value)
    return statuses


@dataclass
class WeekCount:
    cases: int = 0
    farmers: set[uuid.UUID] = field(default_factory=set)


@dataclass(frozen=True)
class Cell:
    district: str
    crop_id: uuid.UUID
    problem_id: uuid.UUID
    week_start: date
    cases: int
    farmers: int
    prior_mean: float
    fires: bool


async def weekly_counts(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    since: date,
    until: date,
    rule: OutbreakSettings,
    district: str | None = None,
    crop_id: uuid.UUID | None = None,
) -> dict[CellKey, dict[date, WeekCount]]:
    """Confirmed cases per district x crop x problem x ISO week, IST days ``since..until``."""
    start = datetime.combine(since, datetime.min.time(), tzinfo=IST)
    end = datetime.combine(until + timedelta(days=1), datetime.min.time(), tzinfo=IST)
    district_col = func.coalesce(Diagnosis.district, Village.district)
    crop_col = func.coalesce(Diagnosis.crop_id, CorpusProblem.crop_id)
    stmt = (
        select(
            district_col.label("district"),
            crop_col.label("crop_id"),
            Diagnosis.final_problem_id,
            Diagnosis.created_at,
            Diagnosis.farmer_id,
        )
        .join(CorpusProblem, CorpusProblem.id == Diagnosis.final_problem_id)
        .join(Farmer, Farmer.id == Diagnosis.farmer_id)
        .join(Village, Village.id == Farmer.village_id)
        .where(
            Diagnosis.tenant_id == tenant_id,
            Diagnosis.deleted_at.is_(None),
            Diagnosis.final_problem_id.is_not(None),
            Diagnosis.status.in_(case_statuses(rule)),
            Diagnosis.created_at >= start,
            Diagnosis.created_at < end,
        )
    )
    if district is not None:
        stmt = stmt.where(district_col == district)
    if crop_id is not None:
        stmt = stmt.where(crop_col == crop_id)
    out: dict[CellKey, dict[date, WeekCount]] = defaultdict(lambda: defaultdict(WeekCount))
    for row in (await session.execute(stmt)).all():
        if row.district is None or row.crop_id is None:
            continue
        week = week_start(row.created_at.astimezone(IST).date())
        count = out[(row.district, row.crop_id, row.final_problem_id)][week]
        count.cases += 1
        count.farmers.add(row.farmer_id)
    return out


def evaluate(
    counts: dict[CellKey, dict[date, WeekCount]], weeks: Sequence[date], rule: OutbreakSettings
) -> list[Cell]:
    """Every cell of ``weeks`` that has cases, with its trailing mean and whether it fires."""
    cells: list[Cell] = []
    for (district, crop_id, problem_id), by_week in counts.items():
        for week in weeks:
            current = by_week.get(week)
            if current is None or current.cases == 0:
                continue
            prior = [
                by_week[w].cases if w in by_week else 0
                for w in (week - timedelta(weeks=i) for i in range(1, rule.baseline_weeks + 1))
            ]
            mean = sum(prior) / rule.baseline_weeks
            fires = current.cases >= rule.min_cases and current.cases >= rule.ratio * mean
            cells.append(
                Cell(
                    district=district,
                    crop_id=crop_id,
                    problem_id=problem_id,
                    week_start=week,
                    cases=current.cases,
                    farmers=len(current.farmers),
                    prior_mean=round(mean, 2),
                    fires=fires,
                )
            )
    cells.sort(key=lambda c: (c.week_start, c.district, str(c.crop_id), str(c.problem_id)))
    return cells


# --------------------------------------------------------------------------- recipients
async def _farmer_recipients(
    session: AsyncSession, tenant_id: uuid.UUID, district: str, crop_id: uuid.UUID, today: date
) -> list[tuple[uuid.UUID | None, uuid.UUID | None]]:
    """(user id, registering officer) of the district's farmers growing the crop now."""
    rows = await session.execute(
        select(Farmer.user_id, Farmer.registered_by)
        .join(Village, Village.id == Farmer.village_id)
        .join(Farm, Farm.farmer_id == Farmer.id)
        .join(CropPlot, CropPlot.farm_id == Farm.id)
        .where(
            Farmer.tenant_id == tenant_id,
            Farmer.deleted_at.is_(None),
            Village.district == district,
            Farm.deleted_at.is_(None),
            CropPlot.deleted_at.is_(None),
            CropPlot.crop_id == crop_id,
            CropPlot.sowing_date >= today - timedelta(days=ACTIVE_PLOT_DAYS),
            (CropPlot.stage.is_(None)) | (CropPlot.stage != CropStage.HARVESTED.value),
        )
        .distinct()
    )
    return [(user_id, officer) for user_id, officer in rows.tuples()]


async def _active_users(
    session: AsyncSession, tenant_id: uuid.UUID, ids: Iterable[uuid.UUID]
) -> list[uuid.UUID]:
    wanted = set(ids)
    if not wanted:
        return []
    rows = await session.scalars(
        select(User.id).where(
            User.tenant_id == tenant_id,
            User.id.in_(wanted),
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
        )
    )
    return sorted(rows, key=str)


async def _role_users(
    session: AsyncSession, tenant_id: uuid.UUID, role: UserRole, *, district: str | None = None
) -> list[uuid.UUID]:
    stmt = select(User.id).where(
        User.tenant_id == tenant_id,
        User.role == role.value,
        User.status == UserStatus.ACTIVE.value,
        User.deleted_at.is_(None),
    )
    if district is not None:
        stmt = stmt.join(Store, Store.id == User.store_id).where(Store.district == district)
    return sorted(await session.scalars(stmt), key=str)


# --------------------------------------------------------------------------- detection
@dataclass
class OutbreakReport:
    tenant_id: uuid.UUID
    weeks: list[date]
    cells: int = 0
    fired: list[Cell] = field(default_factory=list)
    created: list[uuid.UUID] = field(default_factory=list)
    notified_farmers: int = 0
    notified_staff: int = 0


def _notification(
    tenant_id: uuid.UUID, user_id: uuid.UUID, alert: OutbreakAlert, audience: str
) -> Notification:
    kind = NotificationKind.OUTBREAK_ALERT.value
    return Notification(
        tenant_id=tenant_id,
        user_id=user_id,
        kind=kind,
        title_key=f"notification.{kind}.title",
        body_key=f"notification.{kind}.{audience}.body",
        data={
            "alert_id": str(alert.id),
            "district": alert.district,
            "crop_id": str(alert.crop_id),
            "problem_id": str(alert.problem_id),
            "week_start": alert.week_start.isoformat(),
            "case_count": alert.case_count,
        },
    )


async def _notify(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    alert: OutbreakAlert,
    rule: OutbreakSettings,
    today: date,
    now: datetime,
) -> tuple[int, int]:
    farmers = await _farmer_recipients(session, tenant_id, alert.district, alert.crop_id, today)
    farmer_users = (
        await _active_users(session, tenant_id, (u for u, _ in farmers if u is not None))
        if rule.farmer_alerts_enabled
        else []
    )
    officers = await _active_users(
        session,
        tenant_id,
        {o for _, o in farmers if o is not None}
        | set(
            await _role_users(session, tenant_id, UserRole.FIELD_OFFICER, district=alert.district)
        ),
    )
    agronomists = await _role_users(session, tenant_id, UserRole.AGRONOMIST) or await _role_users(
        session, tenant_id, UserRole.OWNER
    )
    staff = [u for u in dict.fromkeys([*officers, *agronomists]) if u not in farmer_users]
    for user_id in farmer_users:
        session.add(_notification(tenant_id, user_id, alert, "farmer"))
    for user_id in staff:
        session.add(_notification(tenant_id, user_id, alert, "staff"))
    alert.notified_at = now
    alert.notified = {
        "farmers": len(farmer_users),
        "officers": len(officers),
        "agronomists": len(agronomists),
        "farmer_alerts_enabled": rule.farmer_alerts_enabled,
    }
    return len(farmer_users), len(staff)


async def detect_outbreaks(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime | None = None,
    weeks_back: int = 1,
) -> OutbreakReport:
    """Evaluate the current ISO week and ``weeks_back`` weeks before it (idempotent)."""
    now = now or datetime.now(UTC)
    today = today_ist(now)
    rule = (await get_tenant_settings(session, tenant_id)).outbreak
    current = week_start(today)
    weeks = [current - timedelta(weeks=i) for i in range(weeks_back, -1, -1)]
    since = weeks[0] - timedelta(weeks=rule.baseline_weeks)
    counts = await weekly_counts(session, tenant_id, since=since, until=today, rule=rule)
    cells = evaluate(counts, weeks, rule)
    report = OutbreakReport(tenant_id=tenant_id, weeks=weeks, cells=len(cells))
    rule_json: dict[str, Any] = rule.model_dump(mode="json")
    for cell in cells:
        if not cell.fires:
            continue
        report.fired.append(cell)
        alert = await session.scalar(
            select(OutbreakAlert).where(
                OutbreakAlert.tenant_id == tenant_id,
                OutbreakAlert.district == cell.district,
                OutbreakAlert.crop_id == cell.crop_id,
                OutbreakAlert.problem_id == cell.problem_id,
                OutbreakAlert.week_start == cell.week_start,
                OutbreakAlert.deleted_at.is_(None),
            )
        )
        if alert is not None:
            if alert.case_count != cell.cases or alert.farmers_affected != cell.farmers:
                alert.case_count = cell.cases
                alert.farmers_affected = cell.farmers
            continue
        iso = cell.week_start.isocalendar()
        alert = OutbreakAlert(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            district=cell.district,
            crop_id=cell.crop_id,
            problem_id=cell.problem_id,
            week_start=cell.week_start,
            iso_year=iso.year,
            iso_week=iso.week,
            case_count=cell.cases,
            farmers_affected=cell.farmers,
            baseline_mean=Decimal(str(cell.prior_mean)),
            rule=rule_json,
            status=OutbreakStatus.ACTIVE.value,
            notified={},
        )
        session.add(alert)
        await session.flush()
        farmers, staff = await _notify(session, tenant_id, alert, rule, today, now)
        report.created.append(alert.id)
        report.notified_farmers += farmers
        report.notified_staff += staff
        log.warning(
            "outbreak_alert_raised",
            tenant_id=str(tenant_id),
            alert_id=str(alert.id),
            district=cell.district,
            week_start=cell.week_start.isoformat(),
            cases=cell.cases,
            prior_mean=cell.prior_mean,
            notified_farmers=farmers,
            notified_staff=staff,
        )
    await session.flush()
    return report


async def run_outbreak_detection(
    tenant_ids: Iterable[uuid.UUID], *, now: datetime | None = None, weeks_back: int = 1
) -> list[OutbreakReport]:
    reports: list[OutbreakReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await detect_outbreaks(
                        session, tenant_id=tenant_id, now=now, weeks_back=weeks_back
                    )
                )
    return reports


# --------------------------------------------------------------------------- reads
@dataclass(frozen=True)
class AlertRow:
    alert: OutbreakAlert
    crop: Crop
    problem: CorpusProblem
    problem_code: str | None


async def active_alerts(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    districts: Sequence[str] | None,
    today: date,
    rule: OutbreakSettings,
    crop_id: uuid.UUID | None = None,
) -> list[AlertRow]:
    oldest = week_start(today) - timedelta(weeks=rule.active_weeks)
    stmt = (
        select(OutbreakAlert, Crop, CorpusProblem, PestOrDisease.code)
        .join(Crop, Crop.id == OutbreakAlert.crop_id)
        .join(CorpusProblem, CorpusProblem.id == OutbreakAlert.problem_id)
        .outerjoin(PestOrDisease, PestOrDisease.id == CorpusProblem.pest_or_disease_id)
        .where(
            OutbreakAlert.tenant_id == tenant_id,
            OutbreakAlert.deleted_at.is_(None),
            OutbreakAlert.status == OutbreakStatus.ACTIVE.value,
            OutbreakAlert.week_start >= oldest,
        )
        .order_by(OutbreakAlert.week_start.desc(), OutbreakAlert.district, OutbreakAlert.id)
    )
    if districts is not None:
        stmt = stmt.where(OutbreakAlert.district.in_(list(districts)))
    if crop_id is not None:
        stmt = stmt.where(OutbreakAlert.crop_id == crop_id)
    return [
        AlertRow(alert=a, crop=c, problem=p, problem_code=code)
        for a, c, p, code in (await session.execute(stmt)).tuples()
    ]


async def farmer_districts_and_crops(
    session: AsyncSession, farmer: Farmer, today: date
) -> tuple[list[str], set[uuid.UUID]]:
    district = await session.scalar(select(Village.district).where(Village.id == farmer.village_id))
    crops = set(
        await session.scalars(
            select(CropPlot.crop_id)
            .join(Farm, Farm.id == CropPlot.farm_id)
            .where(
                Farm.farmer_id == farmer.id,
                Farm.deleted_at.is_(None),
                CropPlot.deleted_at.is_(None),
                CropPlot.sowing_date >= today - timedelta(days=ACTIVE_PLOT_DAYS),
            )
        )
    )
    return ([district] if district else []), crops


@dataclass(frozen=True)
class HealthCell:
    cell: Cell
    crop_code: str
    problem_code: str | None
    problem_type: str
    alert_id: uuid.UUID | None


async def crop_health(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    today: date,
    weeks: int,
    district: str | None = None,
    crop_id: uuid.UUID | None = None,
) -> tuple[list[date], OutbreakSettings, list[HealthCell]]:
    rule = (await get_tenant_settings(session, tenant_id)).outbreak
    current = week_start(today)
    week_list = [current - timedelta(weeks=i) for i in range(weeks - 1, -1, -1)]
    since = week_list[0] - timedelta(weeks=rule.baseline_weeks)
    counts = await weekly_counts(
        session, tenant_id, since=since, until=today, rule=rule, district=district, crop_id=crop_id
    )
    cells = evaluate(counts, week_list, rule)
    crops = {
        c.id: c.code
        for c in (await session.scalars(select(Crop).where(Crop.tenant_id == tenant_id)))
    }
    problems = {
        pid: (code, ptype)
        for pid, code, ptype in (
            await session.execute(
                select(CorpusProblem.id, PestOrDisease.code, CorpusProblem.problem_type)
                .outerjoin(PestOrDisease, PestOrDisease.id == CorpusProblem.pest_or_disease_id)
                .where(CorpusProblem.tenant_id == tenant_id)
            )
        ).tuples()
    }
    alerts = {
        (a.district, a.crop_id, a.problem_id, a.week_start): a.id
        for a in await session.scalars(
            select(OutbreakAlert).where(
                OutbreakAlert.tenant_id == tenant_id,
                OutbreakAlert.deleted_at.is_(None),
                OutbreakAlert.week_start >= week_list[0],
            )
        )
    }
    out = [
        HealthCell(
            cell=c,
            crop_code=crops.get(c.crop_id, "unknown"),
            problem_code=problems.get(c.problem_id, (None, "disease"))[0],
            problem_type=problems.get(c.problem_id, (None, "disease"))[1],
            alert_id=alerts.get((c.district, c.crop_id, c.problem_id, c.week_start)),
        )
        for c in cells
    ]
    return week_list, rule, out


__all__ = [
    "AlertRow",
    "Cell",
    "HealthCell",
    "OutbreakReport",
    "WeekCount",
    "active_alerts",
    "case_statuses",
    "crop_health",
    "detect_outbreaks",
    "evaluate",
    "farmer_districts_and_crops",
    "run_outbreak_detection",
    "week_start",
    "weekly_counts",
]
