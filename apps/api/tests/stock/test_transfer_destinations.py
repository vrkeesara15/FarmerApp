"""ST-003 transfer destinations: ``GET /v1/stock/transfer-destinations`` per role and the
store-manager limits on ``POST /v1/stock/transfers`` (own store -> own cluster only).

Seeded tenant A (fcc): the store manager runs WGL (North Telangana: WGL, KNR, NZB), the
cluster head heads North Telangana, South Telangana is NLG and KMM; the accountant has no
store or cluster. ``/v1/catalog/stores`` keeps scoping the store manager to WGL."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.tenants.models import Store
from tests.authz.conftest import Bearer, World
from tests.orders.helpers import assert_cache_matches_ledger, receive

URL = "/v1/stock/transfer-destinations"


async def _stores(db_session: AsyncSession, world: World) -> dict[str, Store]:
    async with tenant_scope(db_session, world.a.tenant.id):
        rows = (await db_session.execute(select(Store))).scalars().all()
    return {s.code: s for s in rows}


async def _destinations(
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    role: str,
    *,
    from_store: Store | None = None,
    expect: int = 200,
) -> dict[str, Any]:
    params = {"from_store_id": str(from_store.id)} if from_store is not None else None
    resp = await client.get(URL, params=params, headers=bearer(world.a.user(role)))
    assert resp.status_code == expect, resp.text
    body: dict[str, Any] = resp.json()
    return body


def _codes(body: dict[str, Any], stores: dict[str, Store]) -> list[str]:
    by_id = {str(s.id): code for code, s in stores.items()}
    return [by_id[item["id"]] for item in body["items"]]


async def test_store_manager_sees_the_other_stores_of_their_cluster_nearest_first(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    stores = await _stores(db_session, world)
    body = await _destinations(client, bearer, world, "store_manager")
    assert body["from_store_id"] == str(stores["WGL"].id)
    # KNR (~85 km) is nearer to Warangal than NZB (~175 km); the South cluster is absent.
    assert _codes(body, stores) == ["KNR", "NZB"]
    knr, nzb = body["items"]
    assert knr["name"] == "FCC Karimnagar" and knr["district"] == "Karimnagar"
    assert knr["cluster_id"] == str(stores["WGL"].cluster_id)
    assert 60_000 < knr["distance_m"] < 110_000 < nzb["distance_m"] < 220_000
    # Naming their own store is the same answer; any other store is 403.
    same = await _destinations(client, bearer, world, "store_manager", from_store=stores["WGL"])
    assert same == body
    for code in ("KNR", "NLG"):
        problem = await _destinations(
            client, bearer, world, "store_manager", from_store=stores[code], expect=403
        )
        assert problem["code"] == "transfer_source_not_allowed"
    # The catalogue list stays scoped to the manager's own store.
    resp = await client.get(
        "/v1/catalog/stores", headers=bearer(world.a.user(UserRole.STORE_MANAGER))
    )
    assert resp.status_code == 200
    assert [s["id"] for s in resp.json()["items"]] == [str(stores["WGL"].id)]


async def test_deleted_stores_and_other_tenants_are_never_destinations(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    stores = await _stores(db_session, world)
    async with tenant_scope(db_session, world.a.tenant.id):
        knr = await db_session.get_one(Store, stores["KNR"].id)
        knr.deleted_at = datetime.now(UTC)
        await db_session.flush()
    body = await _destinations(client, bearer, world, "store_manager")
    assert _codes(body, stores) == ["NZB"]
    everything = await _destinations(client, bearer, world, "owner")
    assert "KNR" not in _codes(everything, stores)
    assert str(world.b.store_id) not in {i["id"] for i in everything["items"]}


async def test_cluster_head_sees_their_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    stores = await _stores(db_session, world)
    # No store of their own: the whole cluster, by code, without distances.
    body = await _destinations(client, bearer, world, "cluster_head")
    assert body["from_store_id"] is None
    assert _codes(body, stores) == ["KNR", "NZB", "WGL"]
    assert all(item["distance_m"] is None for item in body["items"])
    # From one of their stores: the others, with distances.
    body = await _destinations(client, bearer, world, "cluster_head", from_store=stores["WGL"])
    assert body["from_store_id"] == str(stores["WGL"].id)
    assert _codes(body, stores) == ["KNR", "NZB"]
    assert all(item["distance_m"] > 0 for item in body["items"])
    # A store of another cluster is outside their scope: 404, as for any store internal.
    await _destinations(client, bearer, world, "cluster_head", from_store=stores["NLG"], expect=404)
    await _destinations(
        client, bearer, world, "cluster_head", from_store=world_b_store(world), expect=404
    )


def world_b_store(world: World) -> Store:
    """A stand-in ``Store`` with tenant B's store id (only the id is used)."""
    assert world.b.store_id is not None
    return Store(id=world.b.store_id)


