"""Read models for the catalogue endpoints (WC-005, FA-020, DX-007)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.catalog.models import LabelClaim, PestOrDisease, Product, Sku


class SkuOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    product_id: uuid.UUID
    pack_size_value: Decimal
    pack_size_unit: str
    pack_label: str
    barcode: str | None
    mrp_paise: int
    active: bool
    price_paise: int = Field(
        description="Selling price resolved for the requested store (or the tenant default), "
        "falling back to the MRP."
    )
    stock_qty: Decimal | None = Field(
        default=None,
        description="On hand at `store_id` (sum of the movement ledger); "
        "null when no store was given.",
    )
    created_at: datetime
    updated_at: datetime
    version: int

    @classmethod
    def from_row(cls, sku: Sku, *, price_paise: int, stock_qty: Decimal | None = None) -> SkuOut:
        return cls(
            id=sku.id,
            product_id=sku.product_id,
            pack_size_value=sku.pack_size_value,
            pack_size_unit=sku.pack_size_unit,
            pack_label=sku.pack_label,
            barcode=sku.barcode,
            mrp_paise=sku.mrp_paise,
            active=sku.active,
            price_paise=price_paise,
            stock_qty=stock_qty,
            created_at=sku.created_at,
            updated_at=sku.updated_at,
            version=sku.version,
        )


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    brand: str
    own_brand: bool
    category: str
    hsn: str | None
    gst_rate_bp: int
    description: str | None
    active_ingredient: str | None
    formulation: str | None
    names: dict[str, Any]
    image_uri: str | None
    active: bool
    created_at: datetime
    updated_at: datetime
    version: int


class ProductWithSkusOut(ProductOut):
    skus: list[SkuOut]

    @classmethod
    def from_row(cls, product: Product, skus: list[SkuOut]) -> ProductWithSkusOut:
        return cls(**ProductOut.model_validate(product).model_dump(), skus=skus)


class PestOrDiseaseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    code: str
    name: str
    names: dict[str, Any]
    type: str
    crop_id: uuid.UUID | None
    scientific_name: str | None
    symptoms: str | None
    active: bool


class LabelClaimOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    sku_id: uuid.UUID
    crop_id: uuid.UUID
    pest_or_disease_id: uuid.UUID
    dose_per_acre: str
    dose_value: Decimal | None
    dose_unit: str | None
    dose_per_tank_15l: str | None
    phi_days: int | None
    ppe_text: str | None
    safety_text: str | None
    source_ref: str
    efficacy_tier: int | None
    status: str
    approved_by: uuid.UUID | None
    approved_at: datetime | None
    created_at: datetime
    updated_at: datetime
    version: int
    pest_or_disease: PestOrDiseaseOut | None = None

    @classmethod
    def from_row(cls, claim: LabelClaim, pest: PestOrDisease | None = None) -> LabelClaimOut:
        out = cls.model_validate(claim)
        if pest is not None:
            out.pest_or_disease = PestOrDiseaseOut.model_validate(pest)
        return out


class SkuDetailOut(SkuOut):
    product: ProductOut
    label_claims: list[LabelClaimOut] = Field(
        description="Approved claims; drafts and retired claims only for the agronomist / owner."
    )


class ProductPage(PageOut[ProductWithSkusOut]):
    pass


class LabelClaimPage(PageOut[LabelClaimOut]):
    pass


class PriceOut(BaseModel):
    sku_id: uuid.UUID
    store_id: uuid.UUID | None
    at: date
    price_paise: int


__all__ = [
    "LabelClaimOut",
    "LabelClaimPage",
    "PestOrDiseaseOut",
    "PriceOut",
    "ProductOut",
    "ProductPage",
    "ProductWithSkusOut",
    "SkuDetailOut",
    "SkuOut",
]
