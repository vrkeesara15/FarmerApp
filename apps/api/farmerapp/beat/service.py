"""FA-018 beat plan generation and the officer's edits.

For an officer and an IST day the plan suggests the officer's own farmers (registered by
them) that have a reason to be visited, highest priority first, capped at the tenant's
``beat_daily_target``:

======================= ========= ==========================================================
reason                  priority  rule
======================= ========= ==========================================================
``pest_alert``          40        a diagnosis (answered / provisional / confirmed /
                                  corrected) of the same crop in the farmer's district in
                                  the 7 days before the plan day, and the farmer has a live
                                  crop plot of that crop
``credit_due``          30 (+10   an open khata debit (FIFO ageing, ``farmerapp.khata.aging``)
                        overdue)  due within 7 days of the plan day, or already overdue
``demo_plot_stage``     25        an active demo plot of the officer on the farmer's farm
                                  without an observation for 7 days
``follow_up_due``       20 (+5    no visit to the farmer for ``beat_follow_up_days``
                        never)    (default 14), or never visited (+1 per extra week, max +10)
======================= ========= ==========================================================

A farmer with several reasons carries them all and the sum of the priorities. Ties: farmer
name. The ``generate-beat-plans`` job runs at 06:00 IST (Cloud Scheduler) for every active
field officer; a first read of today's (or tomorrow's) plan generates it when the job has not
run yet. An existing plan is never regenerated, so the officer's edits stand.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import ist_bounds, today_ist
from farmerapp.api.errors import AppError, ConflictError, NotFoundError
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.scope import farmer_filters
from farmerapp.beat.models import BeatPlan
from farmerapp.beat.schemas import BeatPlanOut, BeatPlanUpdate
from farmerapp.demo_plots.models import DemoPlot, DemoStatus
from farmerapp.diagnosis.models import Diagnosis, DiagnosisStatus
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.khata.aging import open_debits
from farmerapp.khata.models import KhataEntry
from farmerapp.logging import get_logger
from farmerapp.notifications.models import NotificationKind
from farmerapp.notifications.service import notify
from farmerapp.tenants.models import Village
from farmerapp.tenants.settings import TenantSettings, get_tenant_settings
from farmerapp.visits.models import Visit

log = get_logger("farmerapp.beat")

PRIORITY = {"pest_alert": 40, "credit_due": 30, "demo_plot_stage": 25, "follow_up_due": 20}
PEST_WINDOW = timedelta(days=7)
CREDIT_WINDOW = timedelta(days=7)
DEMO_STAGE_EVERY = timedelta(days=7)
PEST_STATUSES = (
    DiagnosisStatus.ANSWERED.value,
    DiagnosisStatus.PROVISIONAL.value,
    DiagnosisStatus.CONFIRMED.value,
    DiagnosisStatus.CORRECTED.value,
)


class BeatPlanNotFoundError(NotFoundError):
    code = "beat_plan_not_found"


class BeatItemUnknownError(AppError):
    status = 422
    code = "beat_item_unknown"


class BeatVersionConflictError(ConflictError):
    code = "version_conflict"


@dataclass
class Candidate:
    farmer_id: uuid.UUID
    farmer_name: str
    village_id: uuid.UUID
    reasons: list[dict[str, Any]] = field(default_factory=list)
    priority: int = 0

    def add(self, code: str, detail: dict[str, Any], bonus: int = 0) -> None:
        self.reasons.append({"code": code, "detail": detail})
        self.priority += PRIORITY[code] + bonus


async def _villages(
    session: AsyncSession, tenant_id: uuid.UUID, ids: set[uuid.UUID]
) -> dict[uuid.UUID, tuple[str, str]]:
    if not ids:
        return {}
    rows = await session.execute(
        select(Village.id, Village.name, Village.district).where(
            Village.tenant_id == tenant_id, Village.id.in_(ids)
        )
    )
    return {r[0]: (r[1], r[2]) for r in rows}


async def candidates(
    session: AsyncSession,
    officer: User,
    day: date,
    settings: TenantSettings,
    *,
    now: datetime,
) -> list[Candidate]:
    tid = officer.tenant_id
    day_start, _ = ist_bounds(day, day)
    farmers = (
        await session.execute(
            select(Farmer.id, Farmer.name, Farmer.village_id).where(
                Farmer.tenant_id == tid,
                Farmer.registered_by == officer.id,
                Farmer.deleted_at.is_(None),
            )
        )
    ).all()
    if not farmers:
        return []
    by_id = {f[0]: Candidate(farmer_id=f[0], farmer_name=f[1], village_id=f[2]) for f in farmers}
    ids = list(by_id)
    villages = await _villages(session, tid, {c.village_id for c in by_id.values()})

    # follow-up due: last visit to the farmer (by anyone) before the plan day.
    visits = (
        await session.execute(
            select(Visit.farmer_id, func.max(Visit.checkin_at))
            .where(
                Visit.tenant_id == tid,
                Visit.deleted_at.is_(None),
                Visit.farmer_id.in_(ids),
                Visit.checkin_at < day_start,
            )
            .group_by(Visit.farmer_id)
        )
    ).all()
    last: dict[uuid.UUID, datetime] = {r[0]: r[1] for r in visits}
    due_after = timedelta(days=settings.beat_follow_up_days)
    for fid, cand in by_id.items():
        seen = last.get(fid)
        if seen is None:
            cand.add("follow_up_due", {"last_visit_at": None, "days_since_visit": None}, 5)
            continue
        since = day_start - seen
        if since >= due_after:
            extra_weeks = int((since - due_after) / timedelta(days=7))
            cand.add(
                "follow_up_due",
                {"last_visit_at": seen.isoformat(), "days_since_visit": since.days},
                min(extra_weeks, 10),
            )

    # pest alert: diagnoses of a crop in the farmer's district during the last 7 days.
    districts = {villages[c.village_id][1] for c in by_id.values() if c.village_id in villages}
    district = func.coalesce(Diagnosis.district, Village.district)
    alerts = (
        await session.execute(
            select(district, Diagnosis.crop_id, func.count())
            .select_from(Diagnosis)
            .join(Farmer, Farmer.id == Diagnosis.farmer_id)
            .outerjoin(Village, Village.id == Farmer.village_id)
            .where(
                Diagnosis.tenant_id == tid,
                Diagnosis.deleted_at.is_(None),
                Diagnosis.status.in_(PEST_STATUSES),
                Diagnosis.crop_id.is_not(None),
                Diagnosis.created_at >= day_start - PEST_WINDOW,
                Diagnosis.created_at < day_start,
            )
            .group_by(district, Diagnosis.crop_id)
        )
    ).all()
    pests: dict[str, dict[uuid.UUID, int]] = defaultdict(dict)
    for dist, crop_id, count in alerts:
        if dist in districts:
            pests[dist][crop_id] = int(count)
    if pests:
        plots = await session.execute(
            select(Farm.farmer_id, CropPlot.crop_id)
            .join(CropPlot, CropPlot.farm_id == Farm.id)
            .where(
                Farm.tenant_id == tid,
                Farm.deleted_at.is_(None),
                CropPlot.deleted_at.is_(None),
                Farm.farmer_id.in_(ids),
            )
        )
        flagged: set[tuple[uuid.UUID, uuid.UUID]] = set()
        for fid, crop_id in plots:
            cand = by_id[fid]
            dist = villages.get(cand.village_id, ("", ""))[1]
            count = pests.get(dist, {}).get(crop_id)
            if count and (fid, crop_id) not in flagged:
                flagged.add((fid, crop_id))
                cand.add("pest_alert", {"crop_id": str(crop_id), "district": dist, "cases": count})

    # credit due within 7 days (or overdue): FIFO-aged open debits.
    entries: dict[uuid.UUID, list[KhataEntry]] = defaultdict(list)
    for entry in (
        await session.execute(
            select(KhataEntry).where(KhataEntry.tenant_id == tid, KhataEntry.farmer_id.in_(ids))
        )
    ).scalars():
        entries[entry.farmer_id].append(entry)
    horizon = day + CREDIT_WINDOW
    for fid, rows in entries.items():
        due = [d for d in open_debits(rows, day, settings.credit_due_days) if d.due_date <= horizon]
        if due:
            first = min(due, key=lambda d: d.due_date)
            overdue = first.due_date < day
            by_id[fid].add(
                "credit_due",
                {
                    "due_date": first.due_date.isoformat(),
                    "open_paise": sum(d.open_paise for d in due),
                    "overdue": overdue,
                },
                10 if overdue else 0,
            )

    # demo plot stage due: active demos without an observation for 7 days.
    demos = await session.execute(
        select(
            DemoPlot.id,
            DemoPlot.farmer_id,
            func.coalesce(DemoPlot.last_observed_at, DemoPlot.started_at, DemoPlot.created_at),
        ).where(
            DemoPlot.tenant_id == tid,
            DemoPlot.officer_id == officer.id,
            DemoPlot.deleted_at.is_(None),
            DemoPlot.status == DemoStatus.ACTIVE.value,
            DemoPlot.farmer_id.in_(ids),
        )
    )
    for demo_id, fid, seen_at in demos:
        if seen_at is None or day_start - seen_at >= DEMO_STAGE_EVERY:
            by_id[fid].add("demo_plot_stage", {"demo_plot_id": str(demo_id)})

    out = [c for c in by_id.values() if c.reasons]
    out.sort(key=lambda c: (-c.priority, c.farmer_name, str(c.farmer_id)))
    return out


def _item(cand: Candidate, villages: dict[uuid.UUID, tuple[str, str]]) -> dict[str, Any]:
    return {
        "id": str(uuid.uuid4()),
        "kind": "farmer",
        "farmer_id": str(cand.farmer_id),
        "farmer_name": cand.farmer_name,
        "village_id": str(cand.village_id),
        "village_name": villages.get(cand.village_id, (None, None))[0],
        "reasons": cand.reasons,
        "priority": cand.priority,
        "source": "system",
        "note": None,
    }


async def plan_for(
    session: AsyncSession, tenant_id: uuid.UUID, officer_id: uuid.UUID, day: date
) -> BeatPlan | None:
    return (
        await session.execute(
            select(BeatPlan).where(
                BeatPlan.tenant_id == tenant_id,
                BeatPlan.officer_id == officer_id,
                BeatPlan.plan_date == day,
                BeatPlan.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def generate(
    session: AsyncSession, officer: User, day: date, *, now: datetime | None = None
) -> tuple[BeatPlan, bool]:
    """The officer's plan for ``day`` (``(plan, created)``); an existing plan is kept."""
    now = now or datetime.now(UTC)
    existing = await plan_for(session, officer.tenant_id, officer.id, day)
    if existing is not None:
        return existing, False
    settings = await get_tenant_settings(session, officer.tenant_id)
    picked = (await candidates(session, officer, day, settings, now=now))[
        : settings.beat_daily_target
    ]
    villages = await _villages(session, officer.tenant_id, {c.village_id for c in picked})
    plan = BeatPlan(
        tenant_id=officer.tenant_id,
        officer_id=officer.id,
        plan_date=day,
        target=settings.beat_daily_target,
        items=[_item(c, villages) for c in picked],
        generated_at=now,
    )
    session.add(plan)
    await session.flush()
    await session.refresh(plan)
    log.info(
        "beat_plan_generated",
        officer_id=str(officer.id),
        plan_date=day.isoformat(),
        items=len(picked),
    )
    return plan, True


