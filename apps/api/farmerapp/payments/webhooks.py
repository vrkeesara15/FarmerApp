"""Provider webhooks (SEC-023, FA-021, FM-010).

``POST /v1/webhooks/razorpay`` is public (``x-public``): the signature is the authentication.

1. **Signature.** ``X-Razorpay-Signature`` must be the HMAC-SHA256 of the *raw* body with the
   webhook secret (constant-time compare). A bad signature answers 401
   ``webhook_signature_invalid`` and the attempt is stored (``signature_ok = false``,
   ``status = rejected``, under a synthetic event id so it can never block the genuine
   event) when the claimed tenant exists; otherwise it is only logged.
2. **Tenant.** The verified payload's ``notes.tenant_id`` (we put it on every QR / link);
   an event for no known tenant is acknowledged and ignored (``200 ignored``).
3. **Idempotency (SPEC 8.3).** ``(tenant, provider, event id)`` is unique: a repeat of an
   event already stored answers ``200 duplicate`` and is not processed again.
4. **Replay window.** An event whose ``created_at`` is further than the tenant's
   ``webhook_replay_window_s`` (default 5 min) from now is rejected with 400
   ``webhook_stale`` (not stored: the provider gave up retrying long before that).
5. **Store and publish.** The ``webhook_event`` row is stored, then either published to
   ``payment.webhook`` (the worker applies it: ``farmerapp.payments.worker``) or, with
   ``PAYMENT_WEBHOOK_DELIVERY=inline``, applied in the same transaction.

``apply_webhook_event`` is the processing both paths share:
``payment.captured`` (and ``qr_code.credited`` / ``payment_link.paid``) -> ``paid`` after the
amount is cross-checked against the payment row (a mismatch flags the event
``amount_mismatch`` and does not pay); ``payment.failed`` -> ``failed``. A paid dues payment
posts the khata credit through the ``LedgerPort`` in the same transaction (FM-010: "payment
updates balance within 1 min of webhook" — the path is webhook -> Pub/Sub -> worker -> one
transaction; see docs/prs/FA-021-api.md); a paid order payment emits ``PaymentCaptured``.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, problem_response, problem_responses
from farmerapp.auth.deps import DbSession
from farmerapp.auth.policy import PUBLIC
from farmerapp.db import audit
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import set_tenant
from farmerapp.logging import get_logger
from farmerapp.payments.config import payment_settings
from farmerapp.payments.models import (
    SETTLED_STATUSES,
    Payment,
    PaymentStatus,
    WebhookEvent,
    WebhookStatus,
)
from farmerapp.payments.ports import LedgerPort
from farmerapp.payments.providers import (
    CAPTURED,
    FAILED,
    RAZORPAY_EVENT_ID_HEADER,
    PaymentProvider,
    ProviderEvent,
    WebhookParseError,
)
from farmerapp.payments.publisher import PublishError
from farmerapp.payments.schemas import WebhookAck
from farmerapp.payments.service import (
    PaymentServices,
    emit_captured,
    get_payment_services,
    settle_dues,
    utcnow,
)
from farmerapp.worker.topics import Topic

log = get_logger("farmerapp.payments.webhooks")

REJECTED_PREFIX = "rejected:"
MAX_STORED_RAW = 8192


class WebhookUnavailableError(AppError):
    status = 503
    code = "webhook_unavailable"


class WebhookMalformedError(AppError):
    status = 400
    code = "webhook_malformed"


# --------------------------------------------------------------------------- apply
@dataclass(frozen=True)
class Applied:
    status: WebhookStatus
    error: str | None = None
    payment_id: uuid.UUID | None = None


async def _find_payment(session: AsyncSession, event: ProviderEvent) -> Payment | None:
    hint = event.payment_hint
    if hint:
        try:
            row = await session.get(Payment, uuid.UUID(hint))
        except ValueError:
            row = None
        if row is not None:
            return row
    for provider_order_id in event.provider_order_ids:
        row = (
            await session.execute(
                select(Payment).where(Payment.provider_order_id == provider_order_id).limit(1)
            )
        ).scalar_one_or_none()
        if row is not None:
            return row
    if event.payment_ref:
        return (
            await session.execute(
                select(Payment).where(Payment.provider_ref == event.payment_ref).limit(1)
            )
        ).scalar_one_or_none()
    return None


async def apply_webhook_event(
    session: AsyncSession,
    row: WebhookEvent,
    *,
    provider: PaymentProvider,
    ledger: LedgerPort,
    now: datetime,
) -> Applied:
    """Apply a stored, verified event once (a processed row is left alone)."""
    if row.status != WebhookStatus.RECEIVED or not row.signature_ok:
        return Applied(WebhookStatus(row.status), row.error)
    result = await _apply(session, row, provider=provider, ledger=ledger, now=now)
    row.status, row.error, row.processed_at = result.status.value, result.error, now
    await session.flush()
    log.info(
        "webhook_applied",
        event_id=row.event_id,
        event_type=row.event_type,
        status=result.status.value,
        error=result.error,
        payment_id=str(result.payment_id) if result.payment_id else None,
    )
    return result


async def _apply(
    session: AsyncSession,
    row: WebhookEvent,
    *,
    provider: PaymentProvider,
    ledger: LedgerPort,
    now: datetime,
) -> Applied:
    try:
        event = provider.parse_webhook(json.dumps(row.payload).encode())
    except WebhookParseError:
        return Applied(WebhookStatus.FAILED, "unparseable")
    if event.event_type not in (CAPTURED, FAILED):
        return Applied(WebhookStatus.IGNORED, f"unhandled:{event.event_type}"[:120])
    payment = await _find_payment(session, event)
    if payment is None:
        return Applied(WebhookStatus.IGNORED, "payment_not_found")
    if payment.status in SETTLED_STATUSES | {PaymentStatus.PENDING_RECONCILIATION}:
        return Applied(WebhookStatus.IGNORED, "already_paid", payment.id)
    if event.event_type == FAILED:
        payment.status = PaymentStatus.FAILED.value
        payment.failure_reason = (event.error_reason or "payment_failed")[:64]
        if event.payment_ref:
            payment.provider_ref = event.payment_ref
        return Applied(WebhookStatus.PROCESSED, None, payment.id)
    # SEC-023: never trust the provider's amount blindly — it must equal what we asked for.
    if event.amount_paise != payment.amount_paise:
        log.warning(
            "webhook_amount_mismatch",
            event_id=row.event_id,
            payment_id=str(payment.id),
            expected_paise=payment.amount_paise,
            received_paise=event.amount_paise,
        )
        return Applied(WebhookStatus.FLAGGED, "amount_mismatch", payment.id)
    payment.status = PaymentStatus.PAID.value
    payment.paid_at = now
    payment.provider_ref = event.payment_ref or payment.provider_ref
    payment.provider_event_id = row.event_id
    payment.failure_reason = None
    await session.flush()
    await settle_dues(session, payment, ledger, audit.system_actor(payment.tenant_id))
    await emit_captured(session, payment, now)
    return Applied(WebhookStatus.PROCESSED, None, payment.id)


# --------------------------------------------------------------------------- receive
Outcome = Literal["accepted", "processed", "duplicate", "ignored", "bad_signature", "stale"]


@dataclass(frozen=True)
class Received:
    outcome: Outcome
    event_id: str | None = None
    row: WebhookEvent | None = None


def _lenient_json(body: bytes) -> dict[str, Any]:
    try:
        parsed = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return {"raw": body[:MAX_STORED_RAW].decode("utf-8", "replace")}
    return parsed if isinstance(parsed, dict) else {"raw": parsed}


def _claimed_tenant(payload: dict[str, Any]) -> uuid.UUID | None:
    inner = payload.get("payload")
    if not isinstance(inner, dict):
        return None
    for wrapper in inner.values():
        entity = wrapper.get("entity") if isinstance(wrapper, dict) else None
        notes = entity.get("notes") if isinstance(entity, dict) else None
        if isinstance(notes, dict) and notes.get("tenant_id"):
            try:
                return uuid.UUID(str(notes["tenant_id"]))
            except ValueError:
                return None
    return None


async def _bind_tenant(session: AsyncSession, tenant_id: uuid.UUID | None) -> Tenant | None:
    if tenant_id is None:
        return None
    await set_tenant(session, tenant_id)
    tenant = await session.get(Tenant, tenant_id)
    if tenant is None or tenant.deleted_at is not None:
        return None
    audit.bind_actor(audit.system_actor(tenant_id))
    return tenant


async def receive_webhook(
    session: AsyncSession,
    *,
    body: bytes,
    headers: dict[str, str],
    services: PaymentServices,
    now: datetime,
) -> Received:
    provider = services.provider
    provider_name = provider.name.value
    payload = _lenient_json(body)
    claimed_id = headers.get(RAZORPAY_EVENT_ID_HEADER) or None

    if not provider.verify_webhook(body, headers):
        tenant = await _bind_tenant(session, _claimed_tenant(payload))
        log.warning(
            "webhook_signature_invalid",
            provider=provider_name,
            claimed_event_id=claimed_id,
            tenant_id=str(tenant.id) if tenant else None,
        )
        if tenant is not None:
            session.add(
                WebhookEvent(
                    tenant_id=tenant.id,
                    provider=provider_name,
                    event_id=f"{REJECTED_PREFIX}{uuid.uuid4()}",
                    event_type=str(payload.get("event"))[:64] if payload.get("event") else None,
                    signature_ok=False,
                    payload={"claimed_event_id": claimed_id, "body": payload},
                    received_at=now,
                    processed_at=now,
                    status=WebhookStatus.REJECTED.value,
                    error="signature_invalid",
                )
            )
            await session.flush()
        return Received("bad_signature", claimed_id)

    try:
        event = provider.parse_webhook(body)
    except WebhookParseError as exc:
        raise WebhookMalformedError(str(exc)) from exc
    event_id = claimed_id or payload.get("id")
    if not isinstance(event_id, str) or not event_id:
        raise WebhookMalformedError("The event id header is missing.")
    tenant = await _bind_tenant(session, _claimed_tenant(payload))
    if tenant is None:
        log.info("webhook_unroutable", provider=provider_name, event_id=event_id)
        return Received("ignored", event_id)

    existing = (
        await session.execute(
            select(WebhookEvent).where(
                WebhookEvent.provider == provider_name, WebhookEvent.event_id == event_id
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        log.info("webhook_duplicate", provider=provider_name, event_id=event_id)
        return Received("duplicate", event_id, existing)

    window = payment_settings(tenant.settings).webhook_replay_window_s
    age = abs((now - event.created_at).total_seconds())
    if age > window:
        log.warning("webhook_stale", event_id=event_id, age_s=int(age), window_s=window)
        return Received("stale", event_id)

    row = WebhookEvent(
        tenant_id=tenant.id,
        provider=provider_name,
        event_id=event_id,
        event_type=str(payload.get("event"))[:64],
        signature_ok=True,
        payload=payload,
        received_at=now,
        status=WebhookStatus.RECEIVED.value,
    )
    try:
        async with session.begin_nested():
            session.add(row)
            await session.flush()
    except IntegrityError:  # a concurrent delivery of the same event won the race
        return Received("duplicate", event_id)

    if services.publisher is None:
        await apply_webhook_event(session, row, provider=provider, ledger=services.ledger, now=now)
        return Received("processed", event_id, row)
    try:
        await services.publisher.publish(
            Topic.PAYMENT_WEBHOOK,
            {"tenant_id": str(tenant.id), "webhook_event_id": str(row.id), "event_id": event_id},
        )
    except PublishError as exc:
        raise WebhookUnavailableError("Could not queue the event; retry.") from exc
    return Received("accepted", event_id, row)


# --------------------------------------------------------------------------- route
router = APIRouter(prefix="/webhooks", tags=["webhooks"])


@router.post(
    "/razorpay",
    operation_id="receiveRazorpayWebhook",
    summary="Razorpay webhook (HMAC-signed; idempotent by event id)",
    dependencies=[PUBLIC],
    response_model=WebhookAck,
    responses=problem_responses(
        (400, "webhook_stale"),
        (400, "webhook_malformed"),
        (401, "webhook_signature_invalid"),
        (503, "webhook_unavailable"),
    ),
)
async def razorpay_webhook(
    request: Request,
    session: DbSession,
    services: PaymentServices = Depends(get_payment_services),  # noqa: B008
) -> Response:
    body = await request.body()
    headers = {k.lower(): v for k, v in request.headers.items()}
    received = await receive_webhook(
        session, body=body, headers=headers, services=services, now=utcnow()
    )
    if received.outcome == "bad_signature":
        # Returned (not raised) so the rejected attempt row commits with the request.
        return problem_response(
            request,
            status=401,
            code="webhook_signature_invalid",
            detail="The webhook signature does not verify.",
        )
    if received.outcome == "stale":
        return problem_response(
            request,
            status=400,
            code="webhook_stale",
            detail="The event is outside the replay window.",
        )
    ack = WebhookAck(status=received.outcome, event_id=received.event_id)
    return JSONResponse(ack.model_dump(), status_code=200)


__all__ = [
    "Applied",
    "Received",
    "WebhookMalformedError",
    "apply_webhook_event",
    "receive_webhook",
    "router",
]
