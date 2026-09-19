"""``POST /v1/webhooks/razorpay`` (SEC-023, FA-021, FM-010): HMAC over the raw body, replay
window, idempotency by event id, amount cross-check, Pub/Sub hand-off to the worker."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import case, func, select

from farmerapp.db.models.tenant import Tenant
from farmerapp.khata.models import KhataEntry, khata_balance
from farmerapp.payments.events import PaymentCaptured
from farmerapp.payments.models import Payment, WebhookEvent
from farmerapp.payments.publisher import RecordingPublisher
from farmerapp.payments.worker import WebhookEventNotFoundError, handle_payment_webhook
from farmerapp.worker.messages import PubSubMessage
from farmerapp.worker.topics import Topic
from tests.logcontract import assert_fields, capture, one_event
from tests.payments.helpers import PayWorld, same_session

URL = "/v1/webhooks/razorpay"


async def _qr(client: AsyncClient, pw: PayWorld, body: dict[str, Any]) -> Payment:
    resp = await client.post(
        "/v1/payments", json={"mode": "upi_qr", **body}, headers=pw.headers("store_manager")
    )
    assert resp.status_code == 201, resp.text
    return await pw.session.get_one(Payment, uuid.UUID(resp.json()["payment_id"]))


async def _events(pw: PayWorld) -> list[WebhookEvent]:
    return list(
        (await pw.session.execute(select(WebhookEvent).order_by(WebhookEvent.received_at)))
        .scalars()
        .all()
    )


async def test_signed_capture_marks_paid_once(
    client: AsyncClient, pw: PayWorld, events: list[Any]
) -> None:
    order = await pw.order(118_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    body, headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 118_000), event_id="evt_once"
    )
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.json() == {"status": "processed", "event_id": "evt_once"}
    await pw.session.refresh(payment)
    assert payment.status == "paid" and payment.provider_event_id == "evt_once"
    assert payment.provider_ref and payment.paid_at is not None
    stored = [e for e in await _events(pw) if e.event_id == "evt_once"]
    assert len(stored) == 1 and stored[0].signature_ok and stored[0].status == "processed"
    captured = [e for e in events if isinstance(e, PaymentCaptured)]
    assert [c.order_id for c in captured] == [order.id]
    assert captured[0].provider_event_id == "evt_once"

    # Razorpay retries: same event id -> 200 duplicate, nothing reprocessed.
    again = await client.post(URL, content=body, headers=headers)
    assert again.status_code == 200 and again.json()["status"] == "duplicate"
    assert len([e for e in events if isinstance(e, PaymentCaptured)]) == 1

    # A different event for the same payment cannot pay twice.
    other_body, other_headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 118_000), event_id="evt_twice"
    )
    third = await client.post(URL, content=other_body, headers=other_headers)
    assert third.status_code == 200
    row = next(e for e in await _events(pw) if e.event_id == "evt_twice")
    assert row.status == "ignored" and row.error == "already_paid"

    poll = await client.get(f"/v1/payments/{payment.id}", headers=pw.headers("store_manager"))
    assert poll.json()["state"] == "paid"


async def test_bad_signature_is_401_and_the_attempt_is_stored(
    client: AsyncClient, pw: PayWorld
) -> None:
    order = await pw.order(10_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    body, headers = pw.webhook(
        "payment.captured",
        payment=pw.captured(payment.id, 10_000),
        event_id="evt_forged",
        key="not-the-secret",
    )
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 401 and resp.json()["code"] == "webhook_signature_invalid"
    await pw.session.refresh(payment)
    assert payment.status == "pending"
    rejected = [e for e in await _events(pw) if not e.signature_ok]
    assert len(rejected) == 1
    assert rejected[0].status == "rejected" and rejected[0].event_id.startswith("rejected:")
    assert rejected[0].payload["claimed_event_id"] == "evt_forged"

    # The genuine delivery of the same event id still goes through.
    genuine_body, genuine_headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 10_000), event_id="evt_forged"
    )
    ok = await client.post(URL, content=genuine_body, headers=genuine_headers)
    assert ok.status_code == 200 and ok.json()["status"] == "processed"

    no_header = await client.post(URL, content=body, headers={"X-Razorpay-Event-Id": "e"})
    assert no_header.status_code == 401


async def test_bad_signature_for_an_unknown_tenant_is_only_logged(
    client: AsyncClient, pw: PayWorld
) -> None:
    before = len(await _events(pw))
    resp = await client.post(URL, content=b"garbage", headers={"X-Razorpay-Signature": "00"})
    assert resp.status_code == 401
    assert len(await _events(pw)) == before


async def test_replay_window(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(10_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    stale_at = datetime.now(UTC) - timedelta(minutes=10)
    body, headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 10_000), created_at=stale_at
    )
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 400 and resp.json()["code"] == "webhook_stale"
    await pw.session.refresh(payment)
    assert payment.status == "pending"

    tenant = await pw.session.get_one(Tenant, pw.tenant_id)
    tenant.settings = {**tenant.settings, "webhook_replay_window_s": 3600}
    await pw.session.flush()
    ok = await client.post(URL, content=body, headers=headers)
    assert ok.status_code == 200 and ok.json()["status"] == "processed"


async def test_amount_mismatch_flags_and_does_not_pay(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(10_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    body, headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 1_000), event_id="evt_short"
    )
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 200
    row = next(e for e in await _events(pw) if e.event_id == "evt_short")
    assert row.status == "flagged" and row.error == "amount_mismatch"
    await pw.session.refresh(payment)
    assert payment.status == "pending" and payment.paid_at is None


async def test_failed_payment(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(10_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    failed = {**pw.captured(payment.id, 10_000), "status": "failed"}
    failed["error_reason"] = "payment_timed_out"
    body, headers = pw.webhook("payment.failed", payment=failed)
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 200
    poll = await client.get(f"/v1/payments/{payment.id}", headers=pw.headers("store_manager"))
    assert poll.json()["state"] == "failed"
    assert poll.json()["failure_reason"] == "payment_timed_out"

    # A later capture (the farmer retried) still pays it.
    body, headers = pw.webhook("payment.captured", payment=pw.captured(payment.id, 10_000))
    assert (await client.post(URL, content=body, headers=headers)).status_code == 200
    await pw.session.refresh(payment)
    assert payment.status == "paid" and payment.failure_reason is None


async def test_dues_capture_moves_the_balance_in_the_same_transaction(
    client: AsyncClient, pw: PayWorld
) -> None:
    """FM-010 groundwork: webhook -> khata credit in one transaction chain."""
    await pw.debit(30_000)
    before = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    payment = await _qr(
        client,
        pw,
        {"farmer_id": str(pw.farmer.id), "store_id": str(pw.store.id), "amount_paise": 20_000},
    )
    body, headers = pw.webhook("payment.captured", payment=pw.captured(payment.id, 20_000))
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 200
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == before - 20_000
    await pw.session.refresh(payment)
    assert payment.khata_entry_id is not None
    assert pw.ledger.credits[-1]["actor"].actor_role == "system"
    # Posted by the real ``khata.ledger.post_credit`` (no self-written fallback entry) ...
    entry = await pw.session.get_one(KhataEntry, payment.khata_entry_id)
    assert (entry.type, entry.ref_type, entry.ref_id) == ("credit", "payment", payment.id)
    assert entry.amount_paise == 20_000 and entry.created_by is None  # the system
    credits_for_payment = await pw.session.scalar(
        select(func.count()).select_from(KhataEntry).where(KhataEntry.ref_id == payment.id)
    )
    assert credits_for_payment == 1
    # ... and FA-022 holds: the balance is exactly the sum of the ledger's entries.
    signed = await pw.session.scalar(
        select(
            func.coalesce(
                func.sum(
                    case(
                        (KhataEntry.type == "debit", KhataEntry.amount_paise),
                        else_=-KhataEntry.amount_paise,
                    )
                ),
                0,
            )
        ).where(KhataEntry.farmer_id == pw.farmer.id, KhataEntry.store_id == pw.store.id)
    )
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == signed


async def test_payment_found_by_provider_ids_when_notes_are_missing(
    client: AsyncClient, pw: PayWorld
) -> None:
    order = await pw.order(7_700)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    entity = pw.captured(payment.id, 7_700)
    entity["notes"] = {"tenant_id": str(pw.tenant_id), "payment_id": "not-a-uuid"}
    body, headers = pw.webhook(
        "qr_code.credited",
        payment=entity,
        qr_code={"id": payment.provider_order_id},
    )
    assert (await client.post(URL, content=body, headers=headers)).status_code == 200
    await pw.session.refresh(payment)
    assert payment.status == "paid"


async def test_ignored_and_malformed_events(client: AsyncClient, pw: PayWorld) -> None:
    unknown_payment, headers = pw.webhook(
        "payment.captured", payment=pw.captured(uuid.uuid4(), 100), event_id="evt_nobody"
    )
    resp = await client.post(URL, content=unknown_payment, headers=headers)
    assert resp.status_code == 200 and resp.json()["status"] == "processed"
    row = next(e for e in await _events(pw) if e.event_id == "evt_nobody")
    assert row.status == "ignored" and row.error == "payment_not_found"

    refund, headers = pw.webhook(
        "refund.created", payment=pw.captured(uuid.uuid4(), 100), event_id="evt_refund"
    )
    assert (await client.post(URL, content=refund, headers=headers)).status_code == 200
    row = next(e for e in await _events(pw) if e.event_id == "evt_refund")
    assert row.status == "ignored" and row.error == "unhandled:refund.created"

    no_tenant, headers = pw.webhook(
        "payment.captured", payment={"id": "pay_x", "amount": 1, "notes": {}}
    )
    resp = await client.post(URL, content=no_tenant, headers=headers)
    assert resp.status_code == 200 and resp.json()["status"] == "ignored"

    ghost, headers = pw.webhook(
        "payment.captured",
        payment={"id": "pay_x", "amount": 1, "notes": {"tenant_id": str(uuid.uuid4())}},
    )
    resp = await client.post(URL, content=ghost, headers=headers)
    assert resp.status_code == 200 and resp.json()["status"] == "ignored"

    garbage = b"{not json"
    signed = {"X-Razorpay-Signature": pw.provider.sign(garbage), "X-Razorpay-Event-Id": "e1"}
    resp = await client.post(URL, content=garbage, headers=signed)
    assert resp.status_code == 400 and resp.json()["code"] == "webhook_malformed"

    body, headers = pw.webhook("payment.captured", payment=pw.captured(uuid.uuid4(), 1))
    headers.pop("X-Razorpay-Event-Id")
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 400 and resp.json()["code"] == "webhook_malformed"


# --------------------------------------------------------------------------- Pub/Sub
async def test_pubsub_delivery_and_worker_idempotency(
    client: AsyncClient, pw: PayWorld, events: list[Any]
) -> None:
    recorder = RecordingPublisher()
    pw.services.publisher = recorder
    order = await pw.order(50_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    body, headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 50_000), event_id="evt_queued"
    )
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 200 and resp.json()["status"] == "accepted"
    topic, data = recorder.messages[-1]
    assert topic == Topic.PAYMENT_WEBHOOK
    assert data["tenant_id"] == str(pw.tenant_id) and data["event_id"] == "evt_queued"
    await pw.session.refresh(payment)
    assert payment.status == "pending"  # not applied until the worker runs

    def provider(_tenant_id: uuid.UUID) -> Any:
        return same_session(pw.session)

    applied = await handle_payment_webhook(
        recorder.message(), session_provider=provider, services=pw.services
    )
    assert applied is not None and applied.status == "processed"
    await pw.session.refresh(payment)
    assert payment.status == "paid"
    # Pub/Sub redelivers: the processed row is left alone.
    again = await handle_payment_webhook(
        recorder.message(), session_provider=provider, services=pw.services
    )
    assert again is not None and again.status == "processed"
    assert len([e for e in events if isinstance(e, PaymentCaptured)]) == 1

    # Poison message: acknowledged (None), never retried forever.
    assert await handle_payment_webhook(PubSubMessage(), services=pw.services) is None
    # Row not visible yet (API transaction not committed): raise -> nack -> retry.
    missing = PubSubMessage.model_validate(
        {
            "data": recorder.message().data,
            "attributes": {},
        }
    )
    await recorder.publish(
        Topic.PAYMENT_WEBHOOK,
        {"tenant_id": str(pw.tenant_id), "webhook_event_id": str(uuid.uuid4())},
    )
    with pytest.raises(WebhookEventNotFoundError):
        await handle_payment_webhook(
            recorder.message(), session_provider=provider, services=pw.services
        )
    assert missing.json_body()["event_id"] == "evt_queued"


async def test_publish_failure_is_503_so_the_provider_retries(
    client: AsyncClient, pw: PayWorld
) -> None:
    pw.services.publisher = RecordingPublisher(fail=True)
    body, headers = pw.webhook("payment.captured", payment=pw.captured(uuid.uuid4(), 100))
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 503 and resp.json()["code"] == "webhook_unavailable"


async def test_concurrent_duplicate_insert_is_a_duplicate(pw: PayWorld) -> None:
    """The unique (tenant, provider, event id) constraint is the last line of idempotency."""
    from farmerapp.payments.webhooks import receive_webhook

    body, headers = pw.webhook(
        "payment.captured", payment=pw.captured(uuid.uuid4(), 1), event_id="evt_race"
    )
    lowered = {k.lower(): v for k, v in headers.items()}
    first = await receive_webhook(
        pw.session, body=body, headers=lowered, services=pw.services, now=datetime.now(UTC)
    )
    assert first.outcome == "processed"
    count = await pw.session.scalar(
        select(func.count()).select_from(WebhookEvent).where(WebhookEvent.event_id == "evt_race")
    )
    assert count == 1


# ---------------------------------------------------------------- NF-014 log contract
async def test_webhook_applied_and_payment_captured_log_contract(
    client: AsyncClient, pw: PayWorld, caplog: pytest.LogCaptureFixture
) -> None:
    """``farmerapp_webhook_processing`` (webhook SLO) reads ``processing_ms``;
    ``farmerapp_payments_captured`` counts ``payment_captured`` by ``mode``."""
    capture(caplog)
    order = await pw.order(50_000)
    payment = await _qr(client, pw, {"order_id": str(order.id)})
    body, headers = pw.webhook(
        "payment.captured", payment=pw.captured(payment.id, 50_000), event_id="evt_log"
    )
    resp = await client.post(URL, content=body, headers=headers)
    assert resp.status_code == 200, resp.text
    applied = one_event(caplog, "webhook_applied")
    assert_fields(
        applied, processing_ms=int, status=str, event_type=str, event_id=str, tenant_id=str
    )
    assert applied["processing_ms"] >= 0 and applied["status"] == "processed"
    assert applied["event_id"] == "evt_log" and applied["tenant_id"] == str(pw.tenant_id)
    captured = one_event(caplog, "payment_captured")
    assert_fields(captured, tenant_id=str, mode=str, payment_id=str, amount_paise=int)
    assert captured["mode"] == "upi_qr" and captured["payment_id"] == str(payment.id)


async def test_processing_ms_is_received_to_processed(pw: PayWorld) -> None:
    """Delivered later through Pub/Sub: the time in the queue counts."""
    from farmerapp.payments.webhooks import apply_webhook_event

    order = await pw.order(20_000)
    payment = Payment(
        tenant_id=pw.tenant_id,
        order_id=order.id,
        store_id=pw.store.id,
        mode="upi_qr",
        provider="razorpay",
        amount_paise=20_000,
        status="pending",
    )
    pw.session.add(payment)
    await pw.session.flush()
    received = datetime.now(UTC) - timedelta(seconds=3)
    row = WebhookEvent(
        tenant_id=pw.tenant_id,
        provider="razorpay",
        event_id="evt_queued",
        event_type="payment.captured",
        signature_ok=True,
        status="received",
        payload={},
        received_at=received,
    )
    pw.session.add(row)
    await pw.session.flush()
    import structlog

    with structlog.testing.capture_logs() as logs:
        await apply_webhook_event(
            pw.session,
            row,
            provider=pw.provider,
            ledger=pw.ledger,
            now=received + timedelta(milliseconds=2_500),
        )
    applied = next(e for e in logs if e["event"] == "webhook_applied")
    assert applied["processing_ms"] == 2_500
