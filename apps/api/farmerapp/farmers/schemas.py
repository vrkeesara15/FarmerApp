"""Read models for farmers, farms, crop plots and consent (M1-KICKOFF).

Write models (registration, FA-012) come with the registration endpoint. Farm geometry is
returned as GeoJSON (``boundary``) plus the centroid as ``{"lat", "lon"}``; both are loaded
by the ORM as column properties, no geometry parsing in Python.
"""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.db.audit import mask_phone
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer


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
    version: int

    @classmethod
    def from_row(cls, row: CropPlot) -> CropPlotOut:
        return cls.model_validate(row)


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
    crop_plots: list[CropPlotOut] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime
    version: int

    @classmethod
    def from_row(cls, farm: Farm, plots: list[CropPlot] | None = None) -> FarmOut:
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
            crop_plots=[CropPlotOut.from_row(p) for p in plots or []],
            created_at=farm.created_at,
            updated_at=farm.updated_at,
            version=farm.version,
        )


class ConsentRecordOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
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
    version: int

    @classmethod
    def from_row(cls, farmer: Farmer, *, redact_pii: bool = False) -> FarmerOut:
        out = cls.model_validate(farmer)
        if redact_pii:
            out.phone = mask_phone(farmer.phone)
            out.landmark = None
        return out


class FarmerDetailOut(FarmerOut):
    """Farmer 360 (WC-003): the farmer with farms, crop plots and consent history."""

    farms: list[FarmOut] = Field(default_factory=list)
    consents: list[ConsentRecordOut] = Field(default_factory=list)


FarmerPage = PageOut[FarmerOut]

__all__ = [
    "ConsentRecordOut",
    "CropPlotOut",
    "FarmOut",
    "FarmerDetailOut",
    "FarmerOut",
    "FarmerPage",
    "LatLon",
]
