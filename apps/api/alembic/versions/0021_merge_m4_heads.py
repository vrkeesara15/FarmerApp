"""Merge the M4 heads: flags / rules (0018_flags_rules) and admin (0020)

Revision ID: 0021
Revises: 0018_flags_rules, 0020
Create Date: 2026-09-18 23:45:00 UTC

M4 kickoff (0018_flags_rules, branch ``flags``: ``flag``, ``flag_event``, ``flag_comment``)
and WC-011 / SEC-020 / SEC-025 / SEC-028 (0020, branch ``admin``: ``device``,
``user.tokens_valid_after``, ``refresh_token.revoked_reason``, ``otp_challenge`` purpose
``step_up``) were developed concurrently on 0017. Both are expand-only and touch disjoint
objects; this revision only rejoins the graph so ``alembic upgrade head`` has one head.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0021"
down_revision: str | Sequence[str] | None = ("0018_flags_rules", "0020")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
