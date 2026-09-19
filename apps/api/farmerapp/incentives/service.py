"""WC-009 targets, rule sets, payout preview, the monthly close and the FA-024 port function.

Metrics of an officer's month ``[start, end)`` (IST month boundaries), read from the live
tables:

* ``verified_visits`` — the officer's visits checked in within the month whose ``status`` is
  in the rule set's ``count_visit_statuses`` (VV-005: ``verified`` only by default);
  ``visits`` — every scored visit.
* ``new_farmers`` — farmers the officer registered in the month.
* ``sales_paise`` / ``own_brand_sales_paise`` / ``own_brand_share`` — orders the officer
  placed in the month that are placed and not cancelled (a cancelled order never counts);
  the own-brand split is by order-line value.
* ``collections_paise`` — payments the officer collected (received: paid, reconciled or cash
  pending reconciliation) in the month.
* ``cancelled_prior_sales_paise`` — orders the officer placed in an earlier month and that
  were cancelled in this one (the clawback base).

``incentive_for`` is the function the field-agent branch's ``IncentivePort`` delegates to
(FA-024 "My performance"): the frozen payout when the month is closed, else a live preview
with the active rule set, ``None`` without one.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, time
from typing import Any

from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, NotFoundError
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.campaigns.segments import PURCHASE_STATUSES
from farmerapp.catalog.models import Product, Sku
from farmerapp.farmers.models import Farmer
from farmerapp.incentives.models import (
    IncentivePayout,
    IncentiveRuleSet,
    RuleSetStatus,
    SalesTarget,
    TargetSubject,
)
from farmerapp.incentives.rules import Evaluation, Metrics, RuleDefinition, evaluate
from farmerapp.logging import get_logger
from farmerapp.orders.models import Order, OrderLine, OrderStatus, OrderStatusEvent
from farmerapp.payments.config import IST
from farmerapp.payments.models import RECEIVED_STATUSES, Payment
from farmerapp.visits.models import Visit

log = get_logger("farmerapp.incentives")

TARGET_FIELDS = (
    "visits_verified",
    "new_farmers",
    "sales_paise",
    "collections_paise",
    "own_brand_share_bp",
)


class InvalidRulesError(AppError):
    status = 422
    code = "invalid_incentive_rules"


class NoActiveRulesError(AppError):
    status = 409
    code = "no_active_incentive_rules"


# --------------------------------------------------------------------------- months
def month_start(value: date) -> date:
    return value.replace(day=1)


def next_month(value: date) -> date:
    first = value.replace(day=1)
    return (
        first.replace(year=first.year + 1, month=1)
        if first.month == 12
        else first.replace(month=first.month + 1)
    )


def ist_instant(day: date) -> datetime:
    return datetime.combine(day, time.min, tzinfo=IST).astimezone(UTC)


def month_bounds(month: date) -> tuple[datetime, datetime]:
    """``[start, end)`` in UTC of the IST calendar month containing ``month``."""
    first = month_start(month)
    return ist_instant(first), ist_instant(next_month(first))


def parse_definition(raw: dict[str, Any]) -> RuleDefinition:
    try:
        return RuleDefinition.model_validate(raw)
    except ValidationError as exc:
        raise InvalidRulesError(
            "The incentive rules are not valid.",
            extra={"errors": [{"loc": list(e["loc"]), "msg": e["msg"]} for e in exc.errors()]},
        ) from exc


# --------------------------------------------------------------------------- metrics
async def officer_metrics(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    officer_id: uuid.UUID,
    start: datetime,
    end: datetime,
    *,
    count_visit_statuses: Sequence[str] = ("verified",),
) -> Metrics:
    visit_base = [
        Visit.tenant_id == tenant_id,
        Visit.officer_id == officer_id,
        Visit.deleted_at.is_(None),
        Visit.checkin_at >= start,
        Visit.checkin_at < end,
    ]
    counted = await session.scalar(
        select(func.count()).where(*visit_base, Visit.status.in_(list(count_visit_statuses)))
    )
    scored = await session.scalar(select(func.count()).where(*visit_base, Visit.status != "open"))
    new_farmers = await session.scalar(
        select(func.count()).where(
            Farmer.tenant_id == tenant_id,
            Farmer.registered_by == officer_id,
            Farmer.deleted_at.is_(None),
            Farmer.created_at >= start,
            Farmer.created_at < end,
        )
    )
    orders = select(Order.id).where(
        Order.tenant_id == tenant_id,
        Order.placed_by == officer_id,
        Order.deleted_at.is_(None),
        Order.status.in_(PURCHASE_STATUSES),
        Order.placed_at >= start,
        Order.placed_at < end,
    )
    sales = await session.scalar(
        select(func.coalesce(func.sum(Order.total_paise), 0)).where(Order.id.in_(orders))
    )
    split = (
        await session.execute(
            select(
                func.coalesce(func.sum(OrderLine.line_total_paise), 0),
                func.coalesce(
                    func.sum(OrderLine.line_total_paise).filter(Product.own_brand.is_(True)), 0
                ),
            )
            .join(Sku, Sku.id == OrderLine.sku_id)
            .join(Product, Product.id == Sku.product_id)
            .where(OrderLine.order_id.in_(orders), OrderLine.deleted_at.is_(None))
        )
    ).one()
    lines_total, own_lines = int(split[0] or 0), int(split[1] or 0)
    collected_at = func.coalesce(Payment.paid_at, Payment.created_at)
    collections = await session.scalar(
        select(func.coalesce(func.sum(Payment.amount_paise), 0)).where(
            Payment.tenant_id == tenant_id,
            Payment.collected_by == officer_id,
            Payment.deleted_at.is_(None),
            Payment.status.in_([s.value for s in RECEIVED_STATUSES]),
            Payment.mode != "credit",
            collected_at >= start,
            collected_at < end,
        )
    )
    cancelled = await session.scalar(
        select(func.coalesce(func.sum(Order.total_paise), 0)).where(
            Order.tenant_id == tenant_id,
            Order.placed_by == officer_id,
            Order.status == OrderStatus.CANCELLED.value,
            Order.placed_at < start,
            Order.id.in_(
                select(OrderStatusEvent.order_id).where(
                    OrderStatusEvent.tenant_id == tenant_id,
                    OrderStatusEvent.to_status == OrderStatus.CANCELLED.value,
                    OrderStatusEvent.created_at >= start,
                    OrderStatusEvent.created_at < end,
                )
            ),
        )
    )
    own_sales = round(int(sales or 0) * own_lines / lines_total) if lines_total else 0
    return Metrics(
        verified_visits=int(counted or 0),
        visits=int(scored or 0),
        new_farmers=int(new_farmers or 0),
        sales_paise=int(sales or 0),
        own_brand_sales_paise=own_sales,
        own_brand_share=round(own_lines / lines_total, 6) if lines_total else None,
        collections_paise=int(collections or 0),
        cancelled_prior_sales_paise=int(cancelled or 0),
    )


# --------------------------------------------------------------------------- targets
async def target_for(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    subject_type: TargetSubject,
    subject_id: uuid.UUID,
    month: date,
) -> SalesTarget | None:
    return (
        await session.execute(
            select(SalesTarget).where(
                SalesTarget.tenant_id == tenant_id,
                SalesTarget.subject_type == subject_type.value,
                SalesTarget.subject_id == subject_id,
                SalesTarget.month == month_start(month),
                SalesTarget.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


def target_values(target: SalesTarget | None) -> dict[str, float | int | None]:
    """Targets keyed by metric name (own-brand share as a ratio)."""
    if target is None:
        return {}
    share = target.own_brand_share_bp
    return {
        "verified_visits": target.visits_verified,
        "new_farmers": target.new_farmers,
        "sales_paise": target.sales_paise,
        "collections_paise": target.collections_paise,
        "own_brand_share": share / 10_000 if share is not None else None,
    }


async def upsert_target(
    session: AsyncSession,
    actor: User,
    *,
    month: date,
    subject_type: TargetSubject,
    subject_id: uuid.UUID,
    values: dict[str, int | None],
) -> SalesTarget:
    row = await target_for(session, actor.tenant_id, subject_type, subject_id, month)
    if row is None:
        row = SalesTarget(
            tenant_id=actor.tenant_id,
            month=month_start(month),
            subject_type=subject_type.value,
            subject_id=subject_id,
        )
        session.add(row)
    for name in TARGET_FIELDS:
        if name in values:
            setattr(row, name, values[name])
    row.set_by = actor.id
    await session.flush()
    await session.refresh(row)  # server-side updated_at
    return row


# --------------------------------------------------------------------------- rule sets
async def active_rule_set(session: AsyncSession, tenant_id: uuid.UUID) -> IncentiveRuleSet | None:
    return (
        await session.execute(
            select(IncentiveRuleSet).where(
                IncentiveRuleSet.tenant_id == tenant_id,
                IncentiveRuleSet.status == RuleSetStatus.ACTIVE.value,
                IncentiveRuleSet.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def get_rule_set(
    session: AsyncSession, tenant_id: uuid.UUID, rule_set_id: uuid.UUID
) -> IncentiveRuleSet:
    row = (
        await session.execute(
            select(IncentiveRuleSet).where(
                IncentiveRuleSet.id == rule_set_id,
                IncentiveRuleSet.tenant_id == tenant_id,
                IncentiveRuleSet.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Incentive rule set not found.")
    return row


async def create_rule_set(
    session: AsyncSession, actor: User, *, name: str, definition: dict[str, Any], activate: bool
) -> IncentiveRuleSet:
    parsed = parse_definition(definition)
    latest = await session.scalar(
        select(func.max(IncentiveRuleSet.rule_version)).where(
            IncentiveRuleSet.tenant_id == actor.tenant_id
        )
    )
    row = IncentiveRuleSet(
        tenant_id=actor.tenant_id,
        name=name,
        rule_version=int(latest or 0) + 1,
        status=RuleSetStatus.DRAFT.value,
        definition=parsed.model_dump(mode="json", by_alias=True),
        created_by=actor.id,
    )
    session.add(row)
    await session.flush()
    if activate:
        await activate_rule_set(session, actor, row, now=datetime.now(UTC))
    return row


async def activate_rule_set(
    session: AsyncSession, actor: User, row: IncentiveRuleSet, *, now: datetime
) -> IncentiveRuleSet:
    current = (
        await session.execute(
            select(IncentiveRuleSet).where(
                IncentiveRuleSet.tenant_id == row.tenant_id,
                IncentiveRuleSet.status == RuleSetStatus.ACTIVE.value,
                IncentiveRuleSet.id != row.id,
            )
        )
    ).scalars()
    for previous in current:
        previous.status = RuleSetStatus.RETIRED.value
    await session.flush()  # the partial unique index allows one active set
    row.status = RuleSetStatus.ACTIVE.value
    row.activated_at = now
    row.activated_by = actor.id
    await session.flush()
    return row


# --------------------------------------------------------------------------- payouts
@dataclass(frozen=True)
class IncentiveResult:
    """What FA-024 and the WC-009 payout preview show for one officer and period."""

    officer_id: uuid.UUID
    period_start: date
    period_end: date  # exclusive
    status: str  # "preview" | "closed"
    rule_set_id: uuid.UUID | None
    rule_version: int | None
    eligible: bool
    metrics: dict[str, Any]
    targets: dict[str, Any]
    lines: list[dict[str, Any]]
    gross_paise: int
    clawback_paise: int
    amount_paise: int
    reasons: list[str] = field(default_factory=list)


def _result(
    officer_id: uuid.UUID,
    first: date,
    last: date,
    rules: IncentiveRuleSet,
    metrics: Metrics,
    targets: dict[str, Any],
    evaluation: Evaluation,
) -> IncentiveResult:
    return IncentiveResult(
        officer_id=officer_id,
        period_start=first,
        period_end=last,
        status="preview",
        rule_set_id=rules.id,
        rule_version=rules.rule_version,
        eligible=evaluation.eligible,
        metrics={
            **metrics.as_json(),
            "multiplier": evaluation.multiplier,
            "subtotal_paise": evaluation.subtotal_paise,
            "capped": evaluation.capped,
        },
        targets=targets,
        lines=[line.as_json() for line in evaluation.lines],
        gross_paise=evaluation.gross_paise,
        clawback_paise=evaluation.clawback_paise,
        amount_paise=evaluation.amount_paise,
        reasons=evaluation.reasons,
    )


async def compute(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    officer_id: uuid.UUID,
    first: date,
    last: date,
    rules: IncentiveRuleSet,
) -> IncentiveResult:
    """Live evaluation of ``rules`` for an officer over the IST days ``[first, last)``."""
    definition = parse_definition(rules.definition)
    metrics = await officer_metrics(
        session,
        tenant_id,
        officer_id,
        ist_instant(first),
        ist_instant(last),
        count_visit_statuses=definition.eligibility.count_visit_statuses,
    )
    target = await target_for(session, tenant_id, TargetSubject.OFFICER, officer_id, first)
    targets = target_values(target)
    evaluation = evaluate(definition, metrics, targets)
    return _result(officer_id, first, last, rules, metrics, targets, evaluation)


def frozen_result(payout: IncentivePayout) -> IncentiveResult:
    metrics = dict(payout.metrics or {})
    return IncentiveResult(
        officer_id=payout.officer_id,
        period_start=payout.month,
        period_end=next_month(payout.month),
        status="closed",
        rule_set_id=payout.rule_set_id,
        rule_version=payout.rule_version,
        eligible=payout.eligible,
        metrics={k: v for k, v in metrics.items() if k not in ("targets", "reasons")},
        targets=dict(metrics.get("targets") or {}),
        lines=list(payout.lines or []),
        gross_paise=payout.gross_paise,
        clawback_paise=payout.clawback_paise,
        amount_paise=payout.amount_paise,
        reasons=list(metrics.get("reasons") or []),
    )


async def payout_of(
    session: AsyncSession, tenant_id: uuid.UUID, officer_id: uuid.UUID, month: date
) -> IncentivePayout | None:
    return (
        await session.execute(
            select(IncentivePayout).where(
                IncentivePayout.tenant_id == tenant_id,
                IncentivePayout.officer_id == officer_id,
                IncentivePayout.month == month_start(month),
                IncentivePayout.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def preview(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    officer_id: uuid.UUID,
    month: date,
    *,
    rules: IncentiveRuleSet | None = None,
) -> IncentiveResult:
    """The frozen payout of a closed month; else the live preview (``rules`` or active)."""
    first = month_start(month)
    if rules is None:
        payout = await payout_of(session, tenant_id, officer_id, first)
        if payout is not None:
            return frozen_result(payout)
        rules = await active_rule_set(session, tenant_id)
        if rules is None:
            raise NoActiveRulesError("No incentive rule set is active.")
    return await compute(session, tenant_id, officer_id, first, next_month(first), rules)


async def incentive_for(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    officer_id: uuid.UUID,
    period_start: date | datetime,
    period_end: date | datetime,
) -> IncentiveResult | None:
    """FA-024 ``IncentivePort`` implementation.

    ``period_start`` inclusive, ``period_end`` exclusive (IST dates; datetimes are converted
    to their IST date). A whole calendar month that is closed returns the frozen payout;
    otherwise the active rule set is evaluated live over the period. ``None`` when no rule set
    is active (or the officer does not exist in the tenant)."""
    first = (
        period_start.astimezone(IST).date() if isinstance(period_start, datetime) else period_start
    )
    last = period_end.astimezone(IST).date() if isinstance(period_end, datetime) else period_end
    officer = await session.get(User, officer_id)
    if officer is None or officer.tenant_id != tenant_id:
        return None
    if first.day == 1 and last == next_month(first):
        payout = await payout_of(session, tenant_id, officer_id, first)
        if payout is not None:
            return frozen_result(payout)
    rules = await active_rule_set(session, tenant_id)
    if rules is None:
        return None
    return await compute(session, tenant_id, officer_id, first, last, rules)


@dataclass
class CloseReport:
    tenant_id: uuid.UUID
    month: date
    closed: list[uuid.UUID] = field(default_factory=list)
    already_closed: int = 0
    total_paise: int = 0
    rule_version: int | None = None


async def close_month(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    month: date,
    now: datetime,
    closed_by: uuid.UUID | None = None,
) -> CloseReport:
    """Freeze every field officer's result for ``month`` (idempotent: a frozen officer-month
    is never recomputed). Raises ``no_active_incentive_rules`` without an active set."""
    first = month_start(month)
    if now < ist_instant(next_month(first)):
        raise AppError(
            "A month can be closed once it has ended.", status=409, code="incentive_month_open"
        )
    rules = await active_rule_set(session, tenant_id)
    if rules is None:
        raise NoActiveRulesError("No incentive rule set is active.")
    report = CloseReport(tenant_id=tenant_id, month=first, rule_version=rules.rule_version)
    officers = (
        await session.execute(
            select(User.id)
            .where(
                User.tenant_id == tenant_id,
                User.role == UserRole.FIELD_OFFICER.value,
                User.deleted_at.is_(None),
                User.status == UserStatus.ACTIVE.value,
            )
            .order_by(User.id)
        )
    ).scalars()
    for officer_id in officers:
        if await payout_of(session, tenant_id, officer_id, first) is not None:
            report.already_closed += 1
            continue
        result = await compute(session, tenant_id, officer_id, first, next_month(first), rules)
        session.add(
            IncentivePayout(
                tenant_id=tenant_id,
                officer_id=officer_id,
                month=first,
                rule_set_id=rules.id,
                rule_version=rules.rule_version,
                eligible=result.eligible,
                metrics={**result.metrics, "targets": result.targets, "reasons": result.reasons},
                lines=result.lines,
                gross_paise=result.gross_paise,
                clawback_paise=result.clawback_paise,
                amount_paise=result.amount_paise,
                closed_at=now,
                closed_by=closed_by,
            )
        )
        report.closed.append(officer_id)
        report.total_paise += result.amount_paise
    await session.flush()
    log.info(
        "incentives_closed",
        tenant_id=str(tenant_id),
        month=first.isoformat(),
        officers=len(report.closed),
        already_closed=report.already_closed,
        total_paise=report.total_paise,
        rule_version=rules.rule_version,
    )
    return report


__all__ = [
    "CloseReport",
    "IncentiveResult",
    "InvalidRulesError",
    "NoActiveRulesError",
    "activate_rule_set",
    "active_rule_set",
    "close_month",
    "compute",
    "create_rule_set",
    "incentive_for",
    "month_bounds",
    "month_start",
    "next_month",
    "officer_metrics",
    "payout_of",
    "preview",
    "target_for",
    "target_values",
    "upsert_target",
]
