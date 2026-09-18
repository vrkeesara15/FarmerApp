"""``POST /v1/payments`` and ``GET /v1/payments/{id}`` (FA-021, ST-002, FM-010, SEC-023).

Amounts are recomputed server-side; each mode has its own evidence (QR / link / receipt /
terminal reference / credit decision); scope follows SPEC 2.6.
"""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import func, select

from farmerapp.auth.models import UserRole
from farmerapp.khata.models import CreditApprovalRequest, KhataEntry, khata_balance
from farmerapp.orders.models import OrderStatus
from farmerapp.payments.events import PaymentCaptured
from farmerapp.payments.models import Payment
from tests.payments.helpers import PayWorld, request_transactions


async def _pay(
    client: AsyncClient, pw: PayWorld, body: dict[str, Any], role: str = "store_manager"
) -> Any:
    return await client.post("/v1/payments", json=body, headers=pw.headers(role))


# --------------------------------------------------------------------------- UPI QR / link
async def test_upi_qr_for_an_order_uses_the_server_amount(
    client: AsyncClient, pw: PayWorld
) -> None:
    order = await pw.order(118_000)
    resp = await _pay(client, pw, {"order_id": str(order.id), "mode": "upi_qr"})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "pending" and body["amount_paise"] == 118_000
    assert body["qr_payload"].startswith("upi://pay") and body["expires_at"]
    qr = pw.provider.qrs[-1]
    assert qr["amount"] == 118_000
    assert qr["notes"] == {
        "tenant_id": str(pw.tenant_id),
        "payment_id": body["payment_id"],
        "order_id": str(order.id),
    }
    row = await pw.session.get_one(Payment, uuid.UUID(body["payment_id"]))
    assert row.provider == "razorpay" and row.provider_order_id == qr["id"]
    assert row.collected_by == pw.user("store_manager").id

    poll = await client.get(f"/v1/payments/{row.id}", headers=pw.headers("store_manager"))
    assert poll.status_code == 200
    assert poll.json()["state"] == "waiting" and poll.json()["qr_payload"] == body["qr_payload"]


