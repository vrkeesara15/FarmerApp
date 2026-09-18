"""The orders module's subscriber to FA-021 ``PaymentCaptured`` (ST-005 state machine).

A prepaid order (UPI QR / payment link) is placed with its stock held and waits in
``placed``; an order from before FA-020 may also sit in ``placed``. When a payment for it
is captured — webhook ``paid`` in the worker (SEC-023) or cash / card / credit at the
counter — and the money received now covers the order total, the order moves
``placed -> reserved`` in the payment's own transaction (``bus.dispatch`` runs this in a
savepoint: a failure here is logged and never un-pays the payment). Orders in any other
status are left alone (a POS sale is already handed over; a reserved order stays put).

``register()`` is idempotent; the API (``create_app``) and the worker's payment handler call
it so the subscription exists wherever payments are captured.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.logging import get_logger
from farmerapp.orders.models import Order
from farmerapp.orders.service import advance_paid_order
from farmerapp.payments.config import IST
from farmerapp.payments.events import PaymentCaptured, bus
from farmerapp.payments.service import received_for_order

log = get_logger("farmerapp.orders.payment_events")


async def on_payment_captured(session: AsyncSession, event: PaymentCaptured) -> None:
    order = (
        await session.execute(
            select(Order)
            .where(
                Order.id == event.order_id,
                Order.tenant_id == event.tenant_id,
                Order.deleted_at.is_(None),
            )
            .with_for_update()
        )
    ).scalar_one_or_none()
    if order is None:
        log.warning("payment_captured_order_missing", order_id=str(event.order_id))
        return
    received = await received_for_order(session, order.id)
    if received < order.total_paise:
        log.info(
            "payment_captured_order_partly_paid",
            order_id=str(order.id),
            received_paise=received,
            total_paise=order.total_paise,
        )
        return
    moved = await advance_paid_order(
        session,
        order,
        today=event.at.astimezone(IST).date(),
        note=f"Payment {event.payment_id} captured ({event.mode})",
    )
    log.info(
        "payment_captured_order",
        order_id=str(order.id),
        payment_id=str(event.payment_id),
        advanced=moved,
        status=str(order.status),
    )


def register() -> None:
    bus.subscribe_async(PaymentCaptured, on_payment_captured)


__all__ = ["on_payment_captured", "register"]
