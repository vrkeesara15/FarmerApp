"""FA-012 / FA-025 / NF-003: sync_op, sync_change, idempotency_key, upload_session,
upload_chunk, farm_photo, farmer.phone_verified

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-18 12:00:00 UTC

Backward compatible: six new tables and one nullable-defaulted column; nothing existing is
touched otherwise.

* ``farmer.phone_verified boolean NOT NULL DEFAULT false`` (VA-F01).
* ``farm_photo`` (farm_id -> farm, blob_uri, sha256, taken_at, location geography(Point)).
* ``sync_op`` unique ``(tenant_id, op_id)`` with the stored result (op idempotency).
* ``sync_change`` **append-only** change log: ``seq`` identity, indexed ``(tenant_id, seq)``.
* ``idempotency_key`` unique ``(tenant_id, actor_id, key)`` with the stored response.
* ``upload_session`` / ``upload_chunk`` (bytea staging, unique ``(upload_id, index)``).

Every table: ``enable_rls`` (tenant isolation, forced); ``sync_change`` with
``append_only=True`` and the app role granted USAGE on its identity sequence.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geography
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import APP_ROLE, disable_rls, enable_rls

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TABLES = (
    "farm_photo",
    "sync_op",
    "sync_change",
    "idempotency_key",
    "upload_session",
    "upload_chunk",
)
PURPOSES = ("farm_photo", "visit_photo", "receipt", "diagnosis", "profile")


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


def _lean_columns() -> list[sa.Column[Any]]:
    return [
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def _quoted(values: Sequence[str]) -> str:
    return ", ".join(f"'{v}'" for v in values)


def _tenant_index(table: str) -> None:
    op.create_index(op.f(f"ix_{table}_tenant_id"), table, ["tenant_id"], unique=False)


def upgrade() -> None:
    # ------------------------------------------------------------------ farmer.phone_verified
    op.add_column(
        "farmer",
        sa.Column("phone_verified", sa.Boolean(), server_default=sa.text("false"), nullable=False),
    )

    # ------------------------------------------------------------------ farm_photo
    op.create_table(
        "farm_photo",
        *_base_columns(),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("blob_uri", sa.String(length=512), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=True),
        sa.Column("taken_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "location",
            Geography(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=True,
        ),
        sa.CheckConstraint("char_length(blob_uri) > 0", name=op.f("ck_farm_photo_blob_uri")),
        sa.ForeignKeyConstraint(
            ["farm_id"], ["farm.id"], name=op.f("fk_farm_photo_farm_id_farm"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_farm_photo")),
    )
    _tenant_index("farm_photo")
    op.create_index("ix_farm_photo_farm_id", "farm_photo", ["farm_id"], unique=False)
    enable_rls("farm_photo")

    # ------------------------------------------------------------------ sync_op
    op.create_table(
        "sync_op",
        *_lean_columns(),
        sa.Column("op_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("entity", sa.String(length=32), nullable=False),
        sa.Column("action", sa.String(length=16), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("result", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_sync_op")),
        sa.UniqueConstraint("tenant_id", "op_id", name=op.f("uq_sync_op_tenant_id")),
    )
    op.create_index("ix_sync_op_created_at", "sync_op", ["created_at"], unique=False)
    enable_rls("sync_op")

    # ------------------------------------------------------------------ sync_change (append-only)
    op.create_table(
        "sync_change",
        sa.Column("seq", sa.BigInteger(), sa.Identity(always=True), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("entity", sa.String(length=32), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("action", sa.String(length=16), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("changed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.PrimaryKeyConstraint("seq", name=op.f("pk_sync_change")),
    )
    op.create_index("ix_sync_change_tenant_seq", "sync_change", ["tenant_id", "seq"], unique=False)
    enable_rls("sync_change", append_only=True)
    op.execute(f"GRANT USAGE, SELECT ON SEQUENCE sync_change_seq_seq TO {APP_ROLE}")

    # ------------------------------------------------------------------ idempotency_key
    op.create_table(
        "idempotency_key",
        *_lean_columns(),
        sa.Column("actor_id", sa.Uuid(), nullable=False),
        sa.Column("key", sa.String(length=200), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("method", sa.String(length=8), nullable=False),
        sa.Column("path", sa.String(length=512), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("response", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_idempotency_key")),
        sa.UniqueConstraint(
            "tenant_id", "actor_id", "key", name=op.f("uq_idempotency_key_tenant_id")
        ),
    )
    op.create_index(
        "ix_idempotency_key_expires_at", "idempotency_key", ["expires_at"], unique=False
    )
    enable_rls("idempotency_key")

    # ------------------------------------------------------------------ upload_session
    op.create_table(
        "upload_session",
        *_base_columns(),
        sa.Column("actor_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("content_type", sa.String(length=100), nullable=False),
        sa.Column("purpose", sa.String(length=16), nullable=False),
        sa.Column("chunk_size", sa.Integer(), nullable=False),
        sa.Column("chunk_count", sa.Integer(), nullable=False),
        sa.Column(
            "status", sa.String(length=16), server_default=sa.text("'pending'"), nullable=False
        ),
        sa.Column("blob_uri", sa.String(length=512), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            f"purpose IN ({_quoted(PURPOSES)})", name=op.f("ck_upload_session_purpose")
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'complete')", name=op.f("ck_upload_session_status")
        ),
        sa.CheckConstraint("char_length(sha256) = 64", name=op.f("ck_upload_session_sha256")),
        sa.CheckConstraint(
            "size_bytes > 0 AND chunk_size > 0 AND chunk_count > 0",
            name=op.f("ck_upload_session_sizes"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_upload_session")),
    )
    _tenant_index("upload_session")
    op.create_index("ix_upload_session_actor_id", "upload_session", ["actor_id"], unique=False)
    op.create_index("ix_upload_session_expires_at", "upload_session", ["expires_at"], unique=False)
    op.create_index("ix_upload_session_blob_uri", "upload_session", ["blob_uri"], unique=False)
    enable_rls("upload_session")

    # ------------------------------------------------------------------ upload_chunk
    op.create_table(
        "upload_chunk",
        *_lean_columns(),
        sa.Column("upload_id", sa.Uuid(), nullable=False),
        sa.Column("index", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("data", sa.LargeBinary(), nullable=False),
        sa.CheckConstraint("index >= 0 AND size > 0", name=op.f("ck_upload_chunk_index_size")),
        sa.ForeignKeyConstraint(
            ["upload_id"],
            ["upload_session.id"],
            name=op.f("fk_upload_chunk_upload_id_upload_session"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_upload_chunk")),
        sa.UniqueConstraint("upload_id", "index", name=op.f("uq_upload_chunk_upload_id")),
    )
    enable_rls("upload_chunk")


def downgrade() -> None:
    for table in reversed(TABLES):
        disable_rls(table)
        op.drop_table(table)
    op.drop_column("farmer", "phone_verified")
