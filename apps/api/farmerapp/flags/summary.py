"""AN-009 data quality: one summary of the validation flags the caller can see.

``GET /v1/flags/summary?days=`` replaces the console's browser-side roll-up of
``GET /v1/flags`` (the C70 "Data quality" tab), which could only summarise the page it had
fetched. The figures are over the flags **raised** in the window, in the caller's WC-010
inbox scope (``flags.service.flag_filters``):

* volume by rule and by subject type, with open / resolved and the severity split;
* resolution time (raised -> resolved) as median and p90 hours -- percentiles, not the mean,
  because a handful of flags left open over a weekend drags an average to nonsense;
* repeat subjects: a subject with ``REPEAT_MIN`` or more flags in the window (AN-009 "repeat
  offenders"), newest first;
* per rule, the VA-006 precision of the same window (true positives / resolutions labelled),
  so a rule that fires a lot and is usually wrong is visible in one line.

SPEC 5.3: P0 reads Postgres; the BigQuery marts ``mart_flags_weekly`` and
``mart_flag_repeat_offenders`` hold the same definitions for Looker Studio.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import datetime, timedelta

from sqlalchemy import ColumnElement, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.flags.models import LABELS, RESOLVED, UNRESOLVED, Flag, FlagLabel, FlagStatus
from farmerapp.flags.precision import PRECISION_FLOOR, WINDOW_WEEKS, rule_quality
from farmerapp.flags.schemas import (
    FlagSummaryOut,
    RepeatSubjectOut,
    RuleVolumeOut,
)
from farmerapp.flags.service import flag_filters
from farmerapp.payments.config import IST
from farmerapp.rules.loader import get_rule_set

#: AN-009 "repeat offenders": this many flags on one subject inside the window.
REPEAT_MIN = 2
REPEAT_LIMIT = 20
DEFAULT_DAYS = 90


def _percentile(values: list[float], q: float) -> float | None:
    """Nearest-rank percentile of a sorted-on-demand sample (``q`` in [0, 1])."""
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, round(q * (len(ordered) - 1))))
    return round(ordered[index], 2)


async def flag_summary(
    session: AsyncSession, actor: User, *, now: datetime, days: int = DEFAULT_DAYS
) -> FlagSummaryOut:
    today = now.astimezone(IST).date()
    since_day = today - timedelta(days=days - 1)
    since = datetime.combine(since_day, datetime.min.time(), tzinfo=IST)
    where: list[ColumnElement[bool]] = [
        Flag.deleted_at.is_(None),
        Flag.created_at >= since,
        *flag_filters(actor),
    ]
    rows = (
        await session.execute(
            select(
                Flag.rule_id,
                Flag.severity,
                Flag.status,
                Flag.subject_type,
                Flag.subject_id,
                Flag.created_at,
                Flag.resolved_at,
                Flag.sla_due_at,
                Flag.title,
            ).where(*where)
        )
    ).all()

    unresolved = {s.value for s in UNRESOLVED}
    resolved_statuses = {s.value for s in RESOLVED}
    by_severity: dict[str, int] = defaultdict(int)
    by_subject: dict[str, int] = defaultdict(int)
    per_rule: dict[str, dict[str, float | int]] = defaultdict(
        lambda: {"total": 0, "open": 0, "resolved": 0, "false_positives": 0}
    )
    rule_hours: dict[str, list[float]] = defaultdict(list)
    subjects: dict[tuple[str, uuid.UUID], RepeatSubjectOut] = {}
    hours: list[float] = []
    open_count = overdue = resolved_count = false_positives = 0

    for r in rows:
        by_severity[r.severity] += 1
        by_subject[r.subject_type] += 1
        bucket = per_rule[r.rule_id]
        bucket["total"] += 1
        if r.status in unresolved:
            open_count += 1
            bucket["open"] += 1
            overdue += r.sla_due_at < now
        if r.status in resolved_statuses and r.resolved_at is not None:
            resolved_count += 1
            bucket["resolved"] += 1
            elapsed = max((r.resolved_at - r.created_at).total_seconds() / 3600, 0.0)
            hours.append(elapsed)
            rule_hours[r.rule_id].append(elapsed)
            if LABELS.get(FlagStatus(r.status)) is FlagLabel.FALSE_POSITIVE:
                false_positives += 1
                bucket["false_positives"] += 1
        key = (r.subject_type, r.subject_id)
        seen = subjects.get(key)
        if seen is None:
            subjects[key] = RepeatSubjectOut(
                subject_type=r.subject_type,
                subject_id=r.subject_id,
                flags=1,
                rules=[r.rule_id],
                last_at=r.created_at,
                open_flags=1 if r.status in unresolved else 0,
                title=r.title,
            )
        else:
            seen.flags += 1
            seen.open_flags += r.status in unresolved
            if r.rule_id not in seen.rules:
                seen.rules.append(r.rule_id)
            if r.created_at > seen.last_at:
                seen.last_at, seen.title = r.created_at, r.title

    titles = {c.id: c.title for c in get_rule_set()}
    precision = {
        q.rule_id: q.four_weeks for q in await rule_quality(session, actor.tenant_id, now=now)
    }
    by_rule = [
        RuleVolumeOut(
            rule_id=rule_id,
            title=titles.get(rule_id),
            total=int(v["total"]),
            open=int(v["open"]),
            resolved=int(v["resolved"]),
            false_positives=int(v["false_positives"]),
            false_positive_rate=(
                round(v["false_positives"] / v["resolved"], 4) if v["resolved"] else None
            ),
            median_resolution_hours=_percentile(rule_hours.get(rule_id, []), 0.5),
            p90_resolution_hours=_percentile(rule_hours.get(rule_id, []), 0.9),
            precision=(None if rule_id not in precision else precision[rule_id].precision),
            precision_resolved=(0 if rule_id not in precision else precision[rule_id].resolved),
        )
        for rule_id, v in per_rule.items()
    ]
    by_rule.sort(key=lambda r: (-r.total, r.rule_id))
    repeats = sorted(
        (s for s in subjects.values() if s.flags >= REPEAT_MIN),
        key=lambda s: (-s.flags, -s.last_at.timestamp()),
    )[:REPEAT_LIMIT]

    return FlagSummaryOut(
        days=days,
        from_date=since_day,
        to_date=today,
        total=len(rows),
        open=open_count,
        resolved=resolved_count,
        overdue=overdue,
        by_severity=dict(sorted(by_severity.items())),
        by_subject_type=dict(sorted(by_subject.items())),
        by_rule=by_rule,
        median_resolution_hours=_percentile(hours, 0.5),
        p90_resolution_hours=_percentile(hours, 0.9),
        false_positive_rate=round(false_positives / resolved_count, 4) if resolved_count else None,
        repeat_min=REPEAT_MIN,
        repeat_subjects=repeats,
        precision_floor=PRECISION_FLOOR,
        precision_window_weeks=WINDOW_WEEKS,
    )


__all__ = ["DEFAULT_DAYS", "REPEAT_LIMIT", "REPEAT_MIN", "flag_summary"]
