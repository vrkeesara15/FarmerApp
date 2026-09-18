"""``GET /v1/payments`` — payment history (FA-021, ST-002, FM-010).

Scope (``farmerapp.auth.scope.payment_filters``): owner / director / tenant admin / auditor /
accountant see the tenant, a cluster head their cluster's stores, a store manager their
store, a field officer the payments they collected, a farmer their own.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy import select

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import payment_filters
from farmerapp.khata.credit import credit_blocked_response
from farmerapp.payments.models import Payment, PaymentMode, PaymentStatus
from farmerapp.payments.schemas import (
    PaymentCreate,
    PaymentCreated,
    PaymentOut,
    PaymentPage,
    PaymentStatusOut,
)
from farmerapp.payments.service import (
    CreditBlocked,
    Messaging,
    PaymentServices,
    create_payment,
    get_payment_services,
    status_out,
    visible_payment,
)
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.uploads.router import get_blob_store

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


#: FA-021 / FM-010: who may start a collection. Farmers pay their own dues / orders by UPI.
COLLECT_ROLES = (
    Role.OWNER,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.FARMER,
)


@router.post(
    "",
    operation_id="createPayment",
    summary="Collect a payment for an order or khata dues (UPI QR, link, cash, card, credit)",
    status_code=status.HTTP_201_CREATED,
    response_model=PaymentCreated,
    responses=problem_responses(
        (404, "not_found"),
        (409, "already_paid"),
        (409, "nothing_due"),
        (409, "order_cancelled"),
        (402, "credit_limit_exceeded"),
        (422, "amount_mismatch"),
        (422, "receipt_required"),
        (422, "reference_required"),
        (422, "invalid_blob"),
        (422, "invalid_mode"),
        (422, "phone_required"),
        (403, "mode_not_allowed"),
        (502, "provider_error"),
    ),
)
async def post_payment(
    body: PaymentCreate,
    request: Request,
    actor: Annotated[User, require_roles(*COLLECT_ROLES)],
    session: DbSession,
    auth: Services,
    services: Annotated[PaymentServices, Depends(get_payment_services)],
    blobs: Annotated[BlobStore, Depends(get_blob_store)],
) -> PaymentCreated | JSONResponse:
    created = await create_payment(
        session,
        actor,
        body,
        services=services,
        messaging=Messaging(sms=auth.sms, whatsapp=auth.whatsapp),
        blobs=blobs,
        now=auth.clock.now(),
    )
    if isinstance(created, CreditBlocked):
        # Returned, not raised: the credit approval request must commit (ST-007).
        return credit_blocked_response(request, created.decision)
    return created


@router.get(
    "/{id}",
    operation_id="getPayment",
    summary="One payment's status (A53 polls it: waiting / paid / failed)",
    response_model=PaymentStatusOut,
    responses=problem_responses((404, "not_found")),
)
async def get_payment(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*PAYMENT_ROLES)],
    session: DbSession,
) -> PaymentStatusOut:
    return status_out(await visible_payment(session, actor, id))


__all__ = ["COLLECT_ROLES", "PAYMENT_ROLES", "router"]
