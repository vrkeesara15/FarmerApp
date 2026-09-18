"""Read models for stock (ST-003, ST-004)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.stock.models import StockBatch


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
    days_to_expiry: int | None
    cost_paise: int
    received_at: datetime
    created_at: datetime
    updated_at: datetime
    version: int

    @classmethod
    def from_row(cls, batch: StockBatch, *, on_hand: Decimal, today: date) -> StockBatchOut:
        return cls(
            id=batch.id,
            tenant_id=batch.tenant_id,
            store_id=batch.store_id,
            sku_id=batch.sku_id,
            batch_no=batch.batch_no,
            expiry=batch.expiry,
            qty=batch.qty,
            on_hand=on_hand,
            days_to_expiry=(batch.expiry - today).days if batch.expiry is not None else None,
            cost_paise=batch.cost_paise,
            received_at=batch.received_at,
            created_at=batch.created_at,
            updated_at=batch.updated_at,
            version=batch.version,
        )


class StockPage(PageOut[StockBatchOut]):
    pass


__all__ = ["StockBatchOut", "StockPage"]
