"""Payment collection (FA-021, ST-002, FM-010).

``create_payment`` is the one write path for ``POST /v1/payments``, the POS sale and the
``payment`` sync op:

1. **Target and scope.** An order the caller may see (``order_filters``) or a farmer's
   khata at a store (``khata_farmer_filters`` + the caller's store scope). A farmer may only
   pay by UPI QR / link (FM-010).
2. **Amount (SEC-023).** Always computed here: for an order, its total minus what is already
   received; for dues, the outstanding khata balance at that store. A client amount is only
   *checked*: an order payment must match exactly, a dues payment may be partial up to the
   balance; anything else is 422 ``amount_mismatch``.
3. **Mode.**
   ``upi_qr`` — provider QR (single use, fixed amount), status ``pending`` until the webhook.
   ``payment_link`` — provider link, sent by SMS or WhatsApp through the existing
   adapters; ``pending``.
   ``cash`` — needs ``receipt_uri`` (a completed upload of this tenant);
   ``pending_reconciliation`` until the day close counts it (ST-006).
   ``card_terminal`` — needs ``reference_note`` (the store's own terminal); ``paid``.
   ``credit`` — orders with a farmer only: ``khata.credit.check_and_reserve_credit``
   through the ``LedgerPort`` (ST-007), called *before* anything is written. Allowed ->
   ``paid``; the gate already posted the khata debit, which becomes
   ``payment.khata_entry_id`` (no second debit here). Blocked -> nothing but the gate's
   ``credit_approval_request`` is written and ``CreditBlocked`` is *returned*: callers
   answer 402 ``credit_limit_exceeded`` without raising so the request commits.
   The POS reserves the credit itself before the order exists and passes the decision in.
4. **Effects.** Money in hand for dues posts the khata credit through
   ``khata.ledger.post_credit`` in the same transaction (FM-010: the balance moves
   immediately); money in hand for an order emits ``PaymentCaptured`` on the in-process bus
   (``farmerapp.orders.payment_events`` moves a waiting order on, in this transaction).

Provider payments become ``paid`` in ``farmerapp.payments.webhooks`` (SEC-023).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import Request
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ForbiddenError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.providers import ProviderError, SmsProvider, WhatsAppProvider
from farmerapp.auth.scope import khata_farmer_filters, order_filters, payment_filters, store_filters
from farmerapp.db import audit
from farmerapp.farmers.models import Farmer
from farmerapp.khata.credit import CreditDecision
from farmerapp.khata.models import EntryRef, EntryType, KhataEntry, khata_balance
from farmerapp.logging import get_logger
from farmerapp.orders.models import Order, OrderStatus
from farmerapp.payments.events import PaymentCaptured, bus
from farmerapp.payments.models import (
    PROVIDER_MODES,
    RECEIVED_STATUSES,
    Payment,
    PaymentMode,
    PaymentStatus,
)
from farmerapp.payments.models import PaymentProvider as ProviderName
from farmerapp.payments.ports import KhataLedgerPort, LedgerPort
from farmerapp.payments.providers import (
    FakePaymentProvider,
    PaymentProvider,
    PaymentProviderError,
    RazorpayProvider,
    paise_to_rupees,
)
from farmerapp.payments.publisher import Publisher, PubSubRestPublisher
from farmerapp.payments.schemas import PaymentCreate, PaymentCreated, PaymentStatusOut
from farmerapp.settings import Settings
from farmerapp.tenants.models import Store
from farmerapp.uploads.blobstore import BlobStore, parse_uri

log = get_logger("farmerapp.payments")

PAYMENT_LINK_TEMPLATE = "payment_link"  # WhatsApp template (registration is human work)
PAYMENT_LINK_SMS = "Pay Rs {amount} to {store} securely: {url}"  # DLT template body


# --------------------------------------------------------------------------- errors
class AmountMismatchError(AppError):
    status = 422
    code = "amount_mismatch"


class AlreadyPaidError(AppError):
    status = 409
    code = "already_paid"


class NothingDueError(AppError):
    status = 409
    code = "nothing_due"


class OrderCancelledError(AppError):
    status = 409
    code = "order_cancelled"


class ReceiptRequiredError(AppError):
    status = 422
    code = "receipt_required"


class ReferenceRequiredError(AppError):
    status = 422
    code = "reference_required"


class InvalidBlobError(AppError):
    status = 422
    code = "invalid_blob"


class PhoneRequiredError(AppError):
    status = 422
    code = "phone_required"


class InvalidModeError(AppError):
    status = 422
    code = "invalid_mode"


class ProviderUnavailableError(AppError):
    status = 502
    code = "provider_error"


class ModeNotAllowedError(ForbiddenError):
    code = "mode_not_allowed"


# --------------------------------------------------------------------------- services
def utcnow() -> datetime:
    return datetime.now(UTC)


@dataclass
class PaymentServices:
    """What the payment paths need besides the session (``app.state.payments``)."""

    settings: Settings
    provider: PaymentProvider
    ledger: LedgerPort = field(default_factory=KhataLedgerPort)
    publisher: Publisher | None = None  # None = apply webhooks inline (local / dev)


def build_provider(settings: Settings) -> PaymentProvider:
    if settings.payment_provider == "fake":
        return FakePaymentProvider(webhook_secret=settings.razorpay_webhook_secret)
    return RazorpayProvider(
        base_url=settings.razorpay_base_url,
        key_id=settings.razorpay_key_id,
        key_secret=settings.razorpay_key_secret,
        webhook_secret=settings.razorpay_webhook_secret,
    )


def build_payment_services(settings: Settings) -> PaymentServices:
    publisher: Publisher | None = None
    if settings.payment_webhook_delivery == "pubsub":
        publisher = PubSubRestPublisher(
            base_url=settings.pubsub_emulator_host or "https://pubsub.googleapis.com",
            project=settings.gcp_project,
        )
    return PaymentServices(
        settings=settings, provider=build_provider(settings), publisher=publisher
    )


def get_payment_services(request: Request) -> PaymentServices:
    services: PaymentServices = request.app.state.payments
    return services


def actor_of(user: User) -> audit.Actor:
    """The audit actor bound for this request, else one built from the user."""
    bound = audit.current_actor()
    if bound is not None and bound.actor_id == user.id:
        return bound
    return audit.Actor(tenant_id=user.tenant_id, actor_id=user.id, actor_role=str(user.role))


# --------------------------------------------------------------------------- helpers
async def validate_blob(uri: str, tenant_id: uuid.UUID, blobs: BlobStore) -> str:
    """A completed upload of this tenant (``gs://<bucket>/<tenant_id>/...``) that exists."""
    try:
        _bucket, key = parse_uri(uri)
    except ValueError as exc:
        raise InvalidBlobError("Not a blob URI from /v1/uploads.") from exc
    if not key.startswith(f"{tenant_id}/") or not await blobs.exists(uri):
        raise InvalidBlobError("The blob does not exist in this tenant; upload it first.")
    return uri


async def received_for_order(session: AsyncSession, order_id: uuid.UUID) -> int:
    total = await session.scalar(
        select(func.coalesce(func.sum(Payment.amount_paise), 0)).where(
            Payment.order_id == order_id,
            Payment.deleted_at.is_(None),
            Payment.status.in_([s.value for s in RECEIVED_STATUSES]),
        )
    )
    return int(total or 0)


async def visible_payment(session: AsyncSession, actor: User, payment_id: uuid.UUID) -> Payment:
    row = (
        await session.execute(
            select(Payment).where(
                Payment.id == payment_id, Payment.deleted_at.is_(None), *payment_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Payment not found.")
    return row


async def _visible_order(session: AsyncSession, actor: User, order_id: uuid.UUID) -> Order:
    order = (
        await session.execute(
            select(Order).where(
                Order.id == order_id, Order.deleted_at.is_(None), *order_filters(actor)
            )
        )
    ).scalar_one_or_none()
    if order is None:
        raise NotFoundError("Order not found.")
    return order


async def _dues_target(
    session: AsyncSession, actor: User, farmer_id: uuid.UUID, store_id: uuid.UUID
) -> tuple[Farmer, Store]:
    farmer = (
        await session.execute(
            select(Farmer).where(
                Farmer.id == farmer_id, Farmer.deleted_at.is_(None), *khata_farmer_filters(actor)
            )
        )
    ).scalar_one_or_none()
    stmt = select(Store).where(
        Store.id == store_id, Store.tenant_id == actor.tenant_id, Store.deleted_at.is_(None)
    )
    by_store = store_filters(actor, Store.id)
    if by_store is not None:  # store staff / cluster head: only their stores
        stmt = stmt.where(*by_store)
    store = (await session.execute(stmt)).scalar_one_or_none()
    if farmer is None or store is None:
        raise NotFoundError("Farmer or store not found.")
    return farmer, store


@dataclass(frozen=True)
class Target:
    store_id: uuid.UUID
    farmer_id: uuid.UUID | None
    order: Order | None
    due_paise: int


async def resolve_target(session: AsyncSession, actor: User, body: PaymentCreate) -> Target:
    """Scope-checked target with the server-computed amount due (SEC-023)."""
    if body.order_id is not None:
        order = await _visible_order(session, actor, body.order_id)
        if order.status == OrderStatus.CANCELLED:
            raise OrderCancelledError("The order was cancelled.")
        due = order.total_paise - await received_for_order(session, order.id)
        if due <= 0:
            raise AlreadyPaidError("The order is already paid.")
        if body.amount_paise is not None and body.amount_paise != due:
            raise AmountMismatchError(
                "The amount does not match the order total due.", extra={"due_paise": due}
            )
        return Target(
            store_id=order.store_id, farmer_id=order.farmer_id, order=order, due_paise=due
        )
    if body.farmer_id is None or body.store_id is None:  # the schema validator forbids it
        raise NotFoundError("Farmer or store not found.")
    farmer, store = await _dues_target(session, actor, body.farmer_id, body.store_id)
    balance = await khata_balance(session, farmer.id, store.id)
    if balance <= 0:
        raise NothingDueError("Nothing is due on this khata.")
    amount = balance
    if body.amount_paise is not None:
        if body.amount_paise > balance:
            raise AmountMismatchError(
                "The amount is more than the outstanding balance.", extra={"due_paise": balance}
            )
        amount = body.amount_paise
    return Target(store_id=store.id, farmer_id=farmer.id, order=None, due_paise=amount)


async def _phone_for(session: AsyncSession, body: PaymentCreate, target: Target) -> str:
    if body.phone:
        return body.phone
    if target.farmer_id is not None:
        farmer = await session.get(Farmer, target.farmer_id)
        if farmer is not None:
            return farmer.phone
    raise PhoneRequiredError("A payment link needs the farmer's phone (or `phone`).")


def _notes(payment: Payment) -> dict[str, str]:
    notes = {"tenant_id": str(payment.tenant_id), "payment_id": str(payment.id)}
    if payment.order_id is not None:
        notes["order_id"] = str(payment.order_id)
    return notes


async def _send_link(
    *,
    sms: SmsProvider,
    whatsapp: WhatsAppProvider,
    channel: str,
    phone: str,
    amount_paise: int,
    store_name: str,
    url: str,
) -> None:
    amount = paise_to_rupees(amount_paise)
    try:
        if channel == "whatsapp":
            await whatsapp.send_whatsapp(
                phone, PAYMENT_LINK_TEMPLATE, {"amount": amount, "store": store_name, "url": url}
            )
        else:
            await sms.send_sms(
                phone, PAYMENT_LINK_SMS.format(amount=amount, store=store_name, url=url)
            )
    except ProviderError as exc:
        raise ProviderUnavailableError("The message could not be sent; try again.") from exc


async def emit_captured(session: AsyncSession, payment: Payment, at: datetime) -> None:
    """``PaymentCaptured`` for an order payment; writing subscribers run in ``session``."""
    if payment.order_id is None:
        return
    await bus.dispatch(
        session,
        PaymentCaptured(
            tenant_id=payment.tenant_id,
            payment_id=payment.id,
            order_id=payment.order_id,
            store_id=payment.store_id,
            farmer_id=payment.farmer_id,
            mode=payment.mode,
            amount_paise=payment.amount_paise,
            provider_event_id=payment.provider_event_id,
            at=at,
        ),
    )


async def settle_dues(
    session: AsyncSession, payment: Payment, ledger: LedgerPort, actor: audit.Actor
) -> None:
    """Money in hand against dues: post the khata credit (FM-010) and link it."""
    if payment.order_id is not None or payment.farmer_id is None or payment.khata_entry_id:
        return
    entry = await ledger.post_credit(
        session,
        tenant_id=payment.tenant_id,
        farmer_id=payment.farmer_id,
        store_id=payment.store_id,
        amount_paise=payment.amount_paise,
        ref_type="payment",
        ref_id=payment.id,
        actor=actor,
    )
    payment.khata_entry_id = entry.id


async def _order_on_khata(session: AsyncSession, order_id: uuid.UUID) -> bool:
    """Whether a credit sale debit for the order is on the khata (net of reversals)."""
    signed = await session.scalar(
        select(
            func.coalesce(
                func.sum(
                    case(
                        (KhataEntry.type == EntryType.DEBIT.value, KhataEntry.amount_paise),
                        else_=-KhataEntry.amount_paise,
                    )
                ),
                0,
            )
        ).where(
            KhataEntry.ref_id == order_id,
            KhataEntry.ref_type.in_([EntryRef.ORDER.value, EntryRef.ADJUSTMENT.value]),
        )
    )
    return int(signed or 0) > 0


# --------------------------------------------------------------------------- create
@dataclass
class Messaging:
    sms: SmsProvider
    whatsapp: WhatsAppProvider


@dataclass(frozen=True)
class CreditBlocked:
    """A credit sale beyond the limit: only the approval request was written. Answer 402
    ``credit_limit_exceeded`` (``khata.credit.decision_extra``) **without raising**."""

    decision: CreditDecision


async def create_payment(
    session: AsyncSession,
    actor: User,
    body: PaymentCreate,
    *,
    services: PaymentServices,
    messaging: Messaging,
    blobs: BlobStore,
    now: datetime,
    payment_id: uuid.UUID | None = None,
    target: Target | None = None,
    credit: CreditDecision | None = None,
) -> PaymentCreated | CreditBlocked:
    """Collect a payment (see the module doc). ``credit`` = a decision the caller already
    obtained from the credit gate for this order and amount (the POS); without it a credit
    payment calls the gate here."""
    mode = PaymentMode(body.mode)
    if UserRole(actor.role) == UserRole.FARMER and mode not in PROVIDER_MODES:
        raise ModeNotAllowedError("Farmers pay by UPI QR or payment link.")
    if target is None:
        target = await resolve_target(session, actor, body)
    if mode == PaymentMode.CASH and not body.receipt_uri:
        raise ReceiptRequiredError("Cash needs the receipt photo (`receipt_uri`).")
    if mode == PaymentMode.CARD_TERMINAL and not body.reference_note:
        raise ReferenceRequiredError("Card needs the terminal reference (`reference_note`).")
    if mode == PaymentMode.CREDIT and (target.order is None or target.farmer_id is None):
        raise InvalidModeError("Credit is for an order of a known farmer, not for dues.")
    if mode == PaymentMode.CASH and body.receipt_uri:
        await validate_blob(body.receipt_uri, actor.tenant_id, blobs)

    who = actor_of(actor)
    if mode == PaymentMode.CREDIT and target.farmer_id is not None and target.order is not None:
        if credit is None:
            if await _order_on_khata(session, target.order.id):
                # Placed on credit (FA-020): the gate already posted its debit.
                raise AlreadyPaidError("The order is already on the farmer's khata.")
            credit = await services.ledger.check_and_reserve_credit(
                session,
                tenant_id=actor.tenant_id,
                farmer_id=target.farmer_id,
                store_id=target.store_id,
                amount_paise=target.due_paise,
                order_id=target.order.id,
                actor=who,
            )
        if not credit.allowed:
            log.info(
                "payment_credit_blocked",
                order_id=str(target.order.id),
                approval_request_id=str(credit.approval_request_id),
            )
            return CreditBlocked(credit)
    payment = Payment(
        id=payment_id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        order_id=target.order.id if target.order is not None else None,
        farmer_id=target.farmer_id,
        store_id=target.store_id,
        mode=mode.value,
        amount_paise=target.due_paise,
        provider=(services.provider.name if mode in PROVIDER_MODES else ProviderName.NONE).value,
        status=PaymentStatus.CREATED.value,
        collected_by=actor.id if UserRole(actor.role) != UserRole.FARMER else None,
        receipt_uri=body.receipt_uri if mode == PaymentMode.CASH else None,
        reference_note=body.reference_note if mode == PaymentMode.CARD_TERMINAL else None,
        # ST-007: the gate posted the debit of a credit sale; link it (never a second one).
        khata_entry_id=credit.khata_entry_id if credit is not None else None,
    )
    # The provider is called before the row is written: a provider failure leaves nothing
    # behind, and no row lock is held across the HTTP call.
    out = PaymentCreated(
        payment_id=payment.id,
        mode=mode,
        status=PaymentStatus.CREATED,
        amount_paise=payment.amount_paise,
        order_id=payment.order_id,
        farmer_id=payment.farmer_id,
        store_id=payment.store_id,
    )

    expires = now + timedelta(seconds=services.settings.payment_qr_ttl_seconds)
    description = f"Order {payment.order_id}" if payment.order_id else "Khata dues"
    try:
        if mode == PaymentMode.UPI_QR:
            qr = await services.provider.create_upi_qr(
                amount_paise=payment.amount_paise,
                reference=str(payment.id),
                description=description,
                notes=_notes(payment),
                expires_at=expires,
            )
            payment.provider_order_id, payment.qr_payload = qr.id, qr.payload
            payment.expires_at, payment.status = qr.expires_at, PaymentStatus.PENDING.value
            out.qr_payload, out.expires_at = qr.payload, qr.expires_at
        elif mode == PaymentMode.PAYMENT_LINK:
            phone = await _phone_for(session, body, target)
            link = await services.provider.create_payment_link(
                amount_paise=payment.amount_paise,
                reference=str(payment.id),
                description=description,
                customer_phone=phone,
                notes=_notes(payment),
                expires_at=expires,
            )
            payment.provider_order_id, payment.short_url = link.id, link.short_url
            payment.expires_at, payment.status = link.expires_at, PaymentStatus.PENDING.value
            store = await session.get_one(Store, payment.store_id)
            await _send_link(
                sms=messaging.sms,
                whatsapp=messaging.whatsapp,
                channel=body.channel,
                phone=phone,
                amount_paise=payment.amount_paise,
                store_name=store.name,
                url=link.short_url,
            )
            out.short_url, out.expires_at, out.sent_via = (
                link.short_url,
                link.expires_at,
                body.channel,
            )
    except PaymentProviderError as exc:
        log.warning("payment_provider_failed", mode=mode.value, payment_id=str(payment.id))
        raise ProviderUnavailableError("The payment provider is unavailable; try again.") from exc

    session.add(payment)
    await session.flush()
    if mode not in PROVIDER_MODES:  # money (or credit) in hand now
        payment.status = (
            PaymentStatus.PENDING_RECONCILIATION.value
            if mode == PaymentMode.CASH
            else PaymentStatus.PAID.value
        )
        payment.paid_at = now
        if mode != PaymentMode.CREDIT:
            await settle_dues(session, payment, services.ledger, who)
    await session.flush()
    out.status = PaymentStatus(payment.status)
    out.khata_entry_id = payment.khata_entry_id
    if mode not in PROVIDER_MODES:
        await emit_captured(session, payment, now)
    log.info(
        "payment_created",
        payment_id=str(payment.id),
        mode=mode.value,
        status=payment.status,
        amount_paise=payment.amount_paise,
    )
    return out


# --------------------------------------------------------------------------- status
PollState = Literal["waiting", "paid", "failed"]
_STATE: dict[PaymentStatus, PollState] = {
    PaymentStatus.CREATED: "waiting",
    PaymentStatus.PENDING: "waiting",
    PaymentStatus.PENDING_RECONCILIATION: "paid",
    PaymentStatus.PAID: "paid",
    PaymentStatus.RECONCILED: "paid",
    PaymentStatus.FAILED: "failed",
    PaymentStatus.REFUNDED: "failed",
}


def status_out(payment: Payment) -> PaymentStatusOut:
    status = PaymentStatus(payment.status)
    return PaymentStatusOut(
        id=payment.id,
        state=_STATE[status],
        status=status,
        mode=PaymentMode(payment.mode),
        amount_paise=payment.amount_paise,
        order_id=payment.order_id,
        farmer_id=payment.farmer_id,
        store_id=payment.store_id,
        qr_payload=payment.qr_payload,
        short_url=payment.short_url,
        expires_at=payment.expires_at,
        paid_at=payment.paid_at,
        failure_reason=payment.failure_reason,
    )


__all__ = [
    "AlreadyPaidError",
    "AmountMismatchError",
    "CreditBlocked",
    "InvalidBlobError",
    "InvalidModeError",
    "Messaging",
    "ModeNotAllowedError",
    "NothingDueError",
    "PaymentServices",
    "ProviderUnavailableError",
    "Target",
    "actor_of",
    "build_payment_services",
    "build_provider",
    "create_payment",
    "emit_captured",
    "get_payment_services",
    "received_for_order",
    "resolve_target",
    "settle_dues",
    "status_out",
    "utcnow",
    "validate_blob",
    "visible_payment",
]
