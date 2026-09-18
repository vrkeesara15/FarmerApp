"""``GET /v1/farmers/{id}/khata`` — balance, due dates and ledger (FA-022, FM-010).

The SPEC 2.6 "Khata" row: owner / director / auditor read, cluster head own cluster, store
manager own store, field officer own farmers, farmer own; the agronomist has no access
(``farmerapp.auth.scope.khata_farmer_filters``). A farmer outside the scope is a 404. The
balance is the sum of the ledger (never a stored counter) — the FA-022 acceptance
criterion, proven in ``tests/orders/test_read_api.py``.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import khata_farmer_filters
from farmerapp.farmers.models import Farmer
from farmerapp.khata.models import (
    CreditLimit,
    EntryType,
    KhataEntry,
    khata_balance,
    khata_balances_by_store,
    overdue_paise,
)
from farmerapp.khata.schemas import CreditLimitOut, KhataEntryOut, KhataOut, StoreBalanceOut

router = APIRouter(prefix="/farmers", tags=["khata"])

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


@router.get(
    "/{id}/khata",
    operation_id="getFarmerKhata",
    summary="A farmer's khata: balance (sum of entries), overdue amount, due dates, ledger",
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
    if store_id is not None:
        next_due_stmt = next_due_stmt.where(KhataEntry.store_id == store_id)
        limits_stmt = limits_stmt.where(CreditLimit.store_id == store_id)
    balances = await khata_balances_by_store(session, farmer.id)
    if store_id is not None:
        balances = {s: b for s, b in balances.items() if s == store_id}
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
        entries=[KhataEntryOut.from_row(e) for e in entries],
        next_cursor=next_cursor,
    )


__all__ = ["KHATA_ROLES", "khata_farmer", "router"]
