"""VA-E11 — performance drift (coaching): an officer's verified visits (VV-005 status
``verified``) fell by more than ``max_drop_share`` week on week for two weeks running.

The three complete IST weeks (Monday to Sunday) before the current one are compared:
``w3 -> w2`` and ``w2 -> w1`` must both drop by more than the share, and ``w3`` needs at
least ``min_base_visits`` (a handful of visits is too small to call a trend). Low severity:
a coaching prompt for the cluster head, not a suspicion.

Batch (nightly; the result only changes on Mondays). One flag per officer and week (key
``drift:<Monday of w1>``).
"""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import date, timedelta

from sqlalchemy import select

from farmerapp.rules.checks.common import ist_day, ist_day_bounds
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.visits.models import Visit, VisitStatus


@rule("VA-E11")
async def check(ctx: RuleContext) -> list[Finding]:
    max_drop = float(ctx.param("max_drop_share"))
    min_base = int(ctx.param("min_base_visits"))
    today = ist_day(ctx.now)
    this_monday = today - timedelta(days=today.weekday())
    mondays: list[date] = [this_monday - timedelta(weeks=n) for n in (3, 2, 1)]  # w3, w2, w1
    start, _ = ist_day_bounds(mondays[0])
    end, _ = ist_day_bounds(this_monday)
    stmt = select(Visit.officer_id, Visit.checkin_at).where(
        Visit.tenant_id == ctx.tenant_id,
        Visit.deleted_at.is_(None),
        Visit.status == VisitStatus.VERIFIED.value,
        Visit.checkin_at >= start,
        Visit.checkin_at < end,
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(Visit.officer_id.in_(ctx.subject_ids))
    counts: dict[uuid.UUID, Counter[date]] = {}
    for officer, at in (await ctx.session.execute(stmt)).tuples():
        day = ist_day(at)
        counts.setdefault(officer, Counter())[day - timedelta(days=day.weekday())] += 1
    findings: list[Finding] = []
    for officer, weeks in sorted(counts.items(), key=lambda kv: str(kv[0])):
        w3, w2, w1 = (weeks[m] for m in mondays)
        if w3 < min_base:
            continue
        drop1 = (w3 - w2) / w3
        drop2 = (w2 - w1) / w2 if w2 else 1.0
        if drop1 <= max_drop or drop2 <= max_drop:
            continue
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=officer,
                key=f"drift:{mondays[2].isoformat()}",
                title=f"Verified visits down two weeks running: {w3} -> {w2} -> {w1}",
                evidence=Evidence(
                    records=[record("user", officer)],
                    metrics={
                        "reason": "performance_drift",
                        "weeks": [m.isoformat() for m in mondays],
                        "verified_visits": [w3, w2, w1],
                        "drops": [round(drop1, 3), round(drop2, 3)],
                        "max_drop_share": max_drop,
                    },
                ),
            )
        )
    return findings
