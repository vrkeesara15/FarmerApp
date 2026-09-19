"""FA-023 payloads: daily travel allowance, claims, monthly statement."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field

from farmerapp.travel.models import TravelClaim


class TravelDayOut(BaseModel):
    date: date
    sessions: int = Field(description="Ended duty sessions that started that IST day.")
    km: Decimal = Field(description="Processed duty km of the day (VV-006), before the cap.")
    km_capped: Decimal = Field(description="min(km, tenant `ta_daily_km_cap`).")
    cap_km: int
    rate_per_km_paise: int
    ta_paise: int = Field(description="Travel allowance: km_capped x rate, rounded to a paisa.")
    open_session: bool = Field(description="A session of that day is still open (km pending).")


class TravelClaimIn(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (offline create).")
    claim_date: date
    type: Literal["fuel", "bus", "other"]
    amount_paise: int = Field(gt=0, le=10_000_000, description="Integer paise (<= Rs 1 lakh).")
    receipt_uri: str = Field(
        min_length=1, max_length=512, description="The receipt photo (completed /v1/uploads)."
    )
    note: str | None = Field(default=None, max_length=1000)


class ClaimDecisionIn(BaseModel):
    note: str | None = Field(default=None, max_length=1000)


class TravelClaimOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    claim_date: date
    type: str
    amount_paise: int
    receipt_uri: str
    note: str | None
    km_computed: Decimal | None
    status: str
    decided_by: uuid.UUID | None
    decided_at: datetime | None
    decision_note: str | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: TravelClaim) -> TravelClaimOut:
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            officer_id=row.officer_id,
            claim_date=row.claim_date,
            type=row.type,
            amount_paise=row.amount_paise,
            receipt_uri=row.receipt_uri,
            note=row.note,
            km_computed=row.km_computed,
            status=row.status,
            decided_by=row.decided_by,
            decided_at=row.decided_at,
            decision_note=row.decision_note,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class TravelClaimPage(BaseModel):
    items: list[TravelClaimOut]
    next_cursor: str | None = None


class TravelStatementOut(BaseModel):
    officer_id: uuid.UUID
    month: str = Field(description="YYYY-MM (IST).")
    rate_per_km_paise: int
    cap_km: int
    days: list[TravelDayOut]
    km_total: Decimal
    km_capped_total: Decimal
    ta_total_paise: int
    claims: list[TravelClaimOut]
    claims_submitted_paise: int
    claims_approved_paise: int
    claims_rejected_paise: int
    payable_paise: int = Field(description="Travel allowance + approved claims.")


__all__ = [
    "ClaimDecisionIn",
    "TravelClaimIn",
    "TravelClaimOut",
    "TravelClaimPage",
    "TravelDayOut",
    "TravelStatementOut",
]
