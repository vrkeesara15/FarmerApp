"""Validation flags (SPEC 8.2 ``flag``; VA-002, VA-003, WC-010, OPS-010; migration 0018).

* ``flag`` — one question a validation rule raised about a subject (a farmer, an employee, a
  visit or a store): the rule id **and version**, severity, title, the evidence bundle
  (``{records: [{type, id}], map: {points, polygons}, photos: [blob_uri], metrics}``), the
  owner (``owner_id`` / ``owner_role``) plus ``watchers`` (auditors on high severity, VA-003),
  the SLA deadline from the rule's ``sla_hours`` and the review state. ``scope_cluster_id`` /
  ``scope_store_id`` are resolved once at raise time (the subject's cluster / store) so the
  inbox scope of cluster heads and store managers is a plain column filter.
  ``dedupe_key`` (``<rule>:<subject>:<finding key>``) is unique per tenant among *unresolved*
  flags (partial unique index), so re-running a batch never duplicates an open flag.
* ``flag_event`` — append-only history of every state change, assignment and SLA
  escalation (who, from, to, note). Resolutions carry ``label`` (``true_positive`` /
  ``false_positive``): the VA-006 precision tracker reads labels, not free text.
* ``flag_comment`` — the discussion thread; ``is_subject_explanation`` marks the subject's
  own explanation (VA-005: an officer explains a flag about themselves while it is open).

State machine (SPEC 6.1): ``open -> in_review -> resolved_valid | resolved_fixed |
escalated``; ``escalated -> resolved_fixed | resolved_action``.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    Uuid,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns, TenantRow
from farmerapp.rules.schema import Mode, Severity, Subject


class FlagStatus(StrEnum):
    OPEN = "open"
    IN_REVIEW = "in_review"
    RESOLVED_VALID = "resolved_valid"  # data confirmed OK -> the rule was wrong
    RESOLVED_FIXED = "resolved_fixed"  # data corrected
    ESCALATED = "escalated"  # needs an auditor or HR
    RESOLVED_ACTION = "resolved_action"  # action taken


class FlagEventKind(StrEnum):
    CREATED = "created"
    TRANSITION = "transition"
    ASSIGNED = "assigned"
    SLA_ESCALATED = "sla_escalated"  # OPS-010


class FlagLabel(StrEnum):
    """VA-006: how a resolution counts for the rule's precision."""

    TRUE_POSITIVE = "true_positive"
    FALSE_POSITIVE = "false_positive"


UNRESOLVED = (FlagStatus.OPEN, FlagStatus.IN_REVIEW, FlagStatus.ESCALATED)
RESOLVED = (FlagStatus.RESOLVED_VALID, FlagStatus.RESOLVED_FIXED, FlagStatus.RESOLVED_ACTION)

#: SPEC 6.1 state diagram (the SLA job reassigns owners; it never changes the status).
TRANSITIONS: dict[FlagStatus, frozenset[FlagStatus]] = {
    FlagStatus.OPEN: frozenset({FlagStatus.IN_REVIEW}),
    FlagStatus.IN_REVIEW: frozenset(
        {FlagStatus.RESOLVED_VALID, FlagStatus.RESOLVED_FIXED, FlagStatus.ESCALATED}
    ),
    FlagStatus.ESCALATED: frozenset({FlagStatus.RESOLVED_FIXED, FlagStatus.RESOLVED_ACTION}),
    FlagStatus.RESOLVED_VALID: frozenset(),
    FlagStatus.RESOLVED_FIXED: frozenset(),
    FlagStatus.RESOLVED_ACTION: frozenset(),
}

LABELS: dict[FlagStatus, FlagLabel] = {
    FlagStatus.RESOLVED_VALID: FlagLabel.FALSE_POSITIVE,
    FlagStatus.RESOLVED_FIXED: FlagLabel.TRUE_POSITIVE,
    FlagStatus.RESOLVED_ACTION: FlagLabel.TRUE_POSITIVE,
}

