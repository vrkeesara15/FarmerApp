"""``GET /v1/audit-logs``: a minimal, tenant-scoped, filterable read (WC-103 will build the
viewer on it). Role coverage comes from the generated SEC-006 matrix (``x-roles``)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db import audit
from tests.authz.conftest import Bearer, World

T = datetime(2026, 9, 17, 9, 0, tzinfo=UTC)
# The seed also wrote rows (at the real "now"); these bounds select the ten test events only.
WINDOW = {"from": T.isoformat(), "to": (T + timedelta(minutes=9)).isoformat()}


async def _seed_events(db_session: AsyncSession, world: World) -> list[uuid.UUID]:
    """Ten explicit events, one minute apart, alternating entity and actor."""
    ids: list[uuid.UUID] = []
    owner, admin = world.a.owner, world.a.user(UserRole.TENANT_ADMIN)
    for i in range(10):
        actor = owner if i % 2 == 0 else admin
        entity = "farmer" if i % 3 == 0 else "order"
        row = audit.record(
            db_session,
            action=f"{entity}.update",
            entity=entity,
            entity_id=uuid.UUID(int=i % 4),
            tenant_id=world.a.tenant.id,
            actor=audit.Actor(
                tenant_id=world.a.tenant.id, actor_id=actor.id, actor_role=actor.role
            ),
            before={"i": i - 1},
            after={"i": i},
        )
        row.created_at = T + timedelta(minutes=i)
        ids.append(row.id)
    await db_session.flush()
    return ids


async def _get(client: AsyncClient, headers: dict[str, str], **params: Any) -> dict[str, Any]:
    resp = await client.get("/v1/audit-logs", params=params, headers=headers)
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def test_list_is_newest_first_with_full_rows(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    ids = await _seed_events(db_session, world)
    body = await _get(client, bearer(world.a.user(UserRole.AUDITOR)), **WINDOW)
    assert [item["id"] for item in body["items"]] == [str(i) for i in reversed(ids)]
    assert body["next_cursor"] is None
    newest = body["items"][0]
    assert newest["tenant_id"] == str(world.a.tenant.id)
    assert newest["action"] == "farmer.update" and newest["entity"] == "farmer"
    assert newest["entity_id"] == str(uuid.UUID(int=1))
    assert newest["actor_id"] == str(world.a.user(UserRole.TENANT_ADMIN).id)
    assert newest["actor_role"] == "tenant_admin"
    assert newest["before"] == {"i": 8} and newest["after"] == {"i": 9}
    assert newest["created_at"].startswith("2026-09-17T09:09:00")
    assert set(newest) == {
        "id",
        "tenant_id",
        "actor_id",
        "actor_role",
        "action",
        "entity",
        "entity_id",
        "before",
        "after",
        "ip",
        "device_id",
        "user_agent",
        "trace_id",
        "created_at",
    }


async def test_filters(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await _seed_events(db_session, world)
    headers = bearer(world.a.owner)

    body = await _get(client, headers, entity="farmer", **WINDOW)
    assert [i["entity"] for i in body["items"]] == ["farmer"] * 4

    body = await _get(client, headers, entity="order", entity_id=str(uuid.UUID(int=1)), **WINDOW)
    assert [i["before"]["i"] for i in body["items"]] == [4, 0]  # orders i=5 and i=1, newest first

    admin = world.a.user(UserRole.TENANT_ADMIN)
    body = await _get(client, headers, actor_id=str(admin.id), **WINDOW)
    assert len(body["items"]) == 5 and all(i["actor_role"] == "tenant_admin" for i in body["items"])

    body = await _get(
        client,
        headers,
        **{
            "from": (T + timedelta(minutes=3)).isoformat(),
            "to": (T + timedelta(minutes=5)).isoformat(),
        },
    )
    assert [i["after"]["i"] for i in body["items"]] == [5, 4, 3]

    body = await _get(client, headers, action="farmer.update", **WINDOW)
    assert len(body["items"]) == 4


async def test_cursor_pagination_walks_every_row_once(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    ids = await _seed_events(db_session, world)
    headers = bearer(world.a.user(UserRole.DIRECTOR))
    seen: list[str] = []
    cursor: str | None = None
    pages = 0
    while True:
        params: dict[str, Any] = {"limit": 3, **WINDOW}
        if cursor:
            params["cursor"] = cursor
        body = await _get(client, headers, **params)
        seen.extend(item["id"] for item in body["items"])
        pages += 1
        cursor = body["next_cursor"]
        if cursor is None:
            break
    assert pages == 4
    assert seen == [str(i) for i in reversed(ids)]

    resp = await client.get("/v1/audit-logs", params={"cursor": "garbage"}, headers=headers)
    assert resp.status_code == 400 and resp.json()["code"] == "invalid_cursor"


async def test_validation(client: AsyncClient, world: World, bearer: Bearer) -> None:
    headers = bearer(world.a.owner)
    resp = await client.get("/v1/audit-logs", params={"entity_id": "not-a-uuid"}, headers=headers)
    assert resp.status_code == 422
    resp = await client.get("/v1/audit-logs", params={"from": "yesterday"}, headers=headers)
    assert resp.status_code == 422
    resp = await client.get("/v1/audit-logs", params={"limit": 0}, headers=headers)
    assert resp.status_code == 422


async def test_other_tenant_rows_are_invisible(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    """The seed wrote ``user.create`` rows for both tenants; each owner sees only their own."""
    for tenant, other in ((world.a, world.b), (world.b, world.a)):
        body = await _get(client, bearer(tenant.owner), entity="user", limit=200)
        entity_ids = {item["entity_id"] for item in body["items"]}
        assert entity_ids == {str(u.id) for u in tenant.everyone}
        assert not entity_ids & {str(u.id) for u in other.everyone}
        assert {item["tenant_id"] for item in body["items"]} == {str(tenant.tenant.id)}
