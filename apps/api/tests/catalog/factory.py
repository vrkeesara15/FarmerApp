"""Small builders for the WC-005 tests: products, SKUs, pests and claims in tenant A."""

from __future__ import annotations

import itertools
import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.db.session import tenant_scope
from tests.authz.conftest import Bearer, World

_seq = itertools.count(1)


def unique(prefix: str) -> str:
    return f"{prefix}-{next(_seq)}-{uuid.uuid4().hex[:6]}"


def owner(world: World, bearer: Bearer) -> dict[str, str]:
    return bearer(world.a.owner)


def agronomist(world: World, bearer: Bearer) -> dict[str, str]:
    return bearer(world.a.user(UserRole.AGRONOMIST))


async def product(client: AsyncClient, headers: dict[str, str], **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "name": unique("Test Product"),
        "brand": "TestBrand",
        "category": "pesticide",
        "hsn": "3808",
        "gst_rate_bp": 1800,
        "active_ingredient": "Testamid 10% SC",
    }
    body.update(overrides)
    resp = await client.post("/v1/catalog/products", json=body, headers=headers)
    assert resp.status_code == 201, resp.text
    return dict(resp.json())


async def sku(
    client: AsyncClient, headers: dict[str, str], product_id: str, **overrides: Any
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "product_id": product_id,
        "pack_size_value": "250",
        "pack_size_unit": "ml",
        "barcode": unique("BC"),
        "mrp_paise": 45000,
    }
    body.update(overrides)
    resp = await client.post("/v1/catalog/skus", json=body, headers=headers)
    assert resp.status_code == 201, resp.text
    return dict(resp.json())


async def crops(db_session: AsyncSession, world: World) -> list[Crop]:
    async with tenant_scope(db_session, world.a.tenant.id):
        return list((await db_session.execute(select(Crop).order_by(Crop.code))).scalars().all())


async def pest(
    db_session: AsyncSession,
    world: World,
    *,
    crop_id: uuid.UUID | None,
    type: str = "pest",
) -> PestOrDisease:
    async with tenant_scope(db_session, world.a.tenant.id):
        row = PestOrDisease(
            tenant_id=world.a.tenant.id,
            code=unique("pest").lower(),
            name=unique("Pest"),
            type=type,
            crop_id=crop_id,
        )
        db_session.add(row)
        await db_session.flush()
        return row


def claim_body(
    sku_id: str, crop_id: uuid.UUID, pest_id: uuid.UUID, **overrides: Any
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "sku_id": sku_id,
        "crop_id": str(crop_id),
        "pest_or_disease_id": str(pest_id),
        "dose_per_acre": "80 ml per acre",
        "dose_value": "80",
        "dose_unit": "ml",
        "dose_per_tank_15l": "7 ml",
        "phi_days": 14,
        "ppe_text": "Gloves, mask, long sleeves",
        "safety_text": "Do not spray against the wind.",
        "source_ref": "CIB&RC test reference",
        "efficacy_tier": 1,
    }
    body.update(overrides)
    return body


async def draft_claim(
    client: AsyncClient, headers: dict[str, str], body: dict[str, Any]
) -> dict[str, Any]:
    resp = await client.post("/v1/catalog/label-claims", json=body, headers=headers)
    assert resp.status_code == 201, resp.text
    return dict(resp.json())


async def approve(client: AsyncClient, headers: dict[str, str], claim_id: str) -> dict[str, Any]:
    resp = await client.post(f"/v1/catalog/label-claims/{claim_id}/approve", headers=headers)
    assert resp.status_code == 200, resp.text
    return dict(resp.json())
