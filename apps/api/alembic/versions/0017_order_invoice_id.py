"""FA-020 / ST-001: every fulfilled order carries its GST invoice (``order.invoice_id``)

Revision ID: 0017
Revises: 0016
Create Date: 2026-09-18 18:00:00 UTC

Officer and farmer-app orders now get their tax invoice when they reach ``handed_over`` /
``delivered`` (the POS already issued one at the sale). The order points at it so the order
reads and the sync change feed can tell the officer app that "Share invoice" is possible.

Expand-only: nullable ``order.invoice_id`` (no FK: ``invoice.order_id`` already references
the order, and a cycle would make the order row unwritable before its invoice), a unique
index per tenant, and a backfill from the existing invoices (POS sales). Downgrade drops the
column; the ``invoice`` rows are untouched.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017"
down_revision: str | Sequence[str] | None = "0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("order", sa.Column("invoice_id", sa.Uuid(), nullable=True))
    op.execute(
        'UPDATE "order" o SET invoice_id = i.id FROM invoice i '
        "WHERE i.order_id = o.id AND i.tenant_id = o.tenant_id AND o.invoice_id IS NULL"
    )
    op.create_index("uq_order_invoice_id", "order", ["tenant_id", "invoice_id"], unique=True)


def downgrade() -> None:
    op.drop_index("uq_order_invoice_id", table_name="order")
    op.drop_column("order", "invoice_id")
