"""Read and write models for stock (ST-003, ST-004, FA-020 availability)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.stock.models import StockBatch, WriteOffReason


class StockBatchOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    store_id: uuid.UUID
    sku_id: uuid.UUID
    batch_no: str
    expiry: date | None
    qty: Decimal = Field(description="Cached quantity, maintained with every movement.")
    on_hand: Decimal = Field(description="Sum of the movement ledger for this batch (ST-003).")
    reserved: Decimal = Field(
        default=Decimal(0), description="Held by active order reservations (FA-020)."
    )
    available: Decimal = Field(default=Decimal(0), description="``on_hand - reserved``.")
    days_to_expiry: int | None
    cost_paise: int
    received_at: datetime
    created_at: datetime
    updated_at: datetime
    version: int

    @classmethod
    def from_row(
        cls,
        batch: StockBatch,
        *,
        on_hand: Decimal,
        today: date,
        reserved: Decimal | None = None,
    ) -> StockBatchOut:
        held = reserved if reserved is not None else on_hand * 0
        return cls(
            id=batch.id,
            tenant_id=batch.tenant_id,
            store_id=batch.store_id,
            sku_id=batch.sku_id,
            batch_no=batch.batch_no,
            expiry=batch.expiry,
            qty=batch.qty,
            on_hand=on_hand,
            reserved=held,
            available=on_hand - held,
            days_to_expiry=(batch.expiry - today).days if batch.expiry is not None else None,
            cost_paise=batch.cost_paise,
            received_at=batch.received_at,
            created_at=batch.created_at,
            updated_at=batch.updated_at,
            version=batch.version,
        )


class StockPage(PageOut[StockBatchOut]):
    pass


# --------------------------------------------------------------------------- writes (ST-003)
Qty = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=3)]


class ReceiptLineIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sku_id: uuid.UUID
    batch_no: str = Field(min_length=1, max_length=64)
    expiry: date | None = None
    qty: Qty
    cost_paise: int = Field(ge=0, description="Unit cost in paise.")


class ReceiptIn(BaseModel):
    """Goods receipt: batches arriving from a supplier (a new batch or more of one)."""

    model_config = ConfigDict(extra="forbid")

    reference: str | None = Field(default=None, max_length=120, description="GRN / invoice no.")
    lines: list[ReceiptLineIn] = Field(min_length=1, max_length=100)


class BatchQtyIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    batch_id: uuid.UUID
    qty: Qty


class TransferIn(BaseModel):
    """Move batches between two stores of the tenant: ``transfer_out`` at the source and
    ``transfer_in`` at the destination in one transaction (batch number, expiry and cost
    travel with the stock). No in-transit state in the pilot."""

    model_config = ConfigDict(extra="forbid")

    from_store_id: uuid.UUID
    to_store_id: uuid.UUID
    note: str | None = Field(default=None, max_length=500)
    lines: list[BatchQtyIn] = Field(min_length=1, max_length=100)


class WriteOffLineIn(BatchQtyIn):
    reason: WriteOffReason = WriteOffReason.DAMAGE


class WriteOffIn(BaseModel):
    """Damage / expiry write-off (``damage`` movements) with an optional photo."""

    model_config = ConfigDict(extra="forbid")

    note: str | None = Field(default=None, max_length=500)
    photo_blob_uri: str | None = Field(default=None, min_length=1, max_length=512)
    lines: list[WriteOffLineIn] = Field(min_length=1, max_length=100)


class AdjustmentLineIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    batch_id: uuid.UUID
    counted_qty: Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=3)]


class AdjustmentIn(BaseModel):
    """Stock count correction: the counted quantity per batch; the difference to the ledger
    is written as an ``adjust`` movement (audited, reason required)."""

    model_config = ConfigDict(extra="forbid")

    reason: str = Field(min_length=3, max_length=500)
    lines: list[AdjustmentLineIn] = Field(min_length=1, max_length=100)


class StockMovementOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    store_id: uuid.UUID
    sku_id: uuid.UUID
    batch_id: uuid.UUID | None
    kind: str
    qty: Decimal
    ref_type: str | None
    ref_id: uuid.UUID | None
    note: str | None
    reason: str | None
    photo_uri: str | None
    created_by: uuid.UUID | None
    created_at: datetime


class BatchStateOut(BaseModel):
    """A batch after the write: the cached qty equals the ledger sum."""

    id: uuid.UUID
    store_id: uuid.UUID
    sku_id: uuid.UUID
    batch_no: str
    expiry: date | None
    qty: Decimal
    reserved: Decimal
    available: Decimal


class StockWriteOut(BaseModel):
    ref_type: str = Field(
        description="``receipt`` / ``transfer`` / ``write_off`` / ``adjustment``."
    )
    ref_id: uuid.UUID = Field(description="Id shared by every movement of this write.")
    movements: list[StockMovementOut]
    batches: list[BatchStateOut]


__all__ = [
    "AdjustmentIn",
    "AdjustmentLineIn",
    "BatchQtyIn",
    "BatchStateOut",
    "ReceiptIn",
    "ReceiptLineIn",
    "StockBatchOut",
    "StockMovementOut",
    "StockPage",
    "StockWriteOut",
    "TransferIn",
    "WriteOffIn",
    "WriteOffLineIn",
]
