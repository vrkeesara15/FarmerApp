"""Mock SMS / WhatsApp / Razorpay-like provider. In-memory, dev and test only."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import time
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

WEBHOOK_SECRET = os.environ.get("MOCK_RAZORPAY_WEBHOOK_SECRET", "test_webhook_secret")
KEY_ID = os.environ.get("MOCK_RAZORPAY_KEY_ID", "rzp_test_mock")

app = FastAPI(title="FarmerApp mock providers", version="0.1.0")

STATE: dict[str, Any] = {"sms": [], "whatsapp": [], "orders": {}, "links": {}, "qrs": {}, "payments": {}}
# Delivery simulation: SMS are "delivered" as soon as they are sent unless auto_deliver is off
# (then POST /sms/messages/{id}/deliver marks them, or they stay queued -> WhatsApp fallback).
SMS_CONFIG: dict[str, Any] = {"auto_deliver": True}


def _id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(7)}"


def _now() -> int:
    return int(time.time())


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.delete("/_mock/reset")
def reset() -> dict[str, str]:
    for k in ("sms", "whatsapp"):
        STATE[k].clear()
    for k in ("orders", "links", "qrs", "payments"):
        STATE[k].clear()
    SMS_CONFIG["auto_deliver"] = True
    return {"status": "reset"}


# ---------------------------------------------------------------- SMS / WhatsApp
class SmsSend(BaseModel):
    to: str
    message: str
    sender_id: str = "FARMER"
    template_id: str | None = None  # DLT template id


@app.post("/sms/send", status_code=202)
def sms_send(body: SmsSend) -> dict[str, Any]:
    rec = {"id": _id("sms"), "ts": _now(), **body.model_dump()}
    rec["delivered_at"] = _now() if SMS_CONFIG["auto_deliver"] else None
    STATE["sms"].append(rec)
    return {"id": rec["id"], "status": "queued"}


@app.get("/sms/messages")
def sms_messages(to: str | None = None) -> list[dict[str, Any]]:
    return [m for m in STATE["sms"] if to is None or m["to"] == to]


def _sms(message_id: str) -> dict[str, Any]:
    for m in STATE["sms"]:
        if m["id"] == message_id:
            return m
    raise HTTPException(404, {"error": "no such message"})


@app.get("/sms/status/{message_id}")
def sms_status(message_id: str) -> dict[str, Any]:
    """Delivery report the API polls 30 s after sending (FA-001 WhatsApp fallback)."""
    m = _sms(message_id)
    return {
        "id": message_id,
        "status": "delivered" if m.get("delivered_at") else "pending",
        "delivered_at": m.get("delivered_at"),
    }


@app.post("/sms/messages/{message_id}/deliver")
def sms_deliver(message_id: str) -> dict[str, Any]:
    """Test helper: mark a queued message delivered."""
    m = _sms(message_id)
    m["delivered_at"] = m.get("delivered_at") or _now()
    return sms_status(message_id)


class SmsConfig(BaseModel):
    auto_deliver: bool = True


@app.post("/_mock/sms/config")
def sms_config(body: SmsConfig) -> dict[str, Any]:
    """Test helper: ``auto_deliver=false`` leaves SMS queued so the API falls back to WhatsApp."""
    SMS_CONFIG["auto_deliver"] = body.auto_deliver
    return dict(SMS_CONFIG)


class WhatsAppSend(BaseModel):
    to: str
    template: str
    params: dict[str, Any] = Field(default_factory=dict)
    language: str = "en"


@app.post("/whatsapp/send", status_code=202)
def whatsapp_send(body: WhatsAppSend) -> dict[str, Any]:
    rec = {"id": _id("wa"), "ts": _now(), **body.model_dump()}
    STATE["whatsapp"].append(rec)
    return {"id": rec["id"], "status": "accepted"}


@app.get("/whatsapp/messages")
def whatsapp_messages(to: str | None = None) -> list[dict[str, Any]]:
    return [m for m in STATE["whatsapp"] if to is None or m["to"] == to]


@app.get("/whatsapp/status/{message_id}")
def whatsapp_status(message_id: str) -> dict[str, Any]:
    for m in STATE["whatsapp"]:
        if m["id"] == message_id:
            return {"id": message_id, "status": "delivered", "delivered_at": m["ts"]}
    raise HTTPException(404, {"error": "no such message"})


# ---------------------------------------------------------------- Razorpay-like
class OrderCreate(BaseModel):
    amount: int = Field(gt=0, description="paise")
    currency: str = "INR"
    receipt: str | None = None
    notes: dict[str, Any] = Field(default_factory=dict)


@app.post("/razorpay/v1/orders")
def create_order(body: OrderCreate) -> dict[str, Any]:
    order = {
        "id": _id("order"),
        "entity": "order",
        "amount": body.amount,
        "amount_paid": 0,
        "amount_due": body.amount,
        "currency": body.currency,
        "receipt": body.receipt,
        "status": "created",
        "notes": body.notes,
        "created_at": _now(),
    }
    STATE["orders"][order["id"]] = order
    return order


@app.get("/razorpay/v1/orders/{order_id}")
def get_order(order_id: str) -> dict[str, Any]:
    order = STATE["orders"].get(order_id)
    if order is None:
        raise HTTPException(404, {"error": {"code": "BAD_REQUEST_ERROR", "description": "not found"}})
    return order


class PaymentLinkCreate(BaseModel):
    amount: int = Field(gt=0)
    currency: str = "INR"
    description: str = ""
    customer: dict[str, Any] = Field(default_factory=dict)
    notes: dict[str, Any] = Field(default_factory=dict)
    reference_id: str | None = None


@app.post("/razorpay/v1/payment_links")
def create_payment_link(body: PaymentLinkCreate) -> dict[str, Any]:
    link = {
        "id": _id("plink"),
        "entity": "payment_link",
        "amount": body.amount,
        "amount_paid": 0,
        "currency": body.currency,
        "description": body.description,
        "customer": body.customer,
        "notes": body.notes,
        "reference_id": body.reference_id,
        "status": "created",
        "short_url": f"http://localhost:8090/pay/{secrets.token_urlsafe(6)}",
        "created_at": _now(),
    }
    STATE["links"][link["id"]] = link
    return link


class QrCreate(BaseModel):
    type: str = "upi_qr"
    usage: str = "single_use"
    fixed_amount: bool = True
    payment_amount: int = Field(gt=0)
    description: str = ""
    notes: dict[str, Any] = Field(default_factory=dict)


@app.post("/razorpay/v1/payments/qr_codes")
def create_qr(body: QrCreate) -> dict[str, Any]:
    qr = {
        "id": _id("qr"),
        "entity": "qr_code",
        "status": "active",
        "image_url": f"http://localhost:8090/qr/{secrets.token_urlsafe(6)}.png",
        **body.model_dump(),
        "created_at": _now(),
    }
    STATE["qrs"][qr["id"]] = qr
    return qr


@app.post("/razorpay/v1/orders/{order_id}/pay")
def simulate_payment(order_id: str, method: str = "upi") -> dict[str, Any]:
    """Test helper (not a real Razorpay endpoint): mark an order paid and return the payment."""
    order = get_order(order_id)
    payment = {
        "id": _id("pay"),
        "entity": "payment",
        "amount": order["amount"],
        "currency": order["currency"],
        "status": "captured",
        "order_id": order_id,
        "method": method,
        "captured": True,
        "notes": order.get("notes", {}),
        "created_at": _now(),
    }
    order.update(status="paid", amount_paid=order["amount"], amount_due=0)
    STATE["payments"][payment["id"]] = payment
    return payment


@app.post("/razorpay/v1/payments/qr_codes/{qr_id}/pay")
def simulate_qr_payment(qr_id: str) -> dict[str, Any]:
    """Test helper (not a real Razorpay endpoint): a UPI payment scanned from a QR code."""
    qr = STATE["qrs"].get(qr_id)
    if qr is None:
        raise HTTPException(404, {"error": {"code": "BAD_REQUEST_ERROR", "description": "not found"}})
    payment = {
        "id": _id("pay"),
        "entity": "payment",
        "amount": qr["payment_amount"],
        "currency": "INR",
        "status": "captured",
        "method": "upi",
        "captured": True,
        "notes": qr.get("notes", {}),
        "created_at": _now(),
    }
    qr["status"] = "closed"
    STATE["payments"][payment["id"]] = payment
    return {"payment": payment, "qr_code": qr}


def _settled_items(day: str) -> list[dict[str, Any]]:
    """Captured payments whose capture date (UTC) is ``day`` (YYYY-MM-DD), recon-shaped."""
    items = []
    for p in STATE["payments"].values():
        captured_on = time.strftime("%Y-%m-%d", time.gmtime(p["created_at"]))
        if p.get("status") == "captured" and captured_on == day:
            items.append(
                {
                    "entity_id": p["id"],
                    "type": "payment",
                    "amount": p["amount"],
                    "fee": 0,
                    "tax": 0,
                    "settled": True,
                    "settlement_id": f"setl_{day.replace('-', '')}",
                    "settled_at": p["created_at"],
                    "order_id": p.get("order_id"),
                    "method": p.get("method"),
                    "notes": p.get("notes", {}),
                }
            )
    return items


@app.get("/razorpay/settlements")
def settlements(date: str) -> dict[str, Any]:
    """OPS-008 test helper: the day's settled payments (``?date=YYYY-MM-DD``)."""
    items = _settled_items(date)
    return {"entity": "collection", "count": len(items), "items": items}


