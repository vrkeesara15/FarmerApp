"""Orders (SPEC 8.2 ``order / order_line``; FA-020, ST-001, ST-005, FM-006).

* ``order`` — a sale or an order to fulfil: from a field officer (``channel = officer``,
  FA-020), the farmer app (``farmer_app``, FM-006) or the store counter (``pos``, ST-001).
  ``farmer_id`` is NULL for a walk-in cash sale. ``status`` follows the ST-005 queue
  (``draft`` -> ``placed`` -> ``reserved`` (stock reserved, FA-020) -> ``packed`` -> ``ready``
  -> ``handed_over`` (pickup) / ``delivered`` (delivery); ``cancelled`` from any open
  status). Totals are integer paise with ``total = subtotal - discount + tax`` enforced by
  a CHECK (SEC-023: amounts are recomputed server-side, never trusted from a client).
  ``placed_by`` is the user who placed it (officer, store staff or the farmer's own login);
  ``invoice_no`` is assigned at handover (ST-001 GST invoice; unique per tenant);
  ``client_order_id`` is the id the device generated offline (unique per tenant, sync).
* ``order_line`` — one SKU on an order: quantity, the unit price the price list resolved
  (``farmerapp.catalog.pricing``), the product's GST rate at the time, the line total and,
  when the line came from a recommendation, ``label_claim_id`` — *why* the SKU was
  recommended (DX-007: never a SKU without a matching claim). ``batch_id`` is set when the
  stock is reserved / picked (ST-003).
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import BASIS_POINTS, sql_in
from farmerapp.db.base import Base, BaseColumns, TenantRow


class OrderChannel(StrEnum):
    OFFICER = "officer"  # field agent app (FA-020)
    FARMER_APP = "farmer_app"  # FM-006
    POS = "pos"  # store counter (ST-001)


class OrderStatus(StrEnum):
    DRAFT = "draft"
    PLACED = "placed"
    RESERVED = "reserved"
    PACKED = "packed"
    READY = "ready"
    HANDED_OVER = "handed_over"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


class Fulfilment(StrEnum):
    PICKUP = "pickup"
    DELIVERY = "delivery"


#: Statuses in which the sale is complete (stock left the store, payment due / taken).
FULFILLED_STATUSES = frozenset({OrderStatus.HANDED_OVER, OrderStatus.DELIVERED})
#: Statuses still in the store queue (ST-005).
OPEN_STATUSES = frozenset(
    {OrderStatus.PLACED, OrderStatus.RESERVED, OrderStatus.PACKED, OrderStatus.READY}
)


class Order(Base, BaseColumns):
    __tablename__ = "order"
    __table_args__ = (
        UniqueConstraint("tenant_id", "invoice_no", name="uq_order_invoice_no"),
        UniqueConstraint("tenant_id", "client_order_id", name="uq_order_client_order_id"),
        CheckConstraint(f"channel IN ({sql_in(OrderChannel)})", name="channel"),
        CheckConstraint(f"status IN ({sql_in(OrderStatus)})", name="status"),
        CheckConstraint(f"fulfilment IN ({sql_in(Fulfilment)})", name="fulfilment"),
        CheckConstraint(
            "subtotal_paise >= 0 AND discount_paise >= 0 AND tax_paise >= 0 AND total_paise >= 0",
            name="amounts",
        ),
        CheckConstraint("total_paise = subtotal_paise - discount_paise + tax_paise", name="total"),
        Index("ix_order_store_status", "tenant_id", "store_id", "status"),
        Index("ix_order_farmer_id", "farmer_id"),
        Index("ix_order_placed_by", "placed_by"),
    )

    farmer_id: Mapped[uuid.UUID | None] = mapped_column(  # NULL = walk-in
        ForeignKey("farmer.id", ondelete="SET NULL"), nullable=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="RESTRICT"), nullable=False
    )
    channel: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default=OrderStatus.DRAFT)
    fulfilment: Mapped[str] = mapped_column(String(16), nullable=False, default=Fulfilment.PICKUP)
    subtotal_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    discount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    tax_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    total_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    placed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    placed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_no: Mapped[str | None] = mapped_column(String(32), nullable=True)
    client_order_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)


class OrderLine(Base, BaseColumns):
    __tablename__ = "order_line"
    __table_args__ = (
        CheckConstraint("qty > 0", name="qty"),
        CheckConstraint("unit_price_paise >= 0 AND line_total_paise >= 0", name="amounts"),
        CheckConstraint(f"gst_rate_bp >= 0 AND gst_rate_bp <= {BASIS_POINTS}", name="gst_rate_bp"),
        Index("ix_order_line_order_id", "order_id"),
        Index("ix_order_line_sku_id", "sku_id"),
    )

    order_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("order.id", ondelete="CASCADE"), nullable=False
    )
    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="RESTRICT"), nullable=False
    )
    batch_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stock_batch.id", ondelete="SET NULL"), nullable=True
    )
    qty: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    unit_price_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    gst_rate_bp: Mapped[int] = mapped_column(Integer, nullable=False)
    line_total_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)  # qty x unit, pre-tax
    label_claim_id: Mapped[uuid.UUID | None] = mapped_column(  # why it was recommended (DX-007)
        ForeignKey("label_claim.id", ondelete="SET NULL"), nullable=True
    )


#: ST-005 queue: the statuses each status may move to (anything else is ``invalid_transition``).
TRANSITIONS: dict[OrderStatus, frozenset[OrderStatus]] = {
    OrderStatus.DRAFT: frozenset({OrderStatus.PLACED, OrderStatus.CANCELLED}),
    OrderStatus.PLACED: frozenset({OrderStatus.RESERVED, OrderStatus.CANCELLED}),
    OrderStatus.RESERVED: frozenset({OrderStatus.PACKED, OrderStatus.CANCELLED}),
    OrderStatus.PACKED: frozenset({OrderStatus.READY, OrderStatus.CANCELLED}),
    OrderStatus.READY: frozenset(
        {OrderStatus.HANDED_OVER, OrderStatus.DELIVERED, OrderStatus.CANCELLED}
    ),
    OrderStatus.HANDED_OVER: frozenset(),
    OrderStatus.DELIVERED: frozenset(),
    OrderStatus.CANCELLED: frozenset(),
}


def can_transition(current: str, target: str) -> bool:
    return OrderStatus(target) in TRANSITIONS[OrderStatus(current)]


class OrderStatusEvent(Base, TenantRow):
    """Append-only history of an order's status (ST-005): one row per change, with who
    made it and a note. ``from_status`` is NULL for the placing event."""

    __tablename__ = "order_status_event"
    __table_args__ = (
        CheckConstraint(f"to_status IN ({sql_in(OrderStatus)})", name="to_status"),
        CheckConstraint(
            f"from_status IS NULL OR from_status IN ({sql_in(OrderStatus)})", name="from_status"
        ),
        Index("ix_order_status_event_order", "tenant_id", "order_id", "created_at"),
    )

    # Wall clock so events written in one transaction keep their order.
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
        server_default=func.now(),
    )
    order_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("order.id", ondelete="CASCADE"), nullable=False
    )
    from_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    to_status: Mapped[str] = mapped_column(String(16), nullable=False)
    note: Mapped[str | None] = mapped_column(String(500), nullable=True)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )


def line_total_paise(qty: Decimal, unit_price_paise: int) -> int:
    """``qty x unit price`` rounded half-up to the paisa."""
    return int((qty * unit_price_paise).quantize(Decimal(1), rounding="ROUND_HALF_UP"))


def tax_paise(line_total: int, gst_rate_bp: int) -> int:
    """GST on a pre-tax line total, rounded half-up to the paisa."""
    return int(
        (Decimal(line_total) * gst_rate_bp / BASIS_POINTS).quantize(
            Decimal(1), rounding="ROUND_HALF_UP"
        )
    )


__all__ = [
    "FULFILLED_STATUSES",
    "OPEN_STATUSES",
    "TRANSITIONS",
    "Fulfilment",
    "Order",
    "OrderChannel",
    "OrderLine",
    "OrderStatus",
    "OrderStatusEvent",
    "can_transition",
    "line_total_paise",
    "tax_paise",
]