async def my_plan(session: AsyncSession, actor: User, day: date, *, now: datetime) -> BeatPlanOut:
    plan = await plan_for(session, actor.tenant_id, actor.id, day)
    if plan is None:
        today = today_ist(now)
        if not (today <= day <= today + timedelta(days=1)):
            raise BeatPlanNotFoundError("No beat plan for that day.")
        plan, _ = await generate(session, actor, day, now=now)
    return BeatPlanOut.from_row(plan)


async def update_plan(
    session: AsyncSession, actor: User, day: date, body: BeatPlanUpdate, *, now: datetime
) -> BeatPlanOut:
    plan = await plan_for(session, actor.tenant_id, actor.id, day)
    if plan is None:
        plan, _ = await generate(session, actor, day, now=now)
    if body.version is not None and body.version != plan.version:
        raise BeatVersionConflictError(
            "The plan changed on another device.", extra={"version": plan.version}
        )
    existing = {str(i["id"]): i for i in plan.items or []}
    out: list[dict[str, Any]] = []
    seen_farmers: set[str] = set()
    for item in body.items:
        if item.id is not None:
            current = existing.get(str(item.id))
            if current is None:
                raise BeatItemUnknownError(f"Item {item.id} is not on this plan.")
            new = dict(current)
            if item.note is not None:
                new["note"] = item.note
        elif item.kind == "farmer":
            if item.farmer_id is None:  # the schema requires it for a new farmer item
                raise BeatItemUnknownError("A new farmer item needs farmer_id.")
            farmer = (
                await session.execute(
                    select(Farmer).where(
                        Farmer.id == item.farmer_id,
                        Farmer.deleted_at.is_(None),
                        *farmer_filters(actor),
                    )
                )
            ).scalar_one_or_none()
            if farmer is None:
                raise BeatItemUnknownError("Farmer not found.")
            villages = await _villages(session, actor.tenant_id, {farmer.village_id})
            new = {
                "id": str(uuid.uuid4()),
                "kind": "farmer",
                "farmer_id": str(farmer.id),
                "farmer_name": farmer.name,
                "village_id": str(farmer.village_id),
                "village_name": villages.get(farmer.village_id, (None, None))[0],
                "reasons": [],
                "priority": 0,
                "source": "officer",
                "note": item.note,
            }
        else:
            if item.village_id is None:
                raise BeatItemUnknownError("A new village item needs village_id.")
            villages = await _villages(session, actor.tenant_id, {item.village_id})
            if item.village_id not in villages:
                raise BeatItemUnknownError("Village not found.")
            new = {
                "id": str(uuid.uuid4()),
                "kind": "village",
                "farmer_id": None,
                "farmer_name": None,
                "village_id": str(item.village_id),
                "village_name": villages[item.village_id][0],
                "reasons": [],
                "priority": 0,
                "source": "officer",
                "note": item.note,
            }
        if new.get("farmer_id"):
            if new["farmer_id"] in seen_farmers:
                continue  # the same farmer twice: keep the first position
            seen_farmers.add(new["farmer_id"])
        out.append(new)
    plan.items = out
    plan.status = "edited"
    plan.edited_at = now
    await session.flush()
    await session.refresh(plan)
    return BeatPlanOut.from_row(plan)


