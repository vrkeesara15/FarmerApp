"""ST-007 / FA-020 A56: credit approval requests reach the officer through the sync change
feed (no polling): scoped to the officer who asked and the staff of the sale's store, never
to other officers; devices cannot write them."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient

from farmerapp.auth.models import User, UserRole
from tests.authz.conftest import Bearer, World
from tests.khata.test_credit import _other_farmer, _set_limit
from tests.orders.helpers import place, receive
from tests.sync.conftest import op

ENTITY = "credit_approval_request"


async def _pull(
    client: AsyncClient, headers: dict[str, str], cursor: str | None = None, ops: Any = ()
) -> dict[str, Any]:
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "dev-credit", "cursor": cursor, "ops": list(ops)},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    return body


def _requests(body: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {c["entity_id"]: c for c in body["changes"] if c["entity"] == ENTITY}


def _other_officer(world: World) -> User:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    return next(
        u for u in world.a.everyone if u.role == UserRole.FIELD_OFFICER and u.id != officer.id
    )


async def test_approval_reaches_the_requesting_officer_and_store_staff_only(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    await receive(client, bearer, world, qty=10)
    farmer = _other_farmer(world)
    await _set_limit(client, bearer, world, farmer, 100)
    officer = bearer(world.a.user(UserRole.FIELD_OFFICER))
    problem = await place(client, bearer, world, farmer=farmer, payment_mode="credit", expect=402)
    request_id = problem["approval_request_id"]

    first = await _pull(client, officer)
    pending = _requests(first)[request_id]
    assert pending["data"]["status"] == "pending" and pending["action"] == "create"
    assert pending["data"]["farmer_id"] == str(farmer.id)
    assert pending["data"]["shortfall_paise"] == problem["shortfall_paise"]

    approved = await client.post(
        f"/v1/credit-approvals/{request_id}/approve",
        headers=bearer(world.a.user(UserRole.CLUSTER_HEAD)),
    )
    assert approved.status_code == 200, approved.text
    # The officer's next pull (from its cursor) flips A56 without polling the approvals list.
    later = _requests(await _pull(client, officer, first["cursor"]))
    assert later[request_id]["data"]["status"] == "approved"
    assert later[request_id]["action"] == "update"
    # The store's staff see it; another officer and the approver's own feed do not.
    manager = await _pull(client, bearer(world.a.user(UserRole.STORE_MANAGER)))
    assert _requests(manager)[request_id]["data"]["status"] == "approved"
    assert request_id not in _requests(await _pull(client, bearer(_other_officer(world))))
    assert request_id not in _requests(await _pull(client, bearer(world.a.user(UserRole.FARMER))))
    # Tenant isolation.
    assert _requests(await _pull(client, bearer(world.b.user(UserRole.STORE_MANAGER)))) == {}


async def test_devices_cannot_write_credit_approval_requests(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    officer = bearer(world.a.user(UserRole.FIELD_OFFICER))
    body = await _pull(client, officer, ops=[op(ENTITY, "create", {"status": "approved"})])
    (result,) = body["results"]
    assert result["status"] == "rejected"
    assert result["error"]["code"] == "unsupported_action"
