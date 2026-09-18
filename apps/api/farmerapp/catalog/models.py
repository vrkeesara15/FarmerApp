"""Product master (SPEC 8.2 ``product / sku``, ``label_claim``; WC-005, DX-007, FA-020).

* ``product`` — a catalogue item of one brand: own-brand (``own_brand``, SPEC 1.1: the
  tenant's white-label range with 30-50 % margin) or multi-brand. ``category`` drives the
  GST rate (``gst_rate_bp``, basis points: 1800 = 18 %) and HSN code; ``active_ingredient`` /
  ``formulation`` describe agrochemicals (``"Imidacloprid 17.8% SL"``); ``names`` is the
  display name per language (FA-004) with ``name`` the English fallback.
* ``sku`` — a pack size of a product (``pack_size_value`` + ``pack_size_unit``) with its
  barcode (unique per tenant when present; ST-001 scan) and ``mrp_paise``. Money is integer
  paise everywhere (SPEC 8.2; ``tests/catalog/test_models.py`` asserts no money column is
  numeric or float).
* ``price_list`` — the selling price of a SKU: a tenant default (``store_id`` NULL) or a
  store override, valid from ``effective_from`` to ``effective_to`` (NULL = open ended).
  ``farmerapp.catalog.pricing.price_for`` resolves the price for a store and a day.
* ``pest_or_disease`` — the problem master shared with the diagnosis corpus (M6:
  ``corpus_problem.pest_or_disease_id`` references it): ``code`` (unique per tenant),
  ``type`` (disease / pest / nutrient / abiotic), the crop it is specific to (``crop_id``
  NULL = polyphagous / any crop), local names and a short symptom checklist (SPEC 3.2).
* ``label_claim`` — the CIB&RC registration of a SKU for a crop x problem with the label
  dose per acre (text plus numeric ``dose_value`` / ``dose_unit``), the dose per 15 L tank,
  the pre-harvest interval, PPE and safety text (DX-009) and ``source_ref`` (the CIB&RC
  reference; seed rows carry ``SEED_SOURCE_REF`` until the agronomist replaces them — SPEC
  14.6 human gate). ``status`` is ``draft`` until an agronomist approves it (``approved_by``
  / ``approved_at``); **only approved claims may ever back a recommendation** (DX-007, SPEC
  3.4). ``efficacy_tier`` (1 = best) is the agronomist's ranking input for DX-008. Approved
  claims are immutable: an edit is a new draft with ``supersedes_id``; approving it retires
  the superseded version (``retired_by`` / ``retired_at``). ``farmerapp.catalog.recommendable``
  is the single read path for recommendations.

Enumerations are CHECK constraints on short strings (expand-only), like every other table.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


def sql_in(values: type[StrEnum]) -> str:
    """``'a', 'b', 'c'`` for a CHECK constraint over a ``StrEnum``."""
    return ", ".join(f"'{v.value}'" for v in values)


class ProductCategory(StrEnum):
    SEED = "seed"
    FERTILISER = "fertiliser"
    PESTICIDE = "pesticide"
    FUNGICIDE = "fungicide"
    HERBICIDE = "herbicide"
    GROWTH = "growth"  # growth promoters, bio-stimulants
    TOOL = "tool"
    OTHER = "other"


class PackUnit(StrEnum):
    ML = "ml"
    L = "l"
    G = "g"
    KG = "kg"
    PCS = "pcs"


class ProblemType(StrEnum):
    DISEASE = "disease"
    PEST = "pest"
    NUTRIENT = "nutrient"
    ABIOTIC = "abiotic"


class ClaimStatus(StrEnum):
    DRAFT = "draft"
    APPROVED = "approved"
    RETIRED = "retired"


class DoseUnit(StrEnum):
    ML = "ml"
    G = "g"
    L = "l"
    KG = "kg"


#: Basis points: 100 % = 10 000.
BASIS_POINTS = 10_000


class Product(Base, BaseColumns):
    __tablename__ = "product"
    __table_args__ = (
        UniqueConstraint("tenant_id", "brand", "name"),
        CheckConstraint(f"category IN ({sql_in(ProductCategory)})", name="category"),
        CheckConstraint(f"gst_rate_bp >= 0 AND gst_rate_bp <= {BASIS_POINTS}", name="gst_rate_bp"),
        CheckConstraint("char_length(name) > 0 AND char_length(brand) > 0", name="names"),
        Index("ix_product_tenant_category", "tenant_id", "category"),
        Index("ix_product_tenant_own_brand", "tenant_id", "own_brand"),
        Index(
            "ix_product_name_trgm",
            "name",
            postgresql_using="gin",
            postgresql_ops={"name": "gin_trgm_ops"},
        ),
    )

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    brand: Mapped[str] = mapped_column(String(120), nullable=False)
    own_brand: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
    category: Mapped[str] = mapped_column(String(16), nullable=False)
    hsn: Mapped[str | None] = mapped_column(String(8), nullable=True)
    gst_rate_bp: Mapped[int] = mapped_column(Integer, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    active_ingredient: Mapped[str | None] = mapped_column(Text, nullable=True)
    formulation: Mapped[str | None] = mapped_column(String(64), nullable=True)  # SL, EC, WP...
    names: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )
    image_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)
    active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true"), default=True
    )


class Sku(Base, BaseColumns):
    __tablename__ = "sku"
    __table_args__ = (
        UniqueConstraint("tenant_id", "barcode"),
        CheckConstraint(f"pack_size_unit IN ({sql_in(PackUnit)})", name="pack_size_unit"),
        CheckConstraint("pack_size_value > 0", name="pack_size_value"),
        CheckConstraint("mrp_paise >= 0", name="mrp_paise"),
        Index("ix_sku_product_id", "product_id"),
    )

    product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("product.id", ondelete="CASCADE"), nullable=False
    )
    pack_size_value: Mapped[Decimal] = mapped_column(Numeric(10, 3), nullable=False)
    pack_size_unit: Mapped[str] = mapped_column(String(8), nullable=False)
    barcode: Mapped[str | None] = mapped_column(String(64), nullable=True)
    mrp_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true"), default=True
    )

    @property
    def pack_label(self) -> str:
        """``"250 ml"`` / ``"1 kg"``: the pack size without trailing zeros."""
        value = self.pack_size_value.normalize()
        return f"{value:f} {self.pack_size_unit}"


class PriceList(Base, BaseColumns):
    __tablename__ = "price_list"
    __table_args__ = (
        CheckConstraint("price_paise >= 0", name="price_paise"),
        CheckConstraint(
            "effective_to IS NULL OR effective_to >= effective_from", name="effective_range"
        ),
        Index(
            "ix_price_list_sku_store_from",
            "tenant_id",
            "sku_id",
            "store_id",
            "effective_from",
            postgresql_ops={"effective_from": "DESC"},
        ),
    )

    store_id: Mapped[uuid.UUID | None] = mapped_column(  # NULL = tenant default
        ForeignKey("store.id", ondelete="CASCADE"), nullable=True
    )
    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="CASCADE"), nullable=False
    )
    price_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    effective_from: Mapped[date] = mapped_column(Date, nullable=False)
    effective_to: Mapped[date | None] = mapped_column(Date, nullable=True)


class PestOrDisease(Base, BaseColumns):
    __tablename__ = "pest_or_disease"
    __table_args__ = (
        UniqueConstraint("tenant_id", "code"),
        CheckConstraint(f"type IN ({sql_in(ProblemType)})", name="type"),
        Index("ix_pest_or_disease_crop_id", "crop_id"),
    )

    code: Mapped[str] = mapped_column(String(48), nullable=False)  # paddy_blast, aphids...
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    names: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )
    type: Mapped[str] = mapped_column(String(16), nullable=False)
    crop_id: Mapped[uuid.UUID | None] = mapped_column(  # NULL = any crop (polyphagous)
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=True
    )
    scientific_name: Mapped[str | None] = mapped_column(String(160), nullable=True)
    symptoms: Mapped[str | None] = mapped_column(Text, nullable=True)  # SPEC 3.2 checklist
    active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("true"), default=True
    )


class LabelClaim(Base, BaseColumns):
    __tablename__ = "label_claim"
    __table_args__ = (
        # At most one *approved* version per (sku, crop, pest); drafts / retired versions of
        # the same claim coexist (0014: edits of an approved claim are new draft versions).
        Index(
            "uq_label_claim_approved",
            "tenant_id",
            "sku_id",
            "crop_id",
            "pest_or_disease_id",
            unique=True,
            postgresql_where=text("status = 'approved' AND deleted_at IS NULL"),
        ),
        Index("ix_label_claim_supersedes_id", "supersedes_id"),
        CheckConstraint(f"status IN ({sql_in(ClaimStatus)})", name="status"),
        CheckConstraint(
            f"dose_unit IS NULL OR dose_unit IN ({sql_in(DoseUnit)})", name="dose_unit"
        ),
        CheckConstraint("dose_value IS NULL OR dose_value > 0", name="dose_value"),
        CheckConstraint("phi_days IS NULL OR phi_days >= 0", name="phi_days"),
        CheckConstraint(
            "efficacy_tier IS NULL OR efficacy_tier BETWEEN 1 AND 3", name="efficacy_tier"
        ),
        CheckConstraint("status <> 'approved' OR approved_at IS NOT NULL", name="approved_at"),
        CheckConstraint("char_length(source_ref) > 0", name="source_ref"),
        Index("ix_label_claim_crop_pest", "tenant_id", "crop_id", "pest_or_disease_id", "status"),
        Index("ix_label_claim_pest_or_disease_id", "pest_or_disease_id"),
    )

    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="CASCADE"), nullable=False
    )
    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    pest_or_disease_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("pest_or_disease.id", ondelete="RESTRICT"), nullable=False
    )
    dose_per_acre: Mapped[str] = mapped_column(String(120), nullable=False)  # as on the label
    dose_value: Mapped[Decimal | None] = mapped_column(Numeric(10, 3), nullable=True)
    dose_unit: Mapped[str | None] = mapped_column(String(8), nullable=True)  # per acre
    dose_per_tank_15l: Mapped[str | None] = mapped_column(String(64), nullable=True)
    phi_days: Mapped[int | None] = mapped_column(Integer, nullable=True)  # pre-harvest interval
    ppe_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    safety_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_ref: Mapped[str] = mapped_column(String(200), nullable=False)
    efficacy_tier: Mapped[int | None] = mapped_column(Integer, nullable=True)  # DX-008 input
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'draft'"), default=ClaimStatus.DRAFT
    )
    approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    retired_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    retired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    #: The approved claim this draft is a new version of (approved claims are immutable).
    supersedes_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("label_claim.id", ondelete="SET NULL"), nullable=True
    )

    @property
    def approved(self) -> bool:
        return self.status == ClaimStatus.APPROVED


#: Marks seed-fixture claims that a human must replace with CIB&RC data (SPEC 14.6).
SEED_SOURCE_REF = "seed-fixture — replace with CIB&RC data (human gate)"

__all__ = [
    "BASIS_POINTS",
    "SEED_SOURCE_REF",
    "ClaimStatus",
    "DoseUnit",
    "LabelClaim",
    "PackUnit",
    "PestOrDisease",
    "PriceList",
    "ProblemType",
    "Product",
    "ProductCategory",
    "Sku",
    "sql_in",
]
