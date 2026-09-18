"""The orders module's ``OrderPort`` for the POS (ST-001 x FA-020 / ST-003 / ST-005).

``farmerapp.invoices`` persists a counter sale through ``invoices.ports.OrderPort``; this is
the default implementation, built from the orders and stock services instead of writing
models directly:

* DX-007: lines that carry a ``label_claim_id`` go through ``assert_lines_recommendable``
  (422 ``sku_not_recommendable``);
* stock: ``stock.service.allocate_fefo`` (store batches locked, unexpired only, earliest
  expiry first; short = 409 ``insufficient_stock`` per line), the allocation held as
  ``stock_reservation`` rows and immediately consumed by ``consume_order`` into ``sale``
  movements — the same path a queue handover takes, so ``batch.qty == sum(movements)``;
* the order is a ``pos`` / pickup order written ``handed_over`` (the customer leaves with the
  goods) with one ``order_status_event`` (no notification: the buyer is at the counter).

``draft.order_id`` lets the POS reserve credit for the order before it exists (ST-007: the
gate posts the debit with ``ref_id = order_id``).
"""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.invoices.ports import PosOrderDraft
from farmerapp.orders.models import Fulfilment, Order, OrderChannel, OrderLine, OrderStatus
from farmerapp.orders.service import _record_status, assert_lines_recommendable
from farmerapp.payments.config import IST
from farmerapp.stock.service import LineDemand, allocate_fefo, consume_order, hold_allocations

POS_SALE_NOTE = "POS counter sale"


class OrdersPosPort:
    async def create_pos_order(self, session: AsyncSession, draft: PosOrderDraft) -> Order:
        await assert_lines_recommendable(
            session, draft.tenant_id, [(line.sku_id, line.label_claim_id) for line in draft.lines]
        )
        today = draft.at.astimezone(IST).date()
        demands = [
            LineDemand(index=i, sku_id=line.sku_id, qty=line.qty)
            for i, line in enumerate(draft.lines)
        ]
        allocations = await allocate_fefo(session, draft.store_id, demands, today)
        order = Order(
            id=draft.order_id or uuid.uuid4(),
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
        lines: list[OrderLine] = []
        for line, allocation in zip(draft.lines, allocations, strict=True):
            row = OrderLine(
                tenant_id=draft.tenant_id,
                order_id=order.id,
                sku_id=line.sku_id,
                batch_id=allocation[0][0].id if allocation else None,
                qty=line.qty,
                unit_price_paise=line.unit_price_paise,
                gst_rate_bp=line.gst_rate_bp,
                line_total_paise=line.line_total_paise,
                label_claim_id=line.label_claim_id,
            )
            session.add(row)
            lines.append(row)
        await session.flush()
        held = [
            LineDemand(index=d.index, sku_id=d.sku_id, qty=d.qty, line_id=row.id)
            for d, row in zip(demands, lines, strict=True)
        ]
        await hold_allocations(
            session,
            tenant_id=draft.tenant_id,
            order_id=order.id,
            store_id=draft.store_id,
            demands=held,
            allocations=allocations,
        )
        await consume_order(
            session,
            tenant_id=draft.tenant_id,
            order_id=order.id,
            store_id=draft.store_id,
            demands=held,
            actor_id=draft.placed_by,
            today=today,
        )
        await _record_status(
            session,
            draft.placed_by,
            order,
            None,
            from_status=None,
            to_status=OrderStatus.HANDED_OVER,
            note=draft.notes or POS_SALE_NOTE,
            notify=False,
        )
        return order


__all__ = ["POS_SALE_NOTE", "OrdersPosPort"]
