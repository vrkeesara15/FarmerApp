"""Read models for payments (FA-021, ST-002, FM-010)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict

from farmerapp.api.pagination import PageOut


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
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    version: int


class PaymentPage(PageOut[PaymentOut]):
    pass


__all__ = ["PaymentOut", "PaymentPage"]
