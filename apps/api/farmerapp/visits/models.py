"""Visits (SPEC 8.2 ``visit`` / ``visit_photo``; FA-014 .. FA-017, FA-028, VV-003 .. VV-005).

* ``visit`` — one check-in by an officer at a farmer's farm (``farm_id``) or at the village
  meeting point (``village_id``, ``geofence_result = meeting_point``). ``geofence_result``
  records the FA-014 decision (``inside`` / ``meeting_point``; ``outside`` is recorded for
  evidence but the app blocks it; ``override`` needs ``override_note`` and a cluster head's
  ``override_approved_by``). ``duration_s`` is a **stored generated column**
  (``checkout_at - checkin_at``, FA-017). ``score`` / ``score_components`` (VV-004) and
  ``status`` (VV-005: ``verified`` / ``partial`` / ``unverified``, ``open`` until check-out)
  are computed by ``farmerapp.visits.scoring`` and are **server-owned** in the sync merge
  (``farmerapp.sync.service``), as are ``confirmation_channel`` / ``confirmed_at`` (FA-016).
  ``device_integrity`` keeps the FA-028 flags the app reported at check-in
  (``{is_mock, is_rooted, clock_drift_s}``). ``client_visit_id`` is the id the device
  generated offline (unique per tenant) for sync replays.
* ``visit_photo`` — an in-app photo (FA-015: ``taken_in_app``; gallery uploads are refused
  by the app and score nothing): the blob from a completed NF-003 upload, ``sha256``,
  perceptual hash ``phash`` (VA-E08 duplicates), EXIF time + GPS, the device time and the
  server time at upload.
* ``visit_confirmation`` — one confirmation attempt per channel request (FA-016: SMS OTP,
  farmer-app push, QR). ``status`` is ``pending`` from the request until the channel succeeds
  (``confirmed``) or the request lapses (``expired``); ``confirmed_at`` is set only on
  success, which is the moment the visit itself becomes confirmed (``visit.confirmed_at``).
  The row keeps the OTP challenge, the receiving phone's last four digits, the confirming
  device (VA-E05 looks for the same phone or device confirming many farmers) and, for push /
  QR, the SHA-256 of the signed token the farmer app presents. ``rating`` / ``rating_reason``
  are the FM-011 farmer rating, stored on the same row when the farmer confirms.
* ``override_request`` — the FA-014 geofence override: the officer's note, who asked, the role
  that must decide (``cluster_head``) and the decision (``approved`` / ``rejected``, by whom,
  when). Until approved the visit's geofence component scores 0 (``scoring.py``).

Enumerations are CHECK constraints on short strings (expand-only), like every other table.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from geoalchemy2 import Geography, Geometry
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Computed,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    cast,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, column_property, declared_attr, mapped_column

from farmerapp.db.base import Base, BaseColumns
from farmerapp.db.geo import SRID
from farmerapp.farmers.models import CropStage


class VisitPurpose(StrEnum):
    ADVISORY = "advisory"
    SCOUTING = "scouting"
    DEMO = "demo"
    COLLECTION = "collection"
    SALE = "sale"
    MEETING = "meeting"


class GeofenceResult(StrEnum):
    INSIDE = "inside"  # within the farm geofence (FA-014 / VV-003)
    OUTSIDE = "outside"  # recorded as evidence; the app blocks the check-in
    MEETING_POINT = "meeting_point"  # at the registered village meeting point
    OVERRIDE = "override"  # outside, with a note and cluster-head approval


class VisitStatus(StrEnum):
    VERIFIED = "verified"  # score >= 70 (VV-005)
    PARTIAL = "partial"  # 40-69
    UNVERIFIED = "unverified"  # < 40
    OPEN = "open"  # checked in, not yet checked out / scored


class ConfirmationChannel(StrEnum):
    SMS_OTP = "sms_otp"
    APP_PUSH = "app_push"
    QR = "qr"
    NONE = "none"


class ConfirmationStatus(StrEnum):
    PENDING = "pending"  # requested, waiting for the farmer
    CONFIRMED = "confirmed"  # the channel succeeded (FA-016)
    EXPIRED = "expired"  # superseded or timed out


class OverrideDecision(StrEnum):
    APPROVED = "approved"
    REJECTED = "rejected"


#: FA-014: who decides an override request.
OVERRIDE_APPROVER_ROLE = "cluster_head"

#: FA-017 / VA-E04: set on ``visit.flags`` when the duration is under the tenant minimum.
FLAG_UNDER_MINIMUM = "under_minimum"

#: VA-E08 evidence recorded on ``visit_photo.photo_flags`` (never a rejection).
PHOTO_FLAG_EXIF_TIME_MISSING = "exif_time_missing"
PHOTO_FLAG_EXIF_TIME_MISMATCH = "exif_time_mismatch"
PHOTO_FLAG_EXIF_GPS_MISSING = "exif_gps_missing"
PHOTO_FLAG_EXIF_GPS_MISMATCH = "exif_gps_mismatch"
PHOTO_FLAG_DUPLICATE = "duplicate_photo"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


_POINT_GEOM = Geometry(geometry_type="POINT", srid=SRID)


def _geo_point(nullable: bool = True) -> Mapped[Any]:
    return mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=nullable
    )


class Visit(Base, BaseColumns):
    __tablename__ = "visit"
    __table_args__ = (
        CheckConstraint(f"purpose IN ({_in(VisitPurpose)})", name="purpose"),
        CheckConstraint(f"geofence_result IN ({_in(GeofenceResult)})", name="geofence_result"),
        CheckConstraint(f"status IN ({_in(VisitStatus)})", name="status"),
        CheckConstraint(
            f"confirmation_channel IN ({_in(ConfirmationChannel)})", name="confirmation_channel"
        ),
        CheckConstraint(
            f"crop_stage IS NULL OR crop_stage IN ({_in(CropStage)})", name="crop_stage"
        ),
        CheckConstraint("checkout_at IS NULL OR checkout_at >= checkin_at", name="checkout"),
        CheckConstraint("score IS NULL OR score BETWEEN 0 AND 100", name="score"),
        CheckConstraint(
            "geofence_result <> 'override' OR override_note IS NOT NULL", name="override_note"
        ),
        UniqueConstraint("tenant_id", "client_visit_id"),
        Index("ix_visit_tenant_officer_checkin", "tenant_id", "officer_id", "checkin_at"),
        Index("ix_visit_farmer_id", "farmer_id"),
        Index("ix_visit_farm_id", "farm_id"),
        Index("ix_visit_tenant_status", "tenant_id", "status"),
        Index("ix_visit_checkin_point", "checkin_point", postgresql_using="gist"),  # VA-E03
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="RESTRICT"), nullable=False
    )
    farm_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("farm.id", ondelete="SET NULL"), nullable=True
    )
    village_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("village.id", ondelete="SET NULL"), nullable=True
    )
    purpose: Mapped[str] = mapped_column(String(16), nullable=False)
    checkin_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    checkout_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    checkin_point: Mapped[Any] = _geo_point(nullable=False)
    checkin_accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    checkout_point: Mapped[Any] = _geo_point()
    geofence_result: Mapped[str] = mapped_column(String(16), nullable=False)
    override_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    override_approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    crop_stage: Mapped[str | None] = mapped_column(String(16), nullable=True)
    duration_s: Mapped[int | None] = mapped_column(
        Integer,
        Computed("(EXTRACT(EPOCH FROM (checkout_at - checkin_at)))::integer", persisted=True),
        nullable=True,
    )
    score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    score_components: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=VisitStatus.OPEN, server_default=text("'open'")
    )
    confirmation_channel: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ConfirmationChannel.NONE,
        server_default=text("'none'"),
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    device_integrity: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict, server_default=text("'{}'::jsonb")
    )
    #: Server-set evidence flags that never reject (FA-017 ``under_minimum``; more in M4).
    flags: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default=text("'[]'::jsonb")
    )
    client_visit_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    checkin_lon: Mapped[float] = column_property(func.ST_X(cast(checkin_point, _POINT_GEOM)))
    checkin_lat: Mapped[float] = column_property(func.ST_Y(cast(checkin_point, _POINT_GEOM)))
    checkout_lon: Mapped[float | None] = column_property(
        func.ST_X(cast(checkout_point, _POINT_GEOM))
    )
    checkout_lat: Mapped[float | None] = column_property(
        func.ST_Y(cast(checkout_point, _POINT_GEOM))
    )

    @declared_attr.directive
    def __mapper_args__(cls) -> dict[str, Any]:
        # eager_defaults: ``duration_s`` comes back with RETURNING right after a flush.
        return {"version_id_col": cls.version, "eager_defaults": True}


class VisitPhoto(Base, BaseColumns):
    __tablename__ = "visit_photo"
    __table_args__ = (
        CheckConstraint("char_length(blob_uri) > 0", name="blob_uri"),
        Index("ix_visit_photo_visit_id", "visit_id"),
        Index("ix_visit_photo_tenant_phash", "tenant_id", "phash"),  # VA-E08 duplicates
        Index("ix_visit_photo_tenant_sha256", "tenant_id", "sha256"),
    )

    visit_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("visit.id", ondelete="CASCADE"), nullable=False
    )
    blob_uri: Mapped[str] = mapped_column(String(512), nullable=False)  # gs://bucket/key
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    phash: Mapped[str | None] = mapped_column(Text, nullable=True)
    exif_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    exif_point: Mapped[Any] = _geo_point()
    taken_in_app: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    device_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    server_time: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    #: VA-E08 evidence: EXIF time / GPS inconsistent with the check-in, duplicates.
    photo_flags: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default=text("'[]'::jsonb")
    )
    exif_lon: Mapped[float | None] = column_property(func.ST_X(cast(exif_point, _POINT_GEOM)))
    exif_lat: Mapped[float | None] = column_property(func.ST_Y(cast(exif_point, _POINT_GEOM)))


class VisitConfirmation(Base, BaseColumns):
    __tablename__ = "visit_confirmation"
    __table_args__ = (
        CheckConstraint(
            f"channel IN ({_in(ConfirmationChannel)}) AND channel <> 'none'", name="channel"
        ),
        CheckConstraint("rating IS NULL OR rating BETWEEN 1 AND 5", name="rating"),
        CheckConstraint(
            "farmer_phone_last4 IS NULL OR char_length(farmer_phone_last4) = 4",
            name="farmer_phone_last4",
        ),
        CheckConstraint(f"status IN ({_in(ConfirmationStatus)})", name="status"),
        CheckConstraint("(status = 'confirmed') = (confirmed_at IS NOT NULL)", name="confirmed_at"),
        Index("ix_visit_confirmation_visit_id", "visit_id"),
        Index("ix_visit_confirmation_tenant_phone", "tenant_id", "farmer_phone_last4"),  # VA-E05
        Index("ix_visit_confirmation_tenant_device", "tenant_id", "confirmed_via_device_id"),
    )

    visit_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("visit.id", ondelete="CASCADE"), nullable=False
    )
    channel: Mapped[str] = mapped_column(String(16), nullable=False)
    otp_challenge_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("otp_challenge.id", ondelete="SET NULL"), nullable=True
    )
    farmer_phone_last4: Mapped[str | None] = mapped_column(String(4), nullable=True)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=ConfirmationStatus.CONFIRMED,
        server_default=text("'confirmed'"),
    )
    requested_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    #: SHA-256 of the signed push / QR token the farmer app presents (never the token).
    token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    confirmed_via_device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)  # FM-011
    rating_reason: Mapped[str | None] = mapped_column(String(200), nullable=True)


class OverrideRequest(Base, BaseColumns):
    __tablename__ = "override_request"
    __table_args__ = (
        CheckConstraint("char_length(note) > 0", name="note"),
        CheckConstraint(
            f"decision IS NULL OR decision IN ({_in(OverrideDecision)})", name="decision"
        ),
        CheckConstraint("(decision IS NULL) = (decided_at IS NULL)", name="decided_at"),
        Index("ix_override_request_visit_id", "visit_id"),
        Index("ix_override_request_tenant_decision", "tenant_id", "decision"),
    )

    visit_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("visit.id", ondelete="CASCADE"), nullable=False
    )
    note: Mapped[str] = mapped_column(Text, nullable=False)
    requested_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    requested_by: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    approver_role: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=OVERRIDE_APPROVER_ROLE,
        server_default=text(f"'{OVERRIDE_APPROVER_ROLE}'"),
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    decision: Mapped[str | None] = mapped_column(String(16), nullable=True)
    decided_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    decision_note: Mapped[str | None] = mapped_column(String(500), nullable=True)

    @property
    def pending(self) -> bool:
        return self.decision is None


__all__ = [
    "FLAG_UNDER_MINIMUM",
    "OVERRIDE_APPROVER_ROLE",
    "PHOTO_FLAG_DUPLICATE",
    "PHOTO_FLAG_EXIF_GPS_MISMATCH",
    "PHOTO_FLAG_EXIF_GPS_MISSING",
    "PHOTO_FLAG_EXIF_TIME_MISMATCH",
    "PHOTO_FLAG_EXIF_TIME_MISSING",
    "ConfirmationChannel",
    "ConfirmationStatus",
    "GeofenceResult",
    "OverrideDecision",
    "OverrideRequest",
    "Visit",
    "VisitConfirmation",
    "VisitPhoto",
    "VisitPurpose",
    "VisitStatus",
]
