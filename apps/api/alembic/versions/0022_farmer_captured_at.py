"""VA-F06: the device capture time of a farmer registration (``farmer.captured_at``)

Revision ID: 0022
Revises: 0021
Create Date: 2026-09-18 23:50:00 UTC

Officers register farmers offline and sync them later (FA-025); several captures synced in
one batch get server ``created_at`` values seconds apart and looked like a registration
burst. The sync ``farmer`` create op now stores its ``client_ts`` (capped at the server
time) here and VA-F06 orders registrations by ``coalesce(captured_at, created_at)``.

Expand-only: one nullable column (NULL for online registrations and existing rows, which
fall back to ``created_at``). Downgrade drops it.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0022"
down_revision: str | Sequence[str] | None = "0021"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("farmer", sa.Column("captured_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("farmer", "captured_at")
