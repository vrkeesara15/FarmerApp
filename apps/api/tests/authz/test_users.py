"""``/v1/users`` (minimal WC-011 slice): scope per SPEC 2.6, cursor pagination per SPEC 8.3."""

from __future__ import annotations

import base64
import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from tests.authz.conftest import Bearer, World

CLUSTER_1 = uuid.UUID(int=11)
CLUSTER_2 = uuid.UUID(int=12)
STORE_1 = uuid.UUID(int=21)


async def _all_pages(
    client: AsyncClient, headers: dict[str, str], limit: int
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(50):
        params = {"limit": str(limit)} | ({"cursor": cursor} if cursor else {})
        resp = await client.get("/v1/users", params=params, headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert len(body["items"]) <= limit
        items.extend(body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            return items
    raise AssertionError("pagination did not terminate")


async def test_owner_lists_every_user_in_own_tenant(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    resp = await client.get("/v1/users", headers=bearer(world.a.owner))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["next_cursor"] is None
    ids = {item["id"] for item in body["items"]}
    assert ids == {str(u.id) for u in world.a.everyone}
    assert {str(u.id) for u in world.a.users.values()} <= ids
    assert all(item["tenant_id"] == str(world.a.tenant.id) for item in body["items"])
    assert {item["role"] for item in body["items"]} == {r.value for r in UserRole}
    assert "code_hash" not in resp.text and "device_id" not in body["items"][0]


async def test_cursor_pagination_is_stable_and_complete(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    items = await _all_pages(client, headers, limit=3)
    ids = [item["id"] for item in items]
    assert len(ids) == len(set(ids)) == len(world.a.everyone) == 14
    ordered = [(item["created_at"], item["id"]) for item in items]
    assert ordered == sorted(ordered)

    first = await client.get("/v1/users", params={"limit": "3"}, headers=headers)
    cursor = first.json()["next_cursor"]
    decoded = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
    assert first.json()["items"][-1]["id"] in decoded  # opaque to clients, (created_at, id) inside


async def test_pagination_rejects_bad_input(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    resp = await client.get("/v1/users", params={"cursor": "not-a-cursor"}, headers=headers)
    assert resp.status_code == 400 and resp.json()["code"] == "invalid_cursor"
    for limit in ("0", "201", "x"):
        resp = await client.get("/v1/users", params={"limit": limit}, headers=headers)
        assert resp.status_code == 422, limit


async def test_cluster_head_is_limited_to_own_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    head = world.a.user(UserRole.CLUSTER_HEAD)
    officer = world.a.user(UserRole.FIELD_OFFICER)
    manager = world.a.user(UserRole.STORE_MANAGER)
    head.cluster_id, officer.cluster_id, manager.cluster_id = CLUSTER_1, CLUSTER_1, CLUSTER_2
    await db_session.flush()

    resp = await client.get("/v1/users", headers=bearer(head))
    assert resp.status_code == 200
    assert {i["id"] for i in resp.json()["items"]} == {str(head.id), str(officer.id)}

    resp = await client.get(f"/v1/users/{officer.id}", headers=bearer(head))
    assert resp.status_code == 200 and resp.json()["id"] == str(officer.id)
    resp = await client.get(f"/v1/users/{manager.id}", headers=bearer(head))
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"


async def test_cluster_head_without_cluster_sees_nobody(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    head = world.a.user(UserRole.CLUSTER_HEAD)
    head.cluster_id = None  # the seed places the demo cluster head in a cluster
    await db_session.flush()
    resp = await client.get("/v1/users", headers=bearer(head))
    assert resp.status_code == 200 and resp.json() == {"items": [], "next_cursor": None}
    resp = await client.get(f"/v1/users/{world.a.owner.id}", headers=bearer(head))
    assert resp.status_code == 404


async def test_field_officer_reads_self_but_not_colleagues(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.get(f"/v1/users/{officer.id}", headers=bearer(officer))
    assert resp.status_code == 200 and resp.json()["phone"] == officer.phone
    resp = await client.get(f"/v1/users/{world.a.owner.id}", headers=bearer(officer))
    assert resp.status_code == 403 and resp.json()["code"] == "forbidden"
    resp = await client.get("/v1/users", headers=bearer(officer))
    assert resp.status_code == 403


async def test_get_unknown_or_other_tenant_user_is_404(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    resp = await client.get(f"/v1/users/{uuid.uuid4()}", headers=headers)
    assert resp.status_code == 404
    resp = await client.get(f"/v1/users/{world.b.owner.id}", headers=headers)
    assert resp.status_code == 404
    assert world.b.owner.phone not in resp.text
    resp = await client.get("/v1/users/not-a-uuid", headers=headers)
    assert resp.status_code == 422


async def test_owner_updates_a_user(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    version = officer.version
    resp = await client.patch(
        f"/v1/users/{officer.id}",
        json={
            "name": "Ramesh K.",
            "role": "cluster_head",
            "status": "disabled",
            "store_id": str(STORE_1),
            "cluster_id": str(CLUSTER_1),
        },
        headers=bearer(world.a.owner),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["name"] == "Ramesh K."
    assert body["role"] == "cluster_head"
    assert body["status"] == "disabled"
    assert body["store_id"] == str(STORE_1)
    assert body["cluster_id"] == str(CLUSTER_1)
    assert body["phone"] == officer.phone  # not editable here
    await db_session.refresh(officer)
    assert officer.role == "cluster_head" and officer.version == version + 1

    # a disabled user's token stops working at once
    resp = await client.get("/v1/me", headers=bearer(officer))
    assert resp.status_code == 401 and resp.json()["code"] == "user_disabled"


async def test_update_can_clear_store_and_cluster(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    officer.store_id, officer.cluster_id = STORE_1, CLUSTER_1
    await db_session.flush()
    headers = bearer(world.a.user(UserRole.TENANT_ADMIN))
    resp = await client.patch(
        f"/v1/users/{officer.id}", json={"name": "Only name"}, headers=headers
    )
    assert resp.status_code == 200 and resp.json()["store_id"] == str(STORE_1)
    resp = await client.patch(
        f"/v1/users/{officer.id}", json={"store_id": None, "cluster_id": None}, headers=headers
    )
    assert resp.status_code == 200
    assert resp.json()["store_id"] is None and resp.json()["cluster_id"] is None


async def test_update_validation(client: AsyncClient, world: World, bearer: Bearer) -> None:
    headers = bearer(world.a.user(UserRole.DIRECTOR))
    url = f"/v1/users/{world.a.user(UserRole.FIELD_OFFICER).id}"
    for body in (
        {},
        {"role": "king"},
        {"status": "gone"},
        {"name": ""},
        {"phone": "+919000000099"},
    ):
        resp = await client.patch(url, json=body, headers=headers)
        assert resp.status_code == 422, (body, resp.text)
        assert resp.json()["code"] == "validation_error"


async def test_update_other_tenant_or_unknown_user_is_404(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    resp = await client.patch(f"/v1/users/{world.b.owner.id}", json={"name": "X"}, headers=headers)
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    assert world.b.owner.name != "X"
    resp = await client.patch(f"/v1/users/{uuid.uuid4()}", json={"name": "X"}, headers=headers)
    assert resp.status_code == 404


async def test_update_is_forbidden_for_read_only_roles(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    target = world.a.user(UserRole.FIELD_OFFICER)
    for role in (UserRole.AUDITOR, UserRole.CLUSTER_HEAD, UserRole.FIELD_OFFICER):
        resp = await client.patch(
            f"/v1/users/{target.id}", json={"name": "X"}, headers=bearer(world.a.user(role))
        )
        assert resp.status_code == 403, role
    # even on their own record
    resp = await client.patch(f"/v1/users/{target.id}", json={"name": "X"}, headers=bearer(target))
    assert resp.status_code == 403
