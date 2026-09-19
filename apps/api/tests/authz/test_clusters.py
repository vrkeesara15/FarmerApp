"""``GET /v1/clusters``: names, district and store ids for the console filters and pickers,
scoped per SPEC 2.6 (tenant-wide roles see every cluster, a cluster head their own, a store
manager / field officer the cluster of their store with only that store, agronomists none)."""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.tenants.models import Cluster, Store
from tests.authz.conftest import Bearer, World


async def _expected(session: AsyncSession, tenant_id: uuid.UUID) -> dict[str, list[str]]:
    clusters = (
        (await session.execute(select(Cluster).where(Cluster.tenant_id == tenant_id)))
        .scalars()
        .all()
    )
    stores = (
        await session.execute(
            select(Store.id, Store.cluster_id)
            .where(Store.tenant_id == tenant_id, Store.cluster_id.is_not(None))
            .order_by(Store.code)
        )
    ).all()
    return {str(c.id): [str(s) for s, cid in stores if cid == c.id] for c in clusters}


@pytest.mark.parametrize("role", ["owner", "director", "tenant_admin", "auditor", "accountant"])
async def test_tenant_wide_roles_see_every_cluster_with_names(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession, role: str
) -> None:
    expected = await _expected(db_session, world.a.tenant.id)
    assert expected, "the seed must have clusters"
    resp = await client.get("/v1/clusters", headers=bearer(world.a.user(role)))
    assert resp.status_code == 200, resp.text
    items = resp.json()["items"]
    assert {i["id"]: i["store_ids"] for i in items} == expected
    assert all(i["name"] and i["state"] for i in items)
    assert [i["name"] for i in items] == sorted(i["name"] for i in items)


async def test_cluster_head_sees_own_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    head = world.a.user(UserRole.CLUSTER_HEAD)
    assert head.cluster_id is not None
    expected = await _expected(db_session, world.a.tenant.id)
    resp = await client.get("/v1/clusters", headers=bearer(head))
    assert resp.status_code == 200, resp.text
    items = resp.json()["items"]
    assert [i["id"] for i in items] == [str(head.cluster_id)]
    assert items[0]["store_ids"] == expected[str(head.cluster_id)]


@pytest.mark.parametrize("role", ["store_manager", "field_officer"])
async def test_store_roles_see_their_store_in_its_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession, role: str
) -> None:
    user = world.a.user(role)
    assert user.store_id is not None
    store = await db_session.get(Store, user.store_id)
    assert store is not None
    resp = await client.get("/v1/clusters", headers=bearer(user))
    assert resp.status_code == 200, resp.text
    items = resp.json()["items"]
    assert [(i["id"], i["store_ids"]) for i in items] == [
        (str(store.cluster_id), [str(user.store_id)])
    ]


async def test_agronomist_gets_an_empty_list_and_farmers_are_refused(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    resp = await client.get("/v1/clusters", headers=bearer(world.a.user(UserRole.AGRONOMIST)))
    assert resp.status_code == 200 and resp.json() == {"items": []}
    resp = await client.get("/v1/clusters", headers=bearer(world.a.user(UserRole.FARMER)))
    assert resp.status_code == 403


async def test_other_tenants_clusters_never_appear(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    a_ids = set(await _expected(db_session, world.a.tenant.id))
    resp = await client.get("/v1/clusters", headers=bearer(world.b.owner))
    assert resp.status_code == 200, resp.text
    assert resp.json()["items"], "tenant B has clusters of its own"
    assert a_ids and not a_ids & {i["id"] for i in resp.json()["items"]}
