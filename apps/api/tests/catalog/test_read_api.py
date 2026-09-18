"""``GET /v1/catalog/products``, ``/v1/catalog/skus/{id}``, ``/v1/catalog/label-claims``:
every role reads the catalogue; store price and stock with ``store_id``; label claims are
approved-only except for the agronomist / owner (DX-007, WC-005)."""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.models import SEED_SOURCE_REF, ClaimStatus, LabelClaim, PestOrDisease
from farmerapp.db.session import tenant_scope
from farmerapp.jobs.seed_catalog import SMALL_PRODUCT_KEYS
from farmerapp.stock.ledger import stock_on_hand
from tests.authz.conftest import ROLES, Bearer, World


async def _pages(
    client: AsyncClient, path: str, headers: dict[str, str], limit: int = 50, **params: str
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(50):
        query = {"limit": str(limit), **params}
        if cursor:
            query["cursor"] = cursor
        resp = await client.get(path, params=query, headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        items.extend(body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            return items
    raise AssertionError("pagination did not terminate")


async def test_every_role_lists_products_with_skus_and_prices(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    for role in ROLES:
        items = await _pages(client, "/v1/catalog/products", bearer(world.a.user(role)), limit=2)
        assert len(items) == len(SMALL_PRODUCT_KEYS), role
        assert all(i["tenant_id"] == str(world.a.tenant.id) for i in items)
    items = await _pages(client, "/v1/catalog/products", bearer(world.a.owner))
    skus = [s for p in items for s in p["skus"]]
    assert len(skus) == 10
    for sku in skus:
        assert isinstance(sku["mrp_paise"], int) and isinstance(sku["price_paise"], int)
        assert 0 < sku["price_paise"] <= sku["mrp_paise"]
        assert sku["stock_qty"] is None  # no store given
        assert sku["pack_label"]
    own = [p for p in items if p["own_brand"]]
    assert own and all(p["name"].startswith("FCC") or "FCC" in p["brand"] for p in own)
    assert {p["gst_rate_bp"] for p in items} <= {0, 500, 1200, 1800}


async def test_product_filters(client: AsyncClient, world: World, bearer: Bearer) -> None:
    headers = bearer(world.a.user(UserRole.FIELD_OFFICER))
    pesticides = await _pages(client, "/v1/catalog/products", headers, category="pesticide")
    assert pesticides and {p["category"] for p in pesticides} == {"pesticide"}
    own = await _pages(client, "/v1/catalog/products", headers, own_brand="true")
    multi = await _pages(client, "/v1/catalog/products", headers, own_brand="false")
    assert own and all(p["own_brand"] for p in own)
    assert all(not p["own_brand"] for p in multi)
    assert len(own) + len(multi) == len(SMALL_PRODUCT_KEYS)
    by_ingredient = await _pages(client, "/v1/catalog/products", headers, q="imidacloprid")
    assert [p["active_ingredient"] for p in by_ingredient] == ["Imidacloprid 17.8% SL"]
    assert await _pages(client, "/v1/catalog/products", headers, q="no-such-thing") == []
    resp = await client.get("/v1/catalog/products", params={"category": "snacks"}, headers=headers)
    assert resp.status_code == 422


async def test_store_price_and_stock(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    store_id = world.a.store_id
    assert store_id is not None
    items = await _pages(
        client,
        "/v1/catalog/products",
        bearer(world.a.user(UserRole.FARMER)),
        store_id=str(store_id),
    )
    skus = [s for p in items for s in p["skus"]]
    stocked = [s for s in skus if Decimal(s["stock_qty"]) > 0]
    assert stocked  # the SMALL seed stocks one SKU per store
    async with tenant_scope(db_session, world.a.tenant.id):
        for sku in skus:
            on_hand = await stock_on_hand(db_session, store_id, uuid.UUID(sku["id"]))
            assert Decimal(sku["stock_qty"]) == on_hand
    foreign = await client.get(
        "/v1/catalog/products",
        params={"store_id": str(world.b.store_id)},
        headers=bearer(world.a.owner),
    )
    assert foreign.status_code == 404


async def _add_draft_claim(db_session: AsyncSession, world: World) -> LabelClaim:
    async with tenant_scope(db_session, world.a.tenant.id):
        approved = (
            await db_session.execute(
                select(LabelClaim).where(LabelClaim.sku_id == world.a.sku_id).limit(1)
            )
        ).scalar_one()
        used = {
            c.pest_or_disease_id
            for c in (
                await db_session.execute(
                    select(LabelClaim).where(LabelClaim.sku_id == world.a.sku_id)
                )
            ).scalars()
        }
        pest = (
            await db_session.execute(
                select(PestOrDisease).where(PestOrDisease.id.not_in(used)).limit(1)
            )
        ).scalar_one()
        draft = LabelClaim(
            tenant_id=world.a.tenant.id,
            sku_id=approved.sku_id,
            crop_id=approved.crop_id,
            pest_or_disease_id=pest.id,
            dose_per_acre="1 l/acre",
            source_ref=SEED_SOURCE_REF,
            status=ClaimStatus.DRAFT,
        )
        db_session.add(draft)
        await db_session.flush()
        return draft


async def test_sku_detail_hides_draft_claims_except_for_claim_maintainers(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    draft = await _add_draft_claim(db_session, world)
    url = f"/v1/catalog/skus/{world.a.sku_id}"
    for role in ROLES:
        resp = await client.get(url, headers=bearer(world.a.user(role)))
        assert resp.status_code == 200, (role, resp.text)
        body = resp.json()
        claims = body["label_claims"]
        ids = {c["id"] for c in claims}
        assert claims and all(c["source_ref"] == SEED_SOURCE_REF for c in claims)
        if role in ("agronomist", "owner", "tenant_admin"):
            assert str(draft.id) in ids, role
        else:
            assert str(draft.id) not in ids, role
            assert {c["status"] for c in claims} == {"approved"}, role
        assert body["product"]["id"] == body["product_id"]
        approved = next(c for c in claims if c["status"] == "approved")
        assert approved["dose_per_acre"] and approved["safety_text"]  # DX-009 text present
        assert approved["pest_or_disease"]["code"]
    missing = await client.get(f"/v1/catalog/skus/{world.b.sku_id}", headers=bearer(world.a.owner))
    assert missing.status_code == 404


async def test_label_claims_list_filters_and_status(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    draft = await _add_draft_claim(db_session, world)
    farmer = bearer(world.a.user(UserRole.FARMER))
    approved = await _pages(client, "/v1/catalog/label-claims", farmer, limit=2)
    assert len(approved) == 5 and {c["status"] for c in approved} == {"approved"}
    crop_id = approved[0]["crop_id"]
    pest_id = approved[0]["pest_or_disease_id"]
    filtered = await _pages(
        client, "/v1/catalog/label-claims", farmer, crop_id=crop_id, pest_id=pest_id
    )
    assert filtered and all(
        c["crop_id"] == crop_id and c["pest_or_disease_id"] == pest_id for c in filtered
    )
    by_sku = await _pages(client, "/v1/catalog/label-claims", farmer, sku_id=str(world.a.sku_id))
    assert by_sku and {c["sku_id"] for c in by_sku} == {str(world.a.sku_id)}
    # A farmer asking for drafts still gets approved claims only (DX-007).
    asked = await _pages(client, "/v1/catalog/label-claims", farmer, status="draft")
    assert str(draft.id) not in {c["id"] for c in asked}
    assert {c["status"] for c in asked} == {"approved"}
    agronomist = bearer(world.a.user(UserRole.AGRONOMIST))
    drafts = await _pages(client, "/v1/catalog/label-claims", agronomist, status="draft")
    assert [c["id"] for c in drafts] == [str(draft.id)]
    assert await _pages(client, "/v1/catalog/label-claims", agronomist, status="retired") == []
