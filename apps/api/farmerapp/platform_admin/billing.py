"""WC-014 billing: a monthly usage statement per tenant, as a record and as CSV.

A statement is a **frozen snapshot**: the counters as they stood when it was generated, the
plan and its prices as they stood then, and the arithmetic done once. Re-reading a statement
must never re-derive a number, because the counters keep moving and an invoice that changes
after it was sent is not an invoice. Regenerating a period replaces the row and says so in
the audit trail.

Money is integer paise throughout (CLAUDE.md). One line per metric:

    used        the counter for the period (monthly metrics) or the standing head count
    included    the plan limit (``null`` = unlimited, so never any overage)
    overage     max(used - included, 0)
    unit_price  the plan's price for one unit over the limit, paise
    amount      overage x unit_price

plus the plan's monthly ``base_price_paise``. The total is base + the sum of the line amounts.

**Payment integration is a port, not an implementation.** Charging a tenant means a real
money movement against a real merchant account; SPEC 0.2 names Razorpay for *farmer* payments
(FA-021), and platform billing is a different contract with a different entity, so no provider
is wired here. ``BillingPaymentPort`` is the seam: one method, ``charge``, taking a statement
and returning the provider's reference, which lands in
``billing_statement.external_invoice_ref``. The default ``UnconfiguredBillingPort`` raises,
and nothing in the API calls it. What a human has to do before it can be implemented is listed
in ``docs/prs/M8-tenant-admin.md`` ("Payment port"): choose the entity and provider, obtain the
merchant account, decide GST treatment on the platform fee, and sign off the dunning policy.
"""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, datetime
from typing import Any, Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models.tenant import Tenant
from farmerapp.logging import get_logger
from farmerapp.platform_admin.models import BillingStatement
from farmerapp.platform_admin.plans import Plan, merge_limits, plan_by_name
from farmerapp.platform_admin.usage import month_key, snapshot

log = get_logger("farmerapp.platform_admin.billing")

CSV_COLUMNS = (
    "tenant_slug",
    "period",
    "plan",
    "metric",
    "used",
    "included",
    "overage",
    "unit_price_paise",
    "amount_paise",
)


class BillingPaymentPort(Protocol):
    """The seam a payment provider plugs into (see the module docstring)."""

    async def charge(self, statement: BillingStatement, *, tenant_slug: str) -> str:
        """Charge ``statement.total_paise`` and return the provider's invoice reference."""


class UnconfiguredBillingPort:
    """The default: there is no platform payment provider yet, and pretending otherwise
    would be worse than failing loudly."""

    async def charge(self, statement: BillingStatement, *, tenant_slug: str) -> str:
        raise NotImplementedError(
            "No platform payment provider is configured (WC-014). See the 'Payment port' "
            "section of docs/prs/M8-tenant-admin.md for what a human must decide first."
        )


PAYMENT_PORT: BillingPaymentPort = UnconfiguredBillingPort()


def _lines(plan: Plan, usage: list[Any]) -> tuple[list[dict[str, Any]], int]:
    lines: list[dict[str, Any]] = []
    overage_total = 0
    for line in usage:
        unit_price = int(plan.overage_paise.get(line.metric, 0))
        amount = line.over * unit_price
        overage_total += amount
        lines.append(
            {
                "metric": line.metric,
                "period": line.period,
                "used": line.used,
                "included": line.limit,
                "overage": line.over,
                "unit_price_paise": unit_price,
                "amount_paise": amount,
            }
        )
    return lines, overage_total


async def generate_statement(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    period: str | None = None,
    now: datetime | None = None,
) -> BillingStatement:
    """Build (or rebuild) the statement for ``period``. Session bound to ``tenant_id``."""
    moment = now or datetime.now(UTC)
    key = period or month_key(moment)
    tenant = await session.get(Tenant, tenant_id)
    if tenant is None:  # pragma: no cover - the router resolves the tenant first
        raise LookupError(f"tenant {tenant_id} not found")
    plan = plan_by_name(tenant.plan)
    limits = merge_limits(plan.limits, tenant.plan_limits)
    # The period's monthly counters plus the standing head counts as they are now.
    when = datetime(int(key[:4]), int(key[5:]), 1, tzinfo=UTC)
    usage = await snapshot(session, tenant_id, limits, when=when)
    lines, overage = _lines(plan, usage)

    statement = (
        await session.execute(
            select(BillingStatement).where(
                BillingStatement.tenant_id == tenant_id,
                BillingStatement.period == key,
                BillingStatement.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if statement is None:
        statement = BillingStatement(id=uuid.uuid4(), tenant_id=tenant_id, period=key)
        session.add(statement)
    statement.plan = plan.name
    statement.generated_at = moment
    statement.lines = lines
    statement.base_price_paise = plan.base_price_paise
    statement.overage_paise = overage
    statement.total_paise = plan.base_price_paise + overage
    await session.flush()
    log.info(
        "billing_statement_generated",
        tenant_id=str(tenant_id),
        period=key,
        plan=plan.name,
        total_paise=statement.total_paise,
        overage_paise=overage,
    )
    return statement


def statement_csv(statement: BillingStatement, *, tenant_slug: str) -> str:
    """The statement as CSV, one row per metric plus a ``base`` and a ``total`` row."""
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(CSV_COLUMNS)
    for line in statement.lines:
        writer.writerow(
            [
                tenant_slug,
                statement.period,
                statement.plan,
                line["metric"],
                line["used"],
                "" if line["included"] is None else line["included"],
                line["overage"],
                line["unit_price_paise"],
                line["amount_paise"],
            ]
        )
    writer.writerow(
        [
            tenant_slug,
            statement.period,
            statement.plan,
            "base",
            "",
            "",
            "",
            "",
            statement.base_price_paise,
        ]
    )
    writer.writerow(
        [
            tenant_slug,
            statement.period,
            statement.plan,
            "total",
            "",
            "",
            "",
            "",
            statement.total_paise,
        ]
    )
    return buffer.getvalue()


__all__ = [
    "CSV_COLUMNS",
    "PAYMENT_PORT",
    "BillingPaymentPort",
    "UnconfiguredBillingPort",
    "generate_statement",
    "statement_csv",
]
