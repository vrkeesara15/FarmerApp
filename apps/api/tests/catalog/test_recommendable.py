"""The recommendation guardrail (WC-005 acceptance, DX-007 groundwork, SPEC 3.4).

Property-style: for random claim sets over a few SKUs, crops and pests (draft, approved,
retired, soft-deleted; inactive SKUs and products), ``recommendable_skus`` returns exactly the
SKUs with a live approved claim for that crop x pest — never one without. Retiring a claim
removes the SKU at once; ``assert_sku_recommendable`` rejects every other combination.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.errors import SkuNotRecommendable
from farmerapp.catalog.models import ClaimStatus, LabelClaim, PestOrDisease, Product, Sku
from farmerapp.catalog.recommendable import assert_sku_recommendable, recommendable_skus
from farmerapp.db.session import tenant_scope
from tests.authz.conftest import Bearer, World
from tests.catalog import factory as f

NOW = datetime(2026, 9, 18, 6, 0, tzinfo=UTC)


@dataclass
class _World:
    tenant_id: uuid.UUID
    crops: list[uuid.UUID]
    pests: list[uuid.UUID]
    skus: list[Sku]
    products: dict[uuid.UUID, Product]


async def _build(db_session: AsyncSession, world: World, rng: random.Random) -> _World:
    tid = world.a.tenant.id
    crops = [c.id for c in (await f.crops(db_session, world))[:3]]
    async with tenant_scope(db_session, tid):
        pests = []
        for i in range(3):
            pest = PestOrDisease(
                tenant_id=tid,
                code=f.unique("prop").lower(),
                name=f"Prop pest {i}",
                type=rng.choice(["pest", "disease"]),
                crop_id=None,
            )
            db_session.add(pest)
            pests.append(pest)
        products: dict[uuid.UUID, Product] = {}
        skus: list[Sku] = []
        for _ in range(4):
            product = Product(
                tenant_id=tid,
                name=f.unique("Prop product"),
                brand="Prop",
                own_brand=rng.random() < 0.5,
                category="pesticide",
                gst_rate_bp=1800,
                active=rng.random() > 0.15,
            )
            db_session.add(product)
            await db_session.flush()
            products[product.id] = product
            for _ in range(2):
                sku = Sku(
                    tenant_id=tid,
                    product_id=product.id,
                    pack_size_value=Decimal(rng.choice([100, 250, 500, 1000])),
                    pack_size_unit="ml",
                    mrp_paise=rng.randint(10_000, 90_000),
                    active=rng.random() > 0.15,
                    deleted_at=NOW if rng.random() < 0.1 else None,
                )
                db_session.add(sku)
                skus.append(sku)
        await db_session.flush()
    return _World(tid, crops, [p.id for p in pests], skus, products)


async def _random_claims(
    db_session: AsyncSession, w: _World, rng: random.Random, approver: uuid.UUID
) -> list[LabelClaim]:
    claims: list[LabelClaim] = []
    approved_triples: set[tuple[uuid.UUID, uuid.UUID, uuid.UUID]] = set()
    async with tenant_scope(db_session, w.tenant_id):
        for _ in range(rng.randint(5, 25)):
            sku = rng.choice(w.skus)
            crop = rng.choice(w.crops)
            pest = rng.choice(w.pests)
            status = rng.choice(["draft", "approved", "retired", "approved"])
            triple = (sku.id, crop, pest)
            if status == "approved" and triple in approved_triples:
                status = "retired"  # the partial unique index allows one approved version
            if status == "approved":
                approved_triples.add(triple)
            claim = LabelClaim(
                tenant_id=w.tenant_id,
                sku_id=sku.id,
                crop_id=crop,
                pest_or_disease_id=pest,
                dose_per_acre="100 ml",
                dose_value=Decimal(100),
                dose_unit="ml",
                dose_per_tank_15l="8 ml",
                phi_days=rng.randint(0, 30),
                ppe_text="Gloves",
                safety_text="Keep away from children.",
                source_ref="prop",
                efficacy_tier=rng.choice([None, 1, 2, 3]),
                status=status,
                approved_by=approver if status != "draft" else None,
                approved_at=NOW if status != "draft" else None,
                deleted_at=NOW if rng.random() < 0.08 else None,
            )
            db_session.add(claim)
            claims.append(claim)
        await db_session.flush()
    return claims


def _expected(
    w: _World, claims: list[LabelClaim], crop: uuid.UUID, pest: uuid.UUID
) -> dict[uuid.UUID, LabelClaim]:
    skus = {s.id: s for s in w.skus}
    out: dict[uuid.UUID, LabelClaim] = {}
    for c in claims:
        sku = skus[c.sku_id]
        product = w.products[sku.product_id]
        if (
            c.crop_id == crop
            and c.pest_or_disease_id == pest
            and c.status == ClaimStatus.APPROVED.value
            and c.deleted_at is None
            and sku.active
            and sku.deleted_at is None
            and product.active
        ):
            out[c.id] = c
    return out


@pytest.mark.parametrize("seed", range(12))
async def test_never_returns_a_sku_without_a_matching_approved_claim(
    db_session: AsyncSession, world: World, seed: int
) -> None:
    rng = random.Random(seed)
    w = await _build(db_session, world, rng)
    approver = world.a.user(UserRole.AGRONOMIST).id
    claims = await _random_claims(db_session, w, rng, approver)
    by_id = {c.id: c for c in claims}
    async with tenant_scope(db_session, w.tenant_id):
        for crop in w.crops:
            for pest in w.pests:
                got = await recommendable_skus(
                    db_session, tenant_id=w.tenant_id, crop_id=crop, pest_or_disease_id=pest
                )
                expected = _expected(w, claims, crop, pest)
                # Soundness: every row is backed by a live approved claim for exactly this pair.
                for row in got:
                    claim = by_id[row.label_claim_id]
                    assert claim.id in expected, (seed, row)
                    assert claim.sku_id == row.sku_id
                    assert (claim.crop_id, claim.pest_or_disease_id) == (crop, pest)
                    assert row.dose_per_acre == claim.dose_per_acre
                    assert row.phi_days == claim.phi_days
                    assert row.dose_per_tank_15l == claim.dose_per_tank_15l
                    assert row.ppe_text and row.safety_text
                # Completeness: every approved claim is served.
                assert {r.label_claim_id for r in got} == set(expected), seed
                # Ranking: own brand first, then efficacy tier.
                keys = [(not r.own_brand, r.efficacy_tier or 9) for r in got]
                assert keys == sorted(keys)


async def test_other_tenant_never_leaks(db_session: AsyncSession, world: World) -> None:
    rng = random.Random(99)
    w = await _build(db_session, world, rng)
    claims = await _random_claims(db_session, w, rng, world.a.owner.id)
    approved = next(
        (c for c in claims if c.status == "approved" and c.deleted_at is None), claims[0]
    )
    async with tenant_scope(db_session, world.b.tenant.id):
        got = await recommendable_skus(
            db_session,
            tenant_id=world.b.tenant.id,
            crop_id=approved.crop_id,
            pest_or_disease_id=approved.pest_or_disease_id,
        )
    assert got == []


async def test_retiring_removes_the_sku_immediately_and_validator(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    headers = f.owner(world, bearer)
    agro = f.agronomist(world, bearer)
    prod = await f.product(client, headers, own_brand=True)
    sku = await f.sku(client, headers, prod["id"])
    crop = (await f.crops(db_session, world))[0]
    pest = await f.pest(db_session, world, crop_id=crop.id)
    params = {"crop_id": str(crop.id), "pest_id": str(pest.id)}

    async def preview() -> list[dict[str, object]]:
        resp = await client.get(
            "/v1/catalog/recommendable",
            params=params,
            headers=bearer(world.a.user(UserRole.FIELD_OFFICER)),
        )
        assert resp.status_code == 200, resp.text
        return list(resp.json()["items"])

    draft = await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop.id, pest.id))
    assert await preview() == []  # a draft never backs a recommendation
    tid = world.a.tenant.id
    claim_id = uuid.UUID(str(draft["id"]))
    sku_id = uuid.UUID(str(sku["id"]))
    with pytest.raises(SkuNotRecommendable):
        await assert_sku_recommendable(
            db_session, tenant_id=tid, sku_id=sku_id, label_claim_id=claim_id
        )

    await f.approve(client, agro, str(draft["id"]))
    items = await preview()
    assert [i["sku_id"] for i in items] == [sku["id"]]
    item = items[0]
    assert item["label_claim_id"] == draft["id"] and item["own_brand"] is True
    assert item["dose_per_acre"] == "80 ml per acre" and item["dose_per_tank_15l"] == "7 ml"
    assert item["phi_days"] == 14 and item["ppe_text"] and item["safety_text"]
    ok = await assert_sku_recommendable(
        db_session,
        tenant_id=tid,
        sku_id=sku_id,
        label_claim_id=claim_id,
        crop_id=crop.id,
        pest_or_disease_id=pest.id,
    )
    assert ok.id == claim_id
    # Wrong SKU, crop, pest or tenant: rejected.
    other_crop = (await f.crops(db_session, world))[1]
    for kwargs in (
        {"sku_id": uuid.UUID(str(world.a.sku_id))},
        {"crop_id": other_crop.id},
        {"pest_or_disease_id": uuid.uuid4()},
        {"tenant_id": world.b.tenant.id},
    ):
        args = {
            "tenant_id": tid,
            "sku_id": sku_id,
            "label_claim_id": claim_id,
            "crop_id": crop.id,
            "pest_or_disease_id": pest.id,
            **kwargs,
        }
        with pytest.raises(SkuNotRecommendable):
            await assert_sku_recommendable(db_session, **args)

    # Other crop / pest: not recommendable.
    other = await client.get(
        "/v1/catalog/recommendable",
        params={"crop_id": str(other_crop.id), "pest_id": str(pest.id)},
        headers=agro,
    )
    assert other.json()["items"] == []

    resp = await client.post(f"/v1/catalog/label-claims/{draft['id']}/retire", headers=agro)
    assert resp.status_code == 200
    assert await preview() == []  # immediately
    with pytest.raises(SkuNotRecommendable) as exc:
        await assert_sku_recommendable(
            db_session, tenant_id=tid, sku_id=sku_id, label_claim_id=claim_id
        )
    assert exc.value.code == "sku_not_recommendable" and exc.value.status == 422


async def test_inactive_sku_or_product_is_not_recommendable(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    headers = f.owner(world, bearer)
    agro = f.agronomist(world, bearer)
    prod = await f.product(client, headers)
    sku = await f.sku(client, headers, prod["id"])
    crop = (await f.crops(db_session, world))[0]
    pest = await f.pest(db_session, world, crop_id=crop.id)
    claim = await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop.id, pest.id))
    await f.approve(client, agro, str(claim["id"]))
    params = {"crop_id": str(crop.id), "pest_id": str(pest.id)}
    assert (
        len(
            (await client.get("/v1/catalog/recommendable", params=params, headers=agro)).json()[
                "items"
            ]
        )
        == 1
    )
    await client.patch(f"/v1/catalog/skus/{sku['id']}", json={"active": False}, headers=headers)
    assert (await client.get("/v1/catalog/recommendable", params=params, headers=agro)).json()[
        "items"
    ] == []
    await client.patch(f"/v1/catalog/skus/{sku['id']}", json={"active": True}, headers=headers)
    await client.patch(
        f"/v1/catalog/products/{prod['id']}", json={"active": False}, headers=headers
    )
    assert (await client.get("/v1/catalog/recommendable", params=params, headers=agro)).json()[
        "items"
    ] == []


async def test_recommendable_requires_crop_and_pest(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.user(UserRole.FARMER))
    for params in ({}, {"crop_id": str(uuid.uuid4())}, {"pest_id": str(uuid.uuid4())}):
        resp = await client.get("/v1/catalog/recommendable", params=params, headers=headers)
        assert resp.status_code == 422
    seeded = await client.get(
        "/v1/catalog/recommendable",
        params={"crop_id": str(uuid.uuid4()), "pest_id": str(uuid.uuid4())},
        headers=headers,
    )
    assert seeded.status_code == 200 and seeded.json() == {"items": []}
