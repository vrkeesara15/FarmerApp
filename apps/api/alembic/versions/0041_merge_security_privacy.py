"""Merge the M7 security and privacy head (0040) into the analytics head (0036)

Revision ID: 0041
Revises: 0036, 0040
Create Date: 2026-09-20 00:00:00 UTC

Both branches were developed concurrently on 0035. 0036 (``analytics_segments``) adds
``saved_segment``; 0040 (``security_privacy``) adds ``otp_block``, ``otp_challenge.request_ip``
and the four NF-013 columns on ``data_request``. They are expand-only and touch disjoint
objects, so this revision only rejoins the graph: ``alembic upgrade head`` has a single head
again and ``downgrade`` is a no-op that lets each branch unwind on its own.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0041"
down_revision: str | Sequence[str] | None = ("0036", "0040")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
