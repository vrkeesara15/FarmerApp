"""Ports to the khata ledger (owned by the FA-020 / ST-007 orders branch).

Payments never write the khata directly: a credit sale asks the ledger to check and reserve
credit, and a paid dues payment posts a credit entry. The cross-agent contract is two
functions (exact signatures):

* ``farmerapp.khata.credit.check_and_reserve_credit(session, *, tenant_id, farmer_id,
  store_id, amount_paise, order_id, actor) -> CreditDecision(allowed, approval_request_id,
  shortfall_paise)`` — ST-007 limit enforcement; when allowed, the khata debit of the
  order is the orders branch's (we only call the port).
* ``farmerapp.khata.ledger.post_credit(session, *, tenant_id, farmer_id, store_id,
  amount_paise, ref_type, ref_id, actor) -> KhataEntry`` — a payment against dues.

``LedgerPort`` is that contract as a protocol so tests inject fakes and the real functions
drop in unchanged. ``KhataLedgerPort`` (the default) resolves the two modules lazily:

* before the orders branch lands, ``check_and_reserve_credit`` is unavailable (credit sales
  answer 503 ``credit_unavailable``) and ``post_credit`` falls back to appending the credit
  ``khata_entry`` itself (``ref_type = payment``) — the same row the contract writes, so
  FA-022 "balance = sum of entries" holds either way;
* once ``farmerapp.khata.credit`` / ``farmerapp.khata.ledger`` exist they are used as is.

``actor`` is ``farmerapp.db.audit.Actor`` (who acts, from where; ``system_actor`` for the
worker).
"""

from __future__ import annotations

import importlib
import uuid
from datetime import UTC, datetime
from types import ModuleType
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.db.audit import Actor
from farmerapp.khata.models import EntryRef, EntryType, KhataEntry
from farmerapp.logging import get_logger

log = get_logger("farmerapp.payments.ports")

CREDIT_MODULE = "farmerapp.khata.credit"
LEDGER_MODULE = "farmerapp.khata.ledger"


class CreditUnavailableError(AppError):
    status = 503
    code = "credit_unavailable"


class CreditDecisionLike(Protocol):
    """Structural view of ``farmerapp.khata.credit.CreditDecision``."""

    @property
    def allowed(self) -> bool: ...

    @property
    def approval_request_id(self) -> uuid.UUID | None: ...

    @property
    def shortfall_paise(self) -> int: ...


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
    ) -> CreditDecisionLike: ...

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


def _module(name: str) -> ModuleType | None:
    try:
        return importlib.import_module(name)
    except ModuleNotFoundError as exc:
        if exc.name != name:  # the module exists but something it imports is missing
            raise
        return None


class KhataLedgerPort:
    """The default port: the orders branch's functions when present (see module doc)."""

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
    ) -> CreditDecisionLike:
        module = _module(CREDIT_MODULE)
        if module is None:
            raise CreditUnavailableError(
                "Credit sales need the credit-limit service (ST-007), which is not deployed."
            )
        decision: CreditDecisionLike = await module.check_and_reserve_credit(
            session,
            tenant_id=tenant_id,
            farmer_id=farmer_id,
            store_id=store_id,
            amount_paise=amount_paise,
            order_id=order_id,
            actor=actor,
        )
        return decision

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
        module = _module(LEDGER_MODULE)
        if module is not None:
            entry: KhataEntry = await module.post_credit(
                session,
                tenant_id=tenant_id,
                farmer_id=farmer_id,
                store_id=store_id,
                amount_paise=amount_paise,
                ref_type=ref_type,
                ref_id=ref_id,
                actor=actor,
            )
            return entry
        log.info("khata_post_credit_fallback", ref_type=ref_type, ref_id=str(ref_id))
        entry = KhataEntry(
            tenant_id=tenant_id,
            created_at=datetime.now(UTC),
            farmer_id=farmer_id,
            store_id=store_id,
            type=EntryType.CREDIT,
            amount_paise=amount_paise,
            ref_type=EntryRef(ref_type),
            ref_id=ref_id,
            note="Payment received",
            created_by=actor.actor_id,
        )
        session.add(entry)
        await session.flush()
        return entry


__all__ = [
    "CREDIT_MODULE",
    "LEDGER_MODULE",
    "CreditDecisionLike",
    "CreditUnavailableError",
    "KhataLedgerPort",
    "LedgerPort",
]
