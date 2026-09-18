"""Request / response models for payments, webhooks and the day close (FA-021, ST-002,
ST-006, SEC-023, FM-010)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from farmerapp.api.pagination import PageOut
from farmerapp.payments.models import PaymentMode, PaymentStatus

PHONE_PATTERN = r"^\+91[6-9]\d{9}$"


class PaymentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    order_id: uuid.UUID | None
    khata_entry_id: uuid.UUID | None
    farmer_id: uuid.UUID | None
    store_id: uuid.UUID
    mode: str
    amount_paise: int
    provider: str
    provider_ref: str | None
    provider_event_id: str | None
    status: str
    receipt_uri: str | None
    collected_by: uuid.UUID | None
    reference_note: str | None
    paid_at: datetime | None
    provider_order_id: str | None = None
    short_url: str | None = None
    expires_at: datetime | None = None
    day_close_id: uuid.UUID | None = None
    failure_reason: str | None = None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    version: int


class PaymentPage(PageOut[PaymentOut]):
    pass


# --------------------------------------------------------------------------- collect
class PaymentCreate(BaseModel):
    """``POST /v1/payments``: an order (``order_id``) or khata dues (``farmer_id`` +
    ``store_id``). ``amount_paise`` is optional and only ever *checked*: the server computes
    the amount (order total still due, or the outstanding khata balance; a partial dues
    payment up to the balance is allowed)."""

    model_config = ConfigDict(extra="forbid")

    order_id: uuid.UUID | None = None
    farmer_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None
    mode: PaymentMode
    amount_paise: int | None = Field(default=None, gt=0)
    receipt_uri: str | None = Field(
        default=None, max_length=512, description="Cash: the receipt photo (completed upload)."
    )
    reference_note: str | None = Field(
        default=None, min_length=1, max_length=200, description="Card terminal reference."
    )
    channel: Literal["sms", "whatsapp"] = Field(
        default="sms", description="Payment link delivery channel."
    )
    phone: str | None = Field(
        default=None,
        pattern=PHONE_PATTERN,
        description="Payment link recipient; defaults to the farmer's phone.",
    )
    credit_approval_request_id: uuid.UUID | None = Field(
        default=None,
        description="Mode ``credit`` only (ignored otherwise). ST-007 retry key:"
        " the id of a credit approval request (``approval_request_id`` of an "
        "earlier 402 ``credit_limit_exceeded``). When a cluster head approved it for this farmer "
        "and store and its amount covers this sale, the sale goes through once and the request "
        "becomes ``consumed``; otherwise the normal limit check applies.",
    )

    @model_validator(mode="after")
    def _one_target(self) -> Self:
        dues = self.farmer_id is not None or self.store_id is not None
        if self.order_id is not None and dues:
            raise ValueError("give either order_id or farmer_id + store_id, not both")
        if self.order_id is None and (self.farmer_id is None or self.store_id is None):
            raise ValueError("give order_id, or farmer_id + store_id for a dues payment")
        return self


class PaymentCreated(BaseModel):
    """What the collecting screen needs: the QR to show (``upi_qr``), the link that was sent
    (``payment_link``), or the final status (cash / card / credit)."""

    payment_id: uuid.UUID
    mode: PaymentMode
    status: PaymentStatus
    amount_paise: int
    order_id: uuid.UUID | None
    farmer_id: uuid.UUID | None
    store_id: uuid.UUID
    qr_payload: str | None = None
    short_url: str | None = None
    expires_at: datetime | None = None
    sent_via: Literal["sms", "whatsapp"] | None = None
    khata_entry_id: uuid.UUID | None = None


class PaymentStatusOut(BaseModel):
    """``GET /v1/payments/{id}`` — polled by the A53 "waiting for payment" screen."""

    id: uuid.UUID
    state: Literal["waiting", "paid", "failed"]
    status: PaymentStatus
    mode: PaymentMode
    amount_paise: int
    order_id: uuid.UUID | None
    farmer_id: uuid.UUID | None
    store_id: uuid.UUID
    qr_payload: str | None
    short_url: str | None
    expires_at: datetime | None
    paid_at: datetime | None
    failure_reason: str | None


# --------------------------------------------------------------------------- webhooks
class WebhookAck(BaseModel):
    status: Literal["accepted", "processed", "duplicate", "ignored"]
    event_id: str | None = None


# --------------------------------------------------------------------------- day close
class ModeTotal(BaseModel):
    mode: PaymentMode
    count: int
    amount_paise: int


class CountAmount(BaseModel):
    count: int
    amount_paise: int


class DayCloseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    store_id: uuid.UUID
    business_date: date
    status: str
    cash_expected_paise: int
    cash_counted_paise: int
    variance_paise: int
    variance_flagged: bool
    deposit_slip_uri: str | None
    notes: str | None
    closed_by: uuid.UUID
    closed_at: datetime
    reopened_by: uuid.UUID | None
    reopened_at: datetime | None
    reopen_reason: str | None
    version: int


class DaySummaryOut(BaseModel):
    """ST-002 "day-end totals by mode" for one store and business date (IST)."""

    store_id: uuid.UUID
    business_date: date
    timezone: str
    by_mode: list[ModeTotal] = Field(description="Money received (all five modes, zero-filled).")
    total_received_paise: int = Field(description="Money received (credit sales excluded).")
    waiting: CountAmount = Field(description="UPI QR / links created but not paid yet.")
    failed: CountAmount
    refunds: CountAmount
    expected_cash_paise: int = Field(description="Cash the drawer should hold (ST-006).")
    cash_pending_reconciliation_paise: int
    day_close: DayCloseOut | None


class DayCloseIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    business_date: date
    cash_counted_paise: int = Field(ge=0)
    deposit_slip_uri: str | None = Field(default=None, max_length=512)
    notes: str | None = Field(default=None, max_length=2000)


class DayCloseReopenIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str = Field(min_length=3, max_length=2000)


__all__ = [
    "PHONE_PATTERN",
    "CountAmount",
    "DayCloseIn",
    "DayCloseOut",
    "DayCloseReopenIn",
    "DaySummaryOut",
    "ModeTotal",
    "PaymentCreate",
    "PaymentCreated",
    "PaymentOut",
    "PaymentPage",
    "PaymentStatusOut",
    "WebhookAck",
]
