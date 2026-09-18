"""``OrderPort`` — how the POS sale (ST-001) persists its order and moves stock.

Orders and stock belong to FA-020 / ST-003; the POS only needs "write this priced, taxed
sale as a handed-over ``pos`` order and take the stock out". The port keeps that seam
explicit: tests can inject a fake (``app.state.pos_orders``), and the default is the orders
module's own implementation, ``farmerapp.orders.pos.OrdersPosPort`` (DX-007 claim check,
FEFO allocation through ``stock.service``, ``sale`` movements via ``consume_order``, the
order status history).

``PosOrderDraft.order_id`` is set when the POS already reserved credit for the sale (the
credit gate's debit references it); ``PosOrderLine.label_claim_id`` when a line came from a
recommendation.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.orders.models import Order


@dataclass(frozen=True)
class PosOrderLine:
    sku_id: uuid.UUID
    qty: Decimal
    unit_price_paise: int
    gst_rate_bp: int
    line_total_paise: int  # taxable value (qty x unit, pre-tax)
    label_claim_id: uuid.UUID | None = None  # DX-007: set only for a recommended SKU


@dataclass(frozen=True)
class PosOrderDraft:
    tenant_id: uuid.UUID
    store_id: uuid.UUID
    farmer_id: uuid.UUID | None
    lines: tuple[PosOrderLine, ...]
    subtotal_paise: int
    tax_paise: int
    placed_by: uuid.UUID
    at: datetime
    notes: str | None = None
    order_id: uuid.UUID | None = None  # pre-assigned when credit was reserved for it

    @property
    def total_paise(self) -> int:
        return self.subtotal_paise + self.tax_paise


class OrderPort(Protocol):
    async def create_pos_order(self, session: AsyncSession, draft: PosOrderDraft) -> Order: ...


__all__ = ["OrderPort", "PosOrderDraft", "PosOrderLine"]
