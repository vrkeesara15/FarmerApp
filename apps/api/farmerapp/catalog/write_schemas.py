"""Request / response models of the catalogue write endpoints (WC-005).

Validation that needs no database lives here so the 422 ``validation_error`` names the field
(``errors[].loc``): GST rate from the allowed slabs, HSN of 4, 6 or 8 digits, dose value > 0
with a unit, PHI >= 0, effective ranges. Rules that need the database (barcode uniqueness,
category vs problem type, pest crop scope, duplicate approved claim, price <= MRP, no
overlapping price ranges) are in ``farmerapp.catalog.service`` / ``prices``.
"""

from __future__ import annotations

import re
import uuid
from datetime import date
from decimal import Decimal
from enum import StrEnum
from typing import Any, Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from farmerapp.catalog.models import DoseUnit, PackUnit, ProductCategory
from farmerapp.catalog.schemas import LabelClaimOut, PestOrDiseaseOut, ProductOut, SkuOut

#: GST slabs in basis points (0, 5, 12, 18, 28 %).
GST_RATES_BP: frozenset[int] = frozenset({0, 500, 1200, 1800, 2800})
HSN_RE = re.compile(r"^(\d{4}|\d{6}|\d{8})$")


def check_gst(value: int | None) -> int | None:
    if value is not None and value not in GST_RATES_BP:
        raise ValueError("GST rate must be one of 0, 5, 12, 18 or 28 % (0, 500, 1200, 1800, 2800)")
    return value


