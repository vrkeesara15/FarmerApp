"""VA-006 rule precision: how often a rule's flags turn out to be real, per tenant.

Every resolution records a label on its ``flag_event`` (``flags.models.LABELS``):
``resolved_valid`` (the data was fine — the rule was wrong) is a **false positive**;
``resolved_fixed`` / ``resolved_action`` are **true positives**. Precision is
``TP / (TP + FP)`` over the resolutions in a window (by resolution time), per rule.

* ``weekly_quality_report`` — ``python -m farmerapp.jobs rules-quality-report`` (weekly,
  Monday 03:00 IST): the last week's and the last four weeks' TP / FP / precision, flags
  raised and still open per rule, as one ``rule_quality_report`` notification to every
  tenant admin (the owner when the tenant has none).
* **Auto-disable** — a rule enabled for the tenant whose four-week precision is under
  ``PRECISION_FLOOR`` (30 %) with at least ``MIN_RESOLVED`` resolutions is switched off for
  the tenant (``rule_tenant_override`` enabled = false, source ``auto_precision``, the
  reason with the numbers) *pending review*; the change is audited (``rule.auto_disable``)
  and listed in the report. The engine skips it from the next run.
* **Re-enable** — ``POST /v1/flags/rules/{rule_id}/enable`` (owner / tenant admin, step-up):
  ``enable_rule`` sets the override back to enabled (source ``admin``, reason required,
  audited ``rule.enable``). Its precision window restarts at that moment, so the same old
  resolutions cannot disable it again the next week.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import ConflictError, NotFoundError
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import job_session
from farmerapp.flags.models import (
    UNRESOLVED,
    Flag,
    FlagEvent,
    FlagEventKind,
    FlagLabel,
    OverrideSource,
    RuleTenantOverride,
)
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification
from farmerapp.rules.engine import DISABLED_CACHE
from farmerapp.rules.loader import RuleSet, get_rule_set

log = get_logger("farmerapp.flags.precision")

PRECISION_FLOOR = 0.30
WINDOW_WEEKS = 4
MIN_RESOLVED = 5
REPORT_KIND = "rule_quality_report"

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]


class RuleNotDisabledError(ConflictError):
    code = "rule_not_disabled"


@dataclass
class RulePrecision:
    true_positive: int = 0
    false_positive: int = 0

    @property
    def resolved(self) -> int:
        return self.true_positive + self.false_positive

    @property
    def precision(self) -> float | None:
        return self.true_positive / self.resolved if self.resolved else None

    def as_json(self) -> dict[str, Any]:
        p = self.precision
        return {
            "true_positive": self.true_positive,
            "false_positive": self.false_positive,
            "resolved": self.resolved,
            "precision": round(p, 4) if p is not None else None,
        }


async def label_counts(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    since: datetime,
    until: datetime,
    restart: dict[str, datetime] | None = None,
) -> dict[str, RulePrecision]:
    """TP / FP per rule over the resolutions in ``[since, until)``; ``restart`` moves the
    start of one rule's window later (re-enabled by an admin)."""
    rows = await session.execute(
        select(Flag.rule_id, FlagEvent.label, FlagEvent.created_at)
        .join(Flag, Flag.id == FlagEvent.flag_id)
        .where(
            FlagEvent.tenant_id == tenant_id,
            FlagEvent.kind == FlagEventKind.TRANSITION.value,
            FlagEvent.label.is_not(None),
            FlagEvent.created_at >= since,
            FlagEvent.created_at < until,
            Flag.deleted_at.is_(None),
        )
    )
    out: dict[str, RulePrecision] = {}
    for rule_id, label, at in rows.tuples():
        start = (restart or {}).get(rule_id)
        if start is not None and at < start:
            continue
        counts = out.setdefault(rule_id, RulePrecision())
        if label == FlagLabel.TRUE_POSITIVE.value:
            counts.true_positive += 1
        elif label == FlagLabel.FALSE_POSITIVE.value:
            counts.false_positive += 1
    return out


@dataclass
class RuleQuality:
    rule_id: str
    version: int | None
    title: str | None
    week: RulePrecision
    four_weeks: RulePrecision
    raised_this_week: int
    open_now: int
    enabled: bool
    disabled_reason: str | None = None

    def as_json(self) -> dict[str, Any]:
        return {
            "rule_id": self.rule_id,
            "version": self.version,
            "title": self.title,
            "week": self.week.as_json(),
            "four_weeks": self.four_weeks.as_json(),
            "raised_this_week": self.raised_this_week,
            "open_now": self.open_now,
            "enabled": self.enabled,
            "disabled_reason": self.disabled_reason,
        }


