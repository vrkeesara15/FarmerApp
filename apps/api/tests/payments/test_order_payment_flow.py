"""FA-020 x FA-021 end to end: a prepaid order waits in ``placed`` until its UPI payment is
captured, then the orders module's ``PaymentCaptured`` subscriber moves it to ``reserved``
(ST-005 state machine) and the farmer is notified.

create order -> UPI QR payment -> signed webhook -> Pub/Sub hand-off -> worker handler ->
payment ``paid`` -> order ``reserved`` -> notification for the farmer's login.
"""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.notifications.models import Notification
from farmerapp.orders import payment_events
from farmerapp.orders.models import Order, OrderStatusEvent
from farmerapp.payments.events import PaymentCaptured, bus
from farmerapp.payments.models import Payment
from farmerapp.payments.publisher import RecordingPublisher
from farmerapp.payments.worker import handle_payment_webhook
from farmerapp.stock.models import StockReservation
from tests.orders.helpers import demo_farmer, place, receive
from tests.payments.helpers import PayWorld, same_session

URL = "/v1/webhooks/razorpay"


async def _events_of(pw: PayWorld, order_id: uuid.UUID) -> list[tuple[str | None, str]]:
    rows = (
        (
            await pw.session.execute(
                select(OrderStatusEvent)
                .where(OrderStatusEvent.order_id == order_id)
                .order_by(OrderStatusEvent.created_at, OrderStatusEvent.id)
            )
        )
        .scalars()
        .all()
    )
    return [(r.from_status, r.to_status) for r in rows]


async def test_upi_paid_order_advances_and_notifies_the_farmer(
    client: AsyncClient, pw: PayWorld, events: list[Any]
) -> None:
    world, bearer = pw.world, pw.bearer
    await receive(client, bearer, world, qty=10)
    farmer = demo_farmer(world.a)
    assert farmer.user_id is not None
    officer = pw.user("field_officer")

    # 1. The officer places a prepaid (UPI) order: stock is held, the order waits in placed.
    placed = await place(client, bearer, world, farmer=farmer, payment_mode="upi_qr")
    order_id = uuid.UUID(placed["id"])
    assert placed["status"] == "placed"
    assert [r["status"] for r in placed["reservations"]] == ["active"]
    assert await _events_of(pw, order_id) == [(None, "placed")]

    # 2. The farmer pays their own order by UPI QR.
    resp = await client.post(
        "/v1/payments",
        json={"order_id": str(order_id), "mode": "upi_qr"},
        headers=pw.headers("farmer"),
    )
    assert resp.status_code == 201, resp.text
    payment_id = uuid.UUID(resp.json()["payment_id"])
    assert resp.json()["amount_paise"] == placed["total_paise"]

    # 3. The provider's signed webhook is stored and handed to Pub/Sub.
    recorder = RecordingPublisher()
    pw.services.publisher = recorder
    body, headers = pw.webhook(
        "payment.captured",
        payment=pw.captured(payment_id, placed["total_paise"]),
        event_id="evt_e2e_order",
    )
    ack = await client.post(URL, content=body, headers=headers)
    assert ack.status_code == 200 and ack.json()["status"] == "accepted"
    order = await pw.session.get_one(Order, order_id)
    await pw.session.refresh(order)
    assert order.status == "placed"  # nothing moves before the worker runs

    # 4. The worker applies it: payment paid, order advanced in the same transaction.
    applied = await handle_payment_webhook(
        recorder.message(),
        session_provider=lambda _tenant: same_session(pw.session),
        services=pw.services,
    )
    assert applied is not None and applied.status == "processed"
    payment = await pw.session.get_one(Payment, payment_id)
    await pw.session.refresh(payment)
    assert payment.status == "paid" and payment.provider_event_id == "evt_e2e_order"
    await pw.session.refresh(order)
    assert order.status == "reserved"
    assert await _events_of(pw, order_id) == [(None, "placed"), ("placed", "reserved")]
    advance = (
        await pw.session.execute(
            select(OrderStatusEvent).where(
                OrderStatusEvent.order_id == order_id, OrderStatusEvent.to_status == "reserved"
            )
        )
    ).scalar_one()
    assert advance.actor_id is None and str(payment_id) in (advance.note or "")
    # The held reservation is kept, not doubled.
    reservations = (
        (
            await pw.session.execute(
                select(StockReservation).where(StockReservation.order_id == order_id)
            )
        )
        .scalars()
        .all()
    )
    assert [r.status for r in reservations] == ["active"]
    captured = [e for e in events if isinstance(e, PaymentCaptured)]
    assert [e.order_id for e in captured] == [order_id]

    # 5. The farmer's login (and the placing officer) are notified of the new status.
    notes = (
        (
            await pw.session.execute(
                select(Notification).where(Notification.data["order_id"].astext == str(order_id))
            )
        )
        .scalars()
        .all()
    )
    by_user = {n.user_id: n for n in notes}
    assert set(by_user) == {farmer.user_id, officer.id}
    assert by_user[farmer.user_id].kind == "order_status"
    assert by_user[farmer.user_id].body_key == "order.status.reserved"

    # A redelivery changes nothing (idempotent webhook, order already reserved).
    again = await handle_payment_webhook(
        recorder.message(),
        session_provider=lambda _tenant: same_session(pw.session),
        services=pw.services,
    )
    assert again is not None and again.status == "processed"
    assert await _events_of(pw, order_id) == [(None, "placed"), ("placed", "reserved")]


