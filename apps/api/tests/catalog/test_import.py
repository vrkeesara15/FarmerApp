"""WC-005 CSV import / export (WC-013 builds on it): dry run by default with a row-level error
report, all or nothing, idempotent re-import, label claims only ever imported as drafts."""

from __future__ import annotations

import csv
import io
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.csv_io import CLAIM_COLUMNS, PRODUCT_COLUMNS
from farmerapp.db.models import AuditLog
from farmerapp.db.session import tenant_scope
from tests.authz.conftest import Bearer, World
from tests.catalog import factory as f

HEADER = ",".join(PRODUCT_COLUMNS)


def _csv(rows: list[dict[str, str]], columns: tuple[str, ...] = PRODUCT_COLUMNS) -> str:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=list(columns))
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return buf.getvalue()


def _product_row(**overrides: str) -> dict[str, str]:
    row = {
        "brand": "ImportCo",
        "product_name": "Import Guard",
        "category": "insecticide",
        "own_brand": "true",
        "hsn": "380891",
        "gst_rate_percent": "18",
        "active_ingredient": "Importamid 20% SL",
        "formulation": "SL",
        "pack_size_value": "250",
        "pack_size_unit": "ml",
        "barcode": "8909990000017",
        "mrp_paise": "42000",
        "active": "true",
    }
    row["category"] = "pesticide"
    row.update(overrides)
    return row


async def _import(
    client: AsyncClient, headers: dict[str, str], kind: str, text: str, dry_run: bool | None = None
) -> dict[str, Any]:
    body: dict[str, Any] = {"csv": text}
    if dry_run is not None:
        body["dry_run"] = dry_run
    resp = await client.post(f"/v1/catalog/import/{kind}", json=body, headers=headers)
    assert resp.status_code == 200, resp.text
    return dict(resp.json())


async def _products(client: AsyncClient, headers: dict[str, str], q: str) -> list[dict[str, Any]]:
    resp = await client.get(
        "/v1/catalog/products", params={"q": q, "include_inactive": "true"}, headers=headers
    )
    return list(resp.json()["items"])


