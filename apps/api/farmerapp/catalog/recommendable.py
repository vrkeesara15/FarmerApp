"""The recommendation guardrail (WC-005 acceptance, DX-007, SPEC 3.4).

A SKU may be recommended for a crop and a pest / disease **only** when it has an *approved*,
not retired, not deleted label claim for exactly that crop and that problem. This module is
the single place that answers the question:

* ``recommendable_skus(session, tenant_id=, crop_id=, pest_or_disease_id=)`` — the SKUs that
  may be recommended, each carrying the claim's dose per acre, dose per 15 L tank, PHI, PPE and
  safety text (every chemical recommendation shows them, SPEC 3.4). The DX-007 treatment
  engine ranks this list (own brand first, then efficacy tier — DX-008); it must never add to
  it.
* ``assert_sku_recommendable(session, tenant_id=, sku_id=, label_claim_id=, ...)`` — the
  validator for any code path that attaches a ``label_claim_id`` to an order line (FA-020)
  or a treatment (DX-007): raises ``SkuNotRecommendable`` (422 ``sku_not_recommendable``)
  unless the claim is approved, live and belongs to that SKU (and crop / pest when given).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import ColumnElement, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.errors import SkuNotRecommendable
from farmerapp.catalog.models import ClaimStatus, LabelClaim, Product, Sku


@dataclass(frozen=True)
class RecommendableSku:
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


def _live_approved(tenant_id: uuid.UUID) -> list[ColumnElement[bool]]:
    """WHERE clauses: an approved, live claim on an active, live SKU of an active product."""
    return [
        LabelClaim.tenant_id == tenant_id,
        LabelClaim.status == ClaimStatus.APPROVED.value,
        LabelClaim.deleted_at.is_(None),
        LabelClaim.approved_at.is_not(None),
        Sku.deleted_at.is_(None),
        Sku.active.is_(True),
        Product.deleted_at.is_(None),
        Product.active.is_(True),
    ]


async def recommendable_skus(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    crop_id: uuid.UUID,
    pest_or_disease_id: uuid.UUID,
) -> list[RecommendableSku]:
    """SKUs with an approved label claim for exactly ``crop_id`` x ``pest_or_disease_id``."""
    stmt = (
        select(LabelClaim, Sku, Product)
        .join(Sku, Sku.id == LabelClaim.sku_id)
        .join(Product, Product.id == Sku.product_id)
        .where(
            *_live_approved(tenant_id),
            LabelClaim.crop_id == crop_id,
            LabelClaim.pest_or_disease_id == pest_or_disease_id,
        )
        .order_by(
            Product.own_brand.desc(),
            LabelClaim.efficacy_tier.asc().nulls_last(),
            Product.name,
            Sku.pack_size_value,
            Sku.id,
        )
    )
    out: list[RecommendableSku] = []
    for claim, sku, product in (await session.execute(stmt)).tuples():
        out.append(
            RecommendableSku(
                sku_id=sku.id,
                product_id=product.id,
                product_name=product.name,
                brand=product.brand,
                own_brand=product.own_brand,
                pack_label=sku.pack_label,
                mrp_paise=sku.mrp_paise,
                label_claim_id=claim.id,
                dose_per_acre=claim.dose_per_acre,
                dose_value=claim.dose_value,
                dose_unit=claim.dose_unit,
                dose_per_tank_15l=claim.dose_per_tank_15l,
                phi_days=claim.phi_days,
                ppe_text=claim.ppe_text,
                safety_text=claim.safety_text,
                efficacy_tier=claim.efficacy_tier,
            )
        )
    return out


async def assert_sku_recommendable(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    sku_id: uuid.UUID,
    label_claim_id: uuid.UUID,
    crop_id: uuid.UUID | None = None,
    pest_or_disease_id: uuid.UUID | None = None,
) -> LabelClaim:
    """The approved claim backing ``sku_id``; ``SkuNotRecommendable`` otherwise."""
    stmt = (
        select(LabelClaim)
        .join(Sku, Sku.id == LabelClaim.sku_id)
        .join(Product, Product.id == Sku.product_id)
        .where(
            *_live_approved(tenant_id),
            LabelClaim.id == label_claim_id,
            LabelClaim.sku_id == sku_id,
        )
    )
    if crop_id is not None:
        stmt = stmt.where(LabelClaim.crop_id == crop_id)
    if pest_or_disease_id is not None:
        stmt = stmt.where(LabelClaim.pest_or_disease_id == pest_or_disease_id)
    claim = (await session.execute(stmt)).scalar_one_or_none()
    if claim is None:
        raise SkuNotRecommendable(
            "This SKU has no approved label claim for the crop and problem (DX-007).",
            extra={"sku_id": str(sku_id), "label_claim_id": str(label_claim_id)},
        )
    return claim


__all__ = ["RecommendableSku", "assert_sku_recommendable", "recommendable_skus"]
