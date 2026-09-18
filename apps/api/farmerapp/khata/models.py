"""Khata — the farmer credit ledger (SPEC 8.2 ``khata_entry``; FA-022, ST-007, FM-010).

* ``khata_entry`` — append-only (the app role may only INSERT, ``APPEND_ONLY_TABLES``): a
  ``debit`` (the farmer owes: a credit sale, ``ref_type = order``) or a ``credit`` (the
  farmer paid: ``ref_type = payment``; or a write-off / correction, ``adjustment``), with the
  ``due_date`` and the ``harvest_month`` it is linked to (SPEC 1.1: farmers buy on credit
  until harvest). FA-022 "balance equals sum of ledger entries": ``khata_balance`` is
  ``sum(debit) - sum(credit)`` over the rows, never a stored counter; a correction is a new
  row. ``created_at`` is the wall clock so rows written together keep their order.
* ``credit_limit`` — ST-007: the limit per farmer and store set by the store manager
  (``set_by``); above the tenant's own-approval threshold the cluster head approves
  (``approved_by``). A sale that would take the balance beyond the limit is blocked
  without approval (the loop's write path).
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from enum import StrEnum

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    String,
    UniqueConstraint,
    Uuid,
    case,
    func,
    select,
)
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns, TenantRow


class EntryType(StrEnum):
    DEBIT = "debit"  # the farmer owes
    CREDIT = "credit"  # the farmer paid / was credited


class EntryRef(StrEnum):
    ORDER = "order"
    PAYMENT = "payment"
    ADJUSTMENT = "adjustment"


class KhataEntry(Base, TenantRow):
    __tablename__ = "khata_entry"
    __table_args__ = (
        CheckConstraint(f"type IN ({sql_in(EntryType)})", name="type"),
        CheckConstraint(f"ref_type IN ({sql_in(EntryRef)})", name="ref_type"),
        CheckConstraint("amount_paise > 0", name="amount_paise"),
        CheckConstraint(
            "harvest_month IS NULL OR extract(day FROM harvest_month) = 1", name="harvest_month"
        ),
        Index("ix_khata_entry_farmer_store", "tenant_id", "farmer_id", "store_id", "created_at"),
        Index("ix_khata_entry_due_date", "tenant_id", "due_date"),
        Index("ix_khata_entry_ref", "tenant_id", "ref_type", "ref_id"),
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
        server_default=func.now(),
    )
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="RESTRICT"), nullable=False
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="RESTRICT"), nullable=False
    )
    type: Mapped[str] = mapped_column(String(8), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)  # debits
    ref_type: Mapped[str] = mapped_column(String(16), nullable=False)
    ref_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    harvest_month: Mapped[date | None] = mapped_column(Date, nullable=True)  # first of month
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)  # user.id

    @property
    def signed_paise(self) -> int:
        return self.amount_paise if self.type == EntryType.DEBIT else -self.amount_paise


class CreditLimit(Base, BaseColumns):
    __tablename__ = "credit_limit"
    __table_args__ = (
        UniqueConstraint("tenant_id", "farmer_id", "store_id"),
        CheckConstraint("limit_paise >= 0", name="limit_paise"),
    )

    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=False
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    limit_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    set_by: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )


# --------------------------------------------------------------------------- balance
#: ``+amount`` for a debit, ``-amount`` for a credit: the ledger's signed amount in SQL.
SIGNED_AMOUNT = case(
    (KhataEntry.type == EntryType.DEBIT.value, KhataEntry.amount_paise),
    else_=-KhataEntry.amount_paise,
)


def balance_sql(entries: list[KhataEntry]) -> int:
    """Pure-Python twin of ``khata_balance`` for rows already loaded."""
    return sum(e.signed_paise for e in entries)


async def khata_balance(
    session: AsyncSession,
    farmer_id: uuid.UUID,
    store_id: uuid.UUID | None = None,
    *,
    as_of: datetime | None = None,
) -> int:
    """The farmer's outstanding balance in paise (positive = owes): sum of the ledger
    (FA-022), for one store or across stores, optionally as of a point in time."""
    stmt = select(func.coalesce(func.sum(SIGNED_AMOUNT), 0)).where(
        KhataEntry.farmer_id == farmer_id
    )
    if store_id is not None:
        stmt = stmt.where(KhataEntry.store_id == store_id)
    if as_of is not None:
        stmt = stmt.where(KhataEntry.created_at <= as_of)
    return int(await session.scalar(stmt) or 0)


async def khata_balances_by_store(
    session: AsyncSession, farmer_id: uuid.UUID
) -> dict[uuid.UUID, int]:
    """``store_id -> balance`` for every store the farmer has a ledger with."""
    rows = await session.execute(
        select(KhataEntry.store_id, func.coalesce(func.sum(SIGNED_AMOUNT), 0))
        .where(KhataEntry.farmer_id == farmer_id)
        .group_by(KhataEntry.store_id)
    )
    return {store_id: int(balance) for store_id, balance in rows}


async def overdue_paise(
    session: AsyncSession, farmer_id: uuid.UUID, today: date, store_id: uuid.UUID | None = None
) -> int:
    """Debits past their ``due_date`` minus credits received, floored at zero (VA-F10
    groundwork: "overdue" is what the credits so far did not cover)."""
    debits = select(func.coalesce(func.sum(KhataEntry.amount_paise), 0)).where(
        KhataEntry.farmer_id == farmer_id,
        KhataEntry.type == EntryType.DEBIT.value,
        KhataEntry.due_date.is_not(None),
        KhataEntry.due_date < today,
    )
    credits = select(func.coalesce(func.sum(KhataEntry.amount_paise), 0)).where(
        KhataEntry.farmer_id == farmer_id, KhataEntry.type == EntryType.CREDIT.value
    )
    if store_id is not None:
        debits = debits.where(KhataEntry.store_id == store_id)
        credits = credits.where(KhataEntry.store_id == store_id)
    due = int(await session.scalar(debits) or 0)
    paid = int(await session.scalar(credits) or 0)
    return max(due - paid, 0)


__all__ = [
    "SIGNED_AMOUNT",
    "CreditLimit",
    "EntryRef",
    "EntryType",
    "KhataEntry",
    "balance_sql",
    "khata_balance",
    "khata_balances_by_store",
    "overdue_paise",
]
