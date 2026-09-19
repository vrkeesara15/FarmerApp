"""AN-002 / WC-002 field team scorecard (C20) and officer profile (C21).

Per officer over the range: verified visits per duty day (duty day = an IST day with a duty
session), unique farmers reached, new registrations (farmers they registered), confirmation
rate, average time on farm per verified visit, km per duty day (duty sessions' km), visit
conversion, collections (payments they collected: paid, reconciled or cash awaiting the day
close), open flags (``FlagCountsPort``), a rank (verified visits per duty day, then verified
visits) and a weekly sparkline of verified visits.

SPEC 2.6: tracks are never shown to store managers or other officers, so ``km_per_day`` (and
the per-day km of the profile) is ``null`` for callers outside ``LOCATION_ROLES``; a field
officer only ever gets their own row.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Sequence
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics import facts
from farmerapp.analytics.filters import OfficerInfo, Scope, to_ist_date
from farmerapp.analytics.kpi import (
    CONVERSION_WINDOW,
    VisitFact,
    confirmation_rate,
    ratio,
    time_on_farm_s,
    unique_farmers_reached,
    visit_conversion,
)
from farmerapp.analytics.periods import buckets, points, sum_by_bucket
from farmerapp.analytics.ports import FlagCountsPort, FlagQuery
from farmerapp.analytics.schemas import (
    DutyDayOut,
    FieldTeamOut,
    OfficerProfileOut,
    OfficerVisitOut,
    ScorecardRow,
)
from farmerapp.api.errors import NotFoundError
from farmerapp.farmers.models import Farmer
from farmerapp.location.models import DutySession
from farmerapp.tenants.models import Store
from farmerapp.visits.models import Visit

RECENT_VISITS = 20


def _rows(
    scope: Scope,
    visits: Sequence[VisitFact],
    duty: Sequence[facts.DutyFact],
    registrations: dict[uuid.UUID, int],
    collections: dict[uuid.UUID, int],
    purchases: Sequence[tuple[uuid.UUID, datetime]],
    flags: dict[uuid.UUID, int],
) -> list[ScorecardRow]:
    f = scope.filters
    weeks = buckets(f.from_, f.to, "week")
    by_officer: dict[uuid.UUID, list[VisitFact]] = defaultdict(list)
    for v in visits:
        by_officer[v.officer_id].append(v)
    days: dict[uuid.UUID, set[date]] = defaultdict(set)
    km: dict[uuid.UUID, Decimal] = defaultdict(Decimal)
    for d in duty:
        days[d.officer_id].add(d.day)
        km[d.officer_id] += d.km or Decimal(0)
    rows: list[ScorecardRow] = []
    for officer in scope.officers:
        own = by_officer.get(officer.id, [])
        verified = [v for v in own if v.verified]
        duty_days = len(days.get(officer.id, ()))
        on_farm = time_on_farm_s(own)
        conversion = visit_conversion(own, purchases)
        trend = sum_by_bucket(weeks, [(to_ist_date(v.checkin_at), 1) for v in verified])
        rows.append(
            ScorecardRow(
                officer_id=officer.id,
                name=officer.name,
                store_id=officer.store_id,
                cluster_id=officer.cluster_id,
                rank=0,
                duty_days=duty_days,
                visits=len(own),
                verified_visits=len(verified),
                verified_visits_per_day=_round(ratio(len(verified), duty_days)),
                unique_farmers_reached=unique_farmers_reached(own),
                new_registrations=registrations.get(officer.id, 0),
                confirmation_rate=_round(confirmation_rate(own)),
                avg_time_on_farm_s=round(on_farm / len(verified)) if verified else None,
                time_on_farm_s=on_farm,
                km_per_day=(
                    _round(ratio(float(km.get(officer.id, Decimal(0))), duty_days))
                    if scope.show_location
                    else None
                ),
                conversion_rate=_round(conversion.rate),
                converted_farmers=conversion.converted,
                visited_farmers=conversion.visited,
                collections_paise=collections.get(officer.id, 0),
                flags=flags.get(officer.id, 0),
                trend=points(weeks, trend),
            )
        )
    rows.sort(
        key=lambda r: (
            -(r.verified_visits_per_day or 0.0),
            -r.verified_visits,
            r.name,
            str(r.officer_id),
        )
    )
    for i, row in enumerate(rows, start=1):
        row.rank = i
    return rows


def _round(value: float | None, digits: int = 4) -> float | None:
    return None if value is None else round(value, digits)


async def scorecard(
    session: AsyncSession, scope: Scope, flags: FlagCountsPort
) -> list[ScorecardRow]:
    start, end = scope.filters.bounds
    visits = await facts.visits(session, scope, start, end)
    duty = await facts.duty_sessions(session, scope, start, end)
    regs = await facts.registrations(session, scope, start, end)
    cols = await facts.collections(session, scope, start, end)
    visited = {v.farmer_id for v in visits if v.verified}
    bought = await facts.purchases(
        session, scope.tenant_id, visited, start, end + CONVERSION_WINDOW
    )
    counts = await flags.counts(
        session,
        FlagQuery(
            tenant_id=scope.tenant_id,
            store_ids=scope.store_ids,
            officer_ids=scope.officer_ids,
            opened_before=end,
            viewer=scope.actor,
            officer_only=scope.own_officer_id is not None,
        ),
    )
    return _rows(scope, visits, duty, regs, cols, bought, counts.by_officer)


async def field_team(session: AsyncSession, scope: Scope, flags: FlagCountsPort) -> FieldTeamOut:
    return FieldTeamOut(
        filters=scope.echo(),
        location_visible=scope.show_location,
        items=await scorecard(session, scope, flags),
    )


def visible_officer(scope: Scope, officer_id: uuid.UUID) -> OfficerInfo:
    officer = next((o for o in scope.officers if o.id == officer_id), None)
    if officer is None:
        raise NotFoundError("Officer not found.")
    return officer


async def officer_profile(
    session: AsyncSession, scope: Scope, officer_id: uuid.UUID, flags: FlagCountsPort
) -> OfficerProfileOut:
    officer = visible_officer(scope, officer_id)
    one = Scope(
        actor=scope.actor,
        filters=scope.filters,
        level=scope.level,
        stores=scope.stores,
        officers=(officer,),
        store_ids=scope.store_ids,
        officer_ids=frozenset({officer.id}),
        own_officer_id=officer.id,
        crop_id=scope.crop_id,
    )
    rows = await scorecard(session, one, flags)
    start, end = one.filters.bounds

    # Duty days.
    visits = await facts.visits(session, one, start, end)
    per_day: dict[date, list[VisitFact]] = defaultdict(list)
    for v in visits:
        per_day[to_ist_date(v.checkin_at)].append(v)
    duty = await facts.duty_sessions(session, one, start, end)
    days: dict[date, list[facts.DutyFact]] = defaultdict(list)
    for d in duty:
        days[d.day].append(d)
    duty_days = []
    for day in sorted(days, reverse=True):
        sessions = days[day]
        ends = [s.end_at for s in sessions]
        km = sum((s.km or Decimal(0) for s in sessions), Decimal(0))
        vs = per_day.get(day, [])
        duty_days.append(
            DutyDayOut(
                day=day,
                start_at=min(s.start_at for s in sessions),
                end_at=None if any(e is None for e in ends) else max(e for e in ends if e),
                km=float(km) if one.show_location else None,
                visits=len(vs),
                verified_visits=sum(1 for v in vs if v.verified),
                time_on_farm_s=time_on_farm_s(vs),
            )
        )

    # Recent visits (in the range, newest first).
    recent = await session.execute(
        select(Visit, Farmer.name)
        .join(Farmer, Farmer.id == Visit.farmer_id)
        .where(*facts.visit_filters(one, start, end))
        .order_by(Visit.checkin_at.desc(), Visit.id)
        .limit(RECENT_VISITS)
    )
    on_duty = await session.scalar(
        select(DutySession.id)
        .where(
            DutySession.tenant_id == one.tenant_id,
            DutySession.officer_id == officer.id,
            DutySession.end_at.is_(None),
            DutySession.deleted_at.is_(None),
        )
        .limit(1)
    )
    sales = await facts.sales_aggregate(session, one, start, end, [])
    store_name = (
        await session.scalar(select(Store.name).where(Store.id == officer.store_id))
        if officer.store_id
        else None
    )
    return OfficerProfileOut(
        filters=scope.echo(),
        id=officer.id,
        name=officer.name,
        phone=officer.phone,
        status=officer.status,
        store_id=officer.store_id,
        store_name=store_name,
        cluster_id=officer.cluster_id,
        on_duty=on_duty is not None,
        location_visible=one.show_location,
        scorecard=rows[0],
        duty_days=duty_days,
        recent_visits=[
            OfficerVisitOut(
                id=v.id,
                farmer_id=v.farmer_id,
                farmer_name=name,
                checkin_at=v.checkin_at,
                checkout_at=v.checkout_at,
                status=v.status,
                score=v.score,
                purpose=v.purpose,
            )
            for v, name in recent
        ],
        sales_net_paise=sum(r.net_paise for r in sales),
        sales_orders=sum(r.orders for r in sales),
    )


__all__ = ["field_team", "officer_profile", "scorecard", "visible_officer"]
