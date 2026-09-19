"""FM-015 (API half) / NF-013: deletion request tickets and the admin queue."""

from __future__ import annotations

from datetime import datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.notifications.models import Notification
from farmerapp.privacy.models import DataRequest
from tests.authz.conftest import Bearer, World


async def test_farmer_deletion_request_flow(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    farmer = world.a.user(UserRole.FARMER)
    headers = bearer(farmer)
    none = await client.get("/v1/me/deletion-request", headers=headers)
    assert none.status_code == 404
    resp = await client.post(
        "/v1/me/deletion-request", json={"reason": "Not farming any more"}, headers=headers
    )
    assert resp.status_code == 201, resp.text
    ticket = resp.json()
    assert ticket["status"] == "received" and ticket["type"] == "deletion"
    due = datetime.fromisoformat(ticket["due_by"]) - datetime.fromisoformat(ticket["created_at"])
    assert timedelta(days=29, hours=23) < due <= timedelta(days=30, minutes=5)
    row = await db_session.get_one(DataRequest, ticket["ticket_id"])
    assert row.farmer_id is not None and row.user_id == farmer.id
    admins = (
        await db_session.execute(
            select(Notification.user_id).where(Notification.kind == "data_request_received")
        )
    ).scalars()
    assert set(admins) == {world.a.user(UserRole.TENANT_ADMIN).id}
    # a repeat while it is open returns the same ticket
    again = await client.post("/v1/me/deletion-request", json={}, headers=headers)
    assert again.status_code == 200 and again.json()["ticket_id"] == ticket["ticket_id"]
    mine = await client.get("/v1/me/deletion-request", headers=headers)
    assert mine.json()["ticket_id"] == ticket["ticket_id"]
    # the admin works the ticket
    admin = bearer(world.a.user(UserRole.TENANT_ADMIN))
    listing = (await client.get("/v1/admin/data-requests", headers=admin)).json()
    assert [i["id"] for i in listing["items"]] == [ticket["ticket_id"]]
    assert listing["items"][0]["overdue"] is False
    path = f"/v1/admin/data-requests/{ticket['ticket_id']}"
    step = await client.patch(path, json={"status": "in_progress"}, headers=admin)
    assert step.json()["status"] == "in_progress" and step.json()["handled_at"] is None
    done = await client.patch(
        path,
        json={"status": "completed", "note": "Erased; invoices retained (NF-012)"},
        headers=admin,
    )
    assert done.json()["status"] == "completed" and done.json()["handled_at"]
    assert done.json()["resolution_note"].startswith("Erased")
    back = await client.patch(path, json={"status": "in_progress"}, headers=admin)
    assert back.status_code == 409 and back.json()["code"] == "invalid_transition"
    # closed: a new request opens a new ticket
    fresh = await client.post("/v1/me/deletion-request", json={}, headers=headers)
    assert fresh.status_code == 201 and fresh.json()["ticket_id"] != ticket["ticket_id"]
    filtered = await client.get(
        "/v1/admin/data-requests",
        params={"type": "deletion", "status": ["received"]},
        headers=admin,
    )
    assert [i["id"] for i in filtered.json()["items"]] == [fresh.json()["ticket_id"]]


async def test_staff_can_ask_too_and_only_admins_list(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.post("/v1/me/deletion-request", json={}, headers=bearer(officer))
    assert resp.status_code == 201
    denied = await client.get("/v1/admin/data-requests", headers=bearer(officer))
    assert denied.status_code == 403
    missing = await client.patch(
        "/v1/admin/data-requests/00000000-0000-0000-0000-000000000000",
        json={"status": "rejected"},
        headers=bearer(world.a.owner),
    )
    assert missing.status_code == 404
