"""Treatment engine (DX-007), ranking (DX-008) and dosage / safety (DX-009).

problem -> treatments:

* **cultural** practices come from the corpus problem (per language);
* **organic** and **chemical** products come **only** from
  ``catalog.recommendable.recommendable_skus(crop, pest)`` — SKUs with an approved, live
  label claim for exactly that crop x problem (DX-007: never a SKU without a claim; this
  module never adds to that list). A product is ``organic`` when its active ingredient is a
  botanical / microbial agent (neem, Trichoderma, Pseudomonas, Beauveria, ...), else
  ``chemical``.

Ranking (DX-008), one sort key, most significant first:

1. efficacy tier set by the agronomist on the label claim (1 best; none = after tier 3),
2. own brand before multi-brand,
3. in stock at the farmer's nearest store before out of stock,
4. price at that store (store price list, else tenant default, else MRP), cheaper first.

Because the tier is the first key, an own-brand SKU can never outrank a SKU with a better
efficacy tier (property-tested). Every chemical recommendation carries the label's dose per
acre and per 15 L tank, PHI days, PPE and safety text (DX-009).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import Product
from farmerapp.catalog.pricing import prices_for, resolved_price
from farmerapp.catalog.recommendable import RecommendableSku, recommendable_skus
from farmerapp.farmers.models import Farmer
from farmerapp.stock.ledger import reserved_by_sku, stock_on_hand_by_sku
from farmerapp.tenants.models import Store

#: Botanical / microbial active ingredients: recommended as "organic" options.
ORGANIC_MARKERS: tuple[str, ...] = (
    "azadirachtin",
    "neem",
    "trichoderma",
    "pseudomonas",
    "beauveria",
    "metarhizium",
    "verticillium",
    "bacillus",
    "npv",
    "seaweed",
)
NO_TIER = 99
MAX_PRODUCTS_PER_KIND = 8


def is_organic(active_ingredient: str | None, description: str | None = None) -> bool:
    text = f"{active_ingredient or ''} {description or ''}".lower()
    return any(marker in text for marker in ORGANIC_MARKERS) or "bio-pesticide" in text


@dataclass(frozen=True)
class RankedProduct:
    sku: RecommendableSku
    kind: str  # organic | chemical
    active_ingredient: str | None
    price_paise: int
    stock_qty: Decimal
    in_stock: bool

    def sort_key(self) -> tuple[int, int, int, int, str]:
        tier = self.sku.efficacy_tier if self.sku.efficacy_tier is not None else NO_TIER
        return (
            tier,
            0 if self.sku.own_brand else 1,
            0 if self.in_stock else 1,
            self.price_paise,
            str(self.sku.sku_id),
        )

    def to_json(self, rank: int) -> dict[str, Any]:
        s = self.sku
        return {
            "rank": rank,
            "kind": self.kind,
            "sku_id": str(s.sku_id),
            "product_id": str(s.product_id),
            "product_name": s.product_name,
            "brand": s.brand,
            "own_brand": s.own_brand,
            "pack_label": s.pack_label,
            "active_ingredient": self.active_ingredient,
            "label_claim_id": str(s.label_claim_id),
            "efficacy_tier": s.efficacy_tier,
            # DX-009: from the label claim, shown on every chemical recommendation
            "dose_per_acre": s.dose_per_acre,
            "dose_value": str(s.dose_value) if s.dose_value is not None else None,
            "dose_unit": s.dose_unit,
            "dose_per_tank_15l": s.dose_per_tank_15l,
            "phi_days": s.phi_days,
            "ppe_text": s.ppe_text,
            "safety_text": s.safety_text,
            "price_paise": self.price_paise,
            "mrp_paise": s.mrp_paise,
            "stock_qty": str(self.stock_qty),
            "in_stock": self.in_stock,
        }


def rank(products: list[RankedProduct]) -> list[RankedProduct]:
    """DX-008 order (see module doc)."""
    return sorted(products, key=RankedProduct.sort_key)


@dataclass(frozen=True)
class StoreRef:
    id: uuid.UUID
    code: str
    name: str
    source: str  # village | nearest

    def to_json(self) -> dict[str, Any]:
        return {"id": str(self.id), "code": self.code, "name": self.name, "source": self.source}


async def farmer_store(session: AsyncSession, farmer: Farmer) -> StoreRef | None:
    """The farmer's nearest store (FA-020 rule: the village's store, else the closest)."""
    from farmerapp.api.errors import NotFoundError
    from farmerapp.orders.service import nearest_store

    try:
        found = await nearest_store(session, farmer)
    except NotFoundError:
        return None
    store: Store = found.store
    return StoreRef(id=store.id, code=store.code, name=store.name, source=found.source)


async def treatments_for(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    crop_id: uuid.UUID,
    pest_or_disease_id: uuid.UUID,
    store: StoreRef | None,
    today: date,
    cultural: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """``{"organic": [...], "chemical": [...], "cultural": {lang: [...]}, "store": {...}}``."""
    skus = await recommendable_skus(
        session, tenant_id=tenant_id, crop_id=crop_id, pest_or_disease_id=pest_or_disease_id
    )
    sku_ids = [s.sku_id for s in skus]
    products = {
        p.id: p
        for p in (
            await session.execute(
                select(Product).where(Product.id.in_({s.product_id for s in skus}))
            )
        ).scalars()
    }
    prices = await prices_for(session, sku_ids, store.id if store else None, today)
    on_hand: dict[uuid.UUID, Decimal] = {}
    reserved: dict[uuid.UUID, Decimal] = {}
    if store is not None and sku_ids:
        on_hand = await stock_on_hand_by_sku(session, store.id, sku_ids)
        reserved = await reserved_by_sku(session, store.id, sku_ids)
    ranked: list[RankedProduct] = []
    for s in skus:
        product = products.get(s.product_id)
        ingredient = product.active_ingredient if product else None
        available = on_hand.get(s.sku_id, Decimal(0)) - reserved.get(s.sku_id, Decimal(0))
        ranked.append(
            RankedProduct(
                sku=s,
                kind="organic"
                if is_organic(ingredient, product.description if product else None)
                else "chemical",
                active_ingredient=ingredient,
                price_paise=resolved_price(prices.get(s.sku_id), s.mrp_paise),
                stock_qty=max(available, Decimal(0)),
                in_stock=available > 0,
            )
        )
    ordered = rank(ranked)
    organic = [p for p in ordered if p.kind == "organic"][:MAX_PRODUCTS_PER_KIND]
    chemical = [p for p in ordered if p.kind == "chemical"][:MAX_PRODUCTS_PER_KIND]
    return {
        "organic": [p.to_json(i + 1) for i, p in enumerate(organic)],
        "chemical": [p.to_json(i + 1) for i, p in enumerate(chemical)],
        "cultural": dict(cultural or {}),
        "store": store.to_json() if store else None,
    }


__all__ = [
    "MAX_PRODUCTS_PER_KIND",
    "ORGANIC_MARKERS",
    "RankedProduct",
    "StoreRef",
    "farmer_store",
    "is_organic",
    "rank",
    "treatments_for",
]
