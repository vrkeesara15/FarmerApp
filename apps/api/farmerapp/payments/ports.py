"""Port to the khata ledger (owned by FA-020 / ST-007 / FA-022, ``farmerapp.khata``).

Payments never write the khata directly: a credit sale asks the ledger to check and reserve
credit, and a paid dues payment posts a credit entry. The contract is two functions:

* ``farmerapp.khata.credit.check_and_reserve_credit(session, *, tenant_id, farmer_id,
  store_id, amount_paise, order_id, actor) -> CreditDecision`` — ST-007 limit enforcement.
  When allowed **the gate posts the khata debit itself** (``decision.khata_entry_id``; the
  caller must not post a second one). When blocked it writes / refreshes a pending
  ``credit_approval_request`` and *returns* the decision: the caller answers 402
  ``credit_limit_exceeded`` without raising, so the request commits.
* ``farmerapp.khata.ledger.post_credit(session, *, tenant_id, farmer_id, store_id,
  amount_paise, ref_type, ref_id, actor) -> KhataEntry`` — a payment against dues.

``LedgerPort`` is that contract as a protocol so tests can inject fakes; ``KhataLedgerPort``
(the default) delegates to the real functions. ``actor`` is ``farmerapp.db.audit.Actor``
(who acts, from where; ``system_actor`` for the worker).
"""

from __future__ import annotations

import uuid
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.audit import Actor
from farmerapp.khata import credit as khata_credit
from farmerapp.khata import ledger as khata_ledger
from farmerapp.khata.credit import CreditDecision
from farmerapp.khata.models import KhataEntry


class LedgerPort(Protocol):
    async def check_and_reserve_credit(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        farmer_id: uuid.UUID,
        store_id: uuid.UUID,
        amount_paise: int,
        order_id: uuid.UUID | None,
        actor: Actor,
    ) -> CreditDecision: ...

    async def post_credit(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        farmer_id: uuid.UUID,
        store_id: uuid.UUID,
        amount_paise: int,
        ref_type: str,
        ref_id: uuid.UUID,
        actor: Actor,
    ) -> KhataEntry: ...


class KhataLedgerPort:
    """The default port: ``farmerapp.khata.credit`` / ``farmerapp.khata.ledger``."""

    async def check_and_reserve_credit(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        farmer_id: uuid.UUID,
        store_id: uuid.UUID,
        amount_paise: int,
        order_id: uuid.UUID | None,
        actor: Actor,
    ) -> CreditDecision:
        return await khata_credit.check_and_reserve_credit(
            session,
            tenant_id=tenant_id,
            farmer_id=farmer_id,
            store_id=store_id,
            amount_paise=amount_paise,
            order_id=order_id,
            actor=actor,
        )

    async def post_credit(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        farmer_id: uuid.UUID,
        store_id: uuid.UUID,
        amount_paise: int,
        ref_type: str,
        ref_id: uuid.UUID,
        actor: Actor,
    ) -> KhataEntry:
        return await khata_ledger.post_credit(
            session,
            tenant_id=tenant_id,
            farmer_id=farmer_id,
            store_id=store_id,
            amount_paise=amount_paise,
            ref_type=ref_type,
            ref_id=ref_id,
            actor=actor,
            note="Payment received",
        )


__all__ = ["KhataLedgerPort", "LedgerPort"]
