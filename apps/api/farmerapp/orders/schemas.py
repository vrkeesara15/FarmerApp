"""Read models for orders (FA-020, ST-005, FM-010)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict

from farmerapp.api.pagination import PageOut
from farmerapp.payments.schemas import PaymentOut


class OrderLineOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    order_id: uuid.UUID
    sku_id: uuid.UUID
    batch_id: uuid.UUID | None
    qty: Decimal
    unit_price_paise: int
    gst_rate_bp: int
    line_total_paise: int
    label_claim_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    version: int


class OrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    farmer_id: uuid.UUID | None
    store_id: uuid.UUID
    channel: str
    status: str
    fulfilment: str
    subtotal_paise: int
    discount_paise: int
    tax_paise: int
    total_paise: int
    placed_by: uuid.UUID | None
    placed_at: datetime | None
    notes: str | None
    invoice_no: str | None
    client_order_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    version: int


class OrderDetailOut(OrderOut):
    lines: list[OrderLineOut]
    payments: list[PaymentOut]


class OrderPage(PageOut[OrderOut]):
    pass


__all__ = ["OrderDetailOut", "OrderLineOut", "OrderOut", "OrderPage"]