@app.get("/razorpay/v1/settlements/recon/combined")
def settlements_recon(year: int, month: int, day: int) -> dict[str, Any]:
    """Razorpay's settlement recon shape (what the API's RazorpayProvider calls)."""
    return settlements(f"{year:04d}-{month:02d}-{day:02d}")


class WebhookSimulate(BaseModel):
    target_url: str
    event: str = "payment.captured"
    payload: dict[str, Any] = Field(default_factory=dict)
    event_id: str | None = None


def sign(body: bytes, secret: str = WEBHOOK_SECRET) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


@app.post("/_mock/webhooks/simulate")
async def simulate_webhook(body: WebhookSimulate) -> dict[str, Any]:
    """POST a Razorpay-style webhook to ``target_url`` with a valid HMAC-SHA256 signature."""
    event_id = body.event_id or _id("evt")
    envelope = {
        "entity": "event",
        "account_id": "acc_mock",
        "event": body.event,
        "contains": list(body.payload.keys()),
        "payload": body.payload,
        "created_at": _now(),
    }
    raw = json.dumps(envelope, separators=(",", ":")).encode()
    headers = {
        "Content-Type": "application/json",
        "X-Razorpay-Signature": sign(raw),
        "X-Razorpay-Event-Id": event_id,
    }
    async with httpx.AsyncClient(timeout=10) as client:
        resp = await client.post(body.target_url, content=raw, headers=headers)
    return {"event_id": event_id, "target_status": resp.status_code, "signature": headers["X-Razorpay-Signature"]}
