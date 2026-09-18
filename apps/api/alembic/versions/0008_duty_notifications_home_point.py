"""FA-010 / VV-007 / FA-007 groundwork: user.home_point, duty_session.device_integrity,
notification table

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-18 21:00:00 UTC

Backward compatible: two nullable / defaulted columns and one new table.

* ``user.home_point geography(Point, 4326) NULL`` — VV-007 "idle at home" reference (NULL
  falls back to the officer's store location).
* ``duty_session.device_integrity jsonb NOT NULL DEFAULT '{}'`` — FA-028 flags reported at
  duty start (``{is_mock, is_rooted, clock_drift_s}``), like ``visit.device_integrity``.
* ``notification`` (user, kind, title_key, body_key, data jsonb, created_at, read_at) — the
  minimal in-app inbox row written by the VV-007 auto-end and OPS-006 sync-silence jobs;
  FA-007 adds delivery. RLS enabled + forced; index ``(tenant_id, user_id, created_at DESC)``.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geography
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "user",
        sa.Column(
            "home_point",
            Geography(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=True,
        ),
    )
    op.add_column(
        "duty_session",
        sa.Column(
            "device_integrity",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
    )
    op.create_table(
        "notification",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("title_key", sa.String(length=64), nullable=False),
        sa.Column("body_key", sa.String(length=64), nullable=False),
        sa.Column("data", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "char_length(kind) > 0 AND char_length(title_key) > 0 AND char_length(body_key) > 0",
            name=op.f("ck_notification_keys"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user.id"], name=op.f("fk_notification_user_id_user"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notification")),
    )
    op.create_index(
        "ix_notification_tenant_user_created",
        "notification",
        ["tenant_id", "user_id", sa.text("created_at DESC")],
        unique=False,
    )
    enable_rls("notification")


def downgrade() -> None:
    disable_rls("notification")
    op.drop_index("ix_notification_tenant_user_created", table_name="notification")
    op.drop_table("notification")
    op.drop_column("duty_session", "device_integrity")
    op.drop_column("user", "home_point")
