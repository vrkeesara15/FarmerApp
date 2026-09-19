"""Read and write models for orders (FA-020, ST-005, FM-010)."""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.orders.models import Fulfilment, OrderStatus
from farmerapp.payments.models import PaymentMode
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
    invoice_id: uuid.UUID | None = Field(
        default=None,
        description="The GST invoice (``GET /v1/invoices/{id}``, ``/pdf``, ``/share``): issued "
        "by the POS sale, or when the order reached ``handed_over`` / ``delivered``.",
    )
    client_order_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    version: int


class OrderStatusEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    order_id: uuid.UUID
    from_status: str | None
    to_status: str
    note: str | None
    actor_id: uuid.UUID | None
    created_at: datetime


class OrderReservationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    order_line_id: uuid.UUID
    sku_id: uuid.UUID
    batch_id: uuid.UUID
    qty: Decimal
    status: str


class OrderDetailOut(OrderOut):
    lines: list[OrderLineOut]
    payments: list[PaymentOut]
    events: list[OrderStatusEventOut] = Field(
        default_factory=list, description="Status history, oldest first (ST-005)."
    )
    reservations: list[OrderReservationOut] = Field(
        default_factory=list, description="Stock held per batch (FEFO), FA-020."
    )


class OrderPage(PageOut[OrderOut]):
    pass


class OrderQueueItemOut(OrderOut):
    lines: list[OrderLineOut]


class OrderQueuePage(PageOut[OrderQueueItemOut]):
    pass


# --------------------------------------------------------------------------- writes
Qty = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=3)]


class OrderLineIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sku_id: uuid.UUID
    qty: Qty
    unit_price_paise: int | None = Field(
        default=None,
        ge=0,
        strict=True,
        description="The price the device showed; rejected (409) when it differs from the "
        "server's price list (SEC-023: amounts are recomputed server-side).",
    )
    label_claim_id: uuid.UUID | None = Field(
        default=None, description="Why the SKU was recommended (DX-007; approved claim)."
    )


class OrderCreate(BaseModel):
    """FA-020 order capture. Prices, tax and totals are computed by the server."""

    model_config = ConfigDict(extra="forbid")

    id: uuid.UUID | None = Field(
        default=None, description="Client-generated id (offline capture); the order's id."
    )
    farmer_id: uuid.UUID | None = Field(
        default=None, description="Required except for a farmer ordering for themselves."
    )
    store_id: uuid.UUID | None = Field(
        default=None, description="Defaults to the farmer's nearest store (village store)."
    )
    fulfilment: Fulfilment = Fulfilment.PICKUP
    payment_mode: PaymentMode | None = Field(
        default=None,
        description="``credit`` puts the order on the khata (ST-007 limit check at placing).",
    )
    credit_approval_request_id: uuid.UUID | None = Field(
        default=None,
        description="ST-007 retry key: the id of a credit approval request"
        " (``approval_request_id`` of an "
        "earlier 402 ``credit_limit_exceeded``). When a cluster head approved it for this farmer "
        "and store and its amount covers this sale, the sale goes through once and the request "
        "becomes ``consumed``; otherwise the normal limit check applies.",
    )
    notes: str | None = Field(default=None, max_length=1000)
    lines: list[OrderLineIn] = Field(min_length=1, max_length=50)
    expected_total_paise: int | None = Field(
        default=None,
        ge=0,
        strict=True,
        description="The total the device showed; a different server total is a 409.",
    )


class OrderStatusIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: OrderStatus
    note: str | None = Field(default=None, max_length=500)


# --------------------------------------------------------------------------- nearest store
class StoreBriefOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name: str
    district: str
    cluster_id: uuid.UUID | None


class SkuAvailabilityOut(BaseModel):
    sku_id: uuid.UUID
    on_hand: Decimal
    reserved: Decimal
    available: Decimal


class NearestStoreOut(BaseModel):
    farmer_id: uuid.UUID
    store: StoreBriefOut
    distance_m: float | None = Field(description="Village centre to store, metres.")
    source: str = Field(description="``village`` (the village's store) or ``nearest``.")
    stock: list[SkuAvailabilityOut] = Field(
        default_factory=list, description="Availability of the requested SKUs at the store."
    )


__all__ = [
    "NearestStoreOut",
    "OrderCreate",
    "OrderDetailOut",
    "OrderLineIn",
    "OrderLineOut",
    "OrderOut",
    "OrderPage",
    "OrderQueueItemOut",
    "OrderQueuePage",
    "OrderReservationOut",
    "OrderStatusEventOut",
    "OrderStatusIn",
    "SkuAvailabilityOut",
    "StoreBriefOut",
]
