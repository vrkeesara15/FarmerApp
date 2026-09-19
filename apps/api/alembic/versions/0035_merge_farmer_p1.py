"""Merge the farmer P1 head (0032, branch ``farmer_p1``) into 0034

Revision ID: 0035
Revises: 0034, 0032
Create Date: 2026-09-19 23:30:00 UTC

0033 rejoined the M7 rules (0029, ``rules_m7``) and field P1 (0030, ``field_p1``) branches and
0034 the growth branch (0031, ``growth``). Farmer P1 (0032, ``farmer_p1``: ``crop_task_template``,
``crop_plot_task``, ``outbreak_alert``, ``evaluation_run``, ``model_release``,
``corpus_embedding``, ``encoder_activation``) was developed concurrently on 0029. Every branch is
expand-only and they touch disjoint objects, so this revision only rejoins the graph:
``alembic upgrade head`` has a single head again.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0035"
down_revision: str | Sequence[str] | None = ("0034", "0032")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
