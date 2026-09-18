"""Invoice and POS request / response models (ST-001)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from farmerapp.payments.models import PaymentMode
from farmerapp.payments.schemas import PHONE_PATTERN, PaymentCreated

GSTIN_PATTERN = r"^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$"


class InvoiceLineOut(BaseModel):
    sl: int
    sku_id: uuid.UUID
    description: str
    hsn: str
    qty: Decimal
    unit: str
    unit_price_paise: int
    taxable_paise: int
    gst_rate_bp: int
    cgst_rate_bp: int
    cgst_paise: int
    sgst_rate_bp: int
    sgst_paise: int
    igst_rate_bp: int
    igst_paise: int
    total_paise: int


class InvoiceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    order_id: uuid.UUID
    store_id: uuid.UUID
    farmer_id: uuid.UUID | None
    invoice_no: str
    financial_year: str
    issued_at: datetime
    seller_name: str
    seller_gstin: str
    seller_address: str
    seller_state: str
    seller_state_code: str
    buyer_name: str
    buyer_gstin: str | None
    buyer_state: str
    place_of_supply: str
    supply_type: Literal["intra", "inter"]
    taxable_paise: int
    cgst_paise: int
    sgst_paise: int
    igst_paise: int
    round_off_paise: int
    total_paise: int
    amount_in_words: str
    lines: list[InvoiceLineOut]
    has_pdf: bool

    @classmethod
    def from_row(cls, row: Any) -> InvoiceOut:
        data = {k: getattr(row, k) for k in cls.model_fields if k != "has_pdf"}
        return cls.model_validate({**data, "has_pdf": row.pdf_uri is not None})


class SignedUrlOut(BaseModel):
    url: str
    expires_at: datetime


class InvoiceShareIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    channel: Literal["whatsapp", "sms"]
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)


class InvoiceShareOut(BaseModel):
    channel: Literal["whatsapp", "sms"]
    to: str = Field(description="Masked recipient phone.")
    url_expires_at: datetime


# --------------------------------------------------------------------------- POS
class PosLineIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sku_id: uuid.UUID
    qty: Decimal = Field(gt=0, max_digits=12, decimal_places=3)


class PosPaymentIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: PaymentMode
    receipt_uri: str | None = Field(default=None, max_length=512)
    reference_note: str | None = Field(default=None, min_length=1, max_length=200)
    channel: Literal["sms", "whatsapp"] = "sms"
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)


class PosSaleIn(BaseModel):
    """A counter sale. Prices, GST and totals are computed server-side (SEC-023)."""

    model_config = ConfigDict(extra="forbid")

    farmer_id: uuid.UUID | None = None
    farmer_phone: str | None = Field(
        default=None, pattern=PHONE_PATTERN, description="Farmer lookup by phone."
    )
    buyer_name: str | None = Field(default=None, min_length=1, max_length=200)
    buyer_state: str | None = Field(
        default=None, min_length=2, max_length=80, description="Defaults to the farmer's state."
    )
    buyer_gstin: str | None = Field(default=None, pattern=GSTIN_PATTERN)
    lines: list[PosLineIn] = Field(min_length=1, max_length=100)
    payment: PosPaymentIn

    @model_validator(mode="after")
    def _one_farmer_key(self) -> Self:
        if self.farmer_id is not None and self.farmer_phone is not None:
            raise ValueError("give farmer_id or farmer_phone, not both")
        return self


class PosSaleOut(BaseModel):
    order_id: uuid.UUID
    invoice: InvoiceOut
    payment: PaymentCreated


__all__ = [
    "GSTIN_PATTERN",
    "InvoiceLineOut",
    "InvoiceOut",
    "InvoiceShareIn",
    "InvoiceShareOut",
    "PosLineIn",
    "PosPaymentIn",
    "PosSaleIn",
    "PosSaleOut",
    "SignedUrlOut",
]
