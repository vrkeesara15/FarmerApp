"""``beat_plan`` — FA-018 the officer's suggested stops for one IST day.

One row per officer and day (unique), generated at 06:00 IST by the ``generate-beat-plans``
job (or on first read that day). ``items`` is the ordered list the officer works through:
each item a farmer (with their village) or a village, the system's ``reasons`` (follow-up
due, pest alert in the district, credit due within 7 days, demo plot stage due) and its
``source`` (``system`` or ``officer`` when the officer added it). The officer reorders, adds
and removes items (``PUT /v1/me/beat``; ``status`` becomes ``edited``) — a regenerated plan
never overwrites an edited one. Audited and a sync entity (the plan is used offline).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class BeatPlan(Base, BaseColumns):
    __tablename__ = "beat_plan"
    __table_args__ = (
        UniqueConstraint("tenant_id", "officer_id", "plan_date"),
        CheckConstraint("status IN ('generated', 'edited')", name="status"),
        CheckConstraint("target > 0", name="target"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    plan_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(
        String(12), nullable=False, default="generated", server_default=text("'generated'")
    )
    target: Mapped[int] = mapped_column(Integer, nullable=False)
    items: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, default=list, server_default=text("'[]'::jsonb")
    )
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


__all__ = ["BeatPlan"]
