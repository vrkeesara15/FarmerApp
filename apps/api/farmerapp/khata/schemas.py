"""Read and write models for the khata and credit (FA-022, ST-007, FM-010)."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.khata.aging import OpenDebit
from farmerapp.khata.models import EntryType, KhataEntry
from farmerapp.payments.schemas import PaymentOut


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


class OpenDebitOut(BaseModel):
    """A debit not yet covered by credits (FIFO by due date) and how late it is."""

    entry_id: uuid.UUID
    store_id: uuid.UUID
    amount_paise: int
    open_paise: int
    due_date: date = Field(description="Harvest-linked due date (or tenant default days).")
    days_overdue: int
    bucket: str | None = Field(description="``0_30`` / ``31_60`` / ``61_90`` / ``90_plus``.")

    @classmethod
    def from_debit(cls, debit: OpenDebit) -> OpenDebitOut:
        return cls(
            entry_id=debit.entry_id,
            store_id=debit.store_id,
            amount_paise=debit.amount_paise,
            open_paise=debit.open_paise,
            due_date=debit.due_date,
            days_overdue=debit.days_overdue,
            bucket=debit.bucket,
        )


class OverdueBucketsOut(BaseModel):
    """SPEC 5.2 "Credit overdue": open debit amounts by days past due."""

    days_0_30: int = Field(alias="0_30")
    days_31_60: int = Field(alias="31_60")
    days_61_90: int = Field(alias="61_90")
    days_90_plus: int = Field(alias="90_plus")

    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)


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
    open_debits: list[OpenDebitOut] = Field(
        default_factory=list, description="Uncovered debits with due date and ageing."
    )
    overdue_buckets: OverdueBucketsOut
    payment_history: list[PaymentOut] = Field(
        default_factory=list, description="The farmer's payments (not credit sales), newest first."
    )
    entries: list[KhataEntryOut] = Field(description="Newest first.")
    next_cursor: str | None = None


class KhataEntryIn(BaseModel):
    """Manual adjustment (store manager): a new row, never an edit (the ledger is
    append-only); a correction of a wrong entry is the opposite entry with a reason."""

    model_config = ConfigDict(extra="forbid")

    type: EntryType
    amount_paise: int = Field(gt=0, strict=True)
    reason: str = Field(min_length=3, max_length=500)
    store_id: uuid.UUID | None = Field(default=None, description="Defaults to the caller's store.")
    due_date: date | None = Field(default=None, description="Debits: defaults to harvest-linked.")


class CreditLimitIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    store_id: uuid.UUID
    limit_paise: int = Field(ge=0, strict=True)


class CreditApprovalOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    farmer_id: uuid.UUID
    store_id: uuid.UUID
    order_id: uuid.UUID | None
    amount_paise: int
    balance_paise: int
    limit_paise: int
    shortfall_paise: int
    requested_by: uuid.UUID | None
    status: str
    decided_by: uuid.UUID | None
    decided_at: datetime | None
    decision_note: str | None
    used_at: datetime | None
    consumed_at: datetime | None = Field(
        default=None, description="When a sale used this approval (status ``consumed``)."
    )
    consumed_by_order_id: uuid.UUID | None = Field(
        default=None, description="The order of the sale that used this approval."
    )
    created_at: datetime
    updated_at: datetime
    version: int


class CreditApprovalPage(PageOut[CreditApprovalOut]):
    pass


class CreditDecisionIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    note: str | None = Field(default=None, max_length=500)


__all__ = [
    "CreditApprovalOut",
    "CreditApprovalPage",
    "CreditDecisionIn",
    "CreditLimitIn",
    "CreditLimitOut",
    "KhataEntryIn",
    "KhataEntryOut",
    "KhataOut",
    "OpenDebitOut",
    "OverdueBucketsOut",
    "StoreBalanceOut",
]
