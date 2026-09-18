"""extensions and tenant

Revision ID: 0001
Revises:
Create Date: 2026-09-17 00:00:00 UTC

"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

EXTENSIONS = ("postgis", "vector", "pg_trgm")


def upgrade() -> None:
    for ext in EXTENSIONS:
        op.execute(f'CREATE EXTENSION IF NOT EXISTS "{ext}"')

    op.create_table(
        "tenant",
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
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("plan", sa.String(length=50), server_default=sa.text("'pilot'"), nullable=False),
        sa.Column(
            "branding",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "settings",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_tenant")),
    )
    op.create_index(op.f("ix_tenant_tenant_id"), "tenant", ["tenant_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_tenant_tenant_id"), table_name="tenant")
    op.drop_table("tenant")
    # Extensions are left in place: other objects may depend on them.
