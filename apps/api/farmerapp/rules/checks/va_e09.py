"""VA-E09 — sales anomalies of the employee who placed the sale (``order.placed_by``).

* ``discount_above_policy`` — ``discount_paise`` above the tenant's
  ``discount_policy_max_bps`` of ``subtotal_paise``;
* ``sale_to_staff_phone`` — the order's farmer has the phone of a staff account (any active
  or disabled non-farmer user of the tenant; compared by SEC-026 phone hash, never plain);
* ``cancellations_after_cutoff`` — at least ``min_cancellations_after_cutoff`` of the
  employee's orders placed in an incentive period (from the previous cut-off to the
  tenant's ``incentive_cutoff_day`` of the month, IST) were cancelled after that cut-off,
  i.e. after they counted for the incentive.

Batch (nightly). The first two: orders placed in the last ``lookback_hours``, one flag per
employee and IST day (key ``sales:<day>``) listing the orders. The third: cancellations of
the last ``cancellation_lookback_days``, one flag per employee and incentive period
(key ``cancellations:<YYYY-MM>``). High severity: cluster head plus auditors.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, time, timedelta

from sqlalchemy import func, select

from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.models import Farmer
from farmerapp.orders.models import Order, OrderStatus, OrderStatusEvent
from farmerapp.pii.crypto import phone_hash
from farmerapp.rules.checks.common import IST, ist_day
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.settings import get_tenant_settings


def cutoff_moment(day: date, cutoff_day: int) -> datetime:
    """The incentive cut-off of ``day``'s month (start of the cut-off day, IST)."""
    return datetime.combine(day.replace(day=cutoff_day), time(0), tzinfo=IST)


def previous_cutoff(moment: datetime, cutoff_day: int) -> datetime:
    first = moment.astimezone(IST).date().replace(day=1)
    return cutoff_moment(first - timedelta(days=1), cutoff_day)


async def _staff(ctx: RuleContext) -> tuple[set[uuid.UUID], set[str]]:
    rows = await ctx.session.execute(
        select(User.id, User.phone_hash, User.phone_plain).where(
            User.tenant_id == ctx.tenant_id,
            User.role != UserRole.FARMER.value,
            User.deleted_at.is_(None),
        )
    )
    ids: set[uuid.UUID] = set()
    hashes: set[str] = set()
    for uid, hashed, plain in rows.tuples():
        ids.add(uid)
        if hashed or plain:
            hashes.add(hashed or phone_hash(plain or ""))
    return ids, hashes


