"""FA-027 farmer meetings.

* ``farmer_meeting`` — a group session an officer holds at a village's registered meeting
  point. The check-in point is tested like a visit with purpose ``meeting`` (VV-003,
  ``farmerapp.visits.geofence``: within the meeting point radius); outside is refused with
  ``outside_geofence``, exactly as a visit check-in. ``status`` ``open`` while attendance is
  taken, ``closed`` afterwards.
* ``meeting_attendance`` — one row per farmer and meeting (unique): how the farmer proved
  presence (``otp`` — a code sent to the farmer's phone, purpose ``meeting_attendance``; or
  ``qr`` — the signed token of the farmer app's attendance QR, ``GET /v1/me/attendance-qr``)
  and who recorded it. The attendance list is linked to farmer records.

Both audited and sync entities.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from geoalchemy2 import Geography, Geometry
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    String,
    UniqueConstraint,
    cast,
    func,
    text,
)
from sqlalchemy.orm import Mapped, column_property, mapped_column

from farmerapp.db.base import Base, BaseColumns
from farmerapp.db.geo import SRID

_POINT_GEOM = Geometry(geometry_type="POINT", srid=SRID)


class MeetingStatus(StrEnum):
    OPEN = "open"
    CLOSED = "closed"


class AttendanceMethod(StrEnum):
    OTP = "otp"
    QR = "qr"


class FarmerMeeting(Base, BaseColumns):
    __tablename__ = "farmer_meeting"
    __table_args__ = (
        CheckConstraint("status IN ('open', 'closed')", name="status"),
        CheckConstraint("(status = 'closed') = (closed_at IS NOT NULL)", name="closed_at"),
        Index("ix_farmer_meeting_officer_held", "tenant_id", "officer_id", "held_at"),
        Index("ix_farmer_meeting_village_id", "village_id"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    village_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("village.id", ondelete="RESTRICT"), nullable=False
    )
    topic: Mapped[str] = mapped_column(String(200), nullable=False)
    held_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    checkin_point: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=False
    )
    checkin_accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    geofence_result: Mapped[str] = mapped_column(String(16), nullable=False)
    distance_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    status: Mapped[str] = mapped_column(
        String(8), nullable=False, default=MeetingStatus.OPEN.value, server_default=text("'open'")
    )
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    checkin_lon: Mapped[float] = column_property(func.ST_X(cast(checkin_point, _POINT_GEOM)))
    checkin_lat: Mapped[float] = column_property(func.ST_Y(cast(checkin_point, _POINT_GEOM)))


class MeetingAttendance(Base, BaseColumns):
    __tablename__ = "meeting_attendance"
    __table_args__ = (
        UniqueConstraint("meeting_id", "farmer_id"),
        CheckConstraint("method IN ('otp', 'qr')", name="method"),
        Index("ix_meeting_attendance_farmer_id", "farmer_id"),
    )

    meeting_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer_meeting.id", ondelete="CASCADE"), nullable=False
    )
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="RESTRICT"), nullable=False
    )
    method: Mapped[str] = mapped_column(String(8), nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    recorded_by: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    otp_challenge_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)


__all__ = ["AttendanceMethod", "FarmerMeeting", "MeetingAttendance", "MeetingStatus"]
