"""Sync bookkeeping (FA-025, NF-003).

* ``sync_op`` — one row per applied outbox operation, unique on ``(tenant_id, op_id)``:
  the stored ``result`` is what a replayed ``op_id`` gets back (``duplicate``).
* ``sync_change`` — the append-only change log the changes feed reads: ``seq`` (identity)
  is the cursor, ``entity`` / ``entity_id`` / ``action`` / ``version`` say what changed.
  Rows are written by the flush hook in ``farmerapp.sync.changes`` for every synced entity,
  whichever path mutated it (REST, sync, jobs). The app role may only INSERT.

Neither table audits itself (``__audit__ = False``): the audited event is the entity change.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    DateTime,
    Identity,
    Index,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, TenantRow

#: Entities the mobile outbox may write and the changes feed reports (SPEC 8.3). M2 adds
#: visits, their photos and confirmations (FA-014 .. FA-017, ``farmerapp.visits.sync_ops``),
#: duty sessions and policy acceptances (writes land with FA-010 / FA-011). M3 adds the
#: money-bearing entities (orders, lines, payments, khata entries): in the feed now, server
#: wins on conflict, device writes land with FA-020 / FA-021 / FA-022. Credit approval
#: requests (ST-007) reach the officer who asked and the store's staff so A56 learns about the
#: decision without polling; devices never write them (``unsupported_action``).
SYNC_ENTITIES: tuple[str, ...] = (
    "farmer",
    "farm",
    "crop_plot",
    "consent_record",
    "visit",
    "visit_photo",
    "visit_confirmation",
    "duty_session",
    "policy_acceptance",
    "location_batch",  # write-only: points land in location_point, which is never in the feed
    "order",
    "order_line",
    "payment",
    "khata_entry",
    "credit_approval_request",  # ST-007 / FA-020 A56: read-only on devices, never written
    "diagnosis",  # M6: offline capture (create) + results in the feed; never updated by devices
    "crop_plot_task",  # M7 FM-007: calendar offline; devices update status / reminder only
)
#: Never in the change feed, whatever hook sees them: raw location points are high-volume
#: telemetry the device already has (VV-001) and other officers must never receive (SPEC 2.6).
SYNC_EXCLUDED_ENTITIES: frozenset[str] = frozenset({"location_point"})


class SyncOp(Base, TenantRow):
    __tablename__ = "sync_op"
    __table_args__ = (
        UniqueConstraint("tenant_id", "op_id"),
        Index("ix_sync_op_created_at", "created_at"),
    )
    __audit__ = False

    op_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    entity: Mapped[str] = mapped_column(String(32), nullable=False)
    action: Mapped[str] = mapped_column(String(16), nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    result: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)


class SyncChange(Base):
    __tablename__ = "sync_change"
    __table_args__ = (Index("ix_sync_change_tenant_seq", "tenant_id", "seq"),)
    __audit__ = False

    seq: Mapped[int] = mapped_column(BigInteger, Identity(always=True), primary_key=True)
    tenant_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    entity: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    action: Mapped[str] = mapped_column(String(16), nullable=False)  # create | update | delete
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    changed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)


__all__ = ["SYNC_ENTITIES", "SYNC_EXCLUDED_ENTITIES", "SyncChange", "SyncOp"]