@rule("VA-E09")
async def check(ctx: RuleContext) -> list[Finding]:
    settings = await get_tenant_settings(ctx.session, ctx.tenant_id)
    max_bps = settings.discount_policy_max_bps
    cutoff_day = settings.incentive_cutoff_day
    since = ctx.now - timedelta(hours=float(ctx.param("lookback_hours")))
    staff_ids, staff_hashes = await _staff(ctx)
    placed = func.coalesce(Order.placed_at, Order.created_at)
    orders = (
        await ctx.session.execute(
            select(
                Order.id,
                Order.placed_by,
                Order.farmer_id,
                Order.subtotal_paise,
                Order.discount_paise,
                placed,
                Farmer.phone_hash,
                Farmer.phone_plain,
            )
            .outerjoin(Farmer, Farmer.id == Order.farmer_id)
            .where(
                Order.tenant_id == ctx.tenant_id,
                Order.deleted_at.is_(None),
                Order.placed_by.is_not(None),
                Order.status != OrderStatus.DRAFT.value,
                placed >= since,
                placed <= ctx.now,
            )
            .order_by(placed, Order.id)
        )
    ).tuples()
    days: dict[tuple[uuid.UUID, str], dict[str, list[tuple[uuid.UUID, uuid.UUID | None, int]]]] = {}
    for order_id, seller, farmer_id, subtotal, discount, at, f_hash, f_plain in orders:
        if seller is None or seller not in staff_ids:
            continue
        bucket = days.setdefault((seller, ist_day(at).isoformat()), {})
        if subtotal > 0 and discount * 10_000 > max_bps * subtotal:
            bps = discount * 10_000 // subtotal
            bucket.setdefault("discount_above_policy", []).append((order_id, farmer_id, bps))
        hashed = f_hash or (phone_hash(f_plain) if f_plain else None)
        if farmer_id is not None and hashed is not None and hashed in staff_hashes:
            bucket.setdefault("sale_to_staff_phone", []).append((order_id, farmer_id, 0))
    findings: list[Finding] = []
    for (seller, day), reasons in sorted(days.items(), key=str):
        if not reasons:
            continue
        orders_cited = sorted({o for items in reasons.values() for o, _f, _b in items}, key=str)
        farmers_cited = sorted(
            {f for items in reasons.values() for _o, f, _b in items if f is not None}, key=str
        )
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=seller,
                key=f"sales:{day}",
                title="Sales anomalies: " + ", ".join(r.replace("_", " ") for r in sorted(reasons)),
                evidence=Evidence(
                    records=[record("user", seller)]
                    + [record("order", o) for o in orders_cited]
                    + [record("farmer", f) for f in farmers_cited],
                    metrics={
                        "reasons": sorted(reasons),
                        "day": day,
                        "discount_policy_max_bps": max_bps,
                        "discounts_bps": {
                            str(o): b for o, _f, b in reasons.get("discount_above_policy", [])
                        },
                        "staff_phone_orders": [
                            str(o) for o, _f, _b in reasons.get("sale_to_staff_phone", [])
                        ],
                    },
                ),
            )
        )
    findings.extend(await _cancellations(ctx, staff_ids, cutoff_day))
    return findings


async def _cancellations(
    ctx: RuleContext, staff_ids: set[uuid.UUID], cutoff_day: int
) -> list[Finding]:
    minimum = int(ctx.param("min_cancellations_after_cutoff"))
    since = ctx.now - timedelta(days=float(ctx.param("cancellation_lookback_days")))
    placed = func.coalesce(Order.placed_at, Order.created_at)
    rows = await ctx.session.execute(
        select(Order.id, Order.placed_by, placed, OrderStatusEvent.created_at)
        .join(OrderStatusEvent, OrderStatusEvent.order_id == Order.id)
        .where(
            Order.tenant_id == ctx.tenant_id,
            Order.placed_by.is_not(None),
            OrderStatusEvent.to_status == OrderStatus.CANCELLED.value,
            OrderStatusEvent.created_at >= since,
            OrderStatusEvent.created_at <= ctx.now,
        )
        .order_by(OrderStatusEvent.created_at, Order.id)
    )
    periods: dict[tuple[uuid.UUID, str], list[tuple[uuid.UUID, datetime, datetime]]] = {}
    for order_id, seller, placed_at, cancelled_at in rows.tuples():
        if seller is None or seller not in staff_ids:
            continue
        cancel_day = ist_day(cancelled_at)
        cut = cutoff_moment(cancel_day, cutoff_day)
        if cancelled_at < cut:
            cut = previous_cutoff(cut, cutoff_day)  # cancelled before this month's cut-off
        start = previous_cutoff(cut, cutoff_day)
        if not (start <= placed_at < cut <= cancelled_at):
            continue
        period = cut.astimezone(IST).strftime("%Y-%m")
        periods.setdefault((seller, period), []).append((order_id, placed_at, cancelled_at))
    findings: list[Finding] = []
    for (seller, period), items in sorted(periods.items(), key=str):
        if len(items) < minimum:
            continue
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=seller,
                key=f"cancellations:{period}",
                title=f"{len(items)} orders cancelled after the {period} incentive cut-off",
                evidence=Evidence(
                    records=[record("user", seller)] + [record("order", o) for o, _p, _c in items],
                    metrics={
                        "reason": "cancellations_after_cutoff",
                        "period": period,
                        "incentive_cutoff_day": cutoff_day,
                        "cancellations": len(items),
                        "min_cancellations_after_cutoff": minimum,
                    },
                ),
            )
        )
    return findings
