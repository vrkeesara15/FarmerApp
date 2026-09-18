"""``GET /v1/farmers`` and ``GET /v1/farmers/{id}``: SPEC 2.6 row scope per role, PII
redaction for the agronomist, cursor pagination, nested farms / crop plots / consents."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.tenants.models import Store, Village
from tests.authz.conftest import Bearer, World


async def _all_pages(
    client: AsyncClient, headers: dict[str, str], limit: int, **params: str
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(100):
        query = {"limit": str(limit), **params} | ({"cursor": cursor} if cursor else {})
        resp = await client.get("/v1/farmers", params=query, headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert len(body["items"]) <= limit
        items.extend(body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            return items
    raise AssertionError("pagination did not terminate")


async def test_owner_lists_every_farmer_with_cursor_pagination(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    items = await _all_pages(client, bearer(world.a.owner), limit=4)
    ids = [i["id"] for i in items]
    assert len(ids) == len(set(ids)) == len(world.a.farmers) == 15
    assert [(i["created_at"], i["id"]) for i in items] == sorted(
        (i["created_at"], i["id"]) for i in items
    )
    first = items[0]
    assert set(first) >= {
        "id", "tenant_id", "phone", "phone_last4", "name", "village_id", "landmark", "language",
        "consent_marketing", "consent_version", "registered_by", "user_id", "source",
        "land_ownership", "created_at", "updated_at", "version",
    }  # fmt: skip
    assert first["phone"].startswith("+91") and first["phone_last4"] == first["phone"][-4:]
    assert all(i["tenant_id"] == str(world.a.tenant.id) for i in items)
    assert not any(i["phone"].startswith("+9191") for i in items)  # nothing of tenant B


async def test_filters_by_village_and_officer(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    farmer = world.a.farmer
    headers = bearer(world.a.owner)
    by_village = await _all_pages(client, headers, limit=50, village_id=str(farmer.village_id))
    assert by_village and all(i["village_id"] == str(farmer.village_id) for i in by_village)
    by_officer = await _all_pages(
        client, headers, limit=50, registered_by=str(farmer.registered_by)
    )
    assert by_officer and all(i["registered_by"] == str(farmer.registered_by) for i in by_officer)
    assert len(by_officer) == 3  # 15 farmers over 5 officers


async def test_field_officer_sees_only_farmers_they_registered(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    items = await _all_pages(client, bearer(officer), limit=50)
    assert items and all(i["registered_by"] == str(officer.id) for i in items)
    assert len(items) == sum(f.registered_by == officer.id for f in world.a.farmers)
    other = next(f for f in world.a.farmers if f.registered_by != officer.id)
    resp = await client.get(f"/v1/farmers/{other.id}", headers=bearer(officer))
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    mine = next(f for f in world.a.farmers if f.registered_by == officer.id)
    resp = await client.get(f"/v1/farmers/{mine.id}", headers=bearer(officer))
    assert resp.status_code == 200 and resp.json()["id"] == str(mine.id)


async def test_store_manager_sees_own_store_via_villages(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    manager = world.a.user(UserRole.STORE_MANAGER)
    assert manager.store_id is not None
    async with tenant_scope(db_session, world.a.tenant.id):
        villages = {
            v.id
            for v in (
                await db_session.execute(
                    select(Village).where(Village.store_id == manager.store_id)
                )
            ).scalars()
        }
    items = await _all_pages(client, bearer(manager), limit=50)
    assert items and {uuid.UUID(i["village_id"]) for i in items} <= villages
    assert len(items) == sum(f.village_id in villages for f in world.a.farmers) == 3
    manager.store_id = None
    await db_session.flush()
    resp = await client.get("/v1/farmers", headers=bearer(manager))
    assert resp.status_code == 200 and resp.json()["items"] == []


async def test_cluster_head_sees_own_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    head = world.a.user(UserRole.CLUSTER_HEAD)
    assert head.cluster_id is not None
    async with tenant_scope(db_session, world.a.tenant.id):
        stores = (
            (await db_session.execute(select(Store.id).where(Store.cluster_id == head.cluster_id)))
            .scalars()
            .all()
        )
        villages = {
            v.id
            for v in (
                await db_session.execute(select(Village).where(Village.store_id.in_(stores)))
            ).scalars()
        }
    assert len(stores) == 3  # North Telangana: Warangal, Karimnagar, Nizamabad
    items = await _all_pages(client, bearer(head), limit=50)
    assert items and {uuid.UUID(i["village_id"]) for i in items} == villages
    assert len(items) == sum(f.village_id in villages for f in world.a.farmers) == 9
    outside = next(f for f in world.a.farmers if f.village_id not in villages)
    resp = await client.get(f"/v1/farmers/{outside.id}", headers=bearer(head))
    assert resp.status_code == 404


async def test_agronomist_reads_crop_data_without_pii(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    agro = world.a.user(UserRole.AGRONOMIST)
    items = await _all_pages(client, bearer(agro), limit=50)
    assert len(items) == len(world.a.farmers)
    assert all(i["phone"].startswith("+91******") and i["landmark"] is None for i in items)
    resp = await client.get(f"/v1/farmers/{world.a.farmer.id}", headers=bearer(agro))
    assert resp.status_code == 200
    body = resp.json()
    assert body["phone"] == "+91******" + world.a.farmer.phone[-4:]
    assert body["farms"] and body["farms"][0]["crop_plots"]
    assert world.a.farmer.phone not in resp.text


async def test_farmer_reads_only_their_own_record(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    own = next(f for f in world.a.farmers if f.user_id == farmer_user.id)
    resp = await client.get(f"/v1/farmers/{own.id}", headers=bearer(farmer_user))
    assert resp.status_code == 200 and resp.json()["phone"] == farmer_user.phone
    other = next(f for f in world.a.farmers if f.user_id is None)
    resp = await client.get(f"/v1/farmers/{other.id}", headers=bearer(farmer_user))
    assert resp.status_code == 404
    resp = await client.get("/v1/farmers", headers=bearer(farmer_user))
    assert resp.status_code == 403


async def test_farmer_360_has_farms_plots_and_consents(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    farmer = world.a.farmer
    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(world.a.owner))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["id"] == str(farmer.id) and body["phone"] == farmer.phone
    assert 1 <= len(body["farms"]) <= 2
    farm = body["farms"][0]
    assert farm["boundary"]["type"] == "Polygon" and len(farm["boundary"]["coordinates"][0]) == 5
    assert 17 < farm["centroid"]["lat"] < 19.5 and 77 < farm["centroid"]["lon"] < 81
    assert 0.4 < float(farm["area_acres_computed"]) < 5.5
    assert abs(float(farm["area_acres"]) - float(farm["area_acres_computed"])) < 0.3 * float(
        farm["area_acres_computed"]
    )
    assert farm["soil"] and farm["irrigation"] and farm["ownership"] in ("own", "leased")
    assert farm["crop_plots"]
    plot = farm["crop_plots"][0]
    assert plot["season"] in ("kharif", "rabi") and plot["sowing_date"] and plot["variety"]
    assert plot["crop_id"] and plot["stage"] and plot["expected_harvest"]
    consents = body["consents"]
    assert consents and consents[0]["purpose"] == "data" and consents[0]["granted_at"]
    assert all(c["version"] == "2026-09-v1" and c["channel"] == "officer" for c in consents)
    if body["consent_marketing"]:
        assert any(c["purpose"] == "marketing" and c["granted_at"] for c in consents)


async def test_unknown_or_other_tenant_farmer_is_404(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    resp = await client.get(f"/v1/farmers/{uuid.uuid4()}", headers=headers)
    assert resp.status_code == 404
    resp = await client.get(f"/v1/farmers/{world.b.farmer.id}", headers=headers)
    assert resp.status_code == 404
    assert world.b.farmer.phone not in resp.text and str(
        world.b.farmer.id
    ) not in resp.text.replace(f"/v1/farmers/{world.b.farmer.id}", "")
    resp = await client.get("/v1/farmers/not-a-uuid", headers=headers)
    assert resp.status_code == 422


async def test_soft_deleted_farmers_are_hidden(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    from datetime import UTC, datetime

    farmer = world.a.farmer
    async with tenant_scope(db_session, world.a.tenant.id):
        row = await db_session.get_one(Farmer, farmer.id)
        row.deleted_at = datetime.now(UTC)
        await db_session.flush()
    headers = bearer(world.a.owner)
    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=headers)
    assert resp.status_code == 404
    items = await _all_pages(client, headers, limit=50)
    assert str(farmer.id) not in {i["id"] for i in items}


async def test_pagination_rejects_bad_input(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    resp = await client.get("/v1/farmers", params={"cursor": "junk"}, headers=headers)
    assert resp.status_code == 400 and resp.json()["code"] == "invalid_cursor"
    resp = await client.get("/v1/farmers", params={"limit": "0"}, headers=headers)
    assert resp.status_code == 422