async def test_products_dry_run_by_default_then_apply_then_idempotent(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    text = _csv(
        [
            _product_row(),
            _product_row(
                pack_size_value="1", pack_size_unit="l", barcode="8909990000024", mrp_paise="150000"
            ),
            _product_row(
                product_name="Import Grow",
                category="fertiliser",
                gst_rate_percent="5",
                hsn="3105",
                barcode="",
            ),
        ]
    )
    report = await _import(client, headers, "products", text)
    assert report["dry_run"] is True and report["applied"] is False
    assert report["errors"] == [] and report["rows_total"] == 3 and report["rows_ok"] == 3
    assert report["created"] == 5  # 2 products + 3 SKUs
    assert await _products(client, headers, "Import") == []  # nothing written

    applied = await _import(client, headers, "products", text, dry_run=False)
    assert applied["applied"] is True and applied["created"] == 5
    items = await _products(client, headers, "Import")
    guard = next(p for p in items if p["name"] == "Import Guard")
    assert guard["own_brand"] is True and guard["gst_rate_bp"] == 1800 and guard["hsn"] == "380891"
    assert sorted(s["barcode"] for s in guard["skus"]) == ["8909990000017", "8909990000024"]
    grow = next(p for p in items if p["name"] == "Import Grow")
    assert grow["gst_rate_bp"] == 500

    again = await _import(client, headers, "products", text, dry_run=False)
    assert again["created"] == 0 and again["updated"] == 0 and again["applied"] is True

    changed = _csv([_product_row(mrp_paise="43000")])
    update = await _import(client, headers, "products", changed, dry_run=False)
    assert update["created"] == 0 and update["updated"] == 1


async def test_products_row_level_errors_and_nothing_written(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    existing = await f.product(client, headers, name="Other Thing")
    await f.sku(client, headers, existing["id"], barcode="8909990000999")
    text = _csv(
        [
            _product_row(product_name="Good Row", barcode="8909990000055"),
            _product_row(product_name="Bad Gst", gst_rate_percent="13", barcode="8909990000062"),
            _product_row(product_name="Bad Hsn", hsn="12345", barcode="8909990000079"),
            _product_row(product_name="Bad Category", category="snacks", barcode="8909990000086"),
            _product_row(product_name="Bad Mrp", mrp_paise="-1", barcode="8909990000093"),
            _product_row(product_name="Taken Barcode", barcode="8909990000999"),
            _product_row(product_name="Dup Barcode", barcode="8909990000055"),
            _product_row(product_name="Bad Pack", pack_size_unit="bags", barcode="8909990000109"),
        ]
    )
    report = await _import(client, headers, "products", text, dry_run=False)
    assert report["applied"] is False
    errors = {(e["row"], e["column"], e["code"]) for e in report["errors"]}
    assert (3, "gst_rate_percent", "invalid_value") in errors
    assert (4, "hsn", "invalid_value") in errors
    assert (5, "category", "invalid_value") in errors
    assert (6, "mrp_paise", "invalid_value") in errors
    assert (7, "barcode", "barcode_exists") in errors
    assert (8, "barcode", "barcode_duplicate") in errors
    assert (9, "pack_size_unit", "invalid_value") in errors
    assert report["rows_ok"] == 1
    assert await _products(client, headers, "Good Row") == []


async def test_bad_header_is_reported(client: AsyncClient, world: World, bearer: Bearer) -> None:
    headers = f.owner(world, bearer)
    report = await _import(client, headers, "products", "brand,product_name,colour\nA,B,red\n")
    codes = [e["code"] for e in report["errors"]]
    assert codes == ["missing_columns"]
    report = await _import(client, headers, "products", HEADER + ",colour\n")
    assert [e["code"] for e in report["errors"]] == ["unknown_columns"]


async def test_export_products_round_trips(
    client: AsyncClient, world: World, bearer: Bearer, step_up: Bearer, db_session: AsyncSession
) -> None:
    headers = f.owner(world, bearer)
    # SEC-028: a bulk export needs a fresh step-up token, like the audit export.
    no_step_up = await client.get(
        "/v1/catalog/export", params={"kind": "products"}, headers=headers
    )
    assert no_step_up.status_code == 401
    assert no_step_up.json()["code"] == "step_up_required"
    resp = await client.get(
        "/v1/catalog/export",
        params={"kind": "products"},
        headers={**headers, **step_up(world.a.owner)},
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/csv")
    assert "attachment" in resp.headers["content-disposition"]
    rows = list(csv.DictReader(io.StringIO(resp.text)))
    assert tuple(rows[0].keys()) == PRODUCT_COLUMNS
    assert len(rows) == 10  # SMALL seed: 10 SKUs
    assert all(r["gst_rate_percent"] in {"0", "5", "12", "18"} for r in rows)
    # Re-importing the export changes nothing.
    report = await _import(client, headers, "products", resp.text, dry_run=True)
    assert report["errors"] == [] and report["created"] == 0 and report["updated"] == 0
    async with tenant_scope(db_session, world.a.tenant.id):
        logged = await db_session.scalar(
            select(AuditLog).where(AuditLog.action == "catalog.export").limit(1)
        )
    assert logged is not None and logged.after == {"kind": "products", "rows": 10}


async def test_label_claims_import_creates_drafts_only(
    client: AsyncClient, world: World, bearer: Bearer, step_up: Bearer, db_session: AsyncSession
) -> None:
    headers = f.owner(world, bearer)
    agro = f.agronomist(world, bearer)
    prod = await f.product(client, headers)
    sku = await f.sku(client, headers, prod["id"], barcode="8909990001001")
    crop = (await f.crops(db_session, world))[0]
    pest = await f.pest(db_session, world, crop_id=crop.id)
    seed_prod = await f.product(client, headers, category="seed", gst_rate_bp=0)
    seed_sku = await f.sku(client, headers, seed_prod["id"], barcode="8909990001002")

    def row(**overrides: str) -> dict[str, str]:
        base = {
            "id": "",
            "status": "approved",  # ignored: imports never approve (SPEC 14.6)
            "sku_barcode": "8909990001001",
            "crop_code": crop.code,
            "pest_code": pest.code,
            "dose_per_acre": "80 ml per acre",
            "dose_value": "80",
            "dose_unit": "ml",
            "dose_per_tank_15l": "7 ml",
            "phi_days": "14",
            "ppe_text": "Gloves",
            "safety_text": "Keep away from children",
            "source_ref": "CIB&RC import",
            "efficacy_tier": "2",
        }
        base.update(overrides)
        return base

    text = _csv(
        [
            row(),
            row(sku_barcode="0000"),
            row(crop_code="mango"),
            row(sku_barcode="8909990001002"),
            row(dose_value="0", phi_days="-2"),
            row(),
        ],
        CLAIM_COLUMNS,
    )
    report = await _import(client, agro, "label-claims", text, dry_run=True)
    errors = {(e["row"], e["column"], e["code"]) for e in report["errors"]}
    assert (3, "sku_barcode", "not_found") in errors
    assert (4, "crop_code", "not_found") in errors
    assert (5, "pest_code", "claim_category_invalid") in errors
    assert (6, "dose_value", "invalid_value") in errors
    assert (6, "phi_days", "invalid_value") in errors
    assert (7, None, "claim_duplicate") in errors
    assert report["rows_ok"] == 1

    good = _csv([row()], CLAIM_COLUMNS)
    applied = await _import(client, agro, "label-claims", good, dry_run=False)
    assert applied["applied"] is True and applied["created"] == 1
    listed = await client.get(
        "/v1/catalog/label-claims", params={"sku_id": sku["id"], "status": "all"}, headers=agro
    )
    claims = listed.json()["items"]
    assert [c["status"] for c in claims] == ["draft"]
    assert claims[0]["efficacy_tier"] == 2 and claims[0]["phi_days"] == 14

    # Re-import updates the open draft; after approval a changed row is a new draft version.
    changed = _csv([row(phi_days="21")], CLAIM_COLUMNS)
    upd = await _import(client, agro, "label-claims", changed, dry_run=False)
    assert upd["updated"] == 1 and upd["created"] == 0
    await f.approve(client, agro, claims[0]["id"])
    same = await _import(client, agro, "label-claims", changed, dry_run=False)
    assert same["created"] == 0 and same["updated"] == 0
    newer = _csv([row(phi_days="30")], CLAIM_COLUMNS)
    version = await _import(client, agro, "label-claims", newer, dry_run=False)
    assert version["created"] == 1
    listed = await client.get(
        "/v1/catalog/label-claims", params={"sku_id": sku["id"], "status": "draft"}, headers=agro
    )
    draft = listed.json()["items"][0]
    assert draft["supersedes_id"] == claims[0]["id"] and draft["phi_days"] == 30

    exported = await client.get(
        "/v1/catalog/export",
        params={"kind": "label_claims"},
        headers={**agro, **step_up(world.a.user(UserRole.AGRONOMIST))},
    )
    out = list(csv.DictReader(io.StringIO(exported.text)))
    assert tuple(out[0].keys()) == CLAIM_COLUMNS
    mine = [r for r in out if r["sku_barcode"] == "8909990001001"]
    assert sorted(r["status"] for r in mine) == ["approved", "draft"]
    assert seed_sku["barcode"] not in {r["sku_barcode"] for r in out}


async def test_import_roles_per_kind(client: AsyncClient, world: World, bearer: Bearer) -> None:
    body = {"csv": HEADER + "\n"}
    director = bearer(world.a.user(UserRole.DIRECTOR))
    agro = f.agronomist(world, bearer)
    assert (
        await client.post("/v1/catalog/import/products", json=body, headers=agro)
    ).status_code == 403
    assert (
        await client.post("/v1/catalog/import/label-claims", json=body, headers=director)
    ).status_code == 403
    assert (
        await client.post("/v1/catalog/import/products", json=body, headers=director)
    ).status_code == 200
    officer = bearer(world.a.user(UserRole.FIELD_OFFICER))
    assert (await client.get("/v1/catalog/export", headers=officer)).status_code == 403
