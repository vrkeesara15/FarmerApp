"""WC-005 writes: products and SKUs (GST slab, HSN, barcode per tenant), POS barcode lookup,
and the label-claim workflow (draft -> agronomist approval -> retire; approved claims are
immutable, edits are new draft versions) with its validation and audit trail."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.models import AuditLog
from farmerapp.db.session import tenant_scope
from tests.authz.conftest import Bearer, World
from tests.catalog import factory as f


# --------------------------------------------------------------------------- products
@pytest.mark.parametrize("role", ["owner", "director", "tenant_admin"])
async def test_write_roles_create_products(
    client: AsyncClient, world: World, bearer: Bearer, role: str
) -> None:
    body = await f.product(client, bearer(world.a.user(role)), own_brand=True)
    assert body["own_brand"] is True
    assert body["tenant_id"] == str(world.a.tenant.id)
    assert body["gst_rate_bp"] == 1800 and body["hsn"] == "3808"


async def test_agronomist_and_store_roles_cannot_write_products(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    for role in ("agronomist", "store_manager", "field_officer", "farmer"):
        resp = await client.post(
            "/v1/catalog/products",
            json={"name": "X", "brand": "Y", "category": "seed", "gst_rate_bp": 0},
            headers=bearer(world.a.user(role)),
        )
        assert resp.status_code == 403, role


@pytest.mark.parametrize("gst", [0, 500, 1200, 1800, 2800])
async def test_allowed_gst_slabs(
    client: AsyncClient, world: World, bearer: Bearer, gst: int
) -> None:
    await f.product(client, f.owner(world, bearer), gst_rate_bp=gst)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("gst_rate_bp", 1300),
        ("gst_rate_bp", 18),
        ("hsn", "123"),
        ("hsn", "38089"),
        ("hsn", "38A8"),
        ("hsn", "380891991"),
        ("category", "snacks"),
        ("name", ""),
    ],
)
async def test_product_validation(
    client: AsyncClient, world: World, bearer: Bearer, field: str, value: object
) -> None:
    body = {"name": "Valid", "brand": "B", "category": "pesticide", "gst_rate_bp": 1800}
    body[field] = value
    resp = await client.post("/v1/catalog/products", json=body, headers=f.owner(world, bearer))
    assert resp.status_code == 422, resp.text
    problem = resp.json()
    assert problem["code"] == "validation_error"
    assert any(e["loc"][-1] == field for e in problem["errors"]), problem


@pytest.mark.parametrize("hsn", ["3808", "380891", "38089199", None, ""])
async def test_hsn_4_6_8_digits_or_empty(
    client: AsyncClient, world: World, bearer: Bearer, hsn: str | None
) -> None:
    body = await f.product(client, f.owner(world, bearer), hsn=hsn)
    assert body["hsn"] == (hsn or None)


async def test_duplicate_product_and_patch(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    first = await f.product(client, headers, name="Duplo")
    again = await client.post(
        "/v1/catalog/products",
        json={"name": "duplo", "brand": "testbrand", "category": "seed", "gst_rate_bp": 0},
        headers=headers,
    )
    assert again.status_code == 409 and again.json()["code"] == "product_exists"

    resp = await client.patch(
        f"/v1/catalog/products/{first['id']}",
        json={"own_brand": True, "gst_rate_bp": 1200, "version": first["version"]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    patched = resp.json()
    assert patched["own_brand"] is True and patched["gst_rate_bp"] == 1200
    assert patched["version"] == first["version"] + 1
    stale = await client.patch(
        f"/v1/catalog/products/{first['id']}",
        json={"active": False, "version": first["version"]},
        headers=headers,
    )
    assert stale.status_code == 409 and stale.json()["code"] == "version_conflict"
    bad = await client.patch(
        f"/v1/catalog/products/{first['id']}", json={"gst_rate_bp": 700}, headers=headers
    )
    assert bad.status_code == 422
    missing = await client.patch(
        f"/v1/catalog/products/{uuid.uuid4()}", json={"active": False}, headers=headers
    )
    assert missing.status_code == 404


async def test_product_write_is_audited(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    body = await f.product(client, f.owner(world, bearer))
    async with tenant_scope(db_session, world.a.tenant.id):
        rows = (
            (
                await db_session.execute(
                    select(AuditLog).where(AuditLog.entity_id == uuid.UUID(body["id"]))
                )
            )
            .scalars()
            .all()
        )
    assert [r.action for r in rows] == ["product.create"]
    assert rows[0].actor_id == world.a.owner.id


# --------------------------------------------------------------------------- SKUs + barcode
async def test_sku_create_patch_and_barcode_uniqueness(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    prod = await f.product(client, headers)
    first = await f.sku(client, headers, prod["id"], barcode="8901234500011")
    assert first["pack_label"] == "250 ml" and first["price_paise"] == first["mrp_paise"]

    dup = await client.post(
        "/v1/catalog/skus",
        json={
            "product_id": prod["id"],
            "pack_size_value": "1",
            "pack_size_unit": "l",
            "barcode": "8901234500011",
            "mrp_paise": 150000,
        },
        headers=headers,
    )
    assert dup.status_code == 409 and dup.json()["code"] == "barcode_exists"

    second = await f.sku(client, headers, prod["id"], barcode="8901234500028", pack_size_value="1")
    clash = await client.patch(
        f"/v1/catalog/skus/{second['id']}", json={"barcode": "8901234500011"}, headers=headers
    )
    assert clash.status_code == 409 and clash.json()["code"] == "barcode_exists"
    ok = await client.patch(
        f"/v1/catalog/skus/{second['id']}",
        json={"mrp_paise": 160000, "barcode": "8901234500028"},
        headers=headers,
    )
    assert ok.status_code == 200 and ok.json()["mrp_paise"] == 160000

    # Uniqueness is per tenant: tenant B may use the same barcode.
    b_owner = bearer(world.b.owner)
    b_prod = await f.product(client, b_owner)
    await f.sku(client, b_owner, b_prod["id"], barcode="8901234500011")

    missing_product = await client.post(
        "/v1/catalog/skus",
        json={
            "product_id": str(uuid.uuid4()),
            "pack_size_value": "1",
            "pack_size_unit": "kg",
            "mrp_paise": 1,
        },
        headers=headers,
    )
    assert missing_product.status_code == 404
    negative = await client.post(
        "/v1/catalog/skus",
        json={
            "product_id": prod["id"],
            "pack_size_value": "0",
            "pack_size_unit": "kg",
            "mrp_paise": -1,
        },
        headers=headers,
    )
    assert negative.status_code == 422


async def test_barcode_lookup_for_pos(client: AsyncClient, world: World, bearer: Bearer) -> None:
    code = world.a.sku_barcode
    assert code
    for role in ("store_manager", "field_officer", "owner", "accountant"):
        resp = await client.get(f"/v1/catalog/barcode/{code}", headers=bearer(world.a.user(role)))
        assert resp.status_code == 200, (role, resp.text)
        body = resp.json()
        assert body["id"] == str(world.a.sku_id)
        assert body["product"]["id"] == str(world.a.product_id)
        assert 0 < body["price_paise"] <= body["mrp_paise"]
    farmer = await client.get(
        f"/v1/catalog/barcode/{code}", headers=bearer(world.a.user(UserRole.FARMER))
    )
    assert farmer.status_code == 403
    unknown = await client.get("/v1/catalog/barcode/000", headers=f.owner(world, bearer))
    assert unknown.status_code == 404
    foreign = await client.get(
        f"/v1/catalog/barcode/{world.b.sku_barcode}", headers=f.owner(world, bearer)
    )
    assert foreign.status_code == 404 or foreign.json()["id"] != str(world.b.sku_id)


# --------------------------------------------------------------------------- label claims
async def _claim_setup(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession, **product: object
) -> tuple[dict[str, str], dict[str, Any], uuid.UUID, uuid.UUID]:
    headers = f.owner(world, bearer)
    prod = await f.product(client, headers, **product)
    sku = await f.sku(client, headers, prod["id"])
    crop = (await f.crops(db_session, world))[0]
    pest = await f.pest(db_session, world, crop_id=crop.id)
    return headers, sku, crop.id, pest.id


async def test_claim_draft_then_agronomist_approval_records_who(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    agro = f.agronomist(world, bearer)
    draft = await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop_id, pest_id))
    assert draft["status"] == "draft" and draft["approved_by"] is None
    assert draft["pest_or_disease"]["id"] == str(pest_id)

    # Owner and tenant admin may draft but never approve (SPEC 14.6 human gate).
    for role in ("owner", "tenant_admin", "director"):
        resp = await client.post(
            f"/v1/catalog/label-claims/{draft['id']}/approve", headers=bearer(world.a.user(role))
        )
        assert resp.status_code == 403, role

    approved = await f.approve(client, agro, draft["id"])
    assert approved["status"] == "approved"
    assert approved["approved_by"] == str(world.a.user(UserRole.AGRONOMIST).id)
    assert approved["approved_at"] is not None

    again = await client.post(f"/v1/catalog/label-claims/{draft['id']}/approve", headers=agro)
    assert again.status_code == 409 and again.json()["code"] == "claim_not_draft"

    async with tenant_scope(db_session, world.a.tenant.id):
        rows = (
            (
                await db_session.execute(
                    select(AuditLog)
                    .where(AuditLog.entity_id == uuid.UUID(str(draft["id"])))
                    .order_by(AuditLog.created_at)
                )
            )
            .scalars()
            .all()
        )
    actions = [r.action for r in rows]
    assert actions[0] == "label_claim.create" and "label_claim.update" in actions
    update = next(r for r in rows if r.action == "label_claim.update")
    assert update.actor_role == "agronomist"
    assert update.after is not None and update.after["status"] == "approved"


async def test_owner_and_tenant_admin_draft_claims(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    pest2 = await f.pest(db_session, world, crop_id=None)
    await f.draft_claim(
        client, f.owner(world, bearer), f.claim_body(str(sku["id"]), crop_id, pest_id)
    )
    await f.draft_claim(
        client,
        bearer(world.a.user(UserRole.TENANT_ADMIN)),
        f.claim_body(str(sku["id"]), crop_id, pest2.id),
    )
    for role in ("director", "field_officer", "store_manager", "farmer"):
        resp = await client.post(
            "/v1/catalog/label-claims",
            json=f.claim_body(str(sku["id"]), crop_id, pest_id),
            headers=bearer(world.a.user(role)),
        )
        assert resp.status_code == 403, role


@pytest.mark.parametrize(
    ("override", "field"),
    [
        ({"dose_value": "0"}, "dose_value"),
        ({"dose_value": "-5"}, "dose_value"),
        ({"dose_unit": None}, "dose_unit"),
        ({"dose_unit": "cups"}, "dose_unit"),
        ({"phi_days": -1}, "phi_days"),
        ({"phi_days": None}, "phi_days"),
        ({"source_ref": ""}, "source_ref"),
        ({"dose_per_acre": ""}, "dose_per_acre"),
        ({"efficacy_tier": 4}, "efficacy_tier"),
    ],
)
async def test_claim_field_validation(
    client: AsyncClient,
    world: World,
    bearer: Bearer,
    db_session: AsyncSession,
    override: dict[str, object],
    field: str,
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    resp = await client.post(
        "/v1/catalog/label-claims",
        json=f.claim_body(str(sku["id"]), crop_id, pest_id, **override),
        headers=f.agronomist(world, bearer),
    )
    assert resp.status_code == 422, resp.text
    assert any(e["loc"][-1] == field for e in resp.json()["errors"])


async def test_pest_claim_needs_a_crop_protection_product(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    agro = f.agronomist(world, bearer)
    crop = (await f.crops(db_session, world))[0]
    pest = await f.pest(db_session, world, crop_id=crop.id, type="pest")
    disease = await f.pest(db_session, world, crop_id=crop.id, type="disease")
    nutrient = await f.pest(db_session, world, crop_id=crop.id, type="nutrient")
    headers = f.owner(world, bearer)
    for category in ("seed", "fertiliser", "tool", "other"):
        prod = await f.product(client, headers, category=category, gst_rate_bp=0)
        sku = await f.sku(client, headers, prod["id"])
        for problem in (pest, disease):
            resp = await client.post(
                "/v1/catalog/label-claims",
                json=f.claim_body(str(sku["id"]), crop.id, problem.id),
                headers=agro,
            )
            assert resp.status_code == 422, (category, resp.text)
            assert resp.json()["code"] == "claim_category_invalid"
    # A nutrient deficiency may be claimed by a fertiliser.
    fert = await f.product(client, headers, category="fertiliser", gst_rate_bp=500)
    fert_sku = await f.sku(client, headers, fert["id"])
    await f.draft_claim(client, agro, f.claim_body(str(fert_sku["id"]), crop.id, nutrient.id))
    for category in ("pesticide", "fungicide", "herbicide", "growth"):
        prod = await f.product(client, headers, category=category)
        sku = await f.sku(client, headers, prod["id"])
        await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop.id, disease.id))


async def test_pest_scope_must_include_the_crop(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, _ = await _claim_setup(client, world, bearer, db_session)
    crops = await f.crops(db_session, world)
    other = next(c for c in crops if c.id != crop_id)
    foreign_pest = await f.pest(db_session, world, crop_id=other.id)
    polyphagous = await f.pest(db_session, world, crop_id=None)
    agro = f.agronomist(world, bearer)
    resp = await client.post(
        "/v1/catalog/label-claims",
        json=f.claim_body(str(sku["id"]), crop_id, foreign_pest.id),
        headers=agro,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "pest_not_for_crop"
    await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop_id, polyphagous.id))
    for missing in ("sku_id", "crop_id", "pest_or_disease_id"):
        body = f.claim_body(str(sku["id"]), crop_id, polyphagous.id)
        body[missing] = str(uuid.uuid4())
        resp = await client.post("/v1/catalog/label-claims", json=body, headers=agro)
        assert resp.status_code == 404, missing


async def test_no_duplicate_approved_claim(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    agro = f.agronomist(world, bearer)
    body = f.claim_body(str(sku["id"]), crop_id, pest_id)
    first = await f.draft_claim(client, agro, body)
    second = await f.draft_claim(client, agro, body)  # two drafts may coexist
    await f.approve(client, agro, str(first["id"]))
    dup = await client.post("/v1/catalog/label-claims", json=body, headers=agro)
    assert dup.status_code == 409 and dup.json()["code"] == "claim_duplicate"
    assert dup.json()["existing_id"] == first["id"]
    late = await client.post(f"/v1/catalog/label-claims/{second['id']}/approve", headers=agro)
    assert late.status_code == 409 and late.json()["code"] == "claim_duplicate"


async def test_edit_of_approved_claim_is_a_new_draft_version(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    agro = f.agronomist(world, bearer)
    v1 = await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop_id, pest_id))

    # Drafts are edited in place.
    resp = await client.patch(
        f"/v1/catalog/label-claims/{v1['id']}", json={"phi_days": 10}, headers=agro
    )
    assert resp.status_code == 200 and resp.json()["id"] == v1["id"]
    assert resp.json()["phi_days"] == 10
    await f.approve(client, agro, str(v1["id"]))

    # Approved claims are immutable: the edit is a new draft superseding v1.
    resp = await client.patch(
        f"/v1/catalog/label-claims/{v1['id']}",
        json={"dose_value": "100", "dose_per_acre": "100 ml per acre"},
        headers=f.owner(world, bearer),
    )
    assert resp.status_code == 200, resp.text
    v2 = resp.json()
    assert v2["id"] != v1["id"] and v2["status"] == "draft"
    assert v2["supersedes_id"] == v1["id"]
    assert v2["dose_value"] == "100.000" and v2["phi_days"] == 10  # copied + changed
    # A second edit reuses the open draft version.
    resp = await client.patch(
        f"/v1/catalog/label-claims/{v1['id']}", json={"phi_days": 12}, headers=agro
    )
    assert resp.json()["id"] == v2["id"] and resp.json()["phi_days"] == 12
    unchanged = await client.get(
        "/v1/catalog/label-claims",
        params={"sku_id": sku["id"], "status": "approved"},
        headers=agro,
    )
    assert [c["id"] for c in unchanged.json()["items"]] == [v1["id"]]
    assert unchanged.json()["items"][0]["dose_value"] == "80.000"

    # Approving v2 retires v1 in the same transaction.
    approved = await f.approve(client, agro, str(v2["id"]))
    assert approved["status"] == "approved"
    history = await client.get(f"/v1/catalog/label-claims/{v1['id']}/history", headers=agro)
    assert history.status_code == 200
    versions = history.json()["items"]
    assert [v["id"] for v in versions] == [v2["id"], v1["id"]]
    assert [v["status"] for v in versions] == ["approved", "retired"]
    assert versions[1]["retired_by"] == str(world.a.user(UserRole.AGRONOMIST).id)
    same = await client.get(f"/v1/catalog/label-claims/{v2['id']}/history", headers=agro)
    assert [v["id"] for v in same.json()["items"]] == [v2["id"], v1["id"]]


async def test_retire_and_retired_is_final(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    agro = f.agronomist(world, bearer)
    claim = await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop_id, pest_id))
    await f.approve(client, agro, str(claim["id"]))
    for role in ("director", "field_officer", "store_manager"):
        resp = await client.post(
            f"/v1/catalog/label-claims/{claim['id']}/retire", headers=bearer(world.a.user(role))
        )
        assert resp.status_code == 403, role
    resp = await client.post(
        f"/v1/catalog/label-claims/{claim['id']}/retire", headers=f.owner(world, bearer)
    )
    assert resp.status_code == 200 and resp.json()["status"] == "retired"
    assert resp.json()["retired_by"] == str(world.a.owner.id)
    assert resp.json()["retired_at"] is not None
    again = await client.post(f"/v1/catalog/label-claims/{claim['id']}/retire", headers=agro)
    assert again.status_code == 409 and again.json()["code"] == "claim_retired"
    edit = await client.patch(
        f"/v1/catalog/label-claims/{claim['id']}", json={"phi_days": 1}, headers=agro
    )
    assert edit.status_code == 409 and edit.json()["code"] == "claim_retired"
    approve = await client.post(f"/v1/catalog/label-claims/{claim['id']}/approve", headers=agro)
    assert approve.status_code == 409 and approve.json()["code"] == "claim_not_draft"
    # A retired triple may be claimed again (new draft).
    await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop_id, pest_id))


async def test_status_all_filter_and_cross_tenant(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, sku, crop_id, pest_id = await _claim_setup(client, world, bearer, db_session)
    agro = f.agronomist(world, bearer)
    claim = await f.draft_claim(client, agro, f.claim_body(str(sku["id"]), crop_id, pest_id))
    everything = await client.get(
        "/v1/catalog/label-claims", params={"status": "all", "sku_id": sku["id"]}, headers=agro
    )
    assert [c["id"] for c in everything.json()["items"]] == [claim["id"]]
    officer = await client.get(
        "/v1/catalog/label-claims",
        params={"status": "all", "sku_id": sku["id"]},
        headers=bearer(world.a.user(UserRole.FIELD_OFFICER)),
    )
    assert officer.json()["items"] == []  # drafts are for maintainers only
    b_agro = bearer(world.b.user(UserRole.AGRONOMIST))
    for path in (
        f"/v1/catalog/label-claims/{claim['id']}/history",
        f"/v1/catalog/label-claims/{claim['id']}/approve",
    ):
        method = client.get if path.endswith("history") else client.post
        resp = await method(path, headers=b_agro)
        assert resp.status_code == 404, path


async def test_reference_lists(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    headers = bearer(world.a.user(UserRole.FIELD_OFFICER))
    crops = (await client.get("/v1/catalog/crops", headers=headers)).json()["items"]
    assert {c["code"] for c in crops} >= {"paddy", "cotton"}
    crop_id = crops[0]["id"]
    own = await f.pest(db_session, world, crop_id=uuid.UUID(crop_id))
    anywhere = await f.pest(db_session, world, crop_id=None)
    pests = (
        await client.get("/v1/catalog/pests", params={"crop_id": crop_id}, headers=headers)
    ).json()["items"]
    ids = {p["id"] for p in pests}
    assert {str(own.id), str(anywhere.id)} <= ids
    assert all(p["crop_id"] in (None, crop_id) for p in pests)

    stores = (await client.get("/v1/catalog/stores", headers=f.owner(world, bearer))).json()
    assert len(stores["items"]) >= 1
    manager = world.a.user(UserRole.STORE_MANAGER)
    mine = (await client.get("/v1/catalog/stores", headers=bearer(manager))).json()["items"]
    assert [s["id"] for s in mine] == [str(manager.store_id)]
