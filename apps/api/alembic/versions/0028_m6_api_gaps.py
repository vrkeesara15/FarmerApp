"""M6 API gaps: on-device provenance and "ask an expert" on diagnoses

Revision ID: 0028
Revises: 0027
Create Date: 2026-09-19 20:00:00 UTC

* ``diagnosis.on_device`` (jsonb, nullable): the DX-001 on-device block the app sent (model,
  version, plant / quality / crop scores, latency, fallback) — DX-005 provenance.
* ``diagnosis.expert_requested_at`` / ``expert_requested_by`` / ``expert_note``: FM-006
  ``POST /v1/diagnoses/{id}/ask-expert`` moved an answered case into the agronomist queue.

Expand-only (nullable columns, no default rewrite); downgrade drops them.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0028"
down_revision: str | Sequence[str] | None = "0027"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("diagnosis", sa.Column("on_device", postgresql.JSONB(), nullable=True))
    op.add_column(
        "diagnosis", sa.Column("expert_requested_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column("diagnosis", sa.Column("expert_requested_by", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_diagnosis_expert_requested_by_user",
        "diagnosis",
        "user",
        ["expert_requested_by"],
        ["id"],
        ondelete="SET NULL",
    )
    op.add_column("diagnosis", sa.Column("expert_note", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("diagnosis", "expert_note")
    op.drop_constraint("fk_diagnosis_expert_requested_by_user", "diagnosis", type_="foreignkey")
    op.drop_column("diagnosis", "expert_requested_by")
    op.drop_column("diagnosis", "expert_requested_at")
    op.drop_column("diagnosis", "on_device")
