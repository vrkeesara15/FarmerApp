"""WC-005 price lists by store: bulk upsert (tenant default or store), price <= MRP, no
overlapping effective ranges per SKU + store, ``GET`` with ``store_id`` / ``at``, and the
``price_for`` resolver picking up the new rows."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.models import PriceList
from farmerapp.catalog.pricing import price_for
from farmerapp.db.session import tenant_scope
from tests.authz.conftest import Bearer, World
from tests.catalog import factory as f


async def _sku(client: AsyncClient, headers: dict[str, str], mrp: int = 50_000) -> str:
    prod = await f.product(client, headers)
    return str((await f.sku(client, headers, prod["id"], mrp_paise=mrp))["id"])


async def _put(
    client: AsyncClient, headers: dict[str, str], store_id: str | None, items: list[dict[str, Any]]
) -> Any:
    return await client.put(
        "/v1/catalog/price-lists", json={"store_id": store_id, "items": items}, headers=headers
    )


async def test_upsert_default_and_store_rows_and_read_back(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    headers = f.owner(world, bearer)
    sku = await _sku(client, headers)
    store = str(world.a.store_id)
    resp = await _put(
        client,
        headers,
        None,
        [
            {
                "sku_id": sku,
                "price_paise": 48_000,
                "effective_from": "2026-01-01",
                "effective_to": "2026-06-30",
            },
            {"sku_id": sku, "price_paise": 47_000, "effective_from": "2026-07-01"},
        ],
    )
    assert resp.status_code == 200, resp.text
    rows = resp.json()["items"]
    assert [r["price_paise"] for r in rows] == [48_000, 47_000]
    assert all(r["store_id"] is None and r["mrp_paise"] == 50_000 for r in rows)
    resp = await _put(
        client,
        headers,
        store,
        [{"sku_id": sku, "price_paise": 45_000, "effective_from": "2026-09-01"}],
    )
    assert resp.status_code == 200, resp.text

    default = await client.get("/v1/catalog/price-lists", params={"sku_id": sku}, headers=headers)
    assert [r["effective_from"] for r in default.json()["items"]] == ["2026-07-01", "2026-01-01"]
    in_force = await client.get(
        "/v1/catalog/price-lists", params={"sku_id": sku, "at": "2026-03-15"}, headers=headers
    )
    assert [r["price_paise"] for r in in_force.json()["items"]] == [48_000]
    at_store = await client.get(
        "/v1/catalog/price-lists",
        params={"store_id": store, "sku_id": sku},
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    assert [r["price_paise"] for r in at_store.json()["items"]] == [45_000]

    async with tenant_scope(db_session, world.a.tenant.id):
        sku_id = uuid.UUID(sku)
        assert await price_for(db_session, sku_id, world.a.store_id, date(2026, 9, 18)) == 45_000
        assert await price_for(db_session, sku_id, world.a.store_id, date(2026, 8, 1)) == 47_000
        assert await price_for(db_session, sku_id, None, date(2026, 3, 1)) == 48_000
        assert await price_for(db_session, sku_id, None, date(2025, 3, 1)) is None


async def test_same_effective_from_updates_the_row(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    sku = await _sku(client, headers)
    first = await _put(
        client,
        headers,
        None,
        [{"sku_id": sku, "price_paise": 40_000, "effective_from": "2026-01-01"}],
    )
    row = first.json()["items"][0]
    second = await _put(
        client,
        headers,
        None,
        [{"sku_id": sku, "price_paise": 41_000, "effective_from": "2026-01-01"}],
    )
    assert second.status_code == 200
    updated = second.json()["items"][0]
    assert updated["id"] == row["id"] and updated["price_paise"] == 41_000
    assert updated["version"] == row["version"] + 1


async def test_price_above_mrp_is_rejected_per_row(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    sku = await _sku(client, headers, mrp=10_000)
    ok = await _sku(client, headers, mrp=10_000)
    resp = await _put(
        client,
        headers,
        str(world.a.store_id),
        [
            {"sku_id": ok, "price_paise": 10_000, "effective_from": "2026-01-01"},
            {"sku_id": sku, "price_paise": 10_001, "effective_from": "2026-01-01"},
        ],
    )
    assert resp.status_code == 422, resp.text
    body = resp.json()
    assert body["code"] == "price_above_mrp"
    assert body["rows"] == [{"index": 1, "sku_id": sku, "code": "price_above_mrp"}]
    listed = await client.get(
        "/v1/catalog/price-lists",
        params={"store_id": str(world.a.store_id), "sku_id": ok},
        headers=headers,
    )
    assert listed.json()["items"] == []  # all or nothing


@pytest.mark.parametrize(
    ("existing", "new"),
    [
        (("2026-01-01", None), ("2026-06-01", None)),
        (("2026-01-01", "2026-06-30"), ("2026-06-30", None)),
        (("2026-03-01", "2026-03-31"), ("2026-01-01", "2026-12-31")),
        (("2026-06-01", None), ("2026-01-01", "2026-06-01")),
    ],
)
async def test_overlapping_ranges_are_409(
    client: AsyncClient,
    world: World,
    bearer: Bearer,
    existing: tuple[str, str | None],
    new: tuple[str, str | None],
) -> None:
    headers = f.owner(world, bearer)
    sku = await _sku(client, headers)
    store = str(world.a.store_id)
    first = await _put(
        client,
        headers,
        store,
        [
            {
                "sku_id": sku,
                "price_paise": 1,
                "effective_from": existing[0],
                "effective_to": existing[1],
            }
        ],
    )
    assert first.status_code == 200
    resp = await _put(
        client,
        headers,
        store,
        [{"sku_id": sku, "price_paise": 2, "effective_from": new[0], "effective_to": new[1]}],
    )
    assert resp.status_code == 409, resp.text
    body = resp.json()
    assert body["code"] == "price_overlap"
    assert body["rows"][0]["index"] == 0
    assert body["rows"][0]["conflicting_id"] == first.json()["items"][0]["id"]
    # The same range for another store or the tenant default is independent.
    other = await _put(
        client,
        headers,
        None,
        [{"sku_id": sku, "price_paise": 2, "effective_from": new[0], "effective_to": new[1]}],
    )
    assert other.status_code == 200


async def test_overlap_within_a_batch_and_close_then_open(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = f.owner(world, bearer)
    sku = await _sku(client, headers)
    both = await _put(
        client,
        headers,
        None,
        [
            {"sku_id": sku, "price_paise": 1, "effective_from": "2026-01-01"},
            {"sku_id": sku, "price_paise": 2, "effective_from": "2026-05-01"},
        ],
    )
    assert both.status_code == 409
    assert {r["index"] for r in both.json()["rows"]} == {0, 1}

    await _put(
        client, headers, None, [{"sku_id": sku, "price_paise": 1, "effective_from": "2026-01-01"}]
    )
    # Closing the open row and opening the next one in one batch is fine.
    resp = await _put(
        client,
        headers,
        None,
        [
            {
                "sku_id": sku,
                "price_paise": 1,
                "effective_from": "2026-01-01",
                "effective_to": "2026-04-30",
            },
            {"sku_id": sku, "price_paise": 2, "effective_from": "2026-05-01"},
        ],
    )
    assert resp.status_code == 200, resp.text


async def test_validation_and_scope(client: AsyncClient, world: World, bearer: Bearer) -> None:
    headers = f.owner(world, bearer)
    sku = await _sku(client, headers)
    backwards = await _put(
        client,
        headers,
        None,
        [
            {
                "sku_id": sku,
                "price_paise": 1,
                "effective_from": "2026-05-01",
                "effective_to": "2026-04-01",
            }
        ],
    )
    assert backwards.status_code == 422
    empty = await _put(client, headers, None, [])
    assert empty.status_code == 422
    unknown_sku = await _put(
        client,
        headers,
        None,
        [{"sku_id": str(uuid.uuid4()), "price_paise": 1, "effective_from": "2026-01-01"}],
    )
    assert unknown_sku.status_code == 404
    foreign_store = await _put(
        client,
        headers,
        str(world.b.store_id),
        [{"sku_id": sku, "price_paise": 1, "effective_from": "2026-01-01"}],
    )
    assert foreign_store.status_code == 404
    other_store_reader = await client.get(
        "/v1/catalog/price-lists",
        params={"store_id": str(world.b.store_id)},
        headers=headers,
    )
    assert other_store_reader.status_code == 404
    for role in ("store_manager", "agronomist", "field_officer"):
        resp = await _put(
            client,
            bearer(world.a.user(role)),
            None,
            [{"sku_id": sku, "price_paise": 1, "effective_from": "2026-01-01"}],
        )
        assert resp.status_code == 403, role


async def test_store_manager_reads_only_own_store(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    manager = world.a.user(UserRole.STORE_MANAGER)
    async with tenant_scope(db_session, world.a.tenant.id):
        from sqlalchemy import select

        from farmerapp.tenants.models import Store

        other = await db_session.scalar(
            select(Store.id).where(Store.id != manager.store_id).limit(1)
        )
    if other is None:
        pytest.skip("the SMALL seed has a single store")
    resp = await client.get(
        "/v1/catalog/price-lists", params={"store_id": str(other)}, headers=bearer(manager)
    )
    assert resp.status_code == 404


async def test_database_backstop_rejects_overlaps(world: World, db_session: AsyncSession) -> None:
    async with tenant_scope(db_session, world.a.tenant.id):
        sku_id = world.a.sku_id
        assert sku_id is not None
        db_session.add(
            PriceList(
                tenant_id=world.a.tenant.id,
                sku_id=sku_id,
                store_id=world.a.store_id,
                price_paise=1,
                effective_from=date(2030, 1, 1),
            )
        )
        await db_session.flush()
        with pytest.raises(IntegrityError, match="ex_price_list_no_overlap"):
            async with db_session.begin_nested():
                db_session.add(
                    PriceList(
                        tenant_id=world.a.tenant.id,
                        sku_id=sku_id,
                        store_id=world.a.store_id,
                        price_paise=2,
                        effective_from=date(2031, 1, 1),
                    )
                )
                await db_session.flush()
