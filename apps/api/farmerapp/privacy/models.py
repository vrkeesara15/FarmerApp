"""``data_request`` — data-principal requests (FM-015, NF-013 groundwork; Alembic 0027).

One table for the DPDP rights the apps and console expose: ``deletion`` (FM-015 "delete my
account and data"), ``access`` and ``correction`` (NF-013). A request is a ticket: it is
``received`` with a ``due_by`` (30 days, the policy timeline), handled by a tenant admin or
owner (``in_progress`` -> ``completed`` / ``rejected`` with ``handled_by`` / ``handled_at``
and a note). The erasure itself is a human-reviewed operation (retention of financial
records, SPEC NF-012, overrides deletion) — this table is the auditable queue, not the
deleter.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns

#: FM-015 policy timeline: a request is handled within 30 days.
DUE_DAYS = 30


class DataRequestType(StrEnum):
    DELETION = "deletion"
    ACCESS = "access"
    CORRECTION = "correction"


class DataRequestStatus(StrEnum):
    RECEIVED = "received"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    REJECTED = "rejected"


OPEN_STATUSES = frozenset({DataRequestStatus.RECEIVED, DataRequestStatus.IN_PROGRESS})

DATA_REQUEST_TRANSITIONS: dict[DataRequestStatus, frozenset[DataRequestStatus]] = {
    DataRequestStatus.RECEIVED: frozenset(
        {DataRequestStatus.IN_PROGRESS, DataRequestStatus.COMPLETED, DataRequestStatus.REJECTED}
    ),
    DataRequestStatus.IN_PROGRESS: frozenset(
        {DataRequestStatus.COMPLETED, DataRequestStatus.REJECTED}
    ),
    DataRequestStatus.COMPLETED: frozenset(),
    DataRequestStatus.REJECTED: frozenset(),
}


class DataRequest(Base, BaseColumns):
    __tablename__ = "data_request"
    __table_args__ = (
        CheckConstraint(f"type IN ({sql_in(DataRequestType)})", name="type"),
        CheckConstraint(f"status IN ({sql_in(DataRequestStatus)})", name="status"),
        CheckConstraint(
            "(status IN ('completed', 'rejected')) = (handled_at IS NOT NULL)", name="handled_at"
        ),
        Index("ix_data_request_user_created", "tenant_id", "user_id", "created_at"),
        Index("ix_data_request_status_due", "tenant_id", "status", "due_by"),
    )

    type: Mapped[str] = mapped_column(String(16), nullable=False)
    #: the account that asked (the data principal, or who asked on their behalf)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    #: the farmer record the request is about, when the principal is a farmer
    farmer_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("farmer.id", ondelete="SET NULL"), nullable=True
    )
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'received'"), default="received"
    )
    due_by: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    handled_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    handled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolution_note: Mapped[str | None] = mapped_column(Text, nullable=True)


__all__ = [
    "DATA_REQUEST_TRANSITIONS",
    "DUE_DAYS",
    "OPEN_STATUSES",
    "DataRequest",
    "DataRequestStatus",
    "DataRequestType",
]
