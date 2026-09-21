"""AN-004: saved farmer segments reusable by campaigns

Revision ID: 0036
Revises: 0035
Create Date: 2026-09-19 23:55:00 UTC

``saved_segment`` — a named ``farmerapp.campaigns.segments.Segment`` definition the console's
C32 builder stores (AN-004) and ``POST /v1/campaigns`` can be created from (WC-008). Under
RLS like every other table. Expand-only: one new table; downgrade drops it.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0036"
down_revision: str | Sequence[str] | None = "0035"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "saved_segment",
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
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("definition", postgresql.JSONB(), nullable=False),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("last_count", sa.Integer(), nullable=True),
        sa.Column("last_counted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("char_length(name) > 0", name=op.f("ck_saved_segment_name")),
        sa.ForeignKeyConstraint(
            ["created_by"],
            ["user.id"],
            name=op.f("fk_saved_segment_created_by_user"),
            ondelete="SET NULL",
        ),
        sa.UniqueConstraint("tenant_id", "name", name=op.f("uq_saved_segment_tenant_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_saved_segment")),
    )
    op.create_index(op.f("ix_saved_segment_tenant_id"), "saved_segment", ["tenant_id"])
    op.create_index("ix_saved_segment_tenant_name", "saved_segment", ["tenant_id", "name"])
    enable_rls("saved_segment")


def downgrade() -> None:
    disable_rls("saved_segment")
    op.drop_table("saved_segment")
