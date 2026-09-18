"""Payment provider adapters (SPEC 0.2: Razorpay; Cashfree as a swappable adapter).

``PaymentProvider`` is the protocol the payment service codes against:

* ``create_upi_qr`` — a single-use, fixed-amount UPI dynamic QR (FA-021, ST-002).
* ``create_payment_link`` — a payment link we send ourselves by SMS / WhatsApp (the
  provider's own notifications stay off, so the message goes through our DLT / WhatsApp
  adapters and templates).
* ``verify_webhook`` — the provider's signature check over the **raw** body (SEC-023),
  constant-time.
* ``parse_webhook`` — the provider event reduced to what the service needs
  (``ProviderEvent``); amounts in paise.
* ``fetch_settlements`` — settled payments of a day (OPS-008 reconciliation).

Every object we create carries ``notes = {tenant_id, payment_id}``: the webhook is public,
so the verified payload is how it finds its tenant and payment.

Adapters: ``RazorpayProvider`` (HTTP to the Razorpay REST shapes; local / dev / test point
``RAZORPAY_BASE_URL`` at docker/mockserver), ``CashfreeProvider`` (PG API v2023-08-01 shapes;
skeleton, unit-tested against a fake transport, not wired) and ``FakePaymentProvider``
(in-process, tests).
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any, Protocol

import httpx

from farmerapp.payments.models import PaymentProvider as ProviderName

RAZORPAY_SIGNATURE_HEADER = "x-razorpay-signature"
RAZORPAY_EVENT_ID_HEADER = "x-razorpay-event-id"
CASHFREE_SIGNATURE_HEADER = "x-webhook-signature"
CASHFREE_TIMESTAMP_HEADER = "x-webhook-timestamp"


class PaymentProviderError(RuntimeError):
    """The provider rejected or failed the request (surfaces as 502 ``provider_error``)."""


class WebhookParseError(ValueError):
    """A verified body that is not a provider event we understand."""


@dataclass(frozen=True)
class QrCode:
    id: str
    payload: str  # what the device renders (image URL or UPI intent string)
    expires_at: datetime


@dataclass(frozen=True)
class PaymentLink:
    id: str
    short_url: str
    expires_at: datetime


@dataclass(frozen=True)
class ProviderEvent:
    """A provider webhook reduced to the fields the service applies (SEC-023)."""

    event_type: str  # normalised: payment.captured | payment.failed | <provider type>
    created_at: datetime
    payment_ref: str | None = None  # provider payment id (pay_...)
    provider_order_ids: tuple[str, ...] = ()  # QR / link / order ids the payment belongs to
    amount_paise: int | None = None
    notes: Mapping[str, str] = field(default_factory=dict)
    error_reason: str | None = None

    @property
    def tenant_hint(self) -> str | None:
        return self.notes.get("tenant_id")

    @property
    def payment_hint(self) -> str | None:
        return self.notes.get("payment_id")


@dataclass(frozen=True)
class SettlementRecord:
    payment_ref: str
    amount_paise: int
    settled_at: datetime | None
    provider_order_id: str | None = None
    notes: Mapping[str, str] = field(default_factory=dict)


CAPTURED = "payment.captured"
FAILED = "payment.failed"


class PaymentProvider(Protocol):
    name: ProviderName

    async def create_upi_qr(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> QrCode: ...

    async def create_payment_link(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        customer_phone: str | None,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> PaymentLink: ...

    def verify_webhook(self, body: bytes, headers: Mapping[str, str]) -> bool: ...

    def parse_webhook(self, body: bytes) -> ProviderEvent: ...

    async def fetch_settlements(self, day: date) -> list[SettlementRecord]: ...


# --------------------------------------------------------------------------- helpers
def hmac_sha256_hex(secret: str, body: bytes) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def _str_notes(raw: Any) -> dict[str, str]:
    if not isinstance(raw, Mapping):
        return {}  # Razorpay sends ``[]`` for empty notes
    return {str(k): str(v) for k, v in raw.items() if v is not None}


def _ts(value: Any) -> datetime:
    try:
        return datetime.fromtimestamp(int(value), tz=UTC)
    except (TypeError, ValueError) as exc:
        raise WebhookParseError("event created_at is not a unix timestamp") from exc


def _json_object(body: bytes) -> dict[str, Any]:
    try:
        parsed = json.loads(body)
    except (ValueError, UnicodeDecodeError) as exc:
        raise WebhookParseError("body is not JSON") from exc
    if not isinstance(parsed, dict):
        raise WebhookParseError("body is not a JSON object")
    return parsed


def rupees_to_paise(value: Any) -> int:
    """Cashfree amounts are rupees with two decimals: exact conversion, no float maths."""
    return int((Decimal(str(value)) * 100).quantize(Decimal(1)))


def paise_to_rupees(paise: int) -> str:
    return f"{Decimal(paise) / 100:.2f}"


# --------------------------------------------------------------------------- Razorpay
class RazorpayProvider:
    """Razorpay REST (``/v1/payments/qr_codes``, ``/v1/payment_links``,
    ``/v1/settlements/recon/combined``) with basic auth; webhooks signed with
    HMAC-SHA256 over the raw body in ``X-Razorpay-Signature``."""

    name = ProviderName.RAZORPAY

    def __init__(
        self,
        *,
        base_url: str,
        key_id: str,
        key_secret: str,
        webhook_secret: str,
        client: httpx.AsyncClient | None = None,
        timeout: float = 10.0,
    ) -> None:
        self._base = base_url.rstrip("/")
        self._auth = (key_id, key_secret)
        self._webhook_secret = webhook_secret
        self._client = client
        self._timeout = timeout

    async def _request(
        self, method: str, path: str, *, json_body: Any = None, params: Any = None
    ) -> dict[str, Any]:
        url = f"{self._base}{path}"
        try:
            if self._client is not None:
                resp = await self._client.request(
                    method, url, json=json_body, params=params, auth=self._auth
                )
            else:
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    resp = await client.request(
                        method, url, json=json_body, params=params, auth=self._auth
                    )
            resp.raise_for_status()
            data = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise PaymentProviderError(f"razorpay {method} {path} failed") from exc
        if not isinstance(data, dict):
            raise PaymentProviderError(f"razorpay {method} {path}: unexpected response")
        return data

    async def create_upi_qr(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> QrCode:
        data = await self._request(
            "POST",
            "/v1/payments/qr_codes",
            json_body={
                "type": "upi_qr",
                "name": reference,
                "usage": "single_use",
                "fixed_amount": True,
                "payment_amount": amount_paise,
                "description": description,
                "close_by": int(expires_at.timestamp()),
                "notes": dict(notes),
            },
        )
        payload = data.get("image_content") or data.get("image_url")
        if not data.get("id") or not payload:
            raise PaymentProviderError("razorpay qr_code response without id / image")
        close_by = data.get("close_by")
        return QrCode(
            id=str(data["id"]),
            payload=str(payload),
            expires_at=_ts(close_by) if close_by else expires_at,
        )

    async def create_payment_link(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        customer_phone: str | None,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> PaymentLink:
        data = await self._request(
            "POST",
            "/v1/payment_links",
            json_body={
                "amount": amount_paise,
                "currency": "INR",
                "description": description,
                "reference_id": reference,
                "customer": {"contact": customer_phone} if customer_phone else {},
                "notify": {"sms": False, "email": False},  # we send it (DLT / WhatsApp)
                "expire_by": int(expires_at.timestamp()),
                "notes": dict(notes),
            },
        )
        if not data.get("id") or not data.get("short_url"):
            raise PaymentProviderError("razorpay payment_link response without id / short_url")
        return PaymentLink(
            id=str(data["id"]), short_url=str(data["short_url"]), expires_at=expires_at
        )

    def verify_webhook(self, body: bytes, headers: Mapping[str, str]) -> bool:
        return verify_razorpay_signature(self._webhook_secret, body, headers)

    def parse_webhook(self, body: bytes) -> ProviderEvent:
        return parse_razorpay_event(body)

    async def fetch_settlements(self, day: date) -> list[SettlementRecord]:
        data = await self._request(
            "GET",
            "/v1/settlements/recon/combined",
            params={"year": day.year, "month": day.month, "day": day.day},
        )
        out: list[SettlementRecord] = []
        for item in data.get("items", []):
            if not isinstance(item, dict) or item.get("type", "payment") != "payment":
                continue
            settled_at = item.get("settled_at")
            out.append(
                SettlementRecord(
                    payment_ref=str(item.get("entity_id") or item.get("payment_id")),
                    amount_paise=int(item.get("amount", 0)),
                    settled_at=_ts(settled_at) if settled_at else None,
                    provider_order_id=str(item["order_id"]) if item.get("order_id") else None,
                    notes=_str_notes(item.get("notes")),
                )
            )
        return out


def verify_razorpay_signature(hmac_key: str, body: bytes, headers: Mapping[str, str]) -> bool:
    """``X-Razorpay-Signature`` = hex HMAC-SHA256 of the raw body (constant-time compare)."""
    signature = headers.get(RAZORPAY_SIGNATURE_HEADER, "")
    if not signature or not hmac_key:
        return False
    expected = hmac_sha256_hex(hmac_key, body)
    return hmac.compare_digest(expected.encode(), signature.strip().encode())


def parse_razorpay_event(body: bytes) -> ProviderEvent:
    envelope = _json_object(body)
    event = envelope.get("event")
    if not isinstance(event, str) or not event:
        raise WebhookParseError("envelope without event type")
    payload = envelope.get("payload")
    payload = payload if isinstance(payload, dict) else {}

    def entity(key: str) -> dict[str, Any]:
        wrapper = payload.get(key)
        inner = wrapper.get("entity") if isinstance(wrapper, dict) else None
        return inner if isinstance(inner, dict) else {}

    payment, qr, link, order = (
        entity("payment"),
        entity("qr_code"),
        entity("payment_link"),
        entity("order"),
    )
    notes: dict[str, str] = {}
    for source in (order, link, qr, payment):  # the payment's own notes win
        notes.update(_str_notes(source.get("notes")))
    order_ids = tuple(
        dict.fromkeys(str(v) for v in (qr.get("id"), link.get("id"), payment.get("order_id")) if v)
    )
    amount = payment.get("amount")
    normalised = {
        "payment.captured": CAPTURED,
        "qr_code.credited": CAPTURED,
        "payment_link.paid": CAPTURED,
        "order.paid": CAPTURED,
        "payment.failed": FAILED,
    }.get(event, event)
    return ProviderEvent(
        event_type=normalised,
        created_at=_ts(envelope.get("created_at")),
        payment_ref=str(payment["id"]) if payment.get("id") else None,
        provider_order_ids=order_ids,
        amount_paise=int(amount) if isinstance(amount, int) else None,
        notes=notes,
        error_reason=str(payment.get("error_reason") or payment.get("error_description"))
        if payment.get("error_reason") or payment.get("error_description")
        else None,
    )


# --------------------------------------------------------------------------- Cashfree
class CashfreeProvider:
    """Cashfree PG (API version 2023-08-01) behind the same protocol — the swappable
    adapter of SPEC 0.2. Skeleton: request / response shapes and the webhook signature
    (base64 HMAC-SHA256 over ``timestamp + raw body``) are implemented and unit-tested
    against a fake transport; it is not wired into the app (``PAYMENT_PROVIDER`` has no
    ``cashfree`` value yet) and Cashfree webhooks have no route."""

    name = ProviderName.CASHFREE
    api_version = "2023-08-01"

    def __init__(
        self,
        *,
        base_url: str,
        client_id: str,
        client_secret: str,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._base = base_url.rstrip("/")
        self._client_id = client_id
        self._secret = client_secret
        self._client = client or httpx.AsyncClient(timeout=10.0)

    def _headers(self) -> dict[str, str]:
        return {
            "x-client-id": self._client_id,
            "x-client-secret": self._secret,
            "x-api-version": self.api_version,
        }

    async def _post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        try:
            resp = await self._client.post(
                f"{self._base}{path}", json=body, headers=self._headers()
            )
            resp.raise_for_status()
            data = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise PaymentProviderError(f"cashfree POST {path} failed") from exc
        if not isinstance(data, dict):
            raise PaymentProviderError(f"cashfree POST {path}: unexpected response")
        return data

    async def create_upi_qr(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> QrCode:
        order = await self._post(
            "/orders",
            {
                "order_id": reference,
                "order_amount": paise_to_rupees(amount_paise),
                "order_currency": "INR",
                "order_note": description,
                "order_expiry_time": expires_at.isoformat(),
                "order_tags": dict(notes),
                "customer_details": {"customer_id": notes.get("payment_id", reference)},
            },
        )
        session_id = order.get("payment_session_id")
        if not session_id:
            raise PaymentProviderError("cashfree order without payment_session_id")
        pay = await self._post(
            "/orders/sessions",
            {"payment_session_id": session_id, "payment_method": {"upi": {"channel": "qrcode"}}},
        )
        data = pay.get("data")
        payload = data.get("payload") if isinstance(data, dict) else None
        qr = payload.get("qrcode") if isinstance(payload, dict) else None
        if not qr:
            raise PaymentProviderError("cashfree session without a UPI QR payload")
        return QrCode(
            id=str(order.get("order_id", reference)), payload=str(qr), expires_at=expires_at
        )

    async def create_payment_link(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        customer_phone: str | None,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> PaymentLink:
        data = await self._post(
            "/links",
            {
                "link_id": reference,
                "link_amount": paise_to_rupees(amount_paise),
                "link_currency": "INR",
                "link_purpose": description,
                "customer_details": {"customer_phone": customer_phone or ""},
                "link_notify": {"send_sms": False, "send_email": False},
                "link_expiry_time": expires_at.isoformat(),
                "link_notes": dict(notes),
            },
        )
        if not data.get("link_url"):
            raise PaymentProviderError("cashfree link without link_url")
        return PaymentLink(
            id=str(data.get("link_id", reference)),
            short_url=str(data["link_url"]),
            expires_at=expires_at,
        )

    def verify_webhook(self, body: bytes, headers: Mapping[str, str]) -> bool:
        signature = headers.get(CASHFREE_SIGNATURE_HEADER, "")
        timestamp = headers.get(CASHFREE_TIMESTAMP_HEADER, "")
        if not signature or not timestamp:
            return False
        digest = hmac.new(self._secret.encode(), timestamp.encode() + body, hashlib.sha256).digest()
        expected = base64.b64encode(digest).decode()
        return hmac.compare_digest(expected.encode(), signature.strip().encode())

    def parse_webhook(self, body: bytes) -> ProviderEvent:
        envelope = _json_object(body)
        kind = envelope.get("type")
        data = envelope.get("data")
        if not isinstance(kind, str) or not isinstance(data, dict):
            raise WebhookParseError("cashfree event without type / data")
        order_raw, payment_raw = data.get("order"), data.get("payment")
        order: dict[str, Any] = order_raw if isinstance(order_raw, dict) else {}
        payment: dict[str, Any] = payment_raw if isinstance(payment_raw, dict) else {}
        event_time = envelope.get("event_time")
        try:
            created = datetime.fromisoformat(str(event_time))
        except ValueError as exc:
            raise WebhookParseError("cashfree event_time is not ISO 8601") from exc
        amount = payment.get("payment_amount")
        normalised = {
            "PAYMENT_SUCCESS_WEBHOOK": CAPTURED,
            "PAYMENT_FAILED_WEBHOOK": FAILED,
        }.get(kind, kind)
        return ProviderEvent(
            event_type=normalised,
            created_at=created if created.tzinfo else created.replace(tzinfo=UTC),
            payment_ref=str(payment["cf_payment_id"]) if payment.get("cf_payment_id") else None,
            provider_order_ids=(str(order["order_id"]),) if order.get("order_id") else (),
            amount_paise=rupees_to_paise(amount) if amount is not None else None,
            notes=_str_notes(order.get("order_tags")),
            error_reason=str(payment.get("payment_message"))
            if kind == "PAYMENT_FAILED_WEBHOOK"
            else None,
        )

    async def fetch_settlements(self, day: date) -> list[SettlementRecord]:
        data = await self._post(
            "/settlement/recon",
            {
                "pagination": {"limit": 1000},
                "filters": {"start_date": f"{day}T00:00:00Z", "end_date": f"{day}T23:59:59Z"},
            },
        )
        out: list[SettlementRecord] = []
        for item in data.get("data", []):
            if not isinstance(item, dict) or not item.get("cf_payment_id"):
                continue
            out.append(
                SettlementRecord(
                    payment_ref=str(item["cf_payment_id"]),
                    amount_paise=rupees_to_paise(item.get("payment_amount", 0)),
                    settled_at=None,
                    provider_order_id=str(item["order_id"]) if item.get("order_id") else None,
                )
            )
        return out


# --------------------------------------------------------------------------- fake
@dataclass
class FakePaymentProvider:
    """In-process provider (tests, ``PAYMENT_PROVIDER=fake``): records what was created and
    signs / verifies webhooks exactly like Razorpay (same envelope, same HMAC)."""

    webhook_secret: str = "fake-webhook-secret"
    name: ProviderName = ProviderName.RAZORPAY
    qrs: list[dict[str, Any]] = field(default_factory=list)
    links: list[dict[str, Any]] = field(default_factory=list)
    settlements: dict[date, list[SettlementRecord]] = field(default_factory=dict)
    fail_next: bool = False

    def _check(self) -> None:
        if self.fail_next:
            self.fail_next = False
            raise PaymentProviderError("fake provider failure")

    async def create_upi_qr(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> QrCode:
        self._check()
        qr_id = f"qr_{secrets.token_hex(7)}"
        self.qrs.append({"id": qr_id, "amount": amount_paise, "notes": dict(notes)})
        payload = f"upi://pay?pa=fake@razorpay&am={paise_to_rupees(amount_paise)}&tr={qr_id}"
        return QrCode(id=qr_id, payload=payload, expires_at=expires_at)

    async def create_payment_link(
        self,
        *,
        amount_paise: int,
        reference: str,
        description: str,
        customer_phone: str | None,
        notes: Mapping[str, str],
        expires_at: datetime,
    ) -> PaymentLink:
        self._check()
        link_id = f"plink_{secrets.token_hex(7)}"
        self.links.append(
            {"id": link_id, "amount": amount_paise, "phone": customer_phone, "notes": dict(notes)}
        )
        return PaymentLink(
            id=link_id, short_url=f"https://rzp.test/{link_id}", expires_at=expires_at
        )

    def sign(self, body: bytes) -> str:
        return hmac_sha256_hex(self.webhook_secret, body)

    def verify_webhook(self, body: bytes, headers: Mapping[str, str]) -> bool:
        return verify_razorpay_signature(self.webhook_secret, body, headers)

    def parse_webhook(self, body: bytes) -> ProviderEvent:
        return parse_razorpay_event(body)

    async def fetch_settlements(self, day: date) -> list[SettlementRecord]:
        self._check()
        return list(self.settlements.get(day, []))


def razorpay_envelope(
    event: str,
    *,
    payment: Mapping[str, Any] | None = None,
    qr_code: Mapping[str, Any] | None = None,
    payment_link: Mapping[str, Any] | None = None,
    created_at: datetime,
) -> bytes:
    """A Razorpay-style webhook body (tests and the mockserver use the same envelope)."""
    payload: dict[str, Any] = {}
    if payment is not None:
        payload["payment"] = {"entity": dict(payment)}
    if qr_code is not None:
        payload["qr_code"] = {"entity": dict(qr_code)}
    if payment_link is not None:
        payload["payment_link"] = {"entity": dict(payment_link)}
    envelope = {
        "entity": "event",
        "account_id": "acc_test",
        "event": event,
        "contains": list(payload),
        "payload": payload,
        "created_at": int(created_at.timestamp()),
    }
    return json.dumps(envelope, separators=(",", ":")).encode()


__all__ = [
    "CAPTURED",
    "CASHFREE_SIGNATURE_HEADER",
    "CASHFREE_TIMESTAMP_HEADER",
    "FAILED",
    "RAZORPAY_EVENT_ID_HEADER",
    "RAZORPAY_SIGNATURE_HEADER",
    "CashfreeProvider",
    "FakePaymentProvider",
    "PaymentLink",
    "PaymentProvider",
    "PaymentProviderError",
    "ProviderEvent",
    "QrCode",
    "RazorpayProvider",
    "SettlementRecord",
    "WebhookParseError",
    "hmac_sha256_hex",
    "paise_to_rupees",
    "parse_razorpay_event",
    "razorpay_envelope",
    "rupees_to_paise",
    "verify_razorpay_signature",
]
