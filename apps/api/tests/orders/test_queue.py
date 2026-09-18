"""ST-005 order queue: ``POST /v1/orders/{id}/status`` transitions, the append-only status
history, notifications and ``GET /v1/stores/{id}/order-queue``. Acceptance: "status visible
to farmer and officer"."""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.rls import APPEND_ONLY_TABLES
from farmerapp.db.session import tenant_scope
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import (
    TRANSITIONS,
    Order,
    OrderChannel,
    OrderStatus,
    can_transition,
)
from farmerapp.stock.ledger import stock_on_hand
from farmerapp.stock.models import StockMovement
from tests.authz.conftest import Bearer, World
from tests.orders.helpers import (
    assert_cache_matches_ledger,
    available,
    demo_farmer,
    other_store,
    place,
    receive,
)


async def _move(
    client: AsyncClient,
    headers: dict[str, str],
    order_id: str,
    status: str,
    *,
    expect: int = 200,
    note: str | None = None,
) -> dict[str, Any]:
    resp = await client.post(
        f"/v1/orders/{order_id}/status", json={"status": status, "note": note}, headers=headers
    )
    assert resp.status_code == expect, resp.text
    out: dict[str, Any] = resp.json()
    return out


def test_transition_table() -> None:
    assert can_transition("placed", "reserved") and can_transition("ready", "delivered")
    assert not can_transition("reserved", "ready")
    assert not can_transition("handed_over", "cancelled")
    for status in (OrderStatus.HANDED_OVER, OrderStatus.DELIVERED, OrderStatus.CANCELLED):
        assert TRANSITIONS[status] == frozenset()
    open_statuses = (OrderStatus.PLACED, OrderStatus.RESERVED, OrderStatus.PACKED)
    assert all(OrderStatus.CANCELLED in TRANSITIONS[s] for s in open_statuses)
    assert "order_status_event" in APPEND_ONLY_TABLES


async def test_pack_ready_handover_turns_reservation_into_sales(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=6)
    order = await place(client, bearer, world, lines=[{"sku_id": str(world.a.sku_id), "qty": "4"}])
    held = {r["batch_id"]: Decimal(r["qty"]) for r in order["reservations"]}
    manager = world.a.user(UserRole.STORE_MANAGER)
    headers = bearer(manager)
    store_id, sku_id = world.a.store_id, world.a.sku_id
    assert store_id is not None and sku_id is not None
    async with tenant_scope(db_session, world.a.tenant.id):
        on_hand_before = await stock_on_hand(db_session, store_id, sku_id)
    await _move(client, headers, order["id"], "packed", note="packed in bag 3")
    await _move(client, headers, order["id"], "ready")
    done = await _move(client, headers, order["id"], "handed_over")
    assert done["status"] == "handed_over"
    assert [(e["from_status"], e["to_status"]) for e in done["events"]] == [
        (None, "placed"),
        ("placed", "reserved"),
        ("reserved", "packed"),
        ("packed", "ready"),
        ("ready", "handed_over"),
    ]
    assert done["events"][2]["note"] == "packed in bag 3"
    assert done["events"][2]["actor_id"] == str(manager.id)
    assert {r["status"] for r in done["reservations"]} == {"consumed"}
    async with tenant_scope(db_session, world.a.tenant.id):
        sales = (
            (
                await db_session.execute(
                    select(StockMovement).where(
                        StockMovement.ref_type == "order",
                        StockMovement.ref_id == uuid.UUID(order["id"]),
                    )
                )
            )
            .scalars()
            .all()
        )
        assert {m.kind for m in sales} == {"sale"}
        assert {m.batch_id: -m.qty for m in sales} == {uuid.UUID(b): q for b, q in held.items()}
        on_hand_after = await stock_on_hand(db_session, store_id, sku_id)
        assert on_hand_before - on_hand_after == 4
        await assert_cache_matches_ledger(db_session, [world.a.store_id])
        # Notifications: the farmer's login and the placing officer, for every change.
        notes = (
            (
                await db_session.execute(
                    select(Notification)
                    .where(Notification.kind == "order_status")
                    .order_by(Notification.created_at)
                )
            )
            .scalars()
            .all()
        )
    farmer_user = demo_farmer(world.a).user_id
    officer = world.a.user(UserRole.FIELD_OFFICER).id
    by_user: dict[uuid.UUID, list[str]] = {}
    for n in notes:
        by_user.setdefault(n.user_id, []).append(n.body_key)
    assert farmer_user is not None
    assert by_user[farmer_user] == [
        "order.status.reserved",
        "order.status.packed",
        "order.status.ready",
        "order.status.handed_over",
    ]
    assert by_user[officer] == [
        "order.status.packed",
        "order.status.ready",
        "order.status.handed_over",
    ]
    assert manager.id not in by_user
    # Visible to the farmer and to the officer.
    for role in ("farmer", "field_officer"):
        resp = await client.get(f"/v1/orders/{order['id']}", headers=bearer(world.a.user(role)))
        assert resp.json()["status"] == "handed_over", role
    # Terminal: nothing more.
    problem = await _move(client, headers, order["id"], "cancelled", expect=409)
    assert problem["code"] == "invalid_transition" and problem["allowed"] == []


