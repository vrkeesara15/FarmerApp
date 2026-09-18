"""Merge the M3 heads: orders (0012), payments (0013) and catalog (0014)

Revision ID: 0015
Revises: 0012, 0013, 0014
Create Date: 2026-09-18 23:30:00 UTC

FA-020 (0012, branch ``orders``: ``stock_reservation``, ``order_status_event``,
``credit_approval_request``), FA-021 (0013, branch ``payments``: payment columns, ``invoice``,
``invoice_counter``, ``day_close`` reopen) and WC-005 (0014, branch ``catalog``: label-claim
versions, price-list exclusion constraint) were developed concurrently on 0011. All three are
expand-only and touch disjoint objects; this revision only rejoins the graph so
``alembic upgrade head`` has one head.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0015"
down_revision: str | Sequence[str] | None = ("0012", "0013", "0014")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
