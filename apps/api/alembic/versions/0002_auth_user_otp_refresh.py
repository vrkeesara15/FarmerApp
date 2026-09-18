"""auth: user, otp_challenge, refresh_token; tenant.slug

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-17 00:00:00 UTC

Backward compatible: three new tables and one nullable column. RLS policies arrive with
FA-003 (every table already carries tenant_id).
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

ROLES = (
    "owner",
    "director",
    "cluster_head",
    "auditor",
    "store_manager",
    "accountant",
    "field_officer",
    "agronomist",
    "tenant_admin",
    "farmer",
)
PURPOSES = ("login", "farmer_confirm", "farmer_register", "meeting_attendance")


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


def _quoted(values: Sequence[str]) -> str:
    return ", ".join(f"'{v}'" for v in values)


def upgrade() -> None:
    op.add_column("tenant", sa.Column("slug", sa.String(length=50), nullable=True))
    op.create_unique_constraint(op.f("uq_tenant_slug"), "tenant", ["slug"])

    op.create_table(
        "user",
        *_base_columns(),
        sa.Column("phone", sa.String(length=16), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("store_id", sa.Uuid(), nullable=True),
        sa.Column("cluster_id", sa.Uuid(), nullable=True),
        sa.Column("language", sa.String(length=8), server_default=sa.text("'en'"), nullable=False),
        sa.Column(
            "status", sa.String(length=16), server_default=sa.text("'active'"), nullable=False
        ),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.CheckConstraint(f"role IN ({_quoted(ROLES)})", name=op.f("ck_user_role")),
        sa.CheckConstraint("status IN ('active', 'disabled')", name=op.f("ck_user_status")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user")),
        sa.UniqueConstraint("tenant_id", "phone", name=op.f("uq_user_tenant_id")),
    )
    op.create_index(op.f("ix_user_tenant_id"), "user", ["tenant_id"], unique=False)
    op.create_index("ix_user_phone", "user", ["phone"], unique=False)

    op.create_table(
        "otp_challenge",
        *_base_columns(),
        sa.Column("phone", sa.String(length=16), nullable=False),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("code_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("resend_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("window_started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("channel", sa.String(length=16), nullable=False),
        sa.Column("sms_sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("whatsapp_sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("provider_ref", sa.String(length=64), nullable=True),
        sa.Column("user_id", sa.Uuid(), nullable=True),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.CheckConstraint(
            f"purpose IN ({_quoted(PURPOSES)})", name=op.f("ck_otp_challenge_purpose")
        ),
        sa.CheckConstraint("channel IN ('sms', 'whatsapp')", name=op.f("ck_otp_challenge_channel")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_otp_challenge")),
    )
    op.create_index(
        op.f("ix_otp_challenge_tenant_id"), "otp_challenge", ["tenant_id"], unique=False
    )
    op.create_index(
        "ix_otp_challenge_phone_purpose_created",
        "otp_challenge",
        ["phone", "purpose", "created_at"],
        unique=False,
    )

    op.create_table(
        "refresh_token",
        *_base_columns(),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column("device_name", sa.String(length=200), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by", sa.Uuid(), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user.id"], name=op.f("fk_refresh_token_user_id_user"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_refresh_token")),
        sa.UniqueConstraint("token_hash", name=op.f("uq_refresh_token_token_hash")),
    )
    op.create_index(
        op.f("ix_refresh_token_tenant_id"), "refresh_token", ["tenant_id"], unique=False
    )
    op.create_index("ix_refresh_token_family_id", "refresh_token", ["family_id"], unique=False)
    op.create_index("ix_refresh_token_user_id", "refresh_token", ["user_id"], unique=False)


def downgrade() -> None:
    op.drop_table("refresh_token")
    op.drop_table("otp_challenge")
    op.drop_table("user")
    op.drop_constraint(op.f("uq_tenant_slug"), "tenant", type_="unique")
    op.drop_column("tenant", "slug")