async def test_invalid_transitions_are_refused(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    await receive(client, bearer, world, qty=5)
    order = await place(client, bearer, world)
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    problem = await _move(client, headers, order["id"], "ready", expect=409)
    assert problem["code"] == "invalid_transition"
    assert problem["from"] == "reserved" and problem["to"] == "ready"
    assert problem["allowed"] == ["cancelled", "packed"]
    await _move(client, headers, order["id"], "draft", expect=409)
    resp = await client.post(
        f"/v1/orders/{order['id']}/status", json={"status": "lost"}, headers=headers
    )
    assert resp.status_code == 422


async def test_cancel_releases_the_reservation(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=5)
    before = await available(db_session, world, world.a.sku_id, world.a.store_id)
    order = await place(client, bearer, world, lines=[{"sku_id": str(world.a.sku_id), "qty": "3"}])
    assert await available(db_session, world, world.a.sku_id, world.a.store_id) == before - 3
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    await _move(client, headers, order["id"], "packed")
    cancelled = await _move(client, headers, order["id"], "cancelled", note="farmer changed mind")
    assert cancelled["status"] == "cancelled"
    assert {r["status"] for r in cancelled["reservations"]} == {"released"}
    assert await available(db_session, world, world.a.sku_id, world.a.store_id) == before


async def test_placed_order_from_before_fa020_reserves_on_transition(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    """The seeded farmer-app order is ``placed`` with no reservation: moving it to
    ``reserved`` holds FEFO stock; handing over a line without reservation sells FEFO."""
    async with tenant_scope(db_session, world.a.tenant.id):
        seeded = await db_session.scalar(
            select(Order).where(
                Order.channel == OrderChannel.FARMER_APP.value,
                Order.status == OrderStatus.PLACED.value,
            )
        )
    assert seeded is not None
    detail = await client.get(f"/v1/orders/{seeded.id}", headers=bearer(world.a.owner))
    sku = detail.json()["lines"][0]["sku_id"]
    await receive(client, bearer, world, qty=50, sku_id=uuid.UUID(sku))
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    reserved = await _move(client, headers, str(seeded.id), "reserved")
    assert reserved["reservations"] and reserved["status"] == "reserved"
    # The farmer placed it themselves: the officer is not the placer, the farmer is notified.
    async with tenant_scope(db_session, world.a.tenant.id):
        notes = (
            (
                await db_session.execute(
                    select(Notification).where(Notification.kind == "order_status")
                )
            )
            .scalars()
            .all()
        )
    assert {n.user_id for n in notes} == {demo_farmer(world.a).user_id}


async def test_queue_scope_and_filters(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=10)
    order = await place(client, bearer, world)
    manager = bearer(world.a.user(UserRole.STORE_MANAGER))
    url = f"/v1/stores/{world.a.store_id}/order-queue"
    open_ids = [o["id"] for o in (await client.get(url, headers=manager)).json()["items"]]
    assert order["id"] in open_ids
    statuses = {o["status"] for o in (await client.get(url, headers=manager)).json()["items"]}
    assert statuses <= {"placed", "reserved", "packed", "ready"}
    done = await client.get(url, params={"status": ["delivered", "handed_over"]}, headers=manager)
    assert {o["status"] for o in done.json()["items"]} == {"delivered", "handed_over"}
    north = await other_store(db_session, world, same_cluster=True)
    south = await other_store(db_session, world, same_cluster=False)
    cases = [
        ("store_manager", north.id, 404),
        ("cluster_head", world.a.store_id, 200),
        ("cluster_head", south.id, 404),
        ("accountant", south.id, 200),
        ("field_officer", world.a.store_id, 403),
        ("farmer", world.a.store_id, 403),
    ]
    for role, store_id, status in cases:
        resp = await client.get(
            f"/v1/stores/{store_id}/order-queue", headers=bearer(world.a.user(role))
        )
        assert resp.status_code == status, (role, resp.text)
    # Status changes follow the same store scope; officers / farmers cannot move orders.
    for role, expected in (("field_officer", 403), ("farmer", 403), ("agronomist", 403)):
        resp = await client.post(
            f"/v1/orders/{order['id']}/status",
            json={"status": "packed"},
            headers=bearer(world.a.user(role)),
        )
        assert resp.status_code == expected, role
    resp = await client.post(
        f"/v1/orders/{order['id']}/status",
        json={"status": "packed"},
        headers=bearer(world.b.user(UserRole.STORE_MANAGER)),
    )
    assert resp.status_code == 404


async def test_status_history_is_append_only(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=5)
    order = await place(client, bearer, world)
    async with tenant_scope(db_session, world.a.tenant.id):
        for statement in (
            "UPDATE order_status_event SET note = 'x' WHERE order_id = :id",
            "DELETE FROM order_status_event WHERE order_id = :id",
        ):
            with pytest.raises(DBAPIError):
                async with db_session.begin_nested():
                    await db_session.execute(text(statement), {"id": order["id"]})