@pytest.mark.parametrize("role", ["owner", "director", "tenant_admin"])
async def test_management_sees_every_store_of_the_tenant(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession, role: str
) -> None:
    stores = await _stores(db_session, world)
    body = await _destinations(client, bearer, world, role)
    assert body["from_store_id"] is None
    assert _codes(body, stores) == sorted(stores)
    body = await _destinations(client, bearer, world, role, from_store=stores["NLG"])
    assert _codes(body, stores)[0] == "KMM"  # Khammam is Nalgonda's nearest store
    assert sorted(_codes(body, stores)) == sorted(set(stores) - {"NLG"})
    distances = [item["distance_m"] for item in body["items"]]
    assert distances == sorted(distances)


async def test_accountant_follows_the_origin_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    stores = await _stores(db_session, world)
    # Not placed anywhere (finance sees the whole tenant): every store.
    body = await _destinations(client, bearer, world, "accountant")
    assert body["from_store_id"] is None and _codes(body, stores) == sorted(stores)
    # From a store: that store's cluster only (cross-cluster stores are not destinations).
    body = await _destinations(client, bearer, world, "accountant", from_store=stores["NLG"])
    assert _codes(body, stores) == ["KMM"]
    body = await _destinations(client, bearer, world, "accountant", from_store=stores["NZB"])
    assert _codes(body, stores) == ["KNR", "WGL"]


@pytest.mark.parametrize("role", ["auditor", "field_officer", "agronomist", "farmer"])
async def test_other_roles_are_forbidden(
    client: AsyncClient, world: World, bearer: Bearer, role: str
) -> None:
    problem = await _destinations(client, bearer, world, role, expect=403)
    assert problem["code"] == "forbidden"


async def test_store_without_a_cluster_has_no_destinations_for_its_manager(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    async with tenant_scope(db_session, world.a.tenant.id):
        wgl = await db_session.get_one(Store, world.a.store_id)
        wgl.cluster_id = None
        await db_session.flush()
    body = await _destinations(client, bearer, world, "store_manager")
    assert body["items"] == []


# --------------------------------------------------------------------------- transfers
async def _transfer(
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    *,
    batch: dict[str, Any],
    source: Store,
    target: Store,
    role: str = "store_manager",
) -> Any:
    return await client.post(
        "/v1/stock/transfers",
        json={
            "from_store_id": str(source.id),
            "to_store_id": str(target.id),
            "lines": [{"batch_id": batch["id"], "qty": "1"}],
        },
        headers=bearer(world.a.user(role)),
    )


async def test_store_manager_transfers_only_within_the_returned_set(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    stores = await _stores(db_session, world)
    batch = await receive(client, bearer, world, qty=10, batch_no="XFER-1")
    wgl = stores["WGL"]
    ok = await _transfer(client, bearer, world, batch=batch, source=wgl, target=stores["KNR"])
    assert ok.status_code == 201, ok.text
    for code in ("NLG", "KMM"):  # another cluster
        resp = await _transfer(client, bearer, world, batch=batch, source=wgl, target=stores[code])
        assert resp.status_code == 403, resp.text
        assert resp.json()["code"] == "transfer_destination_not_allowed"
    # From a store that is not theirs (even with a batch of that store): 403.
    knr_batch = await receive(
        client, bearer, world, qty=5, store_id=stores["KNR"].id, actor=world.a.owner
    )
    resp = await _transfer(client, bearer, world, batch=knr_batch, source=stores["KNR"], target=wgl)
    assert resp.status_code == 403 and resp.json()["code"] == "transfer_source_not_allowed"
    # Unknown destination: 404; the same store: 422 (unchanged).
    resp = await client.post(
        "/v1/stock/transfers",
        json={
            "from_store_id": str(wgl.id),
            "to_store_id": str(uuid.uuid4()),
            "lines": [{"batch_id": batch["id"], "qty": "1"}],
        },
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    assert resp.status_code == 404
    resp = await _transfer(client, bearer, world, batch=batch, source=wgl, target=wgl)
    assert resp.status_code == 422
    # A deleted store of the cluster is no destination any more.
    async with tenant_scope(db_session, world.a.tenant.id):
        nzb = await db_session.get_one(Store, stores["NZB"].id)
        nzb.deleted_at = datetime.now(UTC)
        await db_session.flush()
    resp = await _transfer(client, bearer, world, batch=batch, source=wgl, target=stores["NZB"])
    assert resp.status_code == 404
    async with tenant_scope(db_session, world.a.tenant.id):
        await assert_cache_matches_ledger(db_session, [wgl.id, stores["KNR"].id])


async def test_cluster_head_and_owner_keep_their_transfer_scope(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    stores = await _stores(db_session, world)
    batch = await receive(client, bearer, world, qty=10, batch_no="XFER-2")
    wgl = stores["WGL"]
    for role in ("cluster_head", "owner"):
        resp = await _transfer(
            client, bearer, world, batch=batch, source=wgl, target=stores["NLG"], role=role
        )
        assert resp.status_code == 201, (role, resp.text)
    # A cluster head cannot move stock out of another cluster's store (store scope: 404).
    nlg_batch = await receive(
        client, bearer, world, qty=3, store_id=stores["NLG"].id, actor=world.a.owner
    )
    resp = await _transfer(
        client,
        bearer,
        world,
        batch=nlg_batch,
        source=stores["NLG"],
        target=wgl,
        role="cluster_head",
    )
    assert resp.status_code == 404