_UNRESOLVED_SQL = f"status IN ({', '.join(repr(s.value) for s in UNRESOLVED)})"


class Flag(Base, BaseColumns):
    __tablename__ = "flag"
    __table_args__ = (
        CheckConstraint(f"status IN ({sql_in(FlagStatus)})", name="status"),
        CheckConstraint(f"severity IN ({sql_in(Severity)})", name="severity"),
        CheckConstraint(f"subject_type IN ({sql_in(Subject)})", name="subject_type"),
        CheckConstraint(f"raised_by_mode IN ({sql_in(Mode)})", name="raised_by_mode"),
        CheckConstraint("rule_version >= 1", name="rule_version"),
        CheckConstraint("escalation_level >= 0", name="escalation_level"),
        CheckConstraint(
            "(status IN ('resolved_valid', 'resolved_fixed', 'resolved_action')) "
            "= (resolved_at IS NOT NULL)",
            name="resolved_at",
        ),
        Index(
            "uq_flag_open_dedupe_key",
            "tenant_id",
            "dedupe_key",
            unique=True,
            postgresql_where=text(f"{_UNRESOLVED_SQL} AND deleted_at IS NULL"),
        ),
        Index("ix_flag_tenant_status_created", "tenant_id", "status", "created_at"),
        Index("ix_flag_tenant_rule", "tenant_id", "rule_id"),
        Index("ix_flag_subject", "tenant_id", "subject_type", "subject_id"),
        Index("ix_flag_owner_id", "owner_id"),
        Index("ix_flag_dedupe_key", "tenant_id", "dedupe_key"),
        Index("ix_flag_sla_due_at", "tenant_id", "sla_due_at"),
    )

    rule_id: Mapped[str] = mapped_column(String(16), nullable=False)
    rule_version: Mapped[int] = mapped_column(Integer, nullable=False)
    subject_type: Mapped[str] = mapped_column(String(16), nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    severity: Mapped[str] = mapped_column(String(8), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    evidence: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    raised_by_mode: Mapped[str] = mapped_column(String(8), nullable=False)
    owner_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    owner_role: Mapped[str | None] = mapped_column(String(32), nullable=True)
    watchers: Mapped[list[uuid.UUID]] = mapped_column(
        ARRAY(Uuid), nullable=False, default=list, server_default=text("'{}'::uuid[]")
    )
    scope_cluster_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    scope_store_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default=FlagStatus.OPEN)
    resolution_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    sla_due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    escalation_level: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    dedupe_key: Mapped[str] = mapped_column(String(255), nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)


class FlagEvent(Base, TenantRow):
    """Append-only (``APPEND_ONLY_TABLES``): the app role can only SELECT and INSERT."""

    __tablename__ = "flag_event"
    __table_args__ = (
        CheckConstraint(f"kind IN ({sql_in(FlagEventKind)})", name="kind"),
        CheckConstraint(f"label IS NULL OR label IN ({sql_in(FlagLabel)})", name="label"),
        Index("ix_flag_event_flag_created", "flag_id", "created_at"),
        Index("ix_flag_event_tenant_label", "tenant_id", "label"),
    )

    flag_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("flag.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)  # NULL = system
    from_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    to_status: Mapped[str] = mapped_column(String(16), nullable=False)
    from_owner_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    to_owner_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    label: Mapped[str | None] = mapped_column(String(16), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


class FlagComment(Base, BaseColumns):
    __tablename__ = "flag_comment"
    __table_args__ = (
        CheckConstraint("char_length(body) > 0", name="body"),
        Index("ix_flag_comment_flag_created", "flag_id", "created_at"),
    )

    flag_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("flag.id", ondelete="CASCADE"), nullable=False
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_subject_explanation: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )


__all__ = [
    "LABELS",
    "RESOLVED",
    "TRANSITIONS",
    "UNRESOLVED",
    "Flag",
    "FlagComment",
    "FlagEvent",
    "FlagEventKind",
    "FlagLabel",
    "FlagStatus",
]