@dataclass
class QualityReport:
    tenant_id: uuid.UUID
    week_start: datetime
    week_end: datetime
    rules: list[RuleQuality] = field(default_factory=list)
    auto_disabled: list[str] = field(default_factory=list)
    notified: list[uuid.UUID] = field(default_factory=list)

    def as_json(self) -> dict[str, Any]:
        return {
            "week_start": self.week_start.isoformat(),
            "week_end": self.week_end.isoformat(),
            "rules": [r.as_json() for r in self.rules],
            "auto_disabled": self.auto_disabled,
        }


async def overrides_of(
    session: AsyncSession, tenant_id: uuid.UUID
) -> dict[str, RuleTenantOverride]:
    rows = await session.scalars(
        select(RuleTenantOverride).where(
            RuleTenantOverride.tenant_id == tenant_id, RuleTenantOverride.deleted_at.is_(None)
        )
    )
    return {r.rule_id: r for r in rows}


async def rule_quality(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    now: datetime,
    rule_set: RuleSet | None = None,
) -> list[RuleQuality]:
    """Per rule of the rule set: last week's and the last four weeks' precision."""
    rules = rule_set or get_rule_set()
    slug = await session.scalar(select(Tenant.slug).where(Tenant.id == tenant_id))
    overrides = await overrides_of(session, tenant_id)
    restart = {
        rid: o.set_at
        for rid, o in overrides.items()
        if o.enabled and o.source == OverrideSource.ADMIN.value
    }
    week = await label_counts(
        session, tenant_id, since=now - timedelta(days=7), until=now, restart=restart
    )
    four = await label_counts(
        session,
        tenant_id,
        since=now - timedelta(weeks=WINDOW_WEEKS),
        until=now,
        restart=restart,
    )
    raised = dict(
        (
            await session.execute(
                select(Flag.rule_id, func.count())
                .where(
                    Flag.tenant_id == tenant_id,
                    Flag.deleted_at.is_(None),
                    Flag.created_at >= now - timedelta(days=7),
                    Flag.created_at < now,
                )
                .group_by(Flag.rule_id)
            )
        )
        .tuples()
        .all()
    )
    open_now = dict(
        (
            await session.execute(
                select(Flag.rule_id, func.count())
                .where(
                    Flag.tenant_id == tenant_id,
                    Flag.deleted_at.is_(None),
                    Flag.status.in_([s.value for s in UNRESOLVED]),
                )
                .group_by(Flag.rule_id)
            )
        )
        .tuples()
        .all()
    )
    out: list[RuleQuality] = []
    for config in rules:
        override = overrides.get(config.id)
        disabled = override is not None and not override.enabled
        out.append(
            RuleQuality(
                rule_id=config.id,
                version=config.version,
                title=config.title,
                week=week.get(config.id, RulePrecision()),
                four_weeks=four.get(config.id, RulePrecision()),
                raised_this_week=int(raised.get(config.id, 0)),
                open_now=int(open_now.get(config.id, 0)),
                enabled=config.enabled_for(slug) and not disabled,
                disabled_reason=override.reason if disabled and override else None,
            )
        )
    return out


def _forget_disabled(session: AsyncSession, tenant_id: uuid.UUID) -> None:
    cache = session.info.get(DISABLED_CACHE)
    if isinstance(cache, dict):
        cache.pop(tenant_id, None)


async def _set_override(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    rule_id: str,
    *,
    enabled: bool,
    source: OverrideSource,
    reason: str,
    now: datetime,
    set_by: uuid.UUID | None,
    version: int | None,
    precision: float | None = None,
    resolved: int | None = None,
    action: str,
) -> RuleTenantOverride:
    row = (
        await session.execute(
            select(RuleTenantOverride).where(
                RuleTenantOverride.tenant_id == tenant_id, RuleTenantOverride.rule_id == rule_id
            )
        )
    ).scalar_one_or_none()
    before = (
        {"enabled": row.enabled, "source": row.source, "reason": row.reason}
        if row is not None
        else None
    )
    if row is None:
        row = RuleTenantOverride(tenant_id=tenant_id, rule_id=rule_id)
        session.add(row)
    row.enabled = enabled
    row.source = source.value
    row.reason = reason
    row.rule_version = version
    row.precision = Decimal(str(round(precision, 4))) if precision is not None else None
    row.resolved_count = resolved
    row.set_by = set_by
    row.set_at = now
    row.deleted_at = None
    await session.flush()
    audit.record(
        session,
        action=action,
        entity="rule_tenant_override",
        entity_id=row.id,
        tenant_id=tenant_id,
        before=before,
        after={"rule_id": rule_id, "enabled": enabled, "source": source.value, "reason": reason},
    )
    _forget_disabled(session, tenant_id)
    return row


