"""``OrderPort`` — how the POS sale (ST-001) persists its order and moves stock.

Orders and stock belong to the FA-020 / ST-003 branch; the POS only needs "write this
priced, taxed sale as a handed-over ``pos`` order and take the stock out". The port keeps
that seam explicit: tests inject a fake, and the orders branch can replace
``LedgerOrderPort`` with its own service (reservations, queue events) without touching
the POS or invoice code.

``LedgerOrderPort`` (the default) writes ``order`` + ``order_line`` with the server-side
prices and GST rates and appends one ``sale`` movement per batch consumed through
``farmerapp.stock.ledger.apply_movement`` — FEFO (earliest expiry first, then oldest
receipt), never below zero (409 ``insufficient_stock``).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.orders.models import Fulfilment, Order, OrderChannel, OrderLine, OrderStatus
from farmerapp.stock.ledger import InsufficientStockError, apply_movement
from farmerapp.stock.models import MovementKind, StockBatch


@dataclass(frozen=True)
class PosOrderLine:
    sku_id: uuid.UUID
    qty: Decimal
    unit_price_paise: int
    gst_rate_bp: int
    line_total_paise: int  # taxable value (qty x unit, pre-tax)


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

    @property
    def total_paise(self) -> int:
        return self.subtotal_paise + self.tax_paise


class OrderPort(Protocol):
    async def create_pos_order(self, session: AsyncSession, draft: PosOrderDraft) -> Order: ...


class LedgerOrderPort:
    async def _take_stock(
        self, session: AsyncSession, draft: PosOrderDraft, line: PosOrderLine, order_id: uuid.UUID
    ) -> uuid.UUID | None:
        batches = (
            (
                await session.execute(
                    select(StockBatch)
                    .where(
                        StockBatch.store_id == draft.store_id,
                        StockBatch.sku_id == line.sku_id,
                        StockBatch.deleted_at.is_(None),
                        StockBatch.qty > 0,
                    )
                    .order_by(
                        StockBatch.expiry.asc().nulls_last(),
                        StockBatch.received_at,
                        StockBatch.id,
                    )
                    .with_for_update()
                )
            )
            .scalars()
            .all()
        )
        if sum((b.qty for b in batches), Decimal(0)) < line.qty:
            raise InsufficientStockError(f"Not enough stock of SKU {line.sku_id} at this store.")
        remaining, first = line.qty, None
        for batch in batches:
            if remaining <= 0:
                break
            take = min(batch.qty, remaining)
            await apply_movement(
                session,
                tenant_id=draft.tenant_id,
                store_id=draft.store_id,
                sku_id=line.sku_id,
                kind=MovementKind.SALE,
                qty=-take,
                batch=batch,
                ref_type="order",
                ref_id=order_id,
                note="POS sale",
                created_by=draft.placed_by,
                at=draft.at,
            )
            first = first or batch.id
            remaining -= take
        return first

    async def create_pos_order(self, session: AsyncSession, draft: PosOrderDraft) -> Order:
        order = Order(
            tenant_id=draft.tenant_id,
            farmer_id=draft.farmer_id,
            store_id=draft.store_id,
            channel=OrderChannel.POS.value,
            status=OrderStatus.HANDED_OVER.value,
            fulfilment=Fulfilment.PICKUP.value,
            subtotal_paise=draft.subtotal_paise,
            discount_paise=0,
            tax_paise=draft.tax_paise,
            total_paise=draft.total_paise,
            placed_by=draft.placed_by,
            placed_at=draft.at,
            notes=draft.notes,
        )
        session.add(order)
        await session.flush()
        for line in draft.lines:
            batch_id = await self._take_stock(session, draft, line, order.id)
            session.add(
                OrderLine(
                    tenant_id=draft.tenant_id,
                    order_id=order.id,
                    sku_id=line.sku_id,
                    batch_id=batch_id,
                    qty=line.qty,
                    unit_price_paise=line.unit_price_paise,
                    gst_rate_bp=line.gst_rate_bp,
                    line_total_paise=line.line_total_paise,
                )
            )
        await session.flush()
        return order


__all__ = ["LedgerOrderPort", "OrderPort", "PosOrderDraft", "PosOrderLine"]
