"""WC-011 / SEC-020 / SEC-025 / SEC-028: devices, fast revocation, step-up OTP

Revision ID: 0020
Revises: 0017
Create Date: 2026-09-18 20:00:00 UTC

Expand-only (branch label ``admin``; the M4 integration merges it with the other M4 heads):

* new ``device`` table (one row per user and device id; ``status`` pending / active /
  revoked / lost; RLS like every tenant table). Backfilled from ``user.device_id`` so the
  device an officer last signed in from stays bound (SEC-020).
* ``user.tokens_valid_after`` (nullable): access tokens issued at or before it are rejected
  (forced logout, disable).
* ``refresh_token.revoked_reason`` (nullable): lets refresh answer ``session_revoked`` /
  ``device_wipe_required`` instead of treating an admin revocation as token reuse.
* ``otp_challenge.purpose`` gains ``step_up`` (CHECK widened).

Downgrade drops the new table and columns and narrows the CHECK after deleting ``step_up``
challenges (short-lived, single-use rows; nothing else refers to them).
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0020"
down_revision: str | Sequence[str] | None = "0017"
branch_labels: str | Sequence[str] | None = ("admin",)
depends_on: str | Sequence[str] | None = None

_OLD_PURPOSES = "('login', 'farmer_confirm', 'farmer_register', 'meeting_attendance')"
_NEW_PURPOSES = "('login', 'farmer_confirm', 'farmer_register', 'meeting_attendance', 'step_up')"


def upgrade() -> None:
    op.create_table(
        "device",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=False),
        sa.Column("platform", sa.String(length=32), nullable=True),
        sa.Column("model", sa.String(length=200), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("first_seen", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen", sa.DateTime(timezone=True), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("bound_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
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
        sa.CheckConstraint(
            "status IN ('pending', 'active', 'revoked', 'lost')", name=op.f("ck_device_status")
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user.id"], name=op.f("fk_device_user_id_user"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_device")),
        sa.UniqueConstraint("tenant_id", "user_id", "device_id", name=op.f("uq_device_tenant_id")),
    )
    op.create_index(op.f("ix_device_tenant_id"), "device", ["tenant_id"], unique=False)
    op.create_index("ix_device_user_id", "device", ["user_id"], unique=False)
    enable_rls("device")

    op.add_column(
        "user", sa.Column("tokens_valid_after", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column("refresh_token", sa.Column("revoked_reason", sa.String(length=32), nullable=True))
    op.drop_constraint(op.f("ck_otp_challenge_purpose"), "otp_challenge", type_="check")
    op.create_check_constraint(
        op.f("ck_otp_challenge_purpose"), "otp_challenge", f"purpose IN {_NEW_PURPOSES}"
    )

    # SEC-020 backfill: the device each live account last signed in from is its bound device.
    op.execute(
        """
        INSERT INTO device (tenant_id, user_id, device_id, first_seen, last_seen, status, bound_at)
        SELECT u.tenant_id, u.id, u.device_id, u.updated_at, u.updated_at, 'active', u.updated_at
        FROM "user" u
        WHERE u.device_id IS NOT NULL AND u.deleted_at IS NULL
        ON CONFLICT DO NOTHING
        """
    )


def downgrade() -> None:
    op.execute("DELETE FROM otp_challenge WHERE purpose = 'step_up'")
    op.drop_constraint(op.f("ck_otp_challenge_purpose"), "otp_challenge", type_="check")
    op.create_check_constraint(
        op.f("ck_otp_challenge_purpose"), "otp_challenge", f"purpose IN {_OLD_PURPOSES}"
    )
    op.drop_column("refresh_token", "revoked_reason")
    op.drop_column("user", "tokens_valid_after")
    disable_rls("device")
    op.drop_index("ix_device_user_id", table_name="device")
    op.drop_index(op.f("ix_device_tenant_id"), table_name="device")
    op.drop_table("device")
