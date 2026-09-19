"""AN-001 / WC-001 owner home (console C10).

KPI row (revenue, own-brand share, credit outstanding and overdue, verified visits, active
farmers, open flags), each with the value over the range, a target, the same period last
year and a trend (daily up to 31 days, else weekly); the revenue and own-brand share lines;
the store map; the top / bottom five officers by verified visits per duty day; open
high-severity flags (``FlagCountsPort``); crop health alerts (AN-006, P1: empty).

Targets come from the tenant setting ``targets`` (WC-009 will write it)::

    {"revenue_paise": 250000000, "own_brand_share": 0.4, "credit_overdue_paise": 0,
     "credit_outstanding_paise": 900000000, "verified_visits": 600, "active_farmers": 180,
     "open_flags": 0, "store_revenue_paise": {"<store id>": 50000000}}

Additive targets (``revenue_paise``, ``verified_visits``, ``store_revenue_paise``) are
monthly: scaled by ``days / 30`` to the selected range. The others are levels, used as is.

Store map score (0-100): revenue attainment against the store's target when there is one
(capped at 100), else revenue relative to the best store in view. Bands: ``green`` >= 80,
``amber`` >= 50, ``red`` below, ``none`` when there are no sales anywhere in view.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Mapping, Sequence
from dataclasses import replace
from datetime import date, timedelta
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics import facts
from farmerapp.analytics.filters import Scope, ist_start, to_ist_date
from farmerapp.analytics.kpi import (
    ACTIVE_WINDOW_DAYS,
    active_counts,
    active_farmers,
    credit_book,
    is_verified,
    ratio,
)
from farmerapp.analytics.periods import Bucket, buckets, granularity_for, points, sum_by_bucket
from farmerapp.analytics.ports import FlagCountsPort, FlagQuery, NullFlagCounts
from farmerapp.analytics.schemas import (
    FlagOut,
    KpiOut,
    OfficerRankOut,
    OwnerHomeOut,
    OwnerHomeSeries,
    StoreMapItem,
)
from farmerapp.db.models.tenant import Tenant
from farmerapp.khata.ledger import credit_settings

TOP_N = 5
MONTH_DAYS = 30
ADDITIVE_TARGETS = frozenset({"revenue_paise", "verified_visits"})


async def tenant_settings(session: AsyncSession, tenant_id: uuid.UUID) -> dict[str, Any]:
    tenant = await session.get(Tenant, tenant_id)
    return dict(tenant.settings or {}) if tenant is not None else {}


def targets_of(settings: Mapping[str, Any]) -> dict[str, Any]:
    raw = settings.get("targets")
    return dict(raw) if isinstance(raw, Mapping) else {}


def target(targets: Mapping[str, Any], key: str, days: int) -> float | None:
    value = targets.get(key)
    if not isinstance(value, int | float) or isinstance(value, bool):
        return None
    if key in ADDITIVE_TARGETS:
        return round(float(value) * days / MONTH_DAYS, 4)
    return float(value)


def band(score: int | None) -> str:
    if score is None:
        return "none"
    if score >= 80:
        return "green"
    if score >= 50:
        return "amber"
    return "red"


def _share_series(bs: Sequence[Bucket], rows: Sequence[facts.SalesRow]) -> list[float | None]:
    own = sum_by_bucket(bs, [(r.keys["day"], r.net_paise) for r in rows if r.keys["own_brand"]])
    total = sum_by_bucket(bs, [(r.keys["day"], r.net_paise) for r in rows])
    return [ratio(o, t) for o, t in zip(own, total, strict=True)]


def _kpi(
    key: str,
    unit: str,
    value: float | None,
    target_value: float | None,
    last_year: float | None,
    bs: Sequence[Bucket],
    trend: Sequence[float | None],
) -> KpiOut:
    return KpiOut.model_validate(
        {
            "key": key,
            "unit": unit,
            "value": value,
            "target": target_value,
            "last_year": last_year,
            "trend": points(bs, list(trend)),
        }
    )


def rank_officers(
    scope: Scope, verified: Mapping[uuid.UUID, int], duty_days: Mapping[uuid.UUID, int]
) -> list[OfficerRankOut]:
    rows = [
        OfficerRankOut(
            id=o.id,
            name=o.name,
            store_id=o.store_id,
            verified_visits=verified.get(o.id, 0),
            duty_days=duty_days.get(o.id, 0),
            verified_visits_per_day=ratio(verified.get(o.id, 0), duty_days.get(o.id, 0)),
        )
        for o in scope.officers
    ]
    return sorted(
        rows,
        key=lambda r: (-(r.verified_visits_per_day or 0.0), -r.verified_visits, r.name, str(r.id)),
    )


async def owner_home(session: AsyncSession, scope: Scope, flags: FlagCountsPort) -> OwnerHomeOut:
    f = scope.filters
    start, end = f.bounds
    ly = f.last_year()
    ly_scope = scope.with_filters(ly)
    ly_start, ly_end = ly.bounds
    gran = granularity_for(f.from_, f.to)
    bs = buckets(f.from_, f.to, gran)
    ly_bs = buckets(ly.from_, ly.to, gran)
    settings = await tenant_settings(session, scope.tenant_id)
    goals = targets_of(settings)
    due_days = credit_settings(settings).credit_due_days

    # Sales: revenue and own-brand share.
    sales = await facts.sales_aggregate(session, scope, start, end, ["day", "own_brand"])
    ly_sales = await facts.sales_aggregate(
        session, ly_scope, ly_start, ly_end, ["day", "own_brand"]
    )
    revenue = sum(r.net_paise for r in sales)
    own = sum(r.net_paise for r in sales if r.keys["own_brand"])
    ly_revenue = sum(r.net_paise for r in ly_sales)
    ly_own = sum(r.net_paise for r in ly_sales if r.keys["own_brand"])
    revenue_trend = sum_by_bucket(bs, [(r.keys["day"], r.net_paise) for r in sales])
    ly_revenue_trend = sum_by_bucket(ly_bs, [(r.keys["day"], r.net_paise) for r in ly_sales])
    share_trend = _share_series(bs, sales)

    # Visits.
    visits = await facts.visits(session, scope, start, end)
    ly_visits = await facts.visits(session, ly_scope, ly_start, ly_end)
    verified = [v for v in visits if v.verified]
    verified_trend = sum_by_bucket(bs, [(to_ist_date(v.checkin_at), 1) for v in verified])

    # Active farmers (a 60-day window ending on each bucket's last day).
    window = timedelta(days=ACTIVE_WINDOW_DAYS - 1)
    events = await facts.activity(session, scope, ist_start(f.from_ - window), end)
    active_trend = active_counts([b.end for b in bs], events)
    ly_events = await facts.activity(session, ly_scope, ist_start(ly.to - window), ly_end)
    ly_active = len(
        active_farmers(ly.to, purchases=ly_events)  # events are already the union of sources
    )

    # Credit book as of the end of each bucket.
    entries = await facts.khata_entries(session, scope, end)
    book = credit_book(entries, f.to, due_days, until=end)
    books = [
        credit_book(entries, b.end, due_days, until=ist_start(b.end + timedelta(days=1)))
        for b in bs
    ]
    ly_book = credit_book(entries, ly.to, due_days, until=ly_end)

    # Open validation flags (through the port; the caller's inbox scope applies).
    fq = FlagQuery(
        tenant_id=scope.tenant_id,
        store_ids=scope.store_ids,
        officer_ids=scope.officer_ids,
        opened_before=end,
        viewer=scope.actor,
        officer_only=scope.own_officer_id is not None,
    )
    flag_counts = await flags.counts(session, fq)
    instants = [ist_start(b.end + timedelta(days=1)) for b in bs]
    flag_trend = [float(n) for n in await flags.open_totals(session, fq, instants)]
    ly_flags = await flags.counts(session, replace(fq, opened_before=ly_end))
    high = await flags.open_high_severity(session, fq, 10)

    days = f.days
    kpis = [
        _kpi(
            "revenue", "paise", revenue, target(goals, "revenue_paise", days), ly_revenue,
            bs, revenue_trend,
        ),
        _kpi(
            "own_brand_share", "ratio", ratio(own, revenue), target(goals, "own_brand_share", days),
            ratio(ly_own, ly_revenue), bs, share_trend,
        ),
        _kpi(
            "credit_outstanding", "paise", book.outstanding_paise,
            target(goals, "credit_outstanding_paise", days), ly_book.outstanding_paise,
            bs, [b.outstanding_paise for b in books],
        ),
        _kpi(
            "credit_overdue", "paise", book.overdue_paise,
            target(goals, "credit_overdue_paise", days), ly_book.overdue_paise,
            bs, [b.overdue_paise for b in books],
        ),
        _kpi(
            "verified_visits", "count", len(verified), target(goals, "verified_visits", days),
            sum(1 for v in ly_visits if is_verified(v.score)), bs, verified_trend,
        ),
        _kpi(
            "active_farmers", "count", active_trend[-1] if active_trend else 0,
            target(goals, "active_farmers", days), ly_active, bs, active_trend,
        ),
        _kpi(
            "open_flags", "count", flag_counts.open_total, target(goals, "open_flags", days),
            ly_flags.open_total, bs, flag_trend,
        ),
    ]  # fmt: skip

    # Store map.
    by_store = await facts.sales_aggregate(session, scope, start, end, ["store_id", "own_brand"])
    store_rev: dict[uuid.UUID, int] = defaultdict(int)
    store_own: dict[uuid.UUID, int] = defaultdict(int)
    for r in by_store:
        store_rev[r.keys["store_id"]] += r.net_paise
        if r.keys["own_brand"]:
            store_own[r.keys["store_id"]] += r.net_paise
    entries_by_store: dict[uuid.UUID, list[Any]] = defaultdict(list)
    for e in entries:
        entries_by_store[e.store_id].append(e)
    store_targets = goals.get("store_revenue_paise")
    store_targets = store_targets if isinstance(store_targets, Mapping) else {}
    best = max((store_rev.get(s.id, 0) for s in scope.stores), default=0)
    stores: list[StoreMapItem] = []
    for s in scope.stores:
        rev = store_rev.get(s.id, 0)
        goal = target({"store": store_targets.get(str(s.id))}, "store", days)
        if goal:
            goal = goal * days / MONTH_DAYS
            score: int | None = min(100, round(100 * rev / goal))
        elif best > 0:
            score = round(100 * rev / best)
        else:
            score = None
        overdue = credit_book(entries_by_store.get(s.id, []), f.to, due_days, until=end)
        stores.append(
            StoreMapItem(
                id=s.id,
                code=s.code,
                name=s.name,
                district=s.district,
                cluster_id=s.cluster_id,
                lat=s.lat,
                lon=s.lon,
                revenue_paise=rev,
                own_brand_share=ratio(store_own.get(s.id, 0), rev),
                overdue_paise=overdue.overdue_paise,
                score=score,
                band=band(score),
            )
        )

    # Officers: verified visits per duty day.
    duty = await facts.duty_sessions(session, scope, start, end)
    duty_days: dict[uuid.UUID, set[date]] = defaultdict(set)
    for d in duty:
        duty_days[d.officer_id].add(d.day)
    verified_by: dict[uuid.UUID, int] = defaultdict(int)
    for v in verified:
        verified_by[v.officer_id] += 1
    ranked = rank_officers(scope, verified_by, {k: len(v) for k, v in duty_days.items()})

    notes = {"crop_health_alerts": "pending_an006"}
    if isinstance(flags, NullFlagCounts):
        notes["open_flags"] = "pending_flags_branch"
    return OwnerHomeOut(
        filters=scope.echo(),
        granularity=gran,
        kpis=kpis,
        credit_overdue_buckets=book.buckets,
        series=OwnerHomeSeries(
            revenue=points(bs, revenue_trend),
            revenue_last_year=points(ly_bs, ly_revenue_trend),
            own_brand_share=points(bs, share_trend),
        ),
        stores=stores,
        officers_top=ranked[:TOP_N],
        officers_bottom=list(reversed(ranked))[:TOP_N],
        high_severity_flags=[FlagOut.model_validate(h, from_attributes=True) for h in high],
        crop_health_alerts=[],
        notes=notes,
    )


__all__ = ["band", "owner_home", "rank_officers", "target", "targets_of", "tenant_settings"]