def check_hsn(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if value == "":
        return None
    if not HSN_RE.match(value):
        raise ValueError("HSN code must be 4, 6 or 8 digits")
    return value


def _blank_to_none(value: Any) -> Any:
    if isinstance(value, str) and value.strip() == "":
        return None
    return value


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


# --------------------------------------------------------------------------- products
class ProductCreate(_Strict):
    name: str = Field(min_length=1, max_length=200)
    brand: str = Field(min_length=1, max_length=120)
    own_brand: bool = False
    category: ProductCategory
    hsn: str | None = Field(default=None, max_length=8, description="4, 6 or 8 digits.")
    gst_rate_bp: int = Field(description="Basis points: one of 0, 500, 1200, 1800, 2800.")
    description: str | None = Field(default=None, max_length=4000)
    active_ingredient: str | None = Field(default=None, max_length=500)
    formulation: str | None = Field(default=None, max_length=64)
    names: dict[str, str] = Field(default_factory=dict)
    image_uri: str | None = Field(default=None, max_length=512)
    active: bool = True

    @field_validator("hsn", mode="before")
    @classmethod
    def _hsn(cls, value: Any) -> Any:
        value = _blank_to_none(value)
        return check_hsn(value) if isinstance(value, str) or value is None else value

    @field_validator("gst_rate_bp")
    @classmethod
    def _gst(cls, value: int | None) -> int | None:
        return check_gst(value)


class ProductUpdate(_Strict):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    brand: str | None = Field(default=None, min_length=1, max_length=120)
    own_brand: bool | None = None
    category: ProductCategory | None = None
    hsn: str | None = Field(default=None, max_length=8)
    gst_rate_bp: int | None = None
    description: str | None = Field(default=None, max_length=4000)
    active_ingredient: str | None = Field(default=None, max_length=500)
    formulation: str | None = Field(default=None, max_length=64)
    names: dict[str, str] | None = None
    image_uri: str | None = Field(default=None, max_length=512)
    active: bool | None = None
    version: int | None = Field(default=None, description="Optimistic lock (409 when stale).")

    @field_validator("hsn", mode="before")
    @classmethod
    def _hsn(cls, value: Any) -> Any:
        value = _blank_to_none(value)
        return check_hsn(value) if isinstance(value, str) or value is None else value

    @field_validator("gst_rate_bp")
    @classmethod
    def _gst(cls, value: int | None) -> int | None:
        return check_gst(value)


class SkuCreate(_Strict):
    product_id: uuid.UUID
    pack_size_value: Decimal = Field(gt=0, max_digits=10, decimal_places=3)
    pack_size_unit: PackUnit
    barcode: str | None = Field(default=None, max_length=64)
    mrp_paise: int = Field(ge=0, description="Integer paise.")
    active: bool = True

    @field_validator("barcode", mode="before")
    @classmethod
    def _barcode(cls, value: Any) -> Any:
        return _blank_to_none(value)


class SkuUpdate(_Strict):
    pack_size_value: Decimal | None = Field(default=None, gt=0, max_digits=10, decimal_places=3)
    pack_size_unit: PackUnit | None = None
    barcode: str | None = Field(default=None, max_length=64)
    mrp_paise: int | None = Field(default=None, ge=0)
    active: bool | None = None
    version: int | None = None

    @field_validator("barcode", mode="before")
    @classmethod
    def _barcode(cls, value: Any) -> Any:
        return _blank_to_none(value)


class BarcodeLookupOut(SkuOut):
    product: ProductOut


# --------------------------------------------------------------------------- reference data
class CropOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name: str
    names: dict[str, Any]
    active: bool


class CropList(BaseModel):
    items: list[CropOut]


class PestList(BaseModel):
    items: list[PestOrDiseaseOut]


class StoreBriefOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name: str


class StoreBriefList(BaseModel):
    items: list[StoreBriefOut]


# --------------------------------------------------------------------------- label claims
class _ClaimFields(_Strict):
    dose_per_acre: str = Field(min_length=1, max_length=120, description="As on the label.")
    dose_value: Decimal = Field(gt=0, max_digits=10, decimal_places=3, description="Per acre.")
    dose_unit: DoseUnit
    dose_per_tank_15l: str | None = Field(default=None, max_length=64)
    phi_days: int = Field(ge=0, le=365, description="Pre-harvest interval in days.")
    ppe_text: str | None = Field(default=None, max_length=2000)
    safety_text: str | None = Field(default=None, max_length=2000)
    source_ref: str = Field(min_length=1, max_length=200, description="CIB&RC reference.")
    efficacy_tier: int | None = Field(default=None, ge=1, le=3)


class LabelClaimCreate(_ClaimFields):
    sku_id: uuid.UUID
    crop_id: uuid.UUID
    pest_or_disease_id: uuid.UUID


class LabelClaimUpdate(_Strict):
    """Any claim field; the (sku, crop, pest) triple is fixed (a new claim otherwise)."""

    dose_per_acre: str | None = Field(default=None, min_length=1, max_length=120)
    dose_value: Decimal | None = Field(default=None, gt=0, max_digits=10, decimal_places=3)
    dose_unit: DoseUnit | None = None
    dose_per_tank_15l: str | None = Field(default=None, max_length=64)
    phi_days: int | None = Field(default=None, ge=0, le=365)
    ppe_text: str | None = Field(default=None, max_length=2000)
    safety_text: str | None = Field(default=None, max_length=2000)
    source_ref: str | None = Field(default=None, min_length=1, max_length=200)
    efficacy_tier: int | None = Field(default=None, ge=1, le=3)
    version: int | None = None


class LabelClaimList(BaseModel):
    items: list[LabelClaimOut]


class ClaimStatusFilter(StrEnum):
    DRAFT = "draft"
    APPROVED = "approved"
    RETIRED = "retired"
    ALL = "all"


class RecommendableSkuOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    sku_id: uuid.UUID
    product_id: uuid.UUID
    product_name: str
    brand: str
    own_brand: bool
    pack_label: str
    mrp_paise: int
    label_claim_id: uuid.UUID
    dose_per_acre: str
    dose_value: Decimal | None
    dose_unit: str | None
    dose_per_tank_15l: str | None
    phi_days: int | None
    ppe_text: str | None
    safety_text: str | None
    efficacy_tier: int | None


class RecommendableList(BaseModel):
    items: list[RecommendableSkuOut]


# --------------------------------------------------------------------------- price lists
class PriceListOut(BaseModel):
    id: uuid.UUID
    sku_id: uuid.UUID
    store_id: uuid.UUID | None
    price_paise: int
    effective_from: date
    effective_to: date | None
    mrp_paise: int
    version: int


class PriceListList(BaseModel):
    items: list[PriceListOut]


class PriceItemIn(_Strict):
    sku_id: uuid.UUID
    price_paise: int = Field(ge=0)
    effective_from: date
    effective_to: date | None = None

    @model_validator(mode="after")
    def _range(self) -> Self:
        if self.effective_to is not None and self.effective_to < self.effective_from:
            raise ValueError("effective_to must be on or after effective_from")
        return self


class PriceListPut(_Strict):
    store_id: uuid.UUID | None = Field(default=None, description="null = tenant default.")
    items: list[PriceItemIn] = Field(min_length=1, max_length=1000)


# --------------------------------------------------------------------------- import / export
class CatalogKind(StrEnum):
    PRODUCTS = "products"
    LABEL_CLAIMS = "label_claims"


class ImportRequest(_Strict):
    csv: str = Field(min_length=1, max_length=5_000_000)
    dry_run: bool = True


class ImportRowError(BaseModel):
    row: int = Field(description="CSV line number (the header is line 1).")
    column: str | None
    code: str
    message: str


class ImportReport(BaseModel):
    kind: CatalogKind
    dry_run: bool
    applied: bool = Field(description="True only when rows were written (no dry run, no errors).")
    rows_total: int
    rows_ok: int
    created: int
    updated: int
    errors: list[ImportRowError]


__all__ = [
    "GST_RATES_BP",
    "BarcodeLookupOut",
    "CatalogKind",
    "ClaimStatusFilter",
    "CropList",
    "CropOut",
    "ImportReport",
    "ImportRequest",
    "ImportRowError",
    "LabelClaimCreate",
    "LabelClaimList",
    "LabelClaimUpdate",
    "PestList",
    "PriceItemIn",
    "PriceListList",
    "PriceListOut",
    "PriceListPut",
    "ProductCreate",
    "ProductUpdate",
    "RecommendableList",
    "RecommendableSkuOut",
    "SkuCreate",
    "SkuUpdate",
    "StoreBriefList",
    "StoreBriefOut",
    "check_gst",
    "check_hsn",
]
