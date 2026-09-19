"""VA-F07 — ghost farmer: registered at least ``inactive_days`` ago and, since then, no
confirmed visit (FA-016 ``visit_confirmation`` confirmed), no purchase (an order that is not
a draft or cancelled) and no app login (a refresh token issued to the farmer's own login,
FM-001). A farmer who became active at any point since registration is not a ghost.

Batch (nightly). One flag per farmer (key ``ghost``) for the store manager; the evidence
cites the farmer and the officer who registered them.

Params: ``inactive_days``.
"""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import exists, select

from farmerapp.auth.models import RefreshToken
from farmerapp.farmers.models import Farmer
from farmerapp.orders.models import Order, OrderStatus
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.visits.models import ConfirmationStatus, Visit, VisitConfirmation


@rule("VA-F07")
async def check(ctx: RuleContext) -> list[Finding]:
    days = int(ctx.param("inactive_days"))
    cutoff = ctx.now - timedelta(days=days)
    confirmed = exists(
        select(VisitConfirmation.id)
        .join(Visit, Visit.id == VisitConfirmation.visit_id)
        .where(
            Visit.farmer_id == Farmer.id,
            VisitConfirmation.status == ConfirmationStatus.CONFIRMED.value,
        )
    )
    purchased = exists(
        select(Order.id).where(
            Order.farmer_id == Farmer.id,
            Order.deleted_at.is_(None),
            Order.status.not_in([OrderStatus.DRAFT.value, OrderStatus.CANCELLED.value]),
        )
    )
    logged_in = exists(select(RefreshToken.id).where(RefreshToken.user_id == Farmer.user_id))
    stmt = (
        select(Farmer.id, Farmer.created_at, Farmer.registered_by)
        .where(
            Farmer.tenant_id == ctx.tenant_id,
            Farmer.deleted_at.is_(None),
            Farmer.created_at <= cutoff,
            ~confirmed,
            ~purchased,
            ~logged_in,
        )
        .order_by(Farmer.created_at, Farmer.id)
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(Farmer.id.in_(ctx.subject_ids))
    findings: list[Finding] = []
    for farmer_id, registered_at, registered_by in (await ctx.session.execute(stmt)).tuples():
        records = [record("farmer", farmer_id)]
        if registered_by is not None:
            records.append(record("user", registered_by))
        inactive = (ctx.now - registered_at).days
        findings.append(
            Finding(
                subject_type=Subject.FARMER,
                subject_id=farmer_id,
                key="ghost",
                title=f"No confirmation, purchase or app login {inactive} days after registration",
                evidence=Evidence(
                    records=records,
                    metrics={
                        "reason": "ghost_farmer",
                        "registered_at": registered_at.isoformat(),
                        "days_since_registration": inactive,
                        "inactive_days": days,
                        "confirmed_visits": 0,
                        "purchases": 0,
                        "app_logins": 0,
                    },
                ),
            )
        )
    return findings
