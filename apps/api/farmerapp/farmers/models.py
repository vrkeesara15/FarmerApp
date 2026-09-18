"""Farmers, farms, crop plots and consent records (SPEC 8.2; FA-012, FA-013, FM-002).

* ``farmer`` — one row per farmer per tenant, unique on ``(tenant_id, phone)`` (FA-012
  "duplicate phone blocked"). ``phone_last4`` is kept next to the phone so the directory can
  search by the last digits once SEC-026 encrypts the full number. ``consent_marketing`` /
  ``consent_version`` cache the latest ``consent_record`` (the record is the source of truth).
  ``registered_by`` is the officer's ``user.id`` (SPEC 2.6 "own farmers"); ``user_id`` links
  the farmer's own login (FM-001) for the "farmer sees own profile" scope.
* ``farm`` — a farmer has many farms (FA-013). ``boundary`` is ``geography(Polygon, 4326)``;
  ``centroid`` and ``area_acres_computed`` are **stored generated columns** (PostGIS
  ``ST_Centroid`` / ``ST_Area`` on the spheroid, both IMMUTABLE), so VA-F02 (centroid within
  50 m) and VA-F03 (declared vs measured acres, overlap) are plain SQL over indexed columns
  and the ORM never has to compute geometry in Python. ``area_acres`` is what the officer
  declared.
* ``crop_plot`` — a crop on a farm in a season (many per farm; FA-013 "3 crop plots").
* ``farm_photo`` — photos of a farm boundary walk (FA-012): the blob URI from a completed
  NF-003 upload, its sha256, when it was taken and the EXIF point if the device had one.
* ``consent_record`` — append-only (FM-002, NF-013): granting and withdrawing are *rows*,
  never updates; the latest row per ``(subject, purpose)`` is the current state. The app role
  cannot UPDATE or DELETE it (``APPEND_ONLY_TABLES``).

Enumerations are CHECK constraints on short strings (same style as ``user.role``) so adding
a value is an expand-only migration.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from geoalchemy2 import Geography, Geometry
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Computed,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Numeric,
    String,
    UniqueConstraint,
    Uuid,
    cast,
    func,
    text,
)
from sqlalchemy.orm import Mapped, column_property, declared_attr, mapped_column

from farmerapp.db.base import Base, BaseColumns, TenantRow
from farmerapp.db.geo import ACRE_M2, SRID


class FarmerSource(StrEnum):
    OFFICER = "officer"  # registered by a field officer in the agent app (FA-012)
    APP = "app"  # self-registered in the farmer app (FM-001)
    IMPORT = "import"  # bulk import by the tenant admin


class LandOwnership(StrEnum):
    OWN = "own"
    LEASED = "leased"


class SoilType(StrEnum):
    BLACK = "black"
    RED = "red"
    SANDY = "sandy"
    LOAMY = "loamy"
    CLAY = "clay"
    ALLUVIAL = "alluvial"
    LATERITE = "laterite"


class IrrigationType(StrEnum):
    RAINFED = "rainfed"
    BOREWELL = "borewell"
    CANAL = "canal"
    TANK = "tank"
    OPEN_WELL = "open_well"
    DRIP = "drip"
    SPRINKLER = "sprinkler"


class Season(StrEnum):
    KHARIF = "kharif"  # June-October (monsoon)
    RABI = "rabi"  # November-March
    ZAID = "zaid"  # summer


class CropStage(StrEnum):
    SOWN = "sown"
    VEGETATIVE = "vegetative"
    FLOWERING = "flowering"
    FRUITING = "fruiting"
    MATURITY = "maturity"
    HARVESTED = "harvested"


class ConsentSubject(StrEnum):
    FARMER = "farmer"
    USER = "user"  # FA-011 location policy acceptance reuses the table later


class ConsentPurpose(StrEnum):
    DATA = "data"  # processing of registration data (required to use the service)
    MARKETING = "marketing"  # promotional messages; separately withdrawable (FM-002)


class ConsentChannel(StrEnum):
    OFFICER = "officer"  # captured by the officer during registration, farmer present
    APP = "app"  # the farmer's own app (FM-002 screen)
    SMS = "sms"
    WHATSAPP = "whatsapp"
    IVR = "ivr"
    PAPER = "paper"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


#: Consent text version used when ``tenant.settings["consent_version"]`` is not set.
#: TODO-LEGAL: placeholder until the legal copy is approved (SPEC 14.6 human gate).
DEFAULT_CONSENT_VERSION = "2026-09-v1"

_POINT_GEOM = Geometry(geometry_type="POINT", srid=SRID)


class Farmer(Base, BaseColumns):
    __tablename__ = "farmer"
    __table_args__ = (
        UniqueConstraint("tenant_id", "phone"),
        CheckConstraint(f"source IN ({_in(FarmerSource)})", name="source"),
        CheckConstraint(
            f"land_ownership IS NULL OR land_ownership IN ({_in(LandOwnership)})",
            name="land_ownership",
        ),
        CheckConstraint("char_length(phone_last4) = 4", name="phone_last4"),
        Index("ix_farmer_village_id", "village_id"),
        Index("ix_farmer_registered_by", "registered_by"),
        Index("ix_farmer_user_id", "user_id"),
        Index("ix_farmer_tenant_phone_last4", "tenant_id", "phone_last4"),
        # VA-F02 fuzzy name match and the directory search (pg_trgm, installed by 0001).
        Index(
            "ix_farmer_name_trgm",
            "name",
            postgresql_using="gin",
            postgresql_ops={"name": "gin_trgm_ops"},
        ),
    )

    phone: Mapped[str] = mapped_column(String(16), nullable=False)
    phone_last4: Mapped[str] = mapped_column(String(4), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    village_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("village.id", ondelete="RESTRICT"), nullable=False
    )
    landmark: Mapped[str | None] = mapped_column(String(200), nullable=True)
    language: Mapped[str] = mapped_column(String(8), nullable=False, server_default=text("'te'"))
    consent_marketing: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
    consent_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    registered_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    source: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'officer'"), default=FarmerSource.OFFICER
    )
    land_ownership: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # FA-012 / VA-F01: set when the farmer confirmed an OTP (at registration through a
    # ``phone_verification_token``, or later on the record); false for offline captures.
    phone_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )

    @staticmethod
    def last4(phone: str) -> str:
        return phone[-4:]


class Farm(Base, BaseColumns):
    __tablename__ = "farm"
    __table_args__ = (
        CheckConstraint(f"soil IS NULL OR soil IN ({_in(SoilType)})", name="soil"),
        CheckConstraint(
            f"irrigation IS NULL OR irrigation IN ({_in(IrrigationType)})", name="irrigation"
        ),
        CheckConstraint(
            f"ownership IS NULL OR ownership IN ({_in(LandOwnership)})", name="ownership"
        ),
        CheckConstraint("area_acres > 0", name="area_acres"),
        Index("ix_farm_farmer_id", "farmer_id"),
        Index("ix_farm_boundary", "boundary", postgresql_using="gist"),
        Index("ix_farm_centroid", "centroid", postgresql_using="gist"),
    )

    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    survey_no: Mapped[str | None] = mapped_column(String(64), nullable=True)
    boundary: Mapped[Any] = mapped_column(
        Geography(geometry_type="POLYGON", srid=SRID, spatial_index=False), nullable=True
    )
    area_acres: Mapped[Decimal] = mapped_column(Numeric(8, 2), nullable=False)  # declared
    soil: Mapped[str | None] = mapped_column(String(16), nullable=True)
    irrigation: Mapped[str | None] = mapped_column(String(16), nullable=True)
    ownership: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # Generated by the database from ``boundary`` (NULL when there is no boundary yet).
    centroid: Mapped[Any] = mapped_column(
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False),
        Computed("ST_Centroid(boundary)", persisted=True),
        nullable=True,
    )
    area_acres_computed: Mapped[Decimal | None] = mapped_column(
        Numeric(10, 3),
        Computed(f"(ST_Area(boundary) / {ACRE_M2})::numeric(10, 3)", persisted=True),
        nullable=True,
    )
    # Read helpers loaded with the row (no geometry parsing in Python).
    boundary_geojson: Mapped[str | None] = column_property(func.ST_AsGeoJSON(boundary))
    centroid_lon: Mapped[float | None] = column_property(func.ST_X(cast(centroid, _POINT_GEOM)))
    centroid_lat: Mapped[float | None] = column_property(func.ST_Y(cast(centroid, _POINT_GEOM)))

    @declared_attr.directive
    def __mapper_args__(cls) -> dict[str, Any]:
        # eager_defaults: fetch the generated columns with RETURNING on INSERT/UPDATE so
        # ``farm.centroid`` / ``farm.area_acres_computed`` are usable right after a flush.
        return {"version_id_col": cls.version, "eager_defaults": True}


class FarmPhoto(Base, BaseColumns):
    __tablename__ = "farm_photo"
    __table_args__ = (
        Index("ix_farm_photo_farm_id", "farm_id"),
        CheckConstraint("char_length(blob_uri) > 0", name="blob_uri"),
    )

    farm_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farm.id", ondelete="CASCADE"), nullable=False
    )
    blob_uri: Mapped[str] = mapped_column(String(512), nullable=False)  # gs://bucket/key
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    taken_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    location: Mapped[Any] = mapped_column(  # EXIF point, if the device recorded one
        Geography(geometry_type="POINT", srid=SRID, spatial_index=False), nullable=True
    )
    location_lon: Mapped[float | None] = column_property(func.ST_X(cast(location, _POINT_GEOM)))
    location_lat: Mapped[float | None] = column_property(func.ST_Y(cast(location, _POINT_GEOM)))


class CropPlot(Base, BaseColumns):
    __tablename__ = "crop_plot"
    __table_args__ = (
        CheckConstraint(f"season IN ({_in(Season)})", name="season"),
        CheckConstraint(f"stage IS NULL OR stage IN ({_in(CropStage)})", name="stage"),
        CheckConstraint("area_acres IS NULL OR area_acres > 0", name="area_acres"),
        Index("ix_crop_plot_farm_id", "farm_id"),
        Index("ix_crop_plot_crop_id", "crop_id"),
    )

    farm_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farm.id", ondelete="CASCADE"), nullable=False
    )
    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    variety: Mapped[str | None] = mapped_column(String(80), nullable=True)
    season: Mapped[str] = mapped_column(String(8), nullable=False)
    sowing_date: Mapped[date] = mapped_column(Date, nullable=False)
    stage: Mapped[str | None] = mapped_column(String(16), nullable=True)
    expected_harvest: Mapped[date | None] = mapped_column(Date, nullable=True)
    area_acres: Mapped[Decimal | None] = mapped_column(Numeric(8, 2), nullable=True)


class ConsentRecord(Base, TenantRow):
    """Append-only: a grant is a row with ``granted_at``; a withdrawal is a *new* row with
    ``withdrawn_at`` (exactly one of the two is set). ``version`` is the consent text version
    the subject saw (human gate: legal copy, SPEC 14.6)."""

    __tablename__ = "consent_record"
    __table_args__ = (
        CheckConstraint(f"subject_type IN ({_in(ConsentSubject)})", name="subject_type"),
        CheckConstraint(f"purpose IN ({_in(ConsentPurpose)})", name="purpose"),
        CheckConstraint(f"channel IN ({_in(ConsentChannel)})", name="channel"),
        CheckConstraint("(granted_at IS NULL) <> (withdrawn_at IS NULL)", name="one_event"),
        Index(
            "ix_consent_record_subject_purpose_created",
            "tenant_id",
            "subject_id",
            "purpose",
            "created_at",
            postgresql_ops={"created_at": "DESC"},
        ),
    )

    # Wall clock, not the transaction's now(): a grant and its withdrawal written in one
    # transaction must still order (the latest row per subject/purpose is the current state).
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
        server_default=func.now(),
    )
    subject_type: Mapped[str] = mapped_column(String(16), nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    purpose: Mapped[str] = mapped_column(String(32), nullable=False)
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    language: Mapped[str | None] = mapped_column(String(8), nullable=True)  # text shown in
    granted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    withdrawn_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    channel: Mapped[str] = mapped_column(String(16), nullable=False)
    recorded_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)  # user.id

    @property
    def granted(self) -> bool:
        return self.granted_at is not None


__all__ = [
    "DEFAULT_CONSENT_VERSION",
    "ConsentChannel",
    "ConsentPurpose",
    "ConsentRecord",
    "ConsentSubject",
    "CropPlot",
    "CropStage",
    "Farm",
    "FarmPhoto",
    "Farmer",
    "FarmerSource",
    "IrrigationType",
    "LandOwnership",
    "Season",
    "SoilType",
]
