"""SMS / WhatsApp provider adapters.

``FakeProvider`` records sends in memory (tests, ``OTP_PROVIDER=fake``).
``MockServerProvider`` talks HTTP to docker/mockserver (local/dev). A real DLT-registered SMS
gateway and the WhatsApp Business API get their own adapters with the same protocols; the
choice is made in ``farmerapp.auth.deps.build_auth_services`` from settings.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Protocol

import httpx

OTP_TEMPLATE = "otp_login"  # WhatsApp template name (DLT-equivalent registration is human work)


class DeliveryStatus(StrEnum):
    DELIVERED = "delivered"
    PENDING = "pending"
    FAILED = "failed"
    UNKNOWN = "unknown"


class ProviderError(RuntimeError):
    """The provider rejected or failed the request."""


class SmsProvider(Protocol):
    async def send_sms(self, to: str, body: str) -> str:
        """Send and return the provider message reference."""
        ...

    async def delivery_status(self, ref: str) -> DeliveryStatus: ...


class WhatsAppProvider(Protocol):
    async def send_whatsapp(self, to: str, template: str, params: dict[str, str]) -> str: ...


def mask_phone(phone: str) -> str:
    """``+919876543210`` -> ``+91******3210``: never log or return a full phone number."""
    prefix = "+91" if phone.startswith("+91") else ""
    rest = phone[len(prefix) :]
    if len(rest) <= 4:
        return prefix + "*" * len(rest)
    return prefix + "*" * (len(rest) - 4) + rest[-4:]


def otp_message(code: str, ttl_seconds: int) -> str:
    minutes = max(1, ttl_seconds // 60)
    return f"{code} is your FarmerApp login code. Valid for {minutes} min. Do not share it."


@dataclass
class FakeMessage:
    to: str
    body: str
    ref: str
    channel: str = "sms"
    template: str | None = None
    params: dict[str, str] = field(default_factory=dict)


class FakeProvider:
    """In-process provider for tests. Implements both protocols."""

    def __init__(self, *, auto_deliver: bool = True) -> None:
        self.sent: list[FakeMessage] = []
        self.auto_deliver = auto_deliver
        self._delivered: set[str] = set()
        self._known: set[str] = set()

    async def send_sms(self, to: str, body: str) -> str:
        ref = f"fake_sms_{secrets.token_hex(4)}"
        self.sent.append(FakeMessage(to=to, body=body, ref=ref))
        self._known.add(ref)
        if self.auto_deliver:
            self._delivered.add(ref)
        return ref

    async def send_whatsapp(self, to: str, template: str, params: dict[str, str]) -> str:
        ref = f"fake_wa_{secrets.token_hex(4)}"
        body = (
            otp_message(params["code"], int(params.get("ttl", "300"))) if "code" in params else ""
        )
        self.sent.append(
            FakeMessage(
                to=to, body=body, ref=ref, channel="whatsapp", template=template, params=params
            )
        )
        self._known.add(ref)
        return ref

    def deliver(self, ref: str) -> None:
        self._delivered.add(ref)

    async def delivery_status(self, ref: str) -> DeliveryStatus:
        if ref in self._delivered:
            return DeliveryStatus.DELIVERED
        if ref in self._known:
            return DeliveryStatus.PENDING
        return DeliveryStatus.UNKNOWN


class MockServerProvider:
    """HTTP adapter for docker/mockserver (``/sms/send``, ``/sms/status/{id}``, ``/whatsapp``)."""

    def __init__(
        self,
        *,
        sms_url: str,
        whatsapp_url: str,
        client: httpx.AsyncClient | None = None,
        timeout: float = 5.0,
    ) -> None:
        self._sms_url = sms_url.rstrip("/")
        self._wa_url = whatsapp_url.rstrip("/")
        self._client = client or httpx.AsyncClient(timeout=timeout)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def _post(self, url: str, payload: dict[str, Any]) -> dict[str, Any]:
        try:
            resp = await self._client.post(url, json=payload)
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            raise ProviderError(f"provider call failed: {url}") from exc
        data: dict[str, Any] = resp.json()
        return data

    async def send_sms(self, to: str, body: str) -> str:
        data = await self._post(f"{self._sms_url}/send", {"to": to, "message": body})
        return str(data["id"])

    async def delivery_status(self, ref: str) -> DeliveryStatus:
        try:
            resp = await self._client.get(f"{self._sms_url}/status/{ref}")
        except httpx.HTTPError:
            return DeliveryStatus.UNKNOWN
        if resp.status_code != 200:
            return DeliveryStatus.UNKNOWN
        status = str(resp.json().get("status", "unknown"))
        try:
            return DeliveryStatus(status)
        except ValueError:
            return DeliveryStatus.PENDING if status == "queued" else DeliveryStatus.UNKNOWN

    async def send_whatsapp(self, to: str, template: str, params: dict[str, str]) -> str:
        data = await self._post(
            f"{self._wa_url}/send", {"to": to, "template": template, "params": params}
        )
        return str(data["id"])
