"""DX-007 / DX-008 / DX-009: label-claim-only treatments, ranking, dosage and safety."""

from __future__ import annotations

import itertools
import random
import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import ClaimStatus, LabelClaim
from farmerapp.catalog.recommendable import RecommendableSku, recommendable_skus
from farmerapp.diagnosis.treatment import (
    NO_TIER,
    RankedProduct,
    StoreRef,
    farmer_store,
    is_organic,
    rank,
    treatments_for,
)
from tests.diagnosis.conftest import Paddy


def _product(
    rng: random.Random, *, tier: int | None, own: bool, stock: bool, price: int
) -> RankedProduct:
    sku = RecommendableSku(
        sku_id=uuid.UUID(int=rng.getrandbits(128)),
        product_id=uuid.uuid4(),
        product_name="P",
        brand="own" if own else "other",
        own_brand=own,
        pack_label="1 l",
        mrp_paise=price,
        label_claim_id=uuid.uuid4(),
        dose_per_acre="200 ml/acre",
        dose_value=Decimal(200),
        dose_unit="ml",
        dose_per_tank_15l="20 ml",
        phi_days=7,
        ppe_text="gloves",
        safety_text="keep away",
        efficacy_tier=tier,
    )
    return RankedProduct(
        sku=sku,
        kind="chemical",
        active_ingredient="x",
        price_paise=price,
        stock_qty=Decimal(5 if stock else 0),
        in_stock=stock,
    )


@pytest.mark.parametrize("seed", range(40))
def test_own_brand_never_outranks_a_higher_efficacy_tier(seed: int) -> None:
    """DX-008 acceptance (property): whatever the brand, stock and price, a better tier
    always ranks first; within a tier own brand, then in stock, then price."""
    rng = random.Random(seed)
    items = [
        _product(
            rng,
            tier=rng.choice([1, 2, 3, None]),
            own=rng.random() < 0.5,
            stock=rng.random() < 0.5,
            price=rng.randint(100, 100_000),
        )
        for _ in range(rng.randint(2, 12))
    ]
    ordered = rank(items)
    tiers = [p.sku.efficacy_tier or NO_TIER for p in ordered]
    assert tiers == sorted(tiers)
    for better, worse in itertools.pairwise(ordered):
        b_tier = better.sku.efficacy_tier or NO_TIER
        w_tier = worse.sku.efficacy_tier or NO_TIER
        if w_tier > b_tier:
            continue
        # same tier: own brand first, then stock, then price
        assert (not better.sku.own_brand, not better.in_stock, better.price_paise) <= (
            not worse.sku.own_brand,
            not worse.in_stock,
            worse.price_paise,
        )
    own_better = [p for p in ordered if p.sku.own_brand]
    for own in own_better:
        idx = ordered.index(own)
        for other in ordered[:idx]:
            assert (other.sku.efficacy_tier or NO_TIER) <= (own.sku.efficacy_tier or NO_TIER)


def test_organic_markers() -> None:
    assert is_organic("Azadirachtin 0.15% EC (neem oil 1500 ppm)")
    assert is_organic(None, "Bio-pesticide; safe near harvest")
    assert is_organic("Trichoderma viride 1% WP")
    assert not is_organic("Imidacloprid 17.8% SL")


async def test_treatments_draw_only_from_approved_label_claims(
    db_session: AsyncSession, paddy: Paddy
) -> None:
    """DX-007 acceptance: no SKU without an approved claim for that crop x problem is ever
    returned — a draft claim for the same crop x problem is not offered."""
    tid = paddy.farmer.tenant_id
    zinc = paddy.problems["paddy_zinc_deficiency"]
    store = await farmer_store(db_session, paddy.farmer)
    assert store is not None
    before = await treatments_for(
        db_session,
        tenant_id=tid,
        crop_id=paddy.crop.id,
        pest_or_disease_id=zinc.pest_or_disease_id,
        store=store,
        today=date(2026, 9, 18),
        cultural={"en": ["Soil test"]},
    )
    claims = (
        (
            await db_session.execute(
                select(LabelClaim).where(
                    LabelClaim.crop_id == paddy.crop.id,
                    LabelClaim.pest_or_disease_id == zinc.pest_or_disease_id,
                )
            )
        )
        .scalars()
        .all()
    )
    assert claims
    claims[0].status = ClaimStatus.DRAFT.value
    claims[0].approved_at = None
    await db_session.flush()
    after = await treatments_for(
        db_session,
        tenant_id=tid,
        crop_id=paddy.crop.id,
        pest_or_disease_id=zinc.pest_or_disease_id,
        store=None,
        today=date(2026, 9, 18),
    )
    allowed = {
        str(s.sku_id)
        for s in await recommendable_skus(
            db_session,
            tenant_id=tid,
            crop_id=paddy.crop.id,
            pest_or_disease_id=zinc.pest_or_disease_id,
        )
    }
    offered_before = {p["sku_id"] for p in before["chemical"] + before["organic"]}
    offered_after = {p["sku_id"] for p in after["chemical"] + after["organic"]}
    assert offered_after == allowed
    assert str(claims[0].sku_id) not in offered_after or any(
        c.sku_id == claims[0].sku_id and c.status == "approved" for c in claims[1:]
    )
    assert offered_after <= offered_before
    assert before["cultural"] == {"en": ["Soil test"]} and before["store"]["id"] == str(store.id)
    assert after["store"] is None
    for product in before["chemical"]:
        # DX-009 on every chemical recommendation (a nutrient label has no PHI: null)
        assert product["dose_per_acre"] and "phi_days" in product and "ppe_text" in product
        assert product["safety_text"] and "dose_per_tank_15l" in product
    ranks = [p["rank"] for p in before["chemical"]]
    assert ranks == list(range(1, len(ranks) + 1))


def test_store_ref_json() -> None:
    ref = StoreRef(id=uuid.uuid4(), code="WGL", name="FCC Warangal", source="village")
    assert ref.to_json()["code"] == "WGL"
