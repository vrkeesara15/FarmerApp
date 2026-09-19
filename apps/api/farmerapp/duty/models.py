"""``track_gap`` — VV-006 gaps of a duty session and the officer's VV-008 reason.

A gap is more than 30 minutes without a kept location point while on duty (from the session
start, between points, up to the session end). Its id is **deterministic** —
``gap_id(duty_session_id, start)`` (uuid5) — so the officer's day timeline, the console day
replay and the stored row always agree on it, even for a gap of a session still open (the row
is written when the officer gives a reason, or when the track processing runs at duty end).

``reason`` is one of ``network | personal_break | vehicle | other`` with an optional note;
it is shown to the cluster head in the day replay (WC-002 / AN-003). Audited like any officer
input (FA-006); a sync entity so the reason can be given offline.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns

GAP_NAMESPACE = uuid.UUID("7f1b9c52-3c1e-4f0e-9a52-5d0d1c6b2a10")


class GapReason(StrEnum):
    NETWORK = "network"
    PERSONAL_BREAK = "personal_break"
    VEHICLE = "vehicle"
    OTHER = "other"


def gap_id(duty_session_id: uuid.UUID, start: datetime) -> uuid.UUID:
    """The stable id of the gap of ``duty_session_id`` that starts at ``start``."""
    micros = int(start.timestamp() * 1_000_000)
    return uuid.uuid5(GAP_NAMESPACE, f"{duty_session_id}:{micros}")


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class TrackGap(Base, BaseColumns):
    __tablename__ = "track_gap"
    __table_args__ = (
        CheckConstraint("end_at > start_at", name="span"),
        CheckConstraint(f"reason IS NULL OR reason IN ({_in(GapReason)})", name="reason"),
        CheckConstraint("(reason IS NULL) = (reason_at IS NULL)", name="reason_at"),
        Index("ix_track_gap_officer_start", "tenant_id", "officer_id", "start_at"),
        Index("ix_track_gap_duty_session_id", "duty_session_id"),
    )

    duty_session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("duty_session.id", ondelete="CASCADE"), nullable=False
    )
    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    duration_s: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str | None] = mapped_column(String(16), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    reason_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


__all__ = ["GAP_NAMESPACE", "GapReason", "TrackGap", "gap_id"]
