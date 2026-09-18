"""Stock (SPEC 8.2 ``stock_batch``; ST-003, ST-004).

* ``stock_batch`` — a lot of one SKU in one store: ``batch_no`` (unique per store and SKU),
  ``expiry`` (ST-004 alerts at 60 / 30 days), unit ``cost_paise`` and ``received_at``.
  ``qty`` is a **cache** of the ledger below, maintained in the same transaction as every
  movement (``farmerapp.stock.ledger.apply_movement``); ``stock_on_hand`` is the truth.
* ``stock_movement`` — the append-only ledger (the app role may only INSERT,
  ``APPEND_ONLY_TABLES``): one signed ``qty`` delta per event — ``receipt`` / ``transfer_in``
  positive, ``sale`` / ``transfer_out`` / ``damage`` negative, ``adjust`` either way — with
  the batch it touched, what caused it (``ref_type`` / ``ref_id``: an order, a transfer, a
  goods receipt note...) and a note. ST-003 "stock per SKU per batch correct after each
  movement" is ``sum(qty)`` over the ledger, never an updated counter. A write-off or an
  adjustment carries its ``reason`` and a write-off an optional ``photo_uri`` (0012).
* ``stock_reservation`` — FA-020 (migration 0012): stock held for an open order, per batch
  (FEFO at placement). Reservations are **not** movements: on hand stays the ledger sum and
  ``available = on_hand - sum(active reservations)``. A reservation is ``active`` until the
  order is handed over / delivered (``consumed``: the ``sale`` movement is written then) or
  cancelled (``released``). A separate table rather than ``reserve`` / ``release`` movement
  kinds keeps ``stock_on_hand`` and every existing ledger reader unchanged.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns, TenantRow


class MovementKind(StrEnum):
    RECEIPT = "receipt"  # goods receipt from a supplier
    SALE = "sale"  # order line handed over / POS sale
    TRANSFER_OUT = "transfer_out"  # to another store
    TRANSFER_IN = "transfer_in"  # from another store
    DAMAGE = "damage"  # write-off (breakage, expiry)
    ADJUST = "adjust"  # stock count correction (either sign)


#: Kinds that must be positive / negative (``adjust`` may be either, never zero).
INBOUND_KINDS = frozenset({MovementKind.RECEIPT, MovementKind.TRANSFER_IN})
OUTBOUND_KINDS = frozenset({MovementKind.SALE, MovementKind.TRANSFER_OUT, MovementKind.DAMAGE})

QTY_SCALE = Decimal("0.001")


class WriteOffReason(StrEnum):
    DAMAGE = "damage"
    EXPIRY = "expiry"
    OTHER = "other"


class ReservationStatus(StrEnum):
    ACTIVE = "active"  # holds stock for an open order
    CONSUMED = "consumed"  # converted into a sale movement (handed over / delivered)
    RELEASED = "released"  # order cancelled


class StockBatch(Base, BaseColumns):
    __tablename__ = "stock_batch"
    __table_args__ = (
        UniqueConstraint("tenant_id", "store_id", "sku_id", "batch_no"),
        CheckConstraint("qty >= 0", name="qty"),
        CheckConstraint("cost_paise >= 0", name="cost_paise"),
        CheckConstraint("char_length(batch_no) > 0", name="batch_no"),
        Index("ix_stock_batch_store_sku", "tenant_id", "store_id", "sku_id"),
        Index("ix_stock_batch_expiry", "tenant_id", "expiry"),
    )

    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="RESTRICT"), nullable=False
    )
    batch_no: Mapped[str] = mapped_column(String(64), nullable=False)
    expiry: Mapped[date | None] = mapped_column(Date, nullable=True)
    qty: Mapped[Decimal] = mapped_column(  # cache of sum(stock_movement.qty) for the batch
        Numeric(12, 3), nullable=False, default=Decimal(0), server_default="0"
    )
    cost_paise: Mapped[int] = mapped_column(
        BigInteger, nullable=False, default=0, server_default="0"
    )
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class StockMovement(Base, TenantRow):
    __tablename__ = "stock_movement"
    __table_args__ = (
        CheckConstraint(f"kind IN ({sql_in(MovementKind)})", name="kind"),
        CheckConstraint(
            "(kind IN ('receipt', 'transfer_in') AND qty > 0) OR "
            "(kind IN ('sale', 'transfer_out', 'damage') AND qty < 0) OR "
            "(kind = 'adjust' AND qty <> 0)",
            name="qty_sign",
        ),
        Index("ix_stock_movement_store_sku", "tenant_id", "store_id", "sku_id", "created_at"),
        Index("ix_stock_movement_batch_id", "batch_id"),
        Index("ix_stock_movement_ref", "tenant_id", "ref_type", "ref_id"),
    )

    # Wall clock so movements written in one transaction keep their order.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
        server_default=func.now(),
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="RESTRICT"), nullable=False
    )
    batch_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stock_batch.id", ondelete="SET NULL"), nullable=True
    )
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)  # signed delta
    ref_type: Mapped[str | None] = mapped_column(String(32), nullable=True)  # order, transfer...
    ref_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)  # user.id
    reason: Mapped[str | None] = mapped_column(String(16), nullable=True)  # write-off / adjust
    photo_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)  # damage photo


class StockReservation(Base, BaseColumns):
    __tablename__ = "stock_reservation"
    __table_args__ = (
        CheckConstraint("qty > 0", name="qty"),
        CheckConstraint(f"status IN ({sql_in(ReservationStatus)})", name="status"),
        Index("ix_stock_reservation_batch_status", "tenant_id", "batch_id", "status"),
        Index("ix_stock_reservation_order_id", "order_id"),
    )

    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="RESTRICT"), nullable=False
    )
    batch_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stock_batch.id", ondelete="CASCADE"), nullable=False
    )
    order_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("order.id", ondelete="CASCADE"), nullable=False
    )
    order_line_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("order_line.id", ondelete="CASCADE"), nullable=False
    )
    qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=ReservationStatus.ACTIVE
    )


__all__ = [
    "INBOUND_KINDS",
    "OUTBOUND_KINDS",
    "QTY_SCALE",
    "MovementKind",
    "ReservationStatus",
    "StockBatch",
    "StockMovement",
    "StockReservation",
    "WriteOffReason",
]
