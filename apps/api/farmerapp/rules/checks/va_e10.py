"""VA-E10 — cash variance at day close (ST-006), about the employee who closed the day.

* ``variance_above_threshold`` — |variance| above the tenant's
  ``day_close_variance_threshold_paise``. Event mode on ``day_close.variance`` (the day close
  dispatches ``CashVarianceDetected``; ``farmerapp.rules.events``) with the close as subject;
  the nightly batch re-checks closes of the last ``lookback_days`` (a missed event is still
  caught; the dedupe key never raises twice). One flag per close (key ``variance:<id>``).
* ``repeated_small_variances`` — batch only: at least ``min_small_variances`` closes by one
  employee within ``window_days`` with a variance between ``min_variance_paise`` and the
  threshold (small, so no auditor alert each time). One flag per employee and ISO week of
  the latest such close (key ``repeated:<YYYY-Www>``).

Only closes in status ``closed`` count (a reopened close is being corrected).
"""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import Select, select

from farmerapp.payments.models import DayClose, DayCloseStatus
from farmerapp.rules.checks.common import ist_day
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Mode, Subject
from farmerapp.tenants.settings import get_tenant_settings


def _closes(ctx: RuleContext) -> Select[tuple[DayClose]]:
    return select(DayClose).where(
        DayClose.tenant_id == ctx.tenant_id,
        DayClose.deleted_at.is_(None),
        DayClose.status == DayCloseStatus.CLOSED.value,
    )


@rule("VA-E10")
async def check(ctx: RuleContext) -> list[Finding]:
    threshold = (
        await get_tenant_settings(ctx.session, ctx.tenant_id)
    ).day_close_variance_threshold_paise
    today = ist_day(ctx.now)
    stmt = _closes(ctx)
    if ctx.subject_ids is not None:
        stmt = stmt.where(DayClose.id.in_(ctx.subject_ids))
    else:
        since = today - timedelta(days=int(ctx.param("lookback_days")))
        stmt = stmt.where(DayClose.business_date >= since)
    findings: list[Finding] = []
    for close in (await ctx.session.execute(stmt.order_by(DayClose.closed_at))).scalars():
        if abs(close.variance_paise) <= threshold:
            continue
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=close.closed_by,
                key=f"variance:{close.id}",
                title=f"Cash variance of Rs {close.variance_paise / 100:.2f} at day close",
                evidence=Evidence(
                    records=[
                        record("user", close.closed_by),
                        record("day_close", close.id),
                        record("store", close.store_id),
                    ],
                    metrics={
                        "reason": "variance_above_threshold",
                        "business_date": close.business_date.isoformat(),
                        "cash_expected_paise": close.cash_expected_paise,
                        "cash_counted_paise": close.cash_counted_paise,
                        "variance_paise": close.variance_paise,
                        "threshold_paise": threshold,
                    },
                ),
            )
        )
    if ctx.mode == Mode.BATCH:
        findings.extend(await _repeated(ctx, threshold))
    return findings


async def _repeated(ctx: RuleContext, threshold: int) -> list[Finding]:
    minimum = int(ctx.param("min_small_variances"))
    floor = int(ctx.param("min_variance_paise"))
    since = ist_day(ctx.now) - timedelta(days=int(ctx.param("window_days")))
    rows = await ctx.session.execute(
        _closes(ctx)
        .where(DayClose.business_date >= since)
        .order_by(DayClose.business_date, DayClose.id)
    )
    by_closer: dict[uuid.UUID, list[DayClose]] = {}
    for close in rows.scalars():
        if floor <= abs(close.variance_paise) <= threshold:
            by_closer.setdefault(close.closed_by, []).append(close)
    findings: list[Finding] = []
    for closer, closes in sorted(by_closer.items(), key=lambda kv: str(kv[0])):
        if len(closes) < minimum:
            continue
        latest = closes[-1].business_date.isocalendar()
        week = f"{latest.year}-W{latest.week:02d}"
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=closer,
                key=f"repeated:{week}",
                title=f"{len(closes)} small cash variances at day close in "
                f"{int(ctx.param('window_days'))} days",
                evidence=Evidence(
                    records=[record("user", closer)] + [record("day_close", c.id) for c in closes],
                    metrics={
                        "reason": "repeated_small_variances",
                        "variances_paise": [c.variance_paise for c in closes],
                        "net_variance_paise": sum(c.variance_paise for c in closes),
                        "business_dates": [c.business_date.isoformat() for c in closes],
                        "threshold_paise": threshold,
                        "min_small_variances": minimum,
                    },
                ),
            )
        )
    return findings
