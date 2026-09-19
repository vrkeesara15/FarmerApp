"""VA-E04 — short visits: more than ``max_short_share`` of an officer's checked-out visits of
one IST day lasted less than the tenant's minimum visit duration.

The minimum is the tenant setting ``min_visit_duration_s`` (FA-017; the same threshold that
marks a single visit ``under_minimum``), so a tenant tunes both in one place; the rule's
own params only say how many short visits make a pattern. ``duration_s`` is the database's
generated ``checkout_at - checkin_at``; open visits are not judged, and a day with fewer
than ``min_visits`` checked-out visits is too small to call.

Batch (nightly): visits checked in during the last ``lookback_hours``. One flag per officer
and IST day (key ``short:<day>``).

Params: ``max_short_share``, ``min_visits``, ``lookback_hours``.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import select

from farmerapp.db.models.tenant import Tenant
from farmerapp.rules.checks.common import ist_day
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.settings import tenant_settings
from farmerapp.visits.models import Visit


@rule("VA-E04")
async def check(ctx: RuleContext) -> list[Finding]:
    max_share = float(ctx.param("max_short_share"))
    min_visits = int(ctx.param("min_visits"))
    since = ctx.now - timedelta(hours=float(ctx.param("lookback_hours")))
    raw = await ctx.session.scalar(select(Tenant.settings).where(Tenant.id == ctx.tenant_id))
    minimum = tenant_settings(raw).min_visit_duration_s
    rows = await ctx.session.execute(
        select(Visit.id, Visit.officer_id, Visit.checkin_at, Visit.duration_s)
        .where(
            Visit.tenant_id == ctx.tenant_id,
            Visit.deleted_at.is_(None),
            Visit.checkin_at >= since,
            Visit.checkin_at <= ctx.now,
            Visit.duration_s.is_not(None),
        )
        .order_by(Visit.checkin_at, Visit.id)
    )
    days: dict[tuple[uuid.UUID, str], list[tuple[uuid.UUID, int]]] = {}
    for visit_id, officer, at, duration in rows.tuples():
        if duration is not None:
            days.setdefault((officer, ist_day(at).isoformat()), []).append((visit_id, duration))
    findings: list[Finding] = []
    for (officer, day), visits in sorted(days.items(), key=str):
        short = [(v, d) for v, d in visits if d < minimum]
        share = len(short) / len(visits)
        if len(visits) < min_visits or share <= max_share:
            continue
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"short:{day}",
                title=f"{len(short)} of {len(visits)} visits shorter than {minimum // 60} min",
                evidence=Evidence(
                    records=[record("user", officer)] + [record("visit", v) for v, _d in short],
                    metrics={
                        "reason": "short_visits",
                        "day": day,
                        "visits": len(visits),
                        "short_visits": len(short),
                        "short_share": round(share, 3),
                        "max_short_share": max_share,
                        "min_visit_duration_s": minimum,
                        "short_durations_s": [d for _v, d in short],
                    },
                ),
            )
        )
    return findings
