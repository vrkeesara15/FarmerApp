"""Payments, provider webhooks and the store day close (SPEC 8.2 ``payment``; FA-021, ST-002,
ST-006, SEC-023, FM-010).

* ``payment`` — one collection attempt: for an order (``order_id``) or against the khata
  (``khata_entry_id`` -> the credit entry it settles), by ``mode`` (UPI dynamic QR, payment
  link by SMS / WhatsApp, cash with a receipt photo ``receipt_uri``, card on the store's own
  terminal with the manual ``reference_note``, or ``credit`` = the sale went on the khata:
  the linked ``khata_entry`` is then the debit). Provider payments carry ``provider_ref``
  (the provider's payment id) and ``provider_event_id`` (the webhook event that marked
  them paid; unique per tenant and provider so a replayed webhook cannot pay twice).
  ``status``: ``created`` -> ``pending`` (QR / link shown) -> ``paid`` (webhook) ->
  ``reconciled`` (card matched to the terminal report) or ``failed`` / ``refunded``; cash is
  ``pending_reconciliation`` until the day close counts it (-> ``reconciled``, 0013).
  Amounts are integer paise and always recomputed server-side.
* ``webhook_event`` — every provider webhook as received (SEC-023): provider, the event id
  (unique per tenant and provider = idempotency, SPEC 8.3), whether the HMAC signature
  verified, the raw payload, when it arrived and when / how it was processed. Replays
  hit the unique constraint and are answered from the stored row.
* ``day_close`` — ST-006: one per store and business date: cash expected from the day's
  cash payments, cash counted, the variance (CHECK: ``counted - expected``), the deposit slip
  photo and who closed. A variance over the tenant threshold flags the auditor (M4 rule).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns


class PaymentMode(StrEnum):
    UPI_QR = "upi_qr"
    PAYMENT_LINK = "payment_link"
    CASH = "cash"
    CARD_TERMINAL = "card_terminal"
    CREDIT = "credit"  # on the khata (FA-021, ST-007)


class PaymentProvider(StrEnum):
    RAZORPAY = "razorpay"
    CASHFREE = "cashfree"
    NONE = "none"  # cash, card terminal, credit


class PaymentStatus(StrEnum):
    CREATED = "created"
    PENDING = "pending"
    PENDING_RECONCILIATION = "pending_reconciliation"  # cash until the day close (ST-006)
    PAID = "paid"
    FAILED = "failed"
    REFUNDED = "refunded"
    RECONCILED = "reconciled"


class WebhookStatus(StrEnum):
    RECEIVED = "received"
    PROCESSED = "processed"
    IGNORED = "ignored"  # unknown event type / no matching payment
    FAILED = "failed"
    FLAGGED = "flagged"  # verified but not applied: amount mismatch (SEC-023)
    REJECTED = "rejected"  # signature did not verify (SEC-023)


class DayCloseStatus(StrEnum):
    CLOSED = "closed"
    REOPENED = "reopened"  # by a cluster head; the next close updates the same row


#: Modes that go through a provider (and therefore a webhook).
PROVIDER_MODES = frozenset({PaymentMode.UPI_QR, PaymentMode.PAYMENT_LINK})
#: Statuses that count as money received (ST-002 day-end totals, FM-010 balance).
SETTLED_STATUSES = frozenset({PaymentStatus.PAID, PaymentStatus.RECONCILED})
#: Statuses in which the money is in hand (settled or cash waiting for the day close).
RECEIVED_STATUSES = SETTLED_STATUSES | {PaymentStatus.PENDING_RECONCILIATION}


class Payment(Base, BaseColumns):
    __tablename__ = "payment"
    __table_args__ = (
        UniqueConstraint("tenant_id", "provider", "provider_event_id"),
        CheckConstraint(f"mode IN ({sql_in(PaymentMode)})", name="mode"),
        CheckConstraint(f"provider IN ({sql_in(PaymentProvider)})", name="provider"),
        CheckConstraint(f"status IN ({sql_in(PaymentStatus)})", name="status"),
        CheckConstraint("amount_paise > 0", name="amount_paise"),
        CheckConstraint(
            "(mode IN ('upi_qr', 'payment_link')) = (provider <> 'none')", name="provider_mode"
        ),
        # A dues payment (FM-010) names the farmer until its khata credit entry exists.
        CheckConstraint(
            "order_id IS NOT NULL OR khata_entry_id IS NOT NULL OR farmer_id IS NOT NULL",
            name="target",
        ),
        Index("ix_payment_store_created", "tenant_id", "store_id", "created_at"),
        Index("ix_payment_order_id", "order_id"),
        Index("ix_payment_farmer_id", "farmer_id"),
        Index("ix_payment_collected_by", "collected_by"),
        Index("ix_payment_provider_order_id", "tenant_id", "provider_order_id"),
        Index("ix_payment_day_close_id", "day_close_id"),
    )

    order_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("order.id", ondelete="SET NULL"), nullable=True
    )
    khata_entry_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("khata_entry.id", ondelete="SET NULL"), nullable=True
    )
    farmer_id: Mapped[uuid.UUID | None] = mapped_column(  # NULL = walk-in
        ForeignKey("farmer.id", ondelete="SET NULL"), nullable=True
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="RESTRICT"), nullable=False
    )
    mode: Mapped[str] = mapped_column(String(16), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    provider: Mapped[str] = mapped_column(String(16), nullable=False, default=PaymentProvider.NONE)
    provider_ref: Mapped[str | None] = mapped_column(String(64), nullable=True)  # pay_...
    provider_event_id: Mapped[str | None] = mapped_column(String(64), nullable=True)  # evt_...
    status: Mapped[str] = mapped_column(String(24), nullable=False, default=PaymentStatus.CREATED)
    receipt_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)  # cash photo
    collected_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    reference_note: Mapped[str | None] = mapped_column(String(200), nullable=True)  # terminal ref
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # 0013 (FA-021): the provider object (QR code / payment link / order id), what the
    # device shows, when it expires, the day close that reconciled a cash payment.
    provider_order_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    qr_payload: Mapped[str | None] = mapped_column(Text, nullable=True)
    short_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    day_close_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("day_close.id", ondelete="SET NULL"), nullable=True
    )
    failure_reason: Mapped[str | None] = mapped_column(String(64), nullable=True)


class WebhookEvent(Base, BaseColumns):
    __tablename__ = "webhook_event"
    __table_args__ = (
        UniqueConstraint("tenant_id", "provider", "event_id"),
        CheckConstraint(f"status IN ({sql_in(WebhookStatus)})", name="status"),
        CheckConstraint("char_length(event_id) > 0", name="event_id"),
        Index("ix_webhook_event_received", "tenant_id", "received_at"),
    )

    provider: Mapped[str] = mapped_column(String(16), nullable=False)
    event_id: Mapped[str] = mapped_column(String(128), nullable=False)
    event_type: Mapped[str | None] = mapped_column(String(64), nullable=True)  # payment.captured
    signature_ok: Mapped[bool] = mapped_column(Boolean, nullable=False)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default=WebhookStatus.RECEIVED)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)


class DayClose(Base, BaseColumns):
    __tablename__ = "day_close"
    __table_args__ = (
        UniqueConstraint("tenant_id", "store_id", "business_date"),
        CheckConstraint(
            "cash_expected_paise >= 0 AND cash_counted_paise >= 0", name="cash_amounts"
        ),
        CheckConstraint(
            "variance_paise = cash_counted_paise - cash_expected_paise", name="variance"
        ),
        CheckConstraint(f"status IN ({sql_in(DayCloseStatus)})", name="status"),
    )

    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    business_date: Mapped[date] = mapped_column(Date, nullable=False)
    cash_expected_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    cash_counted_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    variance_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    deposit_slip_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)
    closed_by: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    closed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    # 0013 (ST-006): re-open by a cluster head, and whether the variance flagged the auditor.
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=DayCloseStatus.CLOSED, server_default="closed"
    )
    reopened_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    reopened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reopen_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    variance_flagged: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )


__all__ = [
    "PROVIDER_MODES",
    "RECEIVED_STATUSES",
    "SETTLED_STATUSES",
    "DayClose",
    "DayCloseStatus",
    "Payment",
    "PaymentMode",
    "PaymentProvider",
    "PaymentStatus",
    "WebhookEvent",
    "WebhookStatus",
]
