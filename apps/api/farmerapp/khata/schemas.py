"""Read models for the khata (FA-022, FM-010)."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.khata.models import KhataEntry


class KhataEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    farmer_id: uuid.UUID
    store_id: uuid.UUID
    type: str
    amount_paise: int
    signed_paise: int = Field(description="+amount for a debit, -amount for a credit.")
    due_date: date | None
    ref_type: str
    ref_id: uuid.UUID | None
    note: str | None
    harvest_month: date | None
    created_by: uuid.UUID | None
    created_at: datetime

    @classmethod
    def from_row(cls, entry: KhataEntry) -> KhataEntryOut:
        return cls.model_validate(entry)


class StoreBalanceOut(BaseModel):
    store_id: uuid.UUID
    balance_paise: int


class CreditLimitOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    farmer_id: uuid.UUID
    store_id: uuid.UUID
    limit_paise: int
    set_by: uuid.UUID
    approved_by: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    version: int


class KhataOut(BaseModel):
    farmer_id: uuid.UUID
    store_id: uuid.UUID | None = Field(
        description="The store the view is filtered to; null = across the tenant's stores."
    )
    balance_paise: int = Field(description="Sum of the ledger: debits minus credits (FA-022).")
    overdue_paise: int = Field(description="Debits past due minus credits, floored at zero.")
    next_due_date: date | None = Field(description="Earliest unpaid due date still ahead.")
    balances: list[StoreBalanceOut] = Field(description="Balance per store.")
    credit_limits: list[CreditLimitOut]
    entries: list[KhataEntryOut] = Field(description="Newest first.")
    next_cursor: str | None = None


__all__ = ["CreditLimitOut", "KhataEntryOut", "KhataOut", "StoreBalanceOut"]
