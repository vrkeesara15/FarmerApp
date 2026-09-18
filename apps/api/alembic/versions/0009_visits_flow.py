"""Visit flow: override_request, visit.flags, visit_photo.photo_flags, visit_confirmation
status / request / token columns

Revision ID: 0009
Revises: 0007
Branch: visits
Create Date: 2026-09-18 21:00:00 UTC

FA-014 / FA-015 / FA-016 / FA-017 / FA-028 write paths (VV-003 .. VV-005). Backward
compatible: one new table, three defaulted columns, three nullable columns and one dropped
NOT NULL; nothing existing is renamed or removed.

* ``override_request`` (FA-014): the officer's note, who asked and when, the role that must
  decide (``cluster_head``), the decision (``approved`` / ``rejected``), who decided and when,
  an optional decision note. Indexed by visit and by ``(tenant_id, decision)`` for the cluster
  head's queue. RLS like every tenant table.
* ``visit.flags jsonb NOT NULL DEFAULT '[]'`` — server-set evidence flags that never reject
  (FA-017 ``under_minimum``).
* ``visit_photo.photo_flags jsonb NOT NULL DEFAULT '[]'`` — VA-E08 evidence (EXIF time / GPS
  missing or inconsistent with the check-in, duplicate perceptual hash).
* ``visit_confirmation``: ``status`` (``pending | confirmed | expired``, default
  ``confirmed`` so existing rows keep their meaning), ``requested_at``, ``expires_at``,
  ``token_hash`` (SHA-256 of the push / QR token), ``confirmed_at`` becomes nullable (a
  pending request has none) with a CHECK tying it to ``status = 'confirmed'``.

This revision sits on its own ``visits`` branch next to the duty / location migration (0008)
developed concurrently; the two heads are joined with ``alembic merge`` afterwards. It
depends on nothing from 0008.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0009"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = ("visits",)
depends_on: str | Sequence[str] | None = None

DECISIONS = ("approved", "rejected")
CONFIRMATION_STATUSES = ("pending", "confirmed", "expired")


def _quoted(values: Sequence[str]) -> str:
    return ", ".join(f"'{v}'" for v in values)


def upgrade() -> None:
    # ------------------------------------------------------------------ override_request
    op.create_table(
        "override_request",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.Column("visit_id", sa.Uuid(), nullable=False),
        sa.Column("note", sa.Text(), nullable=False),
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("requested_by", sa.Uuid(), nullable=False),
        sa.Column(
            "approver_role",
            sa.String(length=32),
            server_default=sa.text("'cluster_head'"),
            nullable=False,
        ),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decision", sa.String(length=16), nullable=True),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column("decision_note", sa.String(length=500), nullable=True),
        sa.CheckConstraint("char_length(note) > 0", name=op.f("ck_override_request_note")),
        sa.CheckConstraint(
            f"decision IS NULL OR decision IN ({_quoted(DECISIONS)})",
            name=op.f("ck_override_request_decision"),
        ),
        sa.CheckConstraint(
            "(decision IS NULL) = (decided_at IS NULL)", name=op.f("ck_override_request_decided_at")
        ),
        sa.ForeignKeyConstraint(
            ["visit_id"],
            ["visit.id"],
            name=op.f("fk_override_request_visit_id_visit"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["requested_by"],
            ["user.id"],
            name=op.f("fk_override_request_requested_by_user"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["decided_by"],
            ["user.id"],
            name=op.f("fk_override_request_decided_by_user"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_override_request")),
    )
    op.create_index(
        op.f("ix_override_request_tenant_id"), "override_request", ["tenant_id"], unique=False
    )
    op.create_index("ix_override_request_visit_id", "override_request", ["visit_id"], unique=False)
    op.create_index(
        "ix_override_request_tenant_decision",
        "override_request",
        ["tenant_id", "decision"],
        unique=False,
    )
    enable_rls("override_request")

    # ------------------------------------------------------------------ visit.flags
    op.add_column(
        "visit",
        sa.Column(
            "flags",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
    )

    # ------------------------------------------------------------------ visit_photo.photo_flags
    op.add_column(
        "visit_photo",
        sa.Column(
            "photo_flags",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
    )

    # ------------------------------------------------------------------ visit_confirmation
    op.add_column(
        "visit_confirmation",
        sa.Column(
            "status",
            sa.String(length=16),
            server_default=sa.text("'confirmed'"),
            nullable=False,
        ),
    )
    op.add_column(
        "visit_confirmation",
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "visit_confirmation",
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "visit_confirmation", sa.Column("token_hash", sa.String(length=64), nullable=True)
    )
    op.alter_column("visit_confirmation", "confirmed_at", nullable=True)
    op.create_check_constraint(
        op.f("ck_visit_confirmation_status"),
        "visit_confirmation",
        f"status IN ({_quoted(CONFIRMATION_STATUSES)})",
    )
    op.create_check_constraint(
        op.f("ck_visit_confirmation_confirmed_at"),
        "visit_confirmation",
        "(status = 'confirmed') = (confirmed_at IS NOT NULL)",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_visit_confirmation_confirmed_at"), "visit_confirmation", type_="check"
    )
    op.drop_constraint(op.f("ck_visit_confirmation_status"), "visit_confirmation", type_="check")
    # Pending rows have no confirmed_at; they cannot survive the NOT NULL that 0007 had.
    op.execute("DELETE FROM visit_confirmation WHERE confirmed_at IS NULL")
    op.alter_column("visit_confirmation", "confirmed_at", nullable=False)
    op.drop_column("visit_confirmation", "token_hash")
    op.drop_column("visit_confirmation", "expires_at")
    op.drop_column("visit_confirmation", "requested_at")
    op.drop_column("visit_confirmation", "status")
    op.drop_column("visit_photo", "photo_flags")
    op.drop_column("visit", "flags")
    disable_rls("override_request")
    op.drop_table("override_request")
