"""Merge the M7 heads: rules (0029, rules_m7) and field P1 (0030, field_p1)

Revision ID: 0033
Revises: 0029, 0030
Create Date: 2026-09-19 21:46:51 UTC

The M7 rules (0029, branch ``rules_m7``: ``crop_calendar``, ``flag_summary``,
``rule_tenant_override``, ``llm_call_log.flag_id``) and field P1 (0030, branch ``field_p1``:
push tokens, track gaps, travel claims, beat plans, demo plots, farmer meetings) were
developed concurrently on 0028. Both are expand-only and touch disjoint objects; this revision
only rejoins the graph so ``alembic upgrade head`` has one head.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0033"
down_revision: str | Sequence[str] | None = ("0029", "0030")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