async def test_capture_leaves_orders_that_are_not_waiting_alone(
    client: AsyncClient, pw: PayWorld
) -> None:
    """A reserved (postpaid) order stays put when its cash payment is taken."""
    world, bearer = pw.world, pw.bearer
    await receive(client, bearer, world, qty=10)
    placed = await place(client, bearer, world, farmer=demo_farmer(world.a))
    assert placed["status"] == "reserved"
    resp = await client.post(
        "/v1/payments",
        json={"order_id": placed["id"], "mode": "card_terminal", "reference_note": "RRN 1"},
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 201, resp.text
    order = await pw.session.get_one(Order, uuid.UUID(placed["id"]))
    await pw.session.refresh(order)
    assert order.status == "reserved"
    assert await _events_of(pw, order.id) == [(None, "placed"), ("placed", "reserved")]


async def test_a_failing_subscriber_never_un_pays_the_payment(
    client: AsyncClient, pw: PayWorld
) -> None:
    """``bus.dispatch`` runs writing subscribers in a savepoint: a failure is logged, its
    writes roll back, and the payment still commits."""
    order = await pw.order(4_000)

    async def boom(session: AsyncSession, event: PaymentCaptured) -> None:
        session.add(Notification(tenant_id=event.tenant_id, user_id=uuid.uuid4(), kind="x"))
        await session.flush()  # NOT NULL violation: the savepoint absorbs it

    bus.subscribe_async(PaymentCaptured, boom)
    try:
        resp = await client.post(
            "/v1/payments",
            json={"order_id": str(order.id), "mode": "card_terminal", "reference_note": "RRN 2"},
            headers=pw.headers("store_manager"),
        )
    finally:
        bus.unsubscribe_async(PaymentCaptured, boom)
    assert resp.status_code == 201, resp.text
    payment = await pw.session.get_one(Payment, uuid.UUID(resp.json()["payment_id"]))
    assert payment.status == "paid"
    await pw.session.refresh(order)
    assert order.status == "reserved"  # the real subscriber still ran (placed -> reserved)


async def test_an_order_placed_on_credit_cannot_be_debited_again(
    client: AsyncClient, pw: PayWorld
) -> None:
    """The gate posted the debit at placing (FA-020); a credit payment must not add one."""
    world, bearer = pw.world, pw.bearer
    await receive(client, bearer, world, qty=10)
    farmer = demo_farmer(world.a)
    await pw.set_limit(50_000_000, farmer=farmer)
    placed = await place(client, bearer, world, farmer=farmer, payment_mode="credit")
    resp = await client.post(
        "/v1/payments",
        json={"order_id": placed["id"], "mode": "credit"},
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 409 and resp.json()["code"] == "already_paid"
    assert pw.ledger.checks == []


def test_register_is_idempotent() -> None:
    payment_events.register()
    payment_events.register()
    assert bus._async[PaymentCaptured].count(payment_events.on_payment_captured) == 1
