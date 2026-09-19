"""VA-F08: perceptual hash of farm photos (``farm_photo.phash``)

Revision ID: 0023
Revises: 0022
Create Date: 2026-09-19 06:00:00 UTC

Visit photos carry a 64-bit pHash (FA-015) so VA-F08 catches near-duplicates (re-encoded,
slightly cropped) across farmers; farm photos only had ``sha256`` and were matched on
identical bytes. The farm write path now computes the pHash from the uploaded blob (same
Pillow / imagehash helper as visit photos); existing rows are filled by
``python -m farmerapp.jobs backfill-farm-photo-phash --tenant ...`` (idempotent).

Expand-only: one nullable column (16 hex chars, NULL until computed or when the blob is not
a decodable image) and an index on ``(tenant_id, phash)`` like ``visit_photo``. Downgrade
drops both.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0023"
down_revision: str | Sequence[str] | None = "0022"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("farm_photo", sa.Column("phash", sa.Text(), nullable=True))
    op.create_index("ix_farm_photo_tenant_phash", "farm_photo", ["tenant_id", "phash"])


def downgrade() -> None:
    op.drop_index("ix_farm_photo_tenant_phash", table_name="farm_photo")
    op.drop_column("farm_photo", "phash")
