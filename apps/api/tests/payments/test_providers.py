"""Provider adapters (FA-021, SEC-023, SPEC 0.2): Razorpay REST shapes and HMAC, the
Cashfree skeleton against a fake transport, the fake provider, the Pub/Sub publisher and the
payments settings."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
from datetime import UTC, date, datetime, timedelta
from typing import Any

import httpx
import pytest

from farmerapp.payments.config import payment_settings, placeholder_gstin, state_code
from farmerapp.payments.providers import (
    CAPTURED,
    FAILED,
    CashfreeProvider,
    FakePaymentProvider,
    PaymentProviderError,
    RazorpayProvider,
    WebhookParseError,
    hmac_sha256_hex,
    paise_to_rupees,
    razorpay_envelope,
    rupees_to_paise,
)
from farmerapp.payments.publisher import (
    PublishError,
    PubSubRestPublisher,
    RecordingPublisher,
    encode,
)
from farmerapp.settings import Settings
from farmerapp.worker.topics import Topic

NOW = datetime(2026, 9, 18, 10, 0, tzinfo=UTC)
KEY = "whk-test"


def _razorpay(handler: Any) -> RazorpayProvider:
    return RazorpayProvider(
        base_url="https://rzp.test/",
        key_id="rzp_test_x",
        key_secret="k",
        webhook_secret=KEY,
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )


# --------------------------------------------------------------------------- Razorpay
def test_signature_verifies_raw_body_only() -> None:
    provider = _razorpay(lambda _r: httpx.Response(500))
    body = razorpay_envelope("payment.captured", payment={"id": "pay_1"}, created_at=NOW)
    good = {"x-razorpay-signature": hmac_sha256_hex(KEY, body)}
    assert provider.verify_webhook(body, good)
    assert not provider.verify_webhook(body + b" ", good)  # any byte change breaks it
    assert not provider.verify_webhook(body, {"x-razorpay-signature": hmac_sha256_hex("x", body)})
    assert not provider.verify_webhook(body, {})
    empty = RazorpayProvider(base_url="", key_id="", key_secret="k", webhook_secret="")
    assert not empty.verify_webhook(body, good)


def test_parse_normalises_events_and_merges_notes() -> None:
    provider = _razorpay(lambda _r: httpx.Response(500))
    body = razorpay_envelope(
        "qr_code.credited",
        payment={"id": "pay_9", "amount": 1500, "notes": {"payment_id": "p1"}},
        qr_code={"id": "qr_9", "notes": {"tenant_id": "t1", "payment_id": "ignored"}},
        created_at=NOW,
    )
    event = provider.parse_webhook(body)
    assert event.event_type == CAPTURED
    assert event.created_at == NOW
    assert event.payment_ref == "pay_9"
    assert event.amount_paise == 1500
    assert event.provider_order_ids == ("qr_9",)
    assert event.tenant_hint == "t1" and event.payment_hint == "p1"

    failed = provider.parse_webhook(
        razorpay_envelope(
            "payment.failed",
            payment={"id": "pay_2", "amount": 10, "error_reason": "payment_timed_out", "notes": []},
            created_at=NOW,
        )
    )
    assert failed.event_type == FAILED and failed.error_reason == "payment_timed_out"
    assert failed.notes == {}

    other = provider.parse_webhook(razorpay_envelope("refund.created", created_at=NOW))
    assert other.event_type == "refund.created" and other.payment_ref is None


@pytest.mark.parametrize(
    "body",
    [b"not json", b"[1, 2]", json.dumps({"payload": {}}).encode(), b'{"event": "x"}'],
)
def test_parse_rejects_malformed(body: bytes) -> None:
    with pytest.raises(WebhookParseError):
        _razorpay(lambda _r: httpx.Response(500)).parse_webhook(body)


async def test_create_qr_link_and_settlements_request_shapes() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        path = request.url.path
        if path.endswith("/qr_codes"):
            return httpx.Response(200, json={"id": "qr_1", "image_url": "https://img/qr_1.png"})
        if path.endswith("/payment_links"):
            return httpx.Response(200, json={"id": "plink_1", "short_url": "https://rzp.io/x"})
        return httpx.Response(
            200,
            json={
                "items": [
                    {"entity_id": "pay_1", "type": "payment", "amount": 500, "settled_at": 1},
                    {"entity_id": "rfnd_1", "type": "refund", "amount": 100},
                    "junk",
                ]
            },
        )

    provider = _razorpay(handler)
    expires = NOW + timedelta(minutes=15)
    qr = await provider.create_upi_qr(
        amount_paise=1500, reference="p1", description="d", notes={"a": "b"}, expires_at=expires
    )
    assert (qr.id, qr.payload, qr.expires_at) == ("qr_1", "https://img/qr_1.png", expires)
    sent = json.loads(seen[0].content)
    assert sent["payment_amount"] == 1500 and sent["fixed_amount"] is True
    assert sent["usage"] == "single_use" and sent["notes"] == {"a": "b"}
    assert sent["close_by"] == int(expires.timestamp())
    auth = base64.b64decode(seen[0].headers["authorization"].split()[1]).decode()
    assert auth == "rzp_test_x:k"

    link = await provider.create_payment_link(
        amount_paise=99,
        reference="p2",
        description="d",
        customer_phone="+919000000001",
        notes={},
        expires_at=expires,
    )
    assert link.short_url == "https://rzp.io/x"
    sent = json.loads(seen[1].content)
    assert sent["notify"] == {"sms": False, "email": False}
    assert sent["customer"] == {"contact": "+919000000001"}

    records = await provider.fetch_settlements(date(2026, 9, 18))
    assert [(r.payment_ref, r.amount_paise) for r in records] == [("pay_1", 500)]
    assert seen[2].url.params["day"] == "18"


async def test_provider_errors_are_wrapped() -> None:
    provider = _razorpay(lambda _r: httpx.Response(502))
    with pytest.raises(PaymentProviderError):
        await provider.create_upi_qr(
            amount_paise=1, reference="r", description="", notes={}, expires_at=NOW
        )
    incomplete = _razorpay(lambda _r: httpx.Response(200, json={"id": "qr_1"}))
    with pytest.raises(PaymentProviderError):
        await incomplete.create_upi_qr(
            amount_paise=1, reference="r", description="", notes={}, expires_at=NOW
        )
    with pytest.raises(PaymentProviderError):
        await incomplete.create_payment_link(
            amount_paise=1,
            reference="r",
            description="",
            customer_phone=None,
            notes={},
            expires_at=NOW,
        )
    listy = _razorpay(lambda _r: httpx.Response(200, json=[1]))
    with pytest.raises(PaymentProviderError):
        await listy.fetch_settlements(date(2026, 9, 18))


async def test_razorpay_without_injected_client_uses_its_own(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    provider = RazorpayProvider(
        base_url="http://127.0.0.1:9", key_id="a", key_secret="b", webhook_secret=KEY, timeout=0.5
    )
    with pytest.raises(PaymentProviderError):
        await provider.fetch_settlements(date(2026, 9, 18))


# --------------------------------------------------------------------------- Cashfree
def _cashfree(handler: Any) -> CashfreeProvider:
    return CashfreeProvider(
        base_url="https://sandbox.cashfree.test/pg",
        client_id="cf_id",
        client_secret="cf_key",
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )


async def test_cashfree_skeleton_implements_the_protocol() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        path = request.url.path
        if path.endswith("/orders"):
            return httpx.Response(200, json={"order_id": "p1", "payment_session_id": "sess"})
        if path.endswith("/orders/sessions"):
            return httpx.Response(200, json={"data": {"payload": {"qrcode": "upi://pay?x"}}})
        if path.endswith("/links"):
            return httpx.Response(200, json={"link_id": "p2", "link_url": "https://cf/l"})
        return httpx.Response(
            200,
            json={"data": [{"cf_payment_id": 77, "payment_amount": 12.5, "order_id": "p1"}, {}]},
        )

    provider = _cashfree(handler)
    qr = await provider.create_upi_qr(
        amount_paise=1250, reference="p1", description="d", notes={"t": "1"}, expires_at=NOW
    )
    assert qr.payload == "upi://pay?x"
    assert json.loads(seen[0].content)["order_amount"] == "12.50"
    assert seen[0].headers["x-api-version"] == CashfreeProvider.api_version
    link = await provider.create_payment_link(
        amount_paise=100,
        reference="p2",
        description="d",
        customer_phone=None,
        notes={},
        expires_at=NOW,
    )
    assert link.short_url == "https://cf/l"
    records = await provider.fetch_settlements(date(2026, 9, 18))
    assert [(r.payment_ref, r.amount_paise) for r in records] == [("77", 1250)]


async def test_cashfree_errors() -> None:
    no_session = _cashfree(lambda _r: httpx.Response(200, json={"order_id": "p1"}))
    with pytest.raises(PaymentProviderError):
        await no_session.create_upi_qr(
            amount_paise=1, reference="r", description="", notes={}, expires_at=NOW
        )
    down = _cashfree(lambda _r: httpx.Response(500))
    with pytest.raises(PaymentProviderError):
        await down.create_payment_link(
            amount_paise=1,
            reference="r",
            description="",
            customer_phone=None,
            notes={},
            expires_at=NOW,
        )

    def no_qr(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/orders"):
            return httpx.Response(200, json={"payment_session_id": "s"})
        return httpx.Response(200, json={"data": {}})

    with pytest.raises(PaymentProviderError):
        await _cashfree(no_qr).create_upi_qr(
            amount_paise=1, reference="r", description="", notes={}, expires_at=NOW
        )
    no_url = _cashfree(lambda _r: httpx.Response(200, json={}))
    with pytest.raises(PaymentProviderError):
        await no_url.create_payment_link(
            amount_paise=1,
            reference="r",
            description="",
            customer_phone=None,
            notes={},
            expires_at=NOW,
        )
    with pytest.raises(PaymentProviderError):
        await _cashfree(lambda _r: httpx.Response(200, json=[])).fetch_settlements(NOW.date())


def test_cashfree_webhook_signature_and_parse() -> None:
    provider = _cashfree(lambda _r: httpx.Response(500))
    body = json.dumps(
        {
            "type": "PAYMENT_SUCCESS_WEBHOOK",
            "event_time": "2026-09-18T15:30:00+05:30",
            "data": {
                "order": {"order_id": "p1", "order_tags": {"tenant_id": "t"}},
                "payment": {"cf_payment_id": 5, "payment_amount": 10.01},
            },
        }
    ).encode()
    ts = "1726650000"
    digest = hmac.new(b"cf_key", ts.encode() + body, hashlib.sha256).digest()
    headers = {"x-webhook-signature": base64.b64encode(digest).decode(), "x-webhook-timestamp": ts}
    assert provider.verify_webhook(body, headers)
    assert not provider.verify_webhook(body, {**headers, "x-webhook-timestamp": "1"})
    assert not provider.verify_webhook(body, {})
    event = provider.parse_webhook(body)
    assert event.event_type == CAPTURED and event.amount_paise == 1001
    assert event.provider_order_ids == ("p1",) and event.notes == {"tenant_id": "t"}

    failed = provider.parse_webhook(
        json.dumps(
            {
                "type": "PAYMENT_FAILED_WEBHOOK",
                "event_time": "2026-09-18T10:00:00",
                "data": {"payment": {"payment_message": "declined"}},
            }
        ).encode()
    )
    assert failed.event_type == FAILED and failed.error_reason == "declined"
    assert failed.created_at.tzinfo is not None
    for bad in (b'{"type": 1}', b'{"type": "X", "data": {}, "event_time": "yesterday"}'):
        with pytest.raises(WebhookParseError):
            provider.parse_webhook(bad)


def test_money_conversions_are_exact() -> None:
    assert rupees_to_paise("12.34") == 1234
    assert rupees_to_paise(0.1) == 10
    assert paise_to_rupees(1) == "0.01"
    assert paise_to_rupees(123456) == "1234.56"


# --------------------------------------------------------------------------- fake
async def test_fake_provider_records_and_fails_on_demand() -> None:
    fake = FakePaymentProvider(webhook_secret=KEY)
    qr = await fake.create_upi_qr(
        amount_paise=100, reference="r", description="", notes={"x": "y"}, expires_at=NOW
    )
    assert qr.payload.startswith("upi://pay") and fake.qrs[0]["notes"] == {"x": "y"}
    body = razorpay_envelope("payment.captured", payment={"id": "p"}, created_at=NOW)
    assert fake.verify_webhook(body, {"x-razorpay-signature": fake.sign(body)})
    assert fake.parse_webhook(body).payment_ref == "p"
    fake.fail_next = True
    with pytest.raises(PaymentProviderError):
        await fake.fetch_settlements(NOW.date())
    assert await fake.fetch_settlements(NOW.date()) == []


# --------------------------------------------------------------------------- publisher
async def test_pubsub_rest_publisher() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"messageIds": ["42"]})

    async def token() -> str:
        return "tok"

    publisher = PubSubRestPublisher(
        base_url="localhost:8085",
        project="p",
        token_provider=token,
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    assert await publisher.publish(Topic.PAYMENT_WEBHOOK, {"a": 1}) == "42"
    assert str(seen[0].url) == "http://localhost:8085/v1/projects/p/topics/payment.webhook:publish"
    assert seen[0].headers["authorization"] == "Bearer tok"
    message = json.loads(seen[0].content)["messages"][0]
    assert message["data"] == encode({"a": 1})
    assert message["attributes"] == {"topic": "payment.webhook"}

    failing = PubSubRestPublisher(
        base_url="http://x",
        project="p",
        client=httpx.AsyncClient(transport=httpx.MockTransport(lambda _r: httpx.Response(503))),
    )
    with pytest.raises(PublishError):
        await failing.publish(Topic.PAYMENT_WEBHOOK, {})
    unreachable = PubSubRestPublisher(base_url="http://127.0.0.1:9", project="p")
    with pytest.raises(PublishError):
        await unreachable.publish(Topic.PAYMENT_WEBHOOK, {})


async def test_recording_publisher_round_trips_to_a_push_message() -> None:
    recorder = RecordingPublisher()
    await recorder.publish(Topic.PAYMENT_WEBHOOK, {"tenant_id": "t"})
    message = recorder.message()
    assert message.json_body() == {"tenant_id": "t"}
    assert message.attributes == {"topic": "payment.webhook"}
    recorder.fail = True
    with pytest.raises(PublishError):
        await recorder.publish(Topic.PAYMENT_WEBHOOK, {})


# --------------------------------------------------------------------------- settings
def test_prd_requires_payment_secrets() -> None:
    strong = "x" * 48
    base: dict[str, Any] = {
        "app_env": "prd",
        "jwt_signing_key": strong,
        "otp_pepper": strong,
        "otp_provider": "mockserver",
    }
    with pytest.raises(ValueError, match="RAZORPAY_WEBHOOK_SECRET"):
        Settings(**base, razorpay_key_secret=strong)
    with pytest.raises(ValueError, match="RAZORPAY_KEY_SECRET"):
        Settings(**base, razorpay_webhook_secret=strong)
    with pytest.raises(ValueError, match="PAYMENT_PROVIDER=fake"):
        Settings(
            **base,
            razorpay_key_secret=strong,
            razorpay_webhook_secret=strong,
            payment_provider="fake",
        )


def test_tenant_payment_settings_defaults_and_overrides() -> None:
    defaults = payment_settings(None)
    assert defaults.webhook_replay_window_s == 300
    assert defaults.day_close_variance_threshold_paise == 50_000
    assert defaults.gstin_for("Telangana") == placeholder_gstin("Telangana") == "36AAAAA0000A1Z5"
    custom = payment_settings(
        {"gstin_by_state": {"Telangana": "36ABCDE1234F1Z5"}, "webhook_replay_window_s": 600}
    )
    assert custom.gstin_for("Telangana") == "36ABCDE1234F1Z5"
    assert custom.webhook_replay_window_s == 600
    assert state_code("Karnataka") == "29" and state_code("Atlantis") == "00"
