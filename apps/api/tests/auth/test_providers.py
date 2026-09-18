"""Provider adapters: fake (unit) and mockserver (HTTP via MockTransport + optional live)."""

from __future__ import annotations

import os
from typing import Any

import httpx
import pytest

from farmerapp.auth.providers import (
    DeliveryStatus,
    FakeProvider,
    MockServerProvider,
    mask_phone,
    otp_message,
)


def test_mask_phone() -> None:
    assert mask_phone("+919876543210") == "+91******3210"
    assert mask_phone("9876543210") == "******3210"
    assert mask_phone("123") == "***"


def test_otp_message_contains_code_and_validity() -> None:
    text = otp_message("482913", 300)
    assert "482913" in text and "5 min" in text


async def test_fake_provider_records_and_delivers() -> None:
    p = FakeProvider()
    ref = await p.send_sms("+919000000001", "hi")
    assert p.sent[0].to == "+919000000001" and p.sent[0].ref == ref
    assert await p.delivery_status(ref) == DeliveryStatus.DELIVERED
    p.auto_deliver = False
    ref2 = await p.send_sms("+919000000001", "hi again")
    assert await p.delivery_status(ref2) == DeliveryStatus.PENDING
    p.deliver(ref2)
    assert await p.delivery_status(ref2) == DeliveryStatus.DELIVERED
    assert await p.delivery_status("unknown") == DeliveryStatus.UNKNOWN
    wa = await p.send_whatsapp("+919000000001", "otp_login", {"code": "1"})
    assert p.sent[-1].ref == wa and p.sent[-1].template == "otp_login"


async def test_mockserver_provider_http_contract() -> None:
    calls: list[tuple[str, str, Any]] = []
    state: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append((request.method, request.url.path, request.content))
        if request.url.path == "/sms/send":
            state["id"] = "sms_1"
            return httpx.Response(202, json={"id": "sms_1", "status": "queued"})
        if request.url.path == "/sms/status/sms_1":
            return httpx.Response(200, json={"id": "sms_1", "status": "delivered"})
        if request.url.path == "/sms/status/missing":
            return httpx.Response(404, json={"detail": "no such message"})
        if request.url.path == "/whatsapp/send":
            return httpx.Response(202, json={"id": "wa_1", "status": "accepted"})
        return httpx.Response(500)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://mock")
    p = MockServerProvider(
        sms_url="http://mock/sms", whatsapp_url="http://mock/whatsapp", client=client
    )
    ref = await p.send_sms("+919000000001", "Your OTP is 123456")
    assert ref == "sms_1"
    assert calls[0][0] == "POST" and calls[0][1] == "/sms/send"
    assert b'"to": "+919000000001"' in calls[0][2].replace(b'":"', b'": "')
    assert await p.delivery_status("sms_1") == DeliveryStatus.DELIVERED
    assert await p.delivery_status("missing") == DeliveryStatus.UNKNOWN
    wa = await p.send_whatsapp("+919000000001", "otp_login", {"code": "123456"})
    assert wa == "wa_1"
    await client.aclose()


async def test_mockserver_provider_error_is_wrapped() -> None:
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(503, text="down")

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="http://mock")
    p = MockServerProvider(
        sms_url="http://mock/sms", whatsapp_url="http://mock/whatsapp", client=client
    )
    from farmerapp.auth.providers import ProviderError

    with pytest.raises(ProviderError):
        await p.send_sms("+919000000001", "x")
    assert await p.delivery_status("x") == DeliveryStatus.UNKNOWN
    await client.aclose()


@pytest.mark.integration
async def test_live_mockserver_receives_sms() -> None:
    """Talks to the compose mockserver (``make up``); skipped when it is not reachable."""
    base = os.environ.get("MOCKSERVER_URL", "http://localhost:8090")
    try:
        async with httpx.AsyncClient(timeout=2) as probe:
            ok = (await probe.get(f"{base}/health")).status_code == 200
    except httpx.HTTPError:
        ok = False
    if not ok:
        pytest.skip(f"mockserver not reachable at {base}")

    p = MockServerProvider(sms_url=f"{base}/sms", whatsapp_url=f"{base}/whatsapp")
    phone = "+919000000099"
    ref = await p.send_sms(phone, otp_message("135790", 300))
    async with httpx.AsyncClient(timeout=5) as c:
        msgs = (await c.get(f"{base}/sms/messages", params={"to": phone})).json()
    assert any(m["id"] == ref and "135790" in m["message"] for m in msgs)
    assert await p.delivery_status(ref) in (DeliveryStatus.DELIVERED, DeliveryStatus.PENDING)
    await p.aclose()
