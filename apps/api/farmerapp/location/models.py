"""Duty and location entities (SPEC 8.2 ``duty_session`` / ``location_point``; FA-010, FA-011,
VV-001, VV-002, VV-007, VV-010, SPEC 2.6 retention).

* ``duty_session`` — one row per duty toggle (FA-010): who, from when to when, where it
  started / ended, the km the track processing computed (VV-006, FA-023) and the detected
  ``stops`` (jsonb). ``end_reason`` says whether the officer ended it or the server did
  (``auto_time`` at the tenant's auto-end time, ``auto_idle`` after idle at home — VV-007,
  ``forced`` by a manager). ``policy_version`` is the location policy accepted at the time
  (VV-010); ``device_id`` / ``app_version`` come from the app.
* ``location_point`` — the raw track (VV-001 sampling), **declaratively partitioned by day
  on ``ts``** (``PARTITION BY RANGE (ts)``; migration 0007). Partitions are daily tables
  ``location_point_pYYYYMMDD`` (UTC days) created by the ``ensure_location_partitions``
  SQL function (``farmerapp.location.partitions``; ``jobs ensure-partitions`` daily) and
  dropped after 180 days by ``purge-location-points`` once the day is folded into
  ``location_daily_agg`` (SPEC 2.6). Every point carries the VV-002 / FA-028 metadata:
  accuracy, speed, bearing, battery, mock-location and root flags, device-vs-server clock
  drift, provider and the server receive time. High-volume telemetry: not audited
  (``__audit__ = False``), never in the sync change feed (``SYNC_EXCLUDED_ENTITIES``), RLS
  still forced on the parent and on every partition. The primary key is ``(id, ts)``
  because a unique constraint on a partitioned table must include the partition key.
* ``location_daily_agg`` — what survives the purge: km, number of points and the first /
  last timestamp per officer and UTC day.
* ``policy_acceptance`` — FA-011 / VV-010 acceptance record: user, policy key, version,
  timestamp, device, app version and the hash of the text shown. Append-only (a newer
  policy is a new row; ``APPEND_ONLY_TABLES``).
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from geoalchemy2 import Geography, Geometry
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    SmallInteger,
    String,
    UniqueConstraint,
    Uuid,
    cast,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, column_property, mapped_column

from farmerapp.db.base import Base, BaseColumns, TenantRow
from farmerapp.db.geo import SRID

#: SPEC 2.6: tracks older than this are aggregated and the raw points deleted.
LOCATION_RETENTION_DAYS = 180
#: Daily partitions of ``location_point`` are named ``location_point_pYYYYMMDD``.
PARTITION_PREFIX = "location_point_p"
LOCATION_POLICY_KEY = "location_policy"


class DutyEndReason(StrEnum):
    MANUAL = "manual"  # the officer toggled duty off (FA-010)
    AUTO_TIME = "auto_time"  # tenant ``auto_duty_end_local_time`` (VV-007)
    AUTO_IDLE = "auto_idle"  # idle at the home location for ``idle_end_minutes`` (VV-007)
    FORCED = "forced"  # ended by a manager / the server (device lost, forced logout)


class LocationProvider(StrEnum):
    FUSED = "fused"
    GPS = "gps"
    NETWORK = "network"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


_POINT_GEOM = Geometry(geometry_type="POINT", srid=SRID)


def _geo_point(nullable: bool = True) -> Mapped[Any]:
    return mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=nullable
    )


class DutySession(Base, BaseColumns):
    __tablename__ = "duty_session"
    __table_args__ = (
        CheckConstraint(
            f"end_reason IS NULL OR end_reason IN ({_in(DutyEndReason)})", name="end_reason"
        ),
        CheckConstraint("end_at IS NULL OR end_at >= start_at", name="end_after_start"),
        CheckConstraint("(end_at IS NULL) = (end_reason IS NULL)", name="end_reason_with_end"),
        CheckConstraint("km IS NULL OR km >= 0", name="km"),
        Index("ix_duty_session_tenant_officer_start", "tenant_id", "officer_id", "start_at"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="RESTRICT"), nullable=False
    )
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    start_point: Mapped[Any] = _geo_point()
    end_point: Mapped[Any] = _geo_point()
    km: Mapped[Decimal | None] = mapped_column(Numeric(8, 2), nullable=True)  # VV-006 / FA-023
    stops: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, default=list, server_default=text("'[]'::jsonb")
    )
    end_reason: Mapped[str | None] = mapped_column(String(16), nullable=True)
    policy_version: Mapped[str] = mapped_column(String(32), nullable=False)  # VV-010
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    # Read helpers (no geometry parsing in Python).
    start_lon: Mapped[float | None] = column_property(func.ST_X(cast(start_point, _POINT_GEOM)))
    start_lat: Mapped[float | None] = column_property(func.ST_Y(cast(start_point, _POINT_GEOM)))
    end_lon: Mapped[float | None] = column_property(func.ST_X(cast(end_point, _POINT_GEOM)))
    end_lat: Mapped[float | None] = column_property(func.ST_Y(cast(end_point, _POINT_GEOM)))

    @property
    def duration_s(self) -> int | None:
        if self.end_at is None:
            return None
        return int((self.end_at - self.start_at).total_seconds())

    @property
    def auto_ended(self) -> bool:
        return self.end_reason in (
            DutyEndReason.AUTO_TIME,
            DutyEndReason.AUTO_IDLE,
            DutyEndReason.FORCED,
        )


class LocationPoint(Base):
    """Raw on-duty location sample (VV-001 / VV-002 / FA-028). See the module docstring."""

    __tablename__ = "location_point"
    __table_args__ = (
        CheckConstraint(
            f"provider IS NULL OR provider IN ({_in(LocationProvider)})", name="provider"
        ),
        CheckConstraint("battery_pct IS NULL OR battery_pct BETWEEN 0 AND 100", name="battery_pct"),
        CheckConstraint("accuracy_m >= 0", name="accuracy_m"),
        Index("ix_location_point_tenant_officer_ts", "tenant_id", "officer_id", "ts"),
        Index("ix_location_point_duty_session_ts", "duty_session_id", "ts"),
        {"postgresql_partition_by": "RANGE (ts)"},
    )
    __audit__ = False  # high-volume telemetry (FA-006 opt-out); never in the sync feed either

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid, primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()")
    )
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    tenant_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    officer_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)  # user.id (no FK: volume)
    duty_session_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    point: Mapped[Any] = _geo_point(nullable=False)
    accuracy_m: Mapped[float] = mapped_column(Float, nullable=False)
    speed_mps: Mapped[float | None] = mapped_column(Float, nullable=True)
    bearing: Mapped[float | None] = mapped_column(Float, nullable=True)
    battery_pct: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    is_mock: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    is_rooted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    clock_drift_s: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )  # device clock minus server clock at upload (VA-E01 > 300 s)
    provider: Mapped[str | None] = mapped_column(String(16), nullable=True)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    lon: Mapped[float] = column_property(func.ST_X(cast(point, _POINT_GEOM)))
    lat: Mapped[float] = column_property(func.ST_Y(cast(point, _POINT_GEOM)))


class LocationDailyAgg(Base, TenantRow):
    """Per officer and UTC day, what the purge keeps of a track (SPEC 2.6)."""

    __tablename__ = "location_daily_agg"
    __table_args__ = (
        UniqueConstraint("tenant_id", "officer_id", "day"),
        CheckConstraint("km >= 0 AND points >= 0", name="non_negative"),
    )

    officer_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    day: Mapped[date] = mapped_column(Date, nullable=False)
    km: Mapped[Decimal] = mapped_column(Numeric(8, 2), nullable=False)
    points: Mapped[int] = mapped_column(Integer, nullable=False)
    first_ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


class PolicyAcceptance(Base, TenantRow):
    """FA-011 / VV-010: explicit acceptance of the location policy, with its version."""

    __tablename__ = "policy_acceptance"
    __table_args__ = (
        CheckConstraint("char_length(policy_key) > 0 AND char_length(version) > 0", name="keys"),
        Index(
            "ix_policy_acceptance_user_key_accepted",
            "tenant_id",
            "user_id",
            "policy_key",
            "accepted_at",
            postgresql_ops={"accepted_at": "DESC"},
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    policy_key: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=LOCATION_POLICY_KEY,
        server_default=text(f"'{LOCATION_POLICY_KEY}'"),
    )
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    accepted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    text_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)  # sha256 of the text


__all__ = [
    "LOCATION_POLICY_KEY",
    "LOCATION_RETENTION_DAYS",
    "PARTITION_PREFIX",
    "DutyEndReason",
    "DutySession",
    "LocationDailyAgg",
    "LocationPoint",
    "LocationProvider",
    "PolicyAcceptance",
]
