"""audit_log: append-only trail of every mutation (FA-006)

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-18 00:00:00 UTC

FA-006 / SEC-028 / NF-012. Backward compatible: one new table, nothing else touched; older
API instances simply do not write to it.

* ``audit_log`` (lean ``TenantRow`` columns: ``id``, ``tenant_id``, ``created_at``; no
  ``updated_at`` / ``deleted_at`` / ``version`` because rows are never changed) with
  ``actor_id`` (NULL = system), ``actor_role``, ``action`` ("<entity>.<verb>"), ``entity``
  (table name), ``entity_id``, ``before`` / ``after`` jsonb diffs (redacted: no secret
  hashes, phones masked), ``ip``, ``device_id``, ``user_agent``, ``trace_id``.
* RLS like every tenant table (``enable_rls``), **append-only** for the app role:
  SELECT + INSERT granted, UPDATE / DELETE / TRUNCATE revoked (the 0003 default privileges
  would otherwise grant them). ``tests/rls/test_meta.py`` knows the table is append-only
  through ``farmerapp.db.rls.APPEND_ONLY_TABLES``.
* Indexes: ``(tenant_id, entity, entity_id, created_at DESC)`` for a record's history and
  ``(tenant_id, created_at, id)`` for the listing / purge.

Retention (NF-012): audit logs are kept **one year minimum**. Nothing here or in the app
deletes them; ``python -m farmerapp.jobs purge-audit-logs`` (default 400 days) is a dry run
that only reports what a purge would remove. The real purge — as the migrate role, after
archival to the exports bucket — is scheduled under OPS / NF-012.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "audit_log",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("actor_role", sa.String(length=32), nullable=False),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("entity", sa.String(length=64), nullable=False),
        sa.Column("entity_id", sa.Uuid(), nullable=False),
        sa.Column("before", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("after", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("ip", sa.String(length=45), nullable=True),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column("user_agent", sa.String(length=512), nullable=True),
        sa.Column("trace_id", sa.String(length=128), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_audit_log")),
    )
    op.create_index(
        "ix_audit_log_tenant_entity_created",
        "audit_log",
        ["tenant_id", "entity", "entity_id", sa.text("created_at DESC")],
        unique=False,
    )
    op.create_index(
        "ix_audit_log_tenant_created",
        "audit_log",
        ["tenant_id", "created_at", "id"],
        unique=False,
    )
    enable_rls("audit_log", append_only=True)


def downgrade() -> None:
    disable_rls("audit_log")
    op.drop_index("ix_audit_log_tenant_created", table_name="audit_log")
    op.drop_index("ix_audit_log_tenant_entity_created", table_name="audit_log")
    op.drop_table("audit_log")
