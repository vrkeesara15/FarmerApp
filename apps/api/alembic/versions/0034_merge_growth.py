"""Merge the last M7 head: growth (0031, branch ``growth``) into 0033

Revision ID: 0034
Revises: 0033, 0031
Create Date: 2026-09-19 22:30:00 UTC

0033 already rejoined the M7 rules (0029, ``rules_m7``) and field P1 (0030, ``field_p1``)
branches. The growth branch (0031, ``growth``: campaigns and recipients, sales targets,
incentive rule sets and payouts, export jobs, report schedules and runs, reorder levels) was
developed concurrently on 0028 as well. Every branch is expand-only and the three touch
disjoint objects, so this revision only rejoins the graph: ``alembic upgrade head`` has a
single head again.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0034"
down_revision: str | Sequence[str] | None = ("0033", "0031")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