async def test_client_amount_is_only_checked(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(50_000)
    wrong = await _pay(
        client, pw, {"order_id": str(order.id), "mode": "upi_qr", "amount_paise": 49_999}
    )
    assert wrong.status_code == 422 and wrong.json()["code"] == "amount_mismatch"
    assert wrong.json()["due_paise"] == 50_000
    right = await _pay(
        client, pw, {"order_id": str(order.id), "mode": "upi_qr", "amount_paise": 50_000}
    )
    assert right.status_code == 201


async def test_paid_and_cancelled_orders_cannot_be_collected(
    client: AsyncClient, pw: PayWorld
) -> None:
    order = await pw.order(20_000)
    first = await _pay(
        client, pw, {"order_id": str(order.id), "mode": "card_terminal", "reference_note": "T1"}
    )
    assert first.status_code == 201 and first.json()["status"] == "paid"
    again = await _pay(client, pw, {"order_id": str(order.id), "mode": "upi_qr"})
    assert again.status_code == 409 and again.json()["code"] == "already_paid"

    cancelled = await pw.order(20_000, status=OrderStatus.CANCELLED)
    resp = await _pay(client, pw, {"order_id": str(cancelled.id), "mode": "upi_qr"})
    assert resp.status_code == 409 and resp.json()["code"] == "order_cancelled"


async def test_payment_link_is_sent_by_sms_or_whatsapp(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(30_000)
    sms = await _pay(client, pw, {"order_id": str(order.id), "mode": "payment_link"})
    assert sms.status_code == 201, sms.text
    body = sms.json()
    assert body["sent_via"] == "sms" and body["short_url"].startswith("https://rzp.test/")
    message = pw.messages.sent[-1]
    assert message.channel == "sms" and message.to == pw.farmer.phone
    assert body["short_url"] in message.body and "300.00" in message.body

    dues = await pw.debit(12_345)
    wa = await _pay(
        client,
        pw,
        {
            "farmer_id": str(pw.farmer.id),
            "store_id": str(pw.store.id),
            "mode": "payment_link",
            "channel": "whatsapp",
            "phone": "+919876543210",
        },
    )
    assert wa.status_code == 201, wa.text
    assert wa.json()["amount_paise"] >= dues.amount_paise
    message = pw.messages.sent[-1]
    assert message.channel == "whatsapp" and message.template == "payment_link"
    assert message.to == "+919876543210" and message.params["url"] == wa.json()["short_url"]


async def test_walk_in_link_needs_a_phone(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(10_000, farmer=False)
    resp = await _pay(client, pw, {"order_id": str(order.id), "mode": "payment_link"})
    assert resp.status_code == 422 and resp.json()["code"] == "phone_required"


async def test_provider_failure_is_502_and_leaves_no_payment(
    client: AsyncClient, pw: PayWorld
) -> None:
    order = await pw.order(10_000)
    pw.provider.fail_next = True
    resp = await _pay(client, pw, {"order_id": str(order.id), "mode": "upi_qr"})
    assert resp.status_code == 502 and resp.json()["code"] == "provider_error"
    count = await pw.session.scalar(
        select(func.count()).select_from(Payment).where(Payment.order_id == order.id)
    )
    assert count == 0


# --------------------------------------------------------------------------- dues
async def test_dues_full_partial_and_over_balance(client: AsyncClient, pw: PayWorld) -> None:
    await pw.debit(40_000)
    balance = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    target = {"farmer_id": str(pw.farmer.id), "store_id": str(pw.store.id)}

    over = await _pay(client, pw, {**target, "mode": "upi_qr", "amount_paise": balance + 1})
    assert over.status_code == 422 and over.json()["code"] == "amount_mismatch"

    partial = await _pay(client, pw, {**target, "mode": "upi_qr", "amount_paise": 10_000})
    assert partial.status_code == 201 and partial.json()["amount_paise"] == 10_000

    full = await _pay(client, pw, {**target, "mode": "upi_qr"})
    assert full.status_code == 201 and full.json()["amount_paise"] == balance
    assert full.json()["order_id"] is None and full.json()["farmer_id"] == str(pw.farmer.id)


async def test_nothing_due_is_409(client: AsyncClient, pw: PayWorld) -> None:
    balance = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    if balance > 0:  # settle whatever the seed left open
        resp = await _pay(
            client,
            pw,
            {
                "farmer_id": str(pw.farmer.id),
                "store_id": str(pw.store.id),
                "mode": "card_terminal",
                "reference_note": "settle",
            },
        )
        assert resp.status_code == 201, resp.text
    resp = await _pay(
        client,
        pw,
        {"farmer_id": str(pw.farmer.id), "store_id": str(pw.store.id), "mode": "upi_qr"},
    )
    assert resp.status_code == 409 and resp.json()["code"] == "nothing_due"


async def test_cash_dues_post_the_khata_credit_immediately(
    client: AsyncClient, pw: PayWorld
) -> None:
    await pw.debit(25_000)
    before = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    receipt = await pw.blob()
    resp = await _pay(
        client,
        pw,
        {
            "farmer_id": str(pw.farmer.id),
            "store_id": str(pw.store.id),
            "mode": "cash",
            "amount_paise": 5_000,
            "receipt_uri": receipt,
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "pending_reconciliation" and body["khata_entry_id"]
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == before - 5_000
    assert pw.ledger.credits[-1]["ref_id"] == uuid.UUID(body["payment_id"])
    assert pw.ledger.credits[-1]["actor"].actor_id == pw.user("store_manager").id


# --------------------------------------------------------------------------- cash / card
async def test_cash_needs_an_uploaded_receipt(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(10_000)
    base = {"order_id": str(order.id), "mode": "cash"}
    missing = await _pay(client, pw, base)
    assert missing.status_code == 422 and missing.json()["code"] == "receipt_required"
    for bad in (
        "not-a-uri",
        f"gs://local/{uuid.uuid4()}/receipt/{'0' * 64}",  # another tenant's prefix
        f"gs://local/{pw.tenant_id}/receipt/{'0' * 64}",  # never uploaded
    ):
        resp = await _pay(client, pw, {**base, "receipt_uri": bad})
        assert resp.status_code == 422 and resp.json()["code"] == "invalid_blob", bad
    ok = await _pay(client, pw, {**base, "receipt_uri": await pw.blob()})
    assert ok.status_code == 201 and ok.json()["status"] == "pending_reconciliation"


async def test_card_needs_the_terminal_reference_and_emits_capture(
    client: AsyncClient, pw: PayWorld, events: list[Any]
) -> None:
    order = await pw.order(15_000)
    missing = await _pay(client, pw, {"order_id": str(order.id), "mode": "card_terminal"})
    assert missing.status_code == 422 and missing.json()["code"] == "reference_required"
    ok = await _pay(
        client,
        pw,
        {"order_id": str(order.id), "mode": "card_terminal", "reference_note": "RRN 123456"},
    )
    assert ok.status_code == 201 and ok.json()["status"] == "paid"
    captured = [e for e in events if isinstance(e, PaymentCaptured)]
    assert len(captured) == 1
    assert captured[0].order_id == order.id and captured[0].mode == "card_terminal"
    assert captured[0].amount_paise == 15_000


# --------------------------------------------------------------------------- credit
async def test_credit_goes_through_the_real_credit_gate(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(60_000)
    before = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    resp = await _pay(client, pw, {"order_id": str(order.id), "mode": "credit"})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "paid" and body["mode"] == "credit"
    check = pw.ledger.checks[-1]
    assert check["order_id"] == order.id and check["amount_paise"] == 60_000
    assert check["farmer_id"] == pw.farmer.id and check["store_id"] == pw.store.id
    assert pw.ledger.credits == []
    # ST-007: the gate posted exactly one debit for the order; the payment links it.
    debits = (
        (await pw.session.execute(select(KhataEntry).where(KhataEntry.ref_id == order.id)))
        .scalars()
        .all()
    )
    assert [(d.type, d.ref_type, d.amount_paise) for d in debits] == [("debit", "order", 60_000)]
    assert body["khata_entry_id"] == str(debits[0].id)
    payment = await pw.session.get_one(Payment, uuid.UUID(body["payment_id"]))
    assert payment.khata_entry_id == debits[0].id
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == before + 60_000


async def test_credit_beyond_the_limit_is_402_and_the_approval_request_commits(
    client: AsyncClient, pw: PayWorld
) -> None:
    request_transactions(pw)  # a raised error would roll the request back, as in production
    balance = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    await pw.set_limit(max(balance, 0) + 10_000)
    order = await pw.order(60_000)
    resp = await _pay(client, pw, {"order_id": str(order.id), "mode": "credit"})
    assert resp.status_code == 402, resp.text
    problem = resp.json()
    assert problem["code"] == "credit_limit_exceeded"
    assert problem["shortfall_paise"] == 50_000 - min(balance, 0)
    request = await pw.session.get_one(
        CreditApprovalRequest, uuid.UUID(problem["approval_request_id"])
    )
    assert request.status == "pending" and request.order_id == order.id
    assert request.amount_paise == 60_000
    # Nothing else was written: no payment, no khata debit.
    assert (
        await pw.session.scalar(
            select(func.count()).select_from(Payment).where(Payment.order_id == order.id)
        )
        == 0
    )
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == balance


async def test_credit_needs_an_order_of_a_known_farmer(client: AsyncClient, pw: PayWorld) -> None:
    await pw.debit(1_000)
    dues = await _pay(
        client,
        pw,
        {"farmer_id": str(pw.farmer.id), "store_id": str(pw.store.id), "mode": "credit"},
    )
    assert dues.status_code == 422 and dues.json()["code"] == "invalid_mode"
    walk_in = await pw.order(1_000, farmer=False)
    resp = await _pay(client, pw, {"order_id": str(walk_in.id), "mode": "credit"})
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_mode"


# --------------------------------------------------------------------------- roles / scope
async def test_farmer_pays_own_order_by_upi_only(client: AsyncClient, pw: PayWorld) -> None:
    demo = next(f for f in pw.world.a.farmers if f.user_id is not None)
    farmer_user = pw.user(UserRole.FARMER)
    assert demo.user_id == farmer_user.id
    order = await pw.order(9_900, farmer=demo)
    cash = await _pay(
        client,
        pw,
        {"order_id": str(order.id), "mode": "cash", "receipt_uri": await pw.blob()},
        role="farmer",
    )
    assert cash.status_code == 403 and cash.json()["code"] == "mode_not_allowed"
    upi = await _pay(client, pw, {"order_id": str(order.id), "mode": "upi_qr"}, role="farmer")
    assert upi.status_code == 201, upi.text
    row = await pw.session.get_one(Payment, uuid.UUID(upi.json()["payment_id"]))
    assert row.collected_by is None
    poll = await client.get(f"/v1/payments/{row.id}", headers=pw.headers("farmer"))
    assert poll.status_code == 200

    someone_else = await pw.order(9_900, farmer=pw.farmer)
    if pw.farmer.id != demo.id:
        resp = await _pay(
            client, pw, {"order_id": str(someone_else.id), "mode": "upi_qr"}, role="farmer"
        )
        assert resp.status_code == 404


async def test_store_scope_hides_other_stores(client: AsyncClient, pw: PayWorld) -> None:
    assert pw.other_store is not None
    order = await pw.order(5_000, store=pw.other_store, farmer=False)
    resp = await _pay(client, pw, {"order_id": str(order.id), "mode": "upi_qr"})
    assert resp.status_code == 404
    dues = await _pay(
        client,
        pw,
        {"farmer_id": str(pw.farmer.id), "store_id": str(pw.other_store.id), "mode": "upi_qr"},
    )
    assert dues.status_code == 404
    owner = await _pay(client, pw, {"order_id": str(order.id), "mode": "upi_qr"}, role="owner")
    assert owner.status_code == 201
    hidden = await client.get(
        f"/v1/payments/{owner.json()['payment_id']}", headers=pw.headers("store_manager")
    )
    assert hidden.status_code == 404


async def test_request_validation(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(1_000)
    both = await _pay(
        client,
        pw,
        {"order_id": str(order.id), "farmer_id": str(pw.farmer.id), "mode": "upi_qr"},
    )
    assert both.status_code == 422
    neither = await _pay(client, pw, {"farmer_id": str(pw.farmer.id), "mode": "upi_qr"})
    assert neither.status_code == 422
