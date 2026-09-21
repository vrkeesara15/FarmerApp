"""Read and write models for farmers, farms, crop plots and consent (M1-KICKOFF, FA-012).

Farm geometry is exchanged as GeoJSON (``boundary``) plus the centroid as ``{"lat", "lon"}``;
reads are loaded by the ORM as column properties, writes are validated here (a closed ring
of at least four WGS84 positions) and by PostGIS in the service (``ST_IsValid``).

The write models double as the payloads of ``POST /v1/sync`` operations: ``FarmerCreate`` is
a ``farmer.create`` op, ``FarmerUpdate`` a ``farmer.update`` and so on; the client-generated
``id`` fields let the app choose ids offline.
"""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from farmerapp.api.pagination import PageOut
from farmerapp.auth.schemas import AssignedOfficerOut, Phone
from farmerapp.db.audit import mask_phone
from farmerapp.farmers.models import (
    ConsentPurpose,
    ConsentRecord,
    CropPlot,
    CropStage,
    Farm,
    Farmer,
    FarmPhoto,
    IrrigationType,
    LandOwnership,
    Season,
    SoilType,
)

# --------------------------------------------------------------------------- read models


class LatLon(BaseModel):
    lat: float
    lon: float


class CropPlotOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    farm_id: uuid.UUID
    crop_id: uuid.UUID
    variety: str | None
    season: str
    sowing_date: date
    stage: str | None
    expected_harvest: date | None
    area_acres: Decimal | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: CropPlot) -> CropPlotOut:
        return cls.model_validate(row)


class FarmPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    blob_uri: str
    sha256: str | None
    taken_at: datetime | None
    location: LatLon | None = None

    @classmethod
    def from_row(cls, row: FarmPhoto) -> FarmPhotoOut:
        location = (
            LatLon(lat=row.location_lat, lon=row.location_lon)
            if row.location_lat is not None and row.location_lon is not None
            else None
        )
        return cls(
            id=row.id,
            blob_uri=row.blob_uri,
            sha256=row.sha256,
            taken_at=row.taken_at,
            location=location,
        )


class FarmOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    farmer_id: uuid.UUID
    name: str | None
    survey_no: str | None
    boundary: dict[str, Any] | None = Field(description="GeoJSON Polygon (WGS84).")
    centroid: LatLon | None
    area_acres: Decimal = Field(description="Declared by the officer / farmer.")
    area_acres_computed: Decimal | None = Field(description="ST_Area of the boundary in acres.")
    soil: str | None
    irrigation: str | None
    ownership: str | None
    photos: list[FarmPhotoOut] = Field(default_factory=list)
    crop_plots: list[CropPlotOut] = Field(default_factory=list)
    warnings: list[str] = Field(
        default_factory=list,
        description="VA-F03 soft checks on this write: `area_mismatch`, `farm_overlap`.",
    )
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(
        cls,
        farm: Farm,
        plots: list[CropPlot] | None = None,
        photos: list[FarmPhoto] | None = None,
        warnings: list[str] | None = None,
    ) -> FarmOut:
        boundary = json.loads(farm.boundary_geojson) if farm.boundary_geojson else None
        centroid = (
            LatLon(lat=farm.centroid_lat, lon=farm.centroid_lon)
            if farm.centroid_lat is not None and farm.centroid_lon is not None
            else None
        )
        return cls(
            id=farm.id,
            farmer_id=farm.farmer_id,
            name=farm.name,
            survey_no=farm.survey_no,
            boundary=boundary,
            centroid=centroid,
            area_acres=farm.area_acres,
            area_acres_computed=farm.area_acres_computed,
            soil=farm.soil,
            irrigation=farm.irrigation,
            ownership=farm.ownership,
            photos=[FarmPhotoOut.from_row(p) for p in photos or []],
            crop_plots=[CropPlotOut.from_row(p) for p in plots or []],
            warnings=list(warnings or []),
            created_at=farm.created_at,
            updated_at=farm.updated_at,
            deleted_at=farm.deleted_at,
            version=farm.version,
        )


class ConsentRecordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    subject_id: uuid.UUID
    purpose: str
    version: str
    language: str | None
    granted_at: datetime | None
    withdrawn_at: datetime | None
    channel: str
    recorded_by: uuid.UUID | None
    created_at: datetime

    @classmethod
    def from_row(cls, row: ConsentRecord) -> ConsentRecordOut:
        return cls.model_validate(row)


class FarmerOut(BaseModel):
    """Directory row. ``phone`` is masked for roles that read crop data only (agronomist)."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    phone: str
    phone_last4: str
    phone_verified: bool
    name: str
    village_id: uuid.UUID
    landmark: str | None
    language: str
    consent_marketing: bool
    consent_version: str | None
    registered_by: uuid.UUID | None
    user_id: uuid.UUID | None
    source: str
    land_ownership: str | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, farmer: Farmer, *, redact_pii: bool = False) -> FarmerOut:
        out = cls.model_validate(farmer)
        if redact_pii:
            out.phone = mask_phone(farmer.phone)
            out.landmark = None
        return out


class FarmerDetailOut(FarmerOut):
    """Farmer 360 (WC-003): the farmer with farms, crop plots and consent history.

    ``warnings`` is the union of the farms' VA-F03 warnings on a write (empty on reads).
    """

    farms: list[FarmOut] = Field(default_factory=list)
    consents: list[ConsentRecordOut] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    referral_id: uuid.UUID | None = Field(
        default=None,
        description="FM-013 (writes only): the referral this registration was attributed to.",
    )
    officer: AssignedOfficerOut | None = Field(
        default=None,
        description=(
            "FM-011 / F62 (reads only): the registering field officer while active, else the "
            "active field officer of the village's store; phone masked unless the reader is "
            "the farmer, the officer or a user-profile reader role."
        ),
    )


FarmerPage = PageOut[FarmerOut]


# --------------------------------------------------------------------------- write models
Acres = Annotated[Decimal, Field(gt=0, le=Decimal("9999.99"), decimal_places=2)]
# Enumerations are the model StrEnums: validated from their string values, serialised as
# strings, and assignable to the CHECK-constrained ``String`` columns.

MAX_RING_POINTS = 500


class GeoJsonPolygon(BaseModel):
    """A GeoJSON Polygon: one outer ring (holes are not accepted for farm boundaries)."""

    type: Literal["Polygon"]
    coordinates: list[list[list[float]]] = Field(min_length=1, max_length=1)

    @field_validator("coordinates")
    @classmethod
    def _closed_ring(cls, rings: list[list[list[float]]]) -> list[list[list[float]]]:
        ring = rings[0]
        if not 4 <= len(ring) <= MAX_RING_POINTS:
            raise ValueError("a polygon ring needs 4 to 500 positions (first == last)")
        for pos in ring:
            if len(pos) < 2:
                raise ValueError("each position is [lon, lat]")
            lon, lat = pos[0], pos[1]
            if not (-180 <= lon <= 180 and -90 <= lat <= 90):
                raise ValueError("positions must be WGS84 [lon, lat]")
        if ring[0][:2] != ring[-1][:2]:
            raise ValueError("the ring must be closed (first position == last)")
        return [[[p[0], p[1]] for p in ring]]

    def ewkt(self) -> str:
        ring = ", ".join(f"{lon:.7f} {lat:.7f}" for lon, lat in self.coordinates[0])
        return f"SRID=4326;POLYGON(({ring}))"


class CropPlotCreate(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client-generated id (offline).")
    crop_id: uuid.UUID
    variety: str | None = Field(default=None, max_length=80)
    season: Season
    sowing_date: date
    stage: CropStage | None = None
    expected_harvest: date | None = None
    area_acres: Acres | None = None


class CropPlotUpdate(BaseModel):
    version: int | None = Field(default=None, description="Expected current version (409).")
    crop_id: uuid.UUID | None = None
    variety: str | None = Field(default=None, max_length=80)
    season: Season | None = None
    sowing_date: date | None = None
    stage: CropStage | None = None
    expected_harvest: date | None = None
    area_acres: Acres | None = None


class FarmCreate(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client-generated id (offline).")
    name: str | None = Field(default=None, max_length=120)
    survey_no: str | None = Field(default=None, max_length=64)
    boundary: GeoJsonPolygon | None = None
    area_acres: Acres = Field(description="Declared acres.")
    soil: SoilType | None = None
    irrigation: IrrigationType | None = None
    ownership: LandOwnership | None = None
    photos: list[str] = Field(
        default_factory=list, max_length=20, description="`blob_uri`s of completed uploads."
    )
    crop_plots: list[CropPlotCreate] = Field(default_factory=list, max_length=50)


class FarmUpdate(BaseModel):
    version: int | None = Field(default=None, description="Expected current version (409).")
    name: str | None = Field(default=None, max_length=120)
    survey_no: str | None = Field(default=None, max_length=64)
    boundary: GeoJsonPolygon | None = None
    area_acres: Acres | None = None
    soil: SoilType | None = None
    irrigation: IrrigationType | None = None
    ownership: LandOwnership | None = None
    photos: list[str] | None = Field(default=None, max_length=20)


class ConsentIn(BaseModel):
    purpose: ConsentPurpose
    granted: bool
    language: str | None = Field(default=None, max_length=8)


class FarmerCreate(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client-generated id (offline).")
    phone: Phone
    name: str = Field(min_length=1, max_length=200)
    village_id: uuid.UUID
    landmark: str | None = Field(default=None, max_length=200)
    language: str = Field(default="te", min_length=2, max_length=8)
    land_ownership: LandOwnership | None = None
    farms: list[FarmCreate] = Field(default_factory=list, max_length=20)
    consents: list[ConsentIn] = Field(default_factory=list, max_length=4)
    phone_verification_token: str | None = Field(
        default=None,
        max_length=1024,
        description="From `POST /v1/farmers/phone/verify/confirm`; absent for offline capture.",
    )
    referral_code: str | None = Field(
        default=None,
        max_length=24,
        description="FM-013: the invite code the farmer was referred with. A code that cannot "
        "be attributed never fails the registration — the reason comes back in `warnings`.",
    )

    @model_validator(mode="after")
    def _one_consent_per_purpose(self) -> FarmerCreate:
        purposes = [c.purpose for c in self.consents]
        if len(purposes) != len(set(purposes)):
            raise ValueError("one consent entry per purpose")
        return self


class FarmerUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")  # in particular: no `phone` (re-verification)

    version: int | None = Field(default=None, description="Expected current version (409).")
    name: str | None = Field(default=None, min_length=1, max_length=200)
    village_id: uuid.UUID | None = None
    landmark: str | None = Field(default=None, max_length=200)
    language: str | None = Field(default=None, min_length=2, max_length=8)
    land_ownership: LandOwnership | None = None


class ConsentCreate(ConsentIn):
    """``POST /v1/farmers/{id}/consents``: append a grant or a withdrawal."""


class PhoneVerifySendRequest(BaseModel):
    phone: Phone


class PhoneVerifyConfirmRequest(BaseModel):
    phone: Phone
    code: str = Field(pattern=r"^\d{6}$")


class PhoneVerifyCodeRequest(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")


class PhoneVerifySendResponse(BaseModel):
    challenge_id: uuid.UUID
    phone_masked: str
    channel: Literal["sms", "whatsapp"]
    expires_in: int
    resend_after: int
    resends_left: int


class PhoneVerificationTokenOut(BaseModel):
    phone_verification_token: str
    expires_in: int = Field(description="Seconds the token stays valid (30 min).")


__all__ = [
    "Acres",
    "ConsentCreate",
    "ConsentIn",
    "ConsentRecordOut",
    "CropPlotCreate",
    "CropPlotOut",
    "CropPlotUpdate",
    "FarmCreate",
    "FarmOut",
    "FarmPhotoOut",
    "FarmUpdate",
    "FarmerCreate",
    "FarmerDetailOut",
    "FarmerOut",
    "FarmerPage",
    "FarmerUpdate",
    "GeoJsonPolygon",
    "LatLon",
    "PhoneVerificationTokenOut",
    "PhoneVerifyCodeRequest",
    "PhoneVerifyConfirmRequest",
    "PhoneVerifySendRequest",
    "PhoneVerifySendResponse",
]
