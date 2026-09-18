"""``GET /v1/payments`` — payment history (FA-021, ST-002, FM-010).

Scope (``farmerapp.auth.scope.payment_filters``): owner / director / tenant admin / auditor /
accountant see the tenant, a cluster head their cluster's stores, a store manager their
store, a field officer the payments they collected, a farmer their own.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import payment_filters
from farmerapp.payments.models import Payment, PaymentMode, PaymentStatus
from farmerapp.payments.schemas import PaymentOut, PaymentPage

router = APIRouter(prefix="/payments", tags=["payments"])

PAYMENT_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.FARMER,
)


@router.get(
    "",
    operation_id="listPayments",
    summary="Payments visible to the caller, oldest first",
    response_model=PaymentPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_payments(
    actor: Annotated[User, require_roles(*PAYMENT_ROLES)],
    session: DbSession,
    page: Page,
    store_id: Annotated[uuid.UUID | None, Query()] = None,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
    order_id: Annotated[uuid.UUID | None, Query()] = None,
    mode: Annotated[PaymentMode | None, Query()] = None,
    status: Annotated[PaymentStatus | None, Query()] = None,
    created_from: Annotated[datetime | None, Query(alias="from")] = None,
    created_to: Annotated[datetime | None, Query(alias="to")] = None,
) -> PaymentPage:
    stmt = select(Payment).where(Payment.deleted_at.is_(None), *payment_filters(actor))
    if store_id is not None:
        stmt = stmt.where(Payment.store_id == store_id)
    if farmer_id is not None:
        stmt = stmt.where(Payment.farmer_id == farmer_id)
    if order_id is not None:
        stmt = stmt.where(Payment.order_id == order_id)
    if mode is not None:
        stmt = stmt.where(Payment.mode == mode.value)
    if status is not None:
        stmt = stmt.where(Payment.status == status.value)
    if created_from is not None:
        stmt = stmt.where(Payment.created_at >= created_from)
    if created_to is not None:
        stmt = stmt.where(Payment.created_at <= created_to)
    after = page.after(Payment.created_at, Payment.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Payment.created_at, Payment.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return PaymentPage(items=[PaymentOut.model_validate(p) for p in items], next_cursor=next_cursor)


__all__ = ["PAYMENT_ROLES", "router"]
