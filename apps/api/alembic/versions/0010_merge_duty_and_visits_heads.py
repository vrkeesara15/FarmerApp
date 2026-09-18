"""Merge the duty (0008) and visits (0009) heads

Revision ID: 0010
Revises: 0008, 0009
Create Date: 2026-09-18 22:00:00 UTC

The FA-010 duty / location API (0008: ``user.home_point``, ``duty_session.device_integrity``,
``notification``) and the FA-014 visit flow (0009, branch ``visits``: ``override_request``,
``visit.flags``, ``visit_photo.photo_flags``, ``visit_confirmation`` status / token columns)
were developed concurrently on 0007. Nothing to do here: both are additive and independent;
this revision only rejoins the graph so ``alembic upgrade head`` has one head.
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "0010"
down_revision: str | Sequence[str] | None = ("0008", "0009")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
