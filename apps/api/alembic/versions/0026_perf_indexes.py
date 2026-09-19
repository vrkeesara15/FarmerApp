"""NF-005: index for the VA-F06 shared-device check

Revision ID: 0026
Revises: 0025
Create Date: 2026-09-19 16:00:00 UTC

The API latency suite (``make perf-api``, docs/perf/NF-005.md) showed the VA-F06 "one device
registers farmers for several officers" query scanning every ``audit_log`` row of the tenant
on each registration (the trail only grows). A small partial index over the
``farmer.create`` rows, ``(tenant_id, device_id)``, makes it an index scan.

Expand-only; downgrade drops the index.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0026"
down_revision: str | Sequence[str] | None = "0025"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_index(
        "ix_audit_log_farmer_create_device",
        "audit_log",
        ["tenant_id", "device_id"],
        postgresql_where=sa.text("action = 'farmer.create'"),
    )


def downgrade() -> None:
    op.drop_index("ix_audit_log_farmer_create_device", table_name="audit_log")
