"""Credit limits and approvals (ST-007).

``check_and_reserve_credit`` is the single gate for every credit sale — orders (FA-020) and
POS sales with payment mode ``credit`` (ST-001 / ST-002, the payments package calls it):

1. The farmer row is locked ``FOR UPDATE`` so concurrent credit sales for one farmer
   serialise (the balance they read cannot be stale).
2. An **approved, unused** ``credit_approval_request`` for the same farmer, store and
   ``order_id`` covering ``amount_paise`` lets the sale proceed once (``used_at`` is set).
3. Otherwise the sale is allowed when ``khata_balance(farmer, store) + amount <= limit``
   (``credit_limit`` for the farmer and store; no row = limit 0).
4. When allowed, the credit is **reserved by posting the khata debit** (``ref_type =
   order``, ``ref_id = order_id``, due date from ``credit_due_date``) in the caller's
   transaction: callers must not post the debit themselves. ``khata_entry_id`` on the
   decision is that row (for ``payment.khata_entry_id``).
5. When not allowed, a ``pending`` approval request is created (or the pending one for the
   same ``order_id`` refreshed) and returned with the shortfall; **nothing is raised**, so
   the request survives the caller's transaction. The caller answers 402
   ``credit_limit_exceeded`` (``CreditLimitExceededError.from_decision``) *without* rolling
   back, i.e. it returns the problem response instead of raising.

Setting limits: a store manager sets limits for their own store up to the tenant setting
``store_manager_max_credit_limit_paise`` (default ₹50,000 = 5,000,000 paise); a cluster head
(own cluster's stores), owner or director sets any amount and is recorded as ``approved_by``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import (
    AppError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    problem_response,
)
from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.models import Farmer
from farmerapp.khata.ledger import (
    Actor,
    actor_user_id,
    post_debit,
    tenant_credit_settings,
)
from farmerapp.khata.models import (
    ApprovalStatus,
    CreditApprovalRequest,
    CreditLimit,
    EntryRef,
    khata_balance,
)
from farmerapp.tenants.models import Store

#: Roles that may set any limit and decide approval requests (cluster head: own cluster).
LIMIT_APPROVER_ROLES = frozenset({UserRole.CLUSTER_HEAD, UserRole.OWNER, UserRole.DIRECTOR})


@dataclass(frozen=True)
class CreditDecision:
    """Outcome of ``check_and_reserve_credit``.

    ``allowed`` — the sale may proceed (the debit is already posted: ``khata_entry_id``).
    ``approval_request_id`` — the pending request to show the user when blocked, or the
    approved request that was used when allowed through an approval.
    ``shortfall_paise`` — how far the sale goes beyond the limit (0 when allowed).
    """

    allowed: bool
    approval_request_id: uuid.UUID | None
    shortfall_paise: int
    khata_entry_id: uuid.UUID | None = None
    balance_paise: int = 0
    limit_paise: int = 0


class CreditLimitExceededError(AppError):
    """402 ``credit_limit_exceeded``: the problem body carries the shortfall and the
    approval request a cluster head can approve."""

    status = 402
    code = "credit_limit_exceeded"

    @classmethod
    def from_decision(cls, decision: CreditDecision) -> CreditLimitExceededError:
        return cls(
            CREDIT_BLOCKED_DETAIL,
            extra=decision_extra(decision),
        )


class LimitNeedsApproverError(ForbiddenError):
    code = "credit_limit_needs_cluster_head"


class ApprovalNotPendingError(ConflictError):
    code = "approval_not_pending"


def decision_extra(decision: CreditDecision) -> dict[str, Any]:
    return {
        "shortfall_paise": decision.shortfall_paise,
        "approval_request_id": (
            str(decision.approval_request_id) if decision.approval_request_id else None
        ),
        "balance_paise": decision.balance_paise,
        "limit_paise": decision.limit_paise,
    }


CREDIT_BLOCKED_DETAIL = (
    "This credit sale is beyond the farmer's limit; a cluster head must approve it."
)


def credit_blocked_response(request: Request, decision: CreditDecision) -> JSONResponse:
    """The 402 ``credit_limit_exceeded`` problem for a blocked decision. Routes *return* it
    (never raise) so the approval request commits with the request transaction."""
    return problem_response(
        request,
        status=CreditLimitExceededError.status,
        code=CreditLimitExceededError.code,
        detail=CREDIT_BLOCKED_DETAIL,
        extra=decision_extra(decision),
    )


async def credit_limit_paise(
    session: AsyncSession, farmer_id: uuid.UUID, store_id: uuid.UUID
) -> int:
    limit = await session.scalar(
        select(CreditLimit.limit_paise).where(
            CreditLimit.farmer_id == farmer_id,
            CreditLimit.store_id == store_id,
            CreditLimit.deleted_at.is_(None),
        )
    )
    return int(limit or 0)


async def check_and_reserve_credit(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    farmer_id: uuid.UUID,
    store_id: uuid.UUID,
    amount_paise: int,
    order_id: uuid.UUID | None,
    actor: Actor,
) -> CreditDecision:
    """Allow (and post the khata debit for) a credit sale, or open an approval request.

    See the module docstring for the contract. ``amount_paise`` must be a positive int.
    """
    if isinstance(amount_paise, bool) or not isinstance(amount_paise, int) or amount_paise <= 0:
        raise ValueError("amount_paise must be a positive integer")
    # Serialise credit sales of one farmer (step 1).
    farmer = (
        await session.execute(
            select(Farmer)
            .where(Farmer.id == farmer_id, Farmer.tenant_id == tenant_id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    now = datetime.now(UTC)
    balance = await khata_balance(session, farmer_id, store_id)
    limit = await credit_limit_paise(session, farmer_id, store_id)

    async def _debit() -> uuid.UUID:
        entry = await post_debit(
            session,
            tenant_id=tenant_id,
            farmer_id=farmer_id,
            store_id=store_id,
            amount_paise=amount_paise,
            ref_type=EntryRef.ORDER,
            ref_id=order_id,
            actor=actor,
            note="Credit sale",
        )
        return entry.id

    if order_id is not None:
        approved = (
            (
                await session.execute(
                    select(CreditApprovalRequest)
                    .where(
                        CreditApprovalRequest.tenant_id == tenant_id,
                        CreditApprovalRequest.farmer_id == farmer_id,
                        CreditApprovalRequest.store_id == store_id,
                        CreditApprovalRequest.order_id == order_id,
                        CreditApprovalRequest.status == ApprovalStatus.APPROVED.value,
                        CreditApprovalRequest.used_at.is_(None),
                        CreditApprovalRequest.amount_paise >= amount_paise,
                    )
                    .order_by(CreditApprovalRequest.created_at)
                    .with_for_update()
                )
            )
            .scalars()
            .first()
        )
        if approved is not None:
            approved.used_at = now
            entry_id = await _debit()
            return CreditDecision(
                allowed=True,
                approval_request_id=approved.id,
                shortfall_paise=0,
                khata_entry_id=entry_id,
                balance_paise=balance,
                limit_paise=limit,
            )

    shortfall = balance + amount_paise - limit
    if shortfall <= 0:
        entry_id = await _debit()
        return CreditDecision(
            allowed=True,
            approval_request_id=None,
            shortfall_paise=0,
            khata_entry_id=entry_id,
            balance_paise=balance,
            limit_paise=limit,
        )

    pending = None
    if order_id is not None:
        pending = (
            (
                await session.execute(
                    select(CreditApprovalRequest)
                    .where(
                        CreditApprovalRequest.tenant_id == tenant_id,
                        CreditApprovalRequest.farmer_id == farmer_id,
                        CreditApprovalRequest.store_id == store_id,
                        CreditApprovalRequest.order_id == order_id,
                        CreditApprovalRequest.status == ApprovalStatus.PENDING.value,
                    )
                    .with_for_update()
                )
            )
            .scalars()
            .first()
        )
    if pending is None:
        pending = CreditApprovalRequest(
            tenant_id=tenant_id,
            farmer_id=farmer_id,
            store_id=store_id,
            order_id=order_id,
            requested_by=actor_user_id(actor),
            status=ApprovalStatus.PENDING,
            amount_paise=amount_paise,
            balance_paise=balance,
            limit_paise=limit,
            shortfall_paise=shortfall,
        )
        session.add(pending)
    else:
        pending.amount_paise = amount_paise
        pending.balance_paise = balance
        pending.limit_paise = limit
        pending.shortfall_paise = shortfall
    await session.flush()
    return CreditDecision(
        allowed=False,
        approval_request_id=pending.id,
        shortfall_paise=shortfall,
        balance_paise=balance,
        limit_paise=limit,
    )


# --------------------------------------------------------------------------- limits
async def set_credit_limit(
    session: AsyncSession,
    actor: User,
    *,
    farmer: Farmer,
    store: Store,
    limit_paise: int,
) -> CreditLimit:
    """Create or change the farmer's limit at ``store`` (the caller checked store scope)."""
    role = UserRole(actor.role)
    if role == UserRole.STORE_MANAGER:
        settings = await tenant_credit_settings(session, actor.tenant_id)
        if limit_paise > settings.store_manager_max_credit_limit_paise:
            raise LimitNeedsApproverError(
                "Limits above the store manager maximum need a cluster head.",
                extra={"max_limit_paise": settings.store_manager_max_credit_limit_paise},
            )
    approver = actor.id if role in LIMIT_APPROVER_ROLES else None
    row = (
        await session.execute(
            select(CreditLimit)
            .where(CreditLimit.farmer_id == farmer.id, CreditLimit.store_id == store.id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if row is None:
        row = CreditLimit(
            tenant_id=actor.tenant_id,
            farmer_id=farmer.id,
            store_id=store.id,
            limit_paise=limit_paise,
            set_by=actor.id,
            approved_by=approver,
        )
        session.add(row)
    else:
        row.limit_paise = limit_paise
        row.set_by = actor.id
        row.approved_by = approver
        row.deleted_at = None
    await session.flush()
    await session.refresh(row)
    return row


# --------------------------------------------------------------------------- approvals
async def decide(
    session: AsyncSession,
    actor: User,
    request: CreditApprovalRequest,
    *,
    approve: bool,
    note: str | None,
) -> CreditApprovalRequest:
    if request.status != ApprovalStatus.PENDING:
        raise ApprovalNotPendingError(f"This request is already {request.status}.")
    request.status = ApprovalStatus.APPROVED if approve else ApprovalStatus.REJECTED
    request.decided_by = actor.id
    request.decided_at = datetime.now(UTC)
    request.decision_note = note
    await session.flush()
    await session.refresh(request)
    return request


__all__ = [
    "CREDIT_BLOCKED_DETAIL",
    "LIMIT_APPROVER_ROLES",
    "ApprovalNotPendingError",
    "CreditDecision",
    "CreditLimitExceededError",
    "LimitNeedsApproverError",
    "check_and_reserve_credit",
    "credit_blocked_response",
    "credit_limit_paise",
    "decide",
    "decision_extra",
    "set_credit_limit",
]
