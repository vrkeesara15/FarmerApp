"""Khata and credit routes (FA-022, ST-007, FM-010).

* ``GET /v1/farmers/{id}/khata`` — balance (sum of the ledger), overdue amount and SPEC 5.2
  buckets, open debits with their harvest-linked due dates, payment history, per-store
  balances, credit limits and the ledger (newest first). SPEC 2.6 "Khata" row: owner /
  director / auditor read, cluster head own cluster, store manager own store, field officer
  own farmers, farmer own; the agronomist has no access
  (``farmerapp.auth.scope.khata_farmer_filters``). A farmer outside the scope is a 404.
* ``POST /v1/farmers/{id}/khata/entries`` — manual adjustment by the store manager of the
  store (reason required, audited; a new row — the ledger is append-only).
* ``PUT /v1/farmers/{id}/credit-limit`` — ST-007 limit per farmer and store: the store
  manager of that store up to ``store_manager_max_credit_limit_paise``; above it a cluster
  head (own cluster), owner or director.
* ``GET /v1/credit-approvals`` and ``POST /v1/credit-approvals/{id}/approve|reject`` — the
  requests opened when a credit sale went beyond the limit; a cluster head (own cluster),
  owner or director decides; an approved request lets that order proceed once.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import ColumnElement, select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import khata_farmer_filters, store_filters, visible_store_filters
from farmerapp.db import audit
from farmerapp.farmers.models import Farmer
from farmerapp.khata import credit
from farmerapp.khata.aging import open_debits, overdue_buckets
from farmerapp.khata.ledger import post_credit, post_debit, tenant_credit_settings
from farmerapp.khata.models import (
    ApprovalStatus,
    CreditApprovalRequest,
    CreditLimit,
    EntryRef,
    EntryType,
    KhataEntry,
    khata_balance,
    khata_balances_by_store,
    overdue_paise,
)
from farmerapp.khata.schemas import (
    CreditApprovalOut,
    CreditApprovalPage,
    CreditDecisionIn,
    CreditLimitIn,
    CreditLimitOut,
    KhataEntryIn,
    KhataEntryOut,
    KhataOut,
    OpenDebitOut,
    OverdueBucketsOut,
    StoreBalanceOut,
)
from farmerapp.payments.models import Payment, PaymentMode
from farmerapp.payments.schemas import PaymentOut
from farmerapp.tenants.models import Store

router = APIRouter(tags=["khata"])

KHATA_ROLES = (
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
#: ST-007: who sets limits (store manager: own store, capped; the others: any amount).
CREDIT_LIMIT_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD, Role.STORE_MANAGER)
#: Who reads the approval queue (store scope, like other store internals).
APPROVAL_READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
)
#: Who decides approval requests.
APPROVER_ROLES = (Role.OWNER, Role.DIRECTOR, Role.CLUSTER_HEAD)
PAYMENT_HISTORY_LIMIT = 50


async def khata_farmer(session: DbSession, actor: User, farmer_id: uuid.UUID) -> Farmer:
    """The farmer if their khata is within the actor's scope; else 404."""
    farmer = (
        await session.execute(
            select(Farmer).where(
                Farmer.id == farmer_id, Farmer.deleted_at.is_(None), *khata_farmer_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    return farmer


async def tenant_farmer(session: DbSession, actor: User, farmer_id: uuid.UUID) -> Farmer:
    """Any live farmer of the actor's tenant (a store serves farmers of every village)."""
    farmer = (
        await session.execute(
            select(Farmer).where(
                Farmer.id == farmer_id,
                Farmer.tenant_id == actor.tenant_id,
                Farmer.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    return farmer


async def _scoped_store(session: DbSession, actor: User, store_id: uuid.UUID) -> Store:
    store = (
        await session.execute(
            select(Store).where(
                Store.id == store_id, Store.deleted_at.is_(None), *visible_store_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if store is None:
        raise NotFoundError("Store not found.")
    return store


@router.get(
    "/farmers/{id}/khata",
    operation_id="getFarmerKhata",
    summary="A farmer's khata: balance, overdue buckets, due dates, payments, ledger",
    response_model=KhataOut,
    responses=problem_responses((400, "invalid_cursor"), (404, "not_found")),
)
async def get_farmer_khata(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*KHATA_ROLES)],
    session: DbSession,
    services: Services,
    page: Page,
    store_id: Annotated[uuid.UUID | None, Query(description="Limit to one store.")] = None,
) -> KhataOut:
    farmer = await khata_farmer(session, actor, id)
    today = services.clock.now().date()
    stmt = select(KhataEntry).where(KhataEntry.farmer_id == farmer.id)
    if store_id is not None:
        stmt = stmt.where(KhataEntry.store_id == store_id)
    before = page.before(KhataEntry.created_at, KhataEntry.id)
    if before is not None:
        stmt = stmt.where(before)
    stmt = stmt.order_by(KhataEntry.created_at.desc(), KhataEntry.id.desc()).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    entries, next_cursor = page.slice(rows)

    next_due_stmt = (
        select(KhataEntry.due_date)
        .where(
            KhataEntry.farmer_id == farmer.id,
            KhataEntry.type == EntryType.DEBIT.value,
            KhataEntry.due_date.is_not(None),
            KhataEntry.due_date >= today,
        )
        .order_by(KhataEntry.due_date)
        .limit(1)
    )
    limits_stmt = select(CreditLimit).where(
        CreditLimit.farmer_id == farmer.id, CreditLimit.deleted_at.is_(None)
    )
    all_stmt = select(KhataEntry).where(KhataEntry.farmer_id == farmer.id)
    payments_stmt = (
        select(Payment)
        .where(
            Payment.farmer_id == farmer.id,
            Payment.deleted_at.is_(None),
            Payment.mode != PaymentMode.CREDIT.value,
        )
        .order_by(Payment.created_at.desc(), Payment.id.desc())
        .limit(PAYMENT_HISTORY_LIMIT)
    )
    if store_id is not None:
        next_due_stmt = next_due_stmt.where(KhataEntry.store_id == store_id)
        limits_stmt = limits_stmt.where(CreditLimit.store_id == store_id)
        all_stmt = all_stmt.where(KhataEntry.store_id == store_id)
        payments_stmt = payments_stmt.where(Payment.store_id == store_id)
    balances = await khata_balances_by_store(session, farmer.id)
    if store_id is not None:
        balances = {s: b for s, b in balances.items() if s == store_id}

    # Ageing per store: a store's credits settle that store's debits (FIFO by due date).
    settings = await tenant_credit_settings(session, farmer.tenant_id)
    by_store: dict[uuid.UUID, list[KhataEntry]] = {}
    for entry in (await session.execute(all_stmt)).scalars():
        by_store.setdefault(entry.store_id, []).append(entry)
    debits = sorted(
        (
            d
            for store_entries in by_store.values()
            for d in open_debits(store_entries, today, settings.credit_due_days)
        ),
        key=lambda d: (d.due_date, str(d.entry_id)),
    )
    return KhataOut(
        farmer_id=farmer.id,
        store_id=store_id,
        balance_paise=await khata_balance(session, farmer.id, store_id),
        overdue_paise=await overdue_paise(session, farmer.id, today, store_id),
        next_due_date=await session.scalar(next_due_stmt),
        balances=[
            StoreBalanceOut(store_id=s, balance_paise=b) for s, b in sorted(balances.items())
        ],
        credit_limits=[
            CreditLimitOut.model_validate(limit)
            for limit in (await session.execute(limits_stmt)).scalars()
        ],
        open_debits=[OpenDebitOut.from_debit(d) for d in debits],
        overdue_buckets=OverdueBucketsOut.model_validate(overdue_buckets(debits)),
        payment_history=[
            PaymentOut.model_validate(p) for p in (await session.execute(payments_stmt)).scalars()
        ],
        entries=[KhataEntryOut.from_row(e) for e in entries],
        next_cursor=next_cursor,
    )


@router.post(
    "/farmers/{id}/khata/entries",
    operation_id="addKhataEntry",
    summary="Manual khata adjustment by the store manager (append-only, reason required)",
    status_code=201,
    response_model=KhataEntryOut,
    responses=problem_responses((404, "not_found"), (422, "validation_error")),
)
async def add_khata_entry(
    id: uuid.UUID,
    body: KhataEntryIn,
    actor: Annotated[User, require_roles(Role.STORE_MANAGER)],
    session: DbSession,
    services: Services,
) -> KhataEntryOut:
    farmer = await tenant_farmer(session, actor, id)
    store_id = body.store_id or actor.store_id
    if store_id is None or store_id != actor.store_id:
        raise NotFoundError("Store not found.")
    common = {
        "tenant_id": actor.tenant_id,
        "farmer_id": farmer.id,
        "store_id": store_id,
        "amount_paise": body.amount_paise,
        "ref_type": EntryRef.ADJUSTMENT.value,
        "ref_id": None,
        "actor": actor,
        "note": body.reason,
    }
    if body.type == EntryType.DEBIT:
        entry = await post_debit(
            session,
            tenant_id=actor.tenant_id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=body.amount_paise,
            ref_type=EntryRef.ADJUSTMENT.value,
            ref_id=None,
            actor=actor,
            note=body.reason,
            due_date=body.due_date,
            harvest_month=body.due_date.replace(day=1) if body.due_date else None,
            today=services.clock.now().date(),
        )
    else:
        entry = await post_credit(
            session,
            tenant_id=actor.tenant_id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=body.amount_paise,
            ref_type=EntryRef.ADJUSTMENT.value,
            ref_id=None,
            actor=actor,
            note=body.reason,
        )
    audit.record(
        session,
        action="khata_entry.adjustment",
        entity="khata_entry",
        entity_id=entry.id,
        tenant_id=actor.tenant_id,
        after={**{k: v for k, v in common.items() if k != "actor"}, "type": body.type.value},
    )
    return KhataEntryOut.from_row(entry)


@router.put(
    "/farmers/{id}/credit-limit",
    operation_id="setCreditLimit",
    summary="Set a farmer's credit limit at a store (ST-007)",
    response_model=CreditLimitOut,
    responses=problem_responses(
        (403, "credit_limit_needs_cluster_head"), (404, "not_found"), (422, "validation_error")
    ),
)
async def put_credit_limit(
    id: uuid.UUID,
    body: CreditLimitIn,
    actor: Annotated[User, require_roles(*CREDIT_LIMIT_ROLES)],
    session: DbSession,
) -> CreditLimitOut:
    farmer = await tenant_farmer(session, actor, id)
    store = await _scoped_store(session, actor, body.store_id)
    row = await credit.set_credit_limit(
        session, actor, farmer=farmer, store=store, limit_paise=body.limit_paise
    )
    return CreditLimitOut.model_validate(row)


# --------------------------------------------------------------------------- approvals
def _approval_filters(actor: User) -> list[ColumnElement[bool]]:
    scope = store_filters(actor, CreditApprovalRequest.store_id)
    return [CreditApprovalRequest.tenant_id == actor.tenant_id, *(scope or [])]


async def _visible_approval(
    session: DbSession, actor: User, request_id: uuid.UUID
) -> CreditApprovalRequest:
    row = (
        await session.execute(
            select(CreditApprovalRequest)
            .where(
                CreditApprovalRequest.id == request_id,
                CreditApprovalRequest.deleted_at.is_(None),
                *_approval_filters(actor),
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Credit approval request not found.")
    return row


@router.get(
    "/credit-approvals",
    operation_id="listCreditApprovals",
    summary="Credit approval requests of the caller's stores, oldest first (ST-007)",
    response_model=CreditApprovalPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_credit_approvals(
    actor: Annotated[User, require_roles(*APPROVAL_READ_ROLES)],
    session: DbSession,
    page: Page,
    status: Annotated[ApprovalStatus | None, Query()] = None,
    store_id: Annotated[uuid.UUID | None, Query()] = None,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
) -> CreditApprovalPage:
    stmt = select(CreditApprovalRequest).where(
        CreditApprovalRequest.deleted_at.is_(None),
        *_approval_filters(actor),
    )
    if status is not None:
        stmt = stmt.where(CreditApprovalRequest.status == status.value)
    if store_id is not None:
        stmt = stmt.where(CreditApprovalRequest.store_id == store_id)
    if farmer_id is not None:
        stmt = stmt.where(CreditApprovalRequest.farmer_id == farmer_id)
    after = page.after(CreditApprovalRequest.created_at, CreditApprovalRequest.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(CreditApprovalRequest.created_at, CreditApprovalRequest.id).limit(
        page.fetch
    )
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return CreditApprovalPage(
        items=[CreditApprovalOut.model_validate(r) for r in items], next_cursor=next_cursor
    )


@router.post(
    "/credit-approvals/{id}/approve",
    operation_id="approveCreditRequest",
    summary="Approve a credit sale beyond the limit (cluster head); the order proceeds once",
    response_model=CreditApprovalOut,
    responses=problem_responses((404, "not_found"), (409, "approval_not_pending")),
)
async def approve_credit_request(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*APPROVER_ROLES)],
    session: DbSession,
    body: CreditDecisionIn | None = None,
) -> CreditApprovalOut:
    row = await _visible_approval(session, actor, id)
    row = await credit.decide(session, actor, row, approve=True, note=body.note if body else None)
    return CreditApprovalOut.model_validate(row)


@router.post(
    "/credit-approvals/{id}/reject",
    operation_id="rejectCreditRequest",
    summary="Reject a credit sale beyond the limit (cluster head)",
    response_model=CreditApprovalOut,
    responses=problem_responses((404, "not_found"), (409, "approval_not_pending")),
)
async def reject_credit_request(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*APPROVER_ROLES)],
    session: DbSession,
    body: CreditDecisionIn | None = None,
) -> CreditApprovalOut:
    row = await _visible_approval(session, actor, id)
    row = await credit.decide(session, actor, row, approve=False, note=body.note if body else None)
    return CreditApprovalOut.model_validate(row)


__all__ = [
    "APPROVAL_READ_ROLES",
    "APPROVER_ROLES",
    "CREDIT_LIMIT_ROLES",
    "KHATA_ROLES",
    "khata_farmer",
    "router",
    "tenant_farmer",
]