@dataclass(frozen=True)
class GenerateReport:
    tenant_id: uuid.UUID
    day: date
    officers: int
    generated: int


async def generate_for_tenant(
    session: AsyncSession, tenant_id: uuid.UUID, day: date, *, now: datetime | None = None
) -> GenerateReport:
    """The 06:00 IST job: a plan for every active field officer who has none for ``day``."""
    now = now or datetime.now(UTC)
    officers = (
        (
            await session.execute(
                select(User).where(
                    User.tenant_id == tenant_id,
                    User.role == UserRole.FIELD_OFFICER.value,
                    User.status == UserStatus.ACTIVE.value,
                    User.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    generated = 0
    for officer in officers:
        plan, created = await generate(session, officer, day, now=now)
        if created:
            generated += 1
            notify(
                session,
                tenant_id=tenant_id,
                user_id=officer.id,
                kind=NotificationKind.BEAT_PLAN_READY.value,
                data={"date": day.isoformat(), "beat_plan_id": plan.id, "items": len(plan.items)},
            )
    await session.flush()
    log.info(
        "beat_plans_generated", tenant_id=str(tenant_id), day=day.isoformat(), generated=generated
    )
    return GenerateReport(tenant_id=tenant_id, day=day, officers=len(officers), generated=generated)


__all__ = [
    "PRIORITY",
    "BeatItemUnknownError",
    "BeatPlanNotFoundError",
    "GenerateReport",
    "candidates",
    "generate",
    "generate_for_tenant",
    "my_plan",
    "plan_for",
    "update_plan",
]
