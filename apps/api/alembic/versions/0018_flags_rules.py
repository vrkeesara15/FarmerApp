"""M4: validation flags, their append-only history and comment thread (VA-002, VA-003)

Revision ID: 0018_flags_rules
Revises: 0017
Create Date: 2026-09-18 22:00:00 UTC

Branch ``flags`` (developed next to the M4 analytics and administration branches on 0017;
the parent merges the heads).

* ``flag`` — rule id + version, subject, severity, title, evidence jsonb, owner / owner
  role / watchers (VA-003), the subject's cluster and store (inbox scope), status (SPEC 6.1
  state machine, CHECK), resolution note, SLA deadline and escalation level (OPS-010),
  ``dedupe_key`` unique per tenant among unresolved flags (partial unique index), resolved
  at / by (CHECK: set exactly when resolved).
* ``flag_event`` — append-only (the app role may only SELECT / INSERT): created,
  transitions, assignments and SLA escalations; resolutions carry the VA-006 ``label``.
* ``flag_comment`` — review thread and the subject's explanation (VA-005 groundwork).

Expand-only: three new tables under RLS; downgrade drops them.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0018_flags_rules"
down_revision: str | Sequence[str] | None = "0017"
branch_labels: str | Sequence[str] | None = ("flags",)
depends_on: str | Sequence[str] | None = None

_STATUS = "'open', 'in_review', 'resolved_valid', 'resolved_fixed', 'escalated', 'resolved_action'"
_UNRESOLVED = "status IN ('open', 'in_review', 'escalated')"
_RESOLVED = "status IN ('resolved_valid', 'resolved_fixed', 'resolved_action')"


def _base_columns() -> list[sa.Column[Any]]:
    return [
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
    ]


def upgrade() -> None:
    op.create_table(
        "flag",
        *_base_columns(),
        sa.Column("rule_id", sa.String(16), nullable=False),
        sa.Column("rule_version", sa.Integer(), nullable=False),
        sa.Column("subject_type", sa.String(16), nullable=False),
        sa.Column("subject_id", sa.Uuid(), nullable=False),
        sa.Column("severity", sa.String(8), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("evidence", postgresql.JSONB(), nullable=False),
        sa.Column("raised_by_mode", sa.String(8), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=True),
        sa.Column("owner_role", sa.String(32), nullable=True),
        sa.Column(
            "watchers",
            postgresql.ARRAY(sa.Uuid()),
            server_default=sa.text("'{}'::uuid[]"),
            nullable=False,
        ),
        sa.Column("scope_cluster_id", sa.Uuid(), nullable=True),
        sa.Column("scope_store_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("resolution_note", sa.Text(), nullable=True),
        sa.Column("sla_due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("escalation_level", sa.Integer(), server_default="0", nullable=False),
        sa.Column("dedupe_key", sa.String(255), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_by", sa.Uuid(), nullable=True),
        sa.CheckConstraint(f"status IN ({_STATUS})", name=op.f("ck_flag_status")),
        sa.CheckConstraint("severity IN ('high', 'medium', 'low')", name=op.f("ck_flag_severity")),
        sa.CheckConstraint(
            "subject_type IN ('farmer', 'employee', 'visit', 'store')",
            name=op.f("ck_flag_subject_type"),
        ),
        sa.CheckConstraint(
            "raised_by_mode IN ('inline', 'event', 'batch')", name=op.f("ck_flag_raised_by_mode")
        ),
        sa.CheckConstraint("rule_version >= 1", name=op.f("ck_flag_rule_version")),
        sa.CheckConstraint("escalation_level >= 0", name=op.f("ck_flag_escalation_level")),
        sa.CheckConstraint(
            f"({_RESOLVED}) = (resolved_at IS NOT NULL)", name=op.f("ck_flag_resolved_at")
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"], ["user.id"], name=op.f("fk_flag_owner_id_user"), ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_flag")),
    )
    op.create_index("ix_flag_tenant_id", "flag", ["tenant_id"])
    op.create_index(
        "uq_flag_open_dedupe_key",
        "flag",
        ["tenant_id", "dedupe_key"],
        unique=True,
        postgresql_where=sa.text(f"{_UNRESOLVED} AND deleted_at IS NULL"),
    )
    op.create_index("ix_flag_tenant_status_created", "flag", ["tenant_id", "status", "created_at"])
    op.create_index("ix_flag_tenant_rule", "flag", ["tenant_id", "rule_id"])
    op.create_index("ix_flag_subject", "flag", ["tenant_id", "subject_type", "subject_id"])
    op.create_index("ix_flag_owner_id", "flag", ["owner_id"])
    op.create_index("ix_flag_dedupe_key", "flag", ["tenant_id", "dedupe_key"])
    op.create_index("ix_flag_sla_due_at", "flag", ["tenant_id", "sla_due_at"])
    enable_rls("flag")

    op.create_table(
        "flag_event",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("flag_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("from_status", sa.String(16), nullable=True),
        sa.Column("to_status", sa.String(16), nullable=False),
        sa.Column("from_owner_id", sa.Uuid(), nullable=True),
        sa.Column("to_owner_id", sa.Uuid(), nullable=True),
        sa.Column("label", sa.String(16), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.CheckConstraint(
            "kind IN ('created', 'transition', 'assigned', 'sla_escalated')",
            name=op.f("ck_flag_event_kind"),
        ),
        sa.CheckConstraint(
            "label IS NULL OR label IN ('true_positive', 'false_positive')",
            name=op.f("ck_flag_event_label"),
        ),
        sa.ForeignKeyConstraint(
            ["flag_id"], ["flag.id"], name=op.f("fk_flag_event_flag_id_flag"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_flag_event")),
    )
    op.create_index("ix_flag_event_flag_created", "flag_event", ["flag_id", "created_at"])
    op.create_index("ix_flag_event_tenant_label", "flag_event", ["tenant_id", "label"])
    enable_rls("flag_event", append_only=True)

    op.create_table(
        "flag_comment",
        *_base_columns(),
        sa.Column("flag_id", sa.Uuid(), nullable=False),
        sa.Column("author_id", sa.Uuid(), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column(
            "is_subject_explanation", sa.Boolean(), server_default=sa.text("false"), nullable=False
        ),
        sa.CheckConstraint("char_length(body) > 0", name=op.f("ck_flag_comment_body")),
        sa.ForeignKeyConstraint(
            ["flag_id"], ["flag.id"], name=op.f("fk_flag_comment_flag_id_flag"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["author_id"],
            ["user.id"],
            name=op.f("fk_flag_comment_author_id_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_flag_comment")),
    )
    op.create_index("ix_flag_comment_tenant_id", "flag_comment", ["tenant_id"])
    op.create_index("ix_flag_comment_flag_created", "flag_comment", ["flag_id", "created_at"])
    enable_rls("flag_comment")


def downgrade() -> None:
    for table in ("flag_comment", "flag_event", "flag"):
        disable_rls(table)
        op.drop_table(table)