async def _admins(session: AsyncSession, tenant_id: uuid.UUID) -> list[uuid.UUID]:
    for role in (UserRole.TENANT_ADMIN, UserRole.OWNER):
        ids = list(
            await session.scalars(
                select(User.id)
                .where(
                    User.tenant_id == tenant_id,
                    User.role == role.value,
                    User.status == UserStatus.ACTIVE.value,
                    User.deleted_at.is_(None),
                )
                .order_by(User.created_at, User.id)
            )
        )
        if ids:
            return ids
    return []


async def weekly_quality_report(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    now: datetime,
    rule_set: RuleSet | None = None,
    floor: float = PRECISION_FLOOR,
    min_resolved: int = MIN_RESOLVED,
) -> QualityReport:
    """The weekly rule-quality report of one tenant; auto-disables low-precision rules."""
    rows = await rule_quality(session, tenant_id, now=now, rule_set=rule_set)
    report = QualityReport(
        tenant_id=tenant_id, week_start=now - timedelta(days=7), week_end=now, rules=rows
    )
    for row in rows:
        p = row.four_weeks.precision
        if not row.enabled or p is None or row.four_weeks.resolved < min_resolved or p >= floor:
            continue
        reason = (
            f"Precision {p:.0%} ({row.four_weeks.true_positive} confirmed of "
            f"{row.four_weeks.resolved} resolved) over {WINDOW_WEEKS} weeks is below "
            f"{floor:.0%}: disabled pending review."
        )
        await _set_override(
            session,
            tenant_id,
            row.rule_id,
            enabled=False,
            source=OverrideSource.AUTO_PRECISION,
            reason=reason,
            now=now,
            set_by=None,
            version=row.version,
            precision=p,
            resolved=row.four_weeks.resolved,
            action="rule.auto_disable",
        )
        row.enabled, row.disabled_reason = False, reason
        report.auto_disabled.append(row.rule_id)
        log.warning(
            "rule_auto_disabled",
            tenant_id=str(tenant_id),
            rule_id=row.rule_id,
            precision=round(p, 4),
            resolved=row.four_weeks.resolved,
        )
    data = report.as_json()
    for user_id in await _admins(session, tenant_id):
        session.add(
            Notification(
                tenant_id=tenant_id,
                user_id=user_id,
                kind=REPORT_KIND,
                title_key=f"notification.{REPORT_KIND}.title",
                body_key=f"notification.{REPORT_KIND}.body",
                data=data,
            )
        )
        report.notified.append(user_id)
    await session.flush()
    log.info(
        "rule_quality_report",
        tenant_id=str(tenant_id),
        rules=len(rows),
        auto_disabled=report.auto_disabled,
        notified=len(report.notified),
    )
    return report


async def enable_rule(
    session: AsyncSession,
    actor: User,
    rule_id: str,
    reason: str,
    *,
    now: datetime,
    rule_set: RuleSet | None = None,
) -> RuleTenantOverride:
    """An admin re-enables a rule the tenant had switched off (audited ``rule.enable``)."""
    rules = rule_set or get_rule_set()
    if rule_id not in rules.rules:
        raise NotFoundError("Rule not found.")
    current = (await overrides_of(session, actor.tenant_id)).get(rule_id)
    if current is None:  # never switched off for this tenant: nothing to re-enable
        raise NotFoundError("This rule has no runtime override for the tenant.")
    if current.enabled:
        raise RuleNotDisabledError("This rule is not disabled for the tenant.")
    return await _set_override(
        session,
        actor.tenant_id,
        rule_id,
        enabled=True,
        source=OverrideSource.ADMIN,
        reason=reason,
        now=now,
        set_by=actor.id,
        version=rules.get(rule_id).version,
        action="rule.enable",
    )


async def run_quality_reports(
    tenant_ids: Iterable[uuid.UUID],
    *,
    now: datetime | None = None,
    session_provider: SessionProvider = job_session,
    rule_set: RuleSet | None = None,
) -> list[QualityReport]:
    """``python -m farmerapp.jobs rules-quality-report``: one transaction per tenant."""
    now = now or datetime.now(UTC)
    out: list[QualityReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with session_provider(tenant_id) as session:
                out.append(
                    await weekly_quality_report(session, tenant_id, now=now, rule_set=rule_set)
                )
    return out


__all__ = [
    "MIN_RESOLVED",
    "PRECISION_FLOOR",
    "REPORT_KIND",
    "WINDOW_WEEKS",
    "QualityReport",
    "RuleNotDisabledError",
    "RulePrecision",
    "RuleQuality",
    "enable_rule",
    "label_counts",
    "rule_quality",
    "run_quality_reports",
    "weekly_quality_report",
]
