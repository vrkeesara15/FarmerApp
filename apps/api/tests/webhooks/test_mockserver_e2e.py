"""End to end through docker/mockserver (``integration``; skipped when it is down).

The QR is created over HTTP by ``RazorpayProvider`` against the mock's Razorpay API, the mock's
webhook simulator signs a ``payment.captured`` event with its own HMAC secret (the dev
default ``RAZORPAY_WEBHOOK_SECRET``) and posts it to a capture server in this process; the
captured raw body and headers are replayed byte for byte into the API. The payment must end
``paid`` — proving the signing and verification agree.
"""

from __future__ import annotations

import asyncio
import socket
import uuid
from contextlib import closing
from typing import Any

import httpx
import pytest
import uvicorn
from httpx import AsyncClient
from starlette.requests import Request
from starlette.responses import Response

from farmerapp.payments.models import Payment
from farmerapp.payments.providers import RazorpayProvider
from farmerapp.settings import get_settings
from tests.payments.helpers import PayWorld

pytestmark = pytest.mark.integration

MOCK = "http://localhost:8090"


def _free_port() -> int:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("", 0))
        port: int = s.getsockname()[1]
        return port


async def _mock_up() -> bool:
    try:
        async with httpx.AsyncClient(timeout=2) as c:
            return (await c.get(f"{MOCK}/health")).status_code == 200
    except httpx.HTTPError:
        return False


async def test_qr_payment_captured_through_the_mockserver(
    client: AsyncClient, pw: PayWorld
) -> None:
    if not await _mock_up():
        pytest.skip("mockserver not reachable on :8090")
    settings = get_settings()
    pw.services.provider = RazorpayProvider(
        base_url=f"{MOCK}/razorpay",
        key_id=settings.razorpay_key_id,
        key_secret=settings.razorpay_key_secret,
        webhook_secret=settings.razorpay_webhook_secret,
    )
    order = await pw.order(23_600)
    resp = await client.post(
        "/v1/payments",
        json={"order_id": str(order.id), "mode": "upi_qr"},
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 201, resp.text
    payment = await pw.session.get_one(Payment, uuid.UUID(resp.json()["payment_id"]))
    assert payment.provider_order_id and payment.provider_order_id.startswith("qr_")

    captured: dict[str, Any] = {}

    async def capture(scope: Any, receive: Any, send: Any) -> None:
        request = Request(scope, receive)
        captured["body"] = await request.body()
        captured["headers"] = dict(request.headers)
        await Response(status_code=200)(scope, receive, send)

    port = _free_port()
    server = uvicorn.Server(
        uvicorn.Config(capture, host="0.0.0.0", port=port, log_level="warning", lifespan="off")
    )
    task = asyncio.create_task(server.serve())
    try:
        for _ in range(50):
            if server.started:
                break
            await asyncio.sleep(0.05)
        entity = {
            "id": f"pay_{uuid.uuid4().hex[:14]}",
            "entity": "payment",
            "amount": 23_600,
            "status": "captured",
            "method": "upi",
            "notes": {"tenant_id": str(pw.tenant_id), "payment_id": str(payment.id)},
        }
        async with httpx.AsyncClient(timeout=10) as mock:
            sim = await mock.post(
                f"{MOCK}/_mock/webhooks/simulate",
                json={
                    "target_url": f"http://host.docker.internal:{port}/hook",
                    "event": "payment.captured",
                    "payload": {
                        "payment": {"entity": entity},
                        "qr_code": {"entity": {"id": payment.provider_order_id}},
                    },
                },
            )
        if sim.status_code != 200 or sim.json().get("target_status") != 200 or not captured:
            pytest.skip("the mockserver container cannot reach this host (host.docker.internal)")
    finally:
        server.should_exit = True
        await task

    forwarded = {
        "Content-Type": "application/json",
        "X-Razorpay-Signature": captured["headers"]["x-razorpay-signature"],
        "X-Razorpay-Event-Id": captured["headers"]["x-razorpay-event-id"],
    }
    hook = await client.post("/v1/webhooks/razorpay", content=captured["body"], headers=forwarded)
    assert hook.status_code == 200, hook.text
    await pw.session.refresh(payment)
    assert payment.status == "paid" and payment.provider_ref == entity["id"]
