"""``travel_claim`` — FA-023 expense claims (fuel / bus / other) with a receipt photo.

The travel allowance itself is not stored: it is computed from the processed duty km
(``farmerapp.travel.service``). A claim carries the km the track processing had computed
for its day at submission (``km_computed``) so the VA-E07 rule (claims vs computed km) and
the approver see the same figure. Money is integer paise. Approved or rejected by the cluster
head of the officer's cluster (owner / director / tenant admin too). A sync entity (created
offline with the receipt uploaded first).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class ClaimType(StrEnum):
    FUEL = "fuel"
    BUS = "bus"
    OTHER = "other"


class ClaimStatus(StrEnum):
    SUBMITTED = "submitted"
    APPROVED = "approved"
    REJECTED = "rejected"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class TravelClaim(Base, BaseColumns):
    __tablename__ = "travel_claim"
    __table_args__ = (
        CheckConstraint(f"type IN ({_in(ClaimType)})", name="type"),
        CheckConstraint(f"status IN ({_in(ClaimStatus)})", name="status"),
        CheckConstraint("amount_paise > 0", name="amount"),
        CheckConstraint(
            "(status = 'submitted') = (decided_by IS NULL AND decided_at IS NULL)",
            name="decision",
        ),
        Index("ix_travel_claim_officer_date", "tenant_id", "officer_id", "claim_date"),
        Index("ix_travel_claim_status", "tenant_id", "status", "created_at"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    claim_date: Mapped[date] = mapped_column(Date, nullable=False)
    type: Mapped[str] = mapped_column(String(8), nullable=False)
    amount_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    receipt_uri: Mapped[str] = mapped_column(String(512), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    km_computed: Mapped[Decimal | None] = mapped_column(Numeric(8, 2), nullable=True)
    status: Mapped[str] = mapped_column(
        String(12),
        nullable=False,
        default=ClaimStatus.SUBMITTED.value,
        server_default=text("'submitted'"),
    )
    decided_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    decision_note: Mapped[str | None] = mapped_column(Text, nullable=True)


__all__ = ["ClaimStatus", "ClaimType", "TravelClaim"]
