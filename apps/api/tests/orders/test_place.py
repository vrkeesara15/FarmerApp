"""FA-020 order capture: ``POST /v1/orders``, the ``order`` sync op and
``GET /v1/stores/nearest``. Acceptance: "order reaches store queue; stock reserved".

Prices and totals are recomputed server-side (client totals that differ are refused),
stock is reserved FEFO (earliest expiry first) and short stock is a 409 with the available
quantity per line.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.models import LabelClaim, Product, Sku
from farmerapp.catalog.pricing import prices_for, resolved_price
from farmerapp.db.session import tenant_scope
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import Order, OrderStatusEvent, line_total_paise, tax_paise
from farmerapp.stock.models import StockReservation
from farmerapp.tenants.models import Village
from tests.authz.conftest import Bearer, World
from tests.farmers.write_fixtures import WriteCtx
from tests.orders.helpers import (
    available,
    demo_farmer,
    other_store,
    place,
    receive,
    today,
)
from tests.sync.conftest import op, sync


async def _unit_price(db_session: AsyncSession, world: World) -> tuple[int, int]:
    """(unit price, GST bp) of the fixture SKU at the store manager's store today."""
    assert world.a.sku_id is not None
    async with tenant_scope(db_session, world.a.tenant.id):
        sku = await db_session.get_one(Sku, world.a.sku_id)
        product = await db_session.get_one(Product, sku.product_id)
        prices = await prices_for(db_session, [sku.id], world.a.store_id, today())
    return resolved_price(prices.get(sku.id), sku.mrp_paise), product.gst_rate_bp


# --------------------------------------------------------------------------- happy path
async def test_officer_order_reaches_queue_with_fefo_reservation(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    late = await receive(client, bearer, world, qty=5, expiry=today() + timedelta(days=400))
    soon = await receive(client, bearer, world, qty=2, expiry=today() + timedelta(days=2))
    free_before = await available(db_session, world, world.a.sku_id, world.a.store_id)
    officer = world.a.user(UserRole.FIELD_OFFICER)
    unit, gst = await _unit_price(db_session, world)
    total_line = line_total_paise(Decimal("3.5"), unit)
    expected_total = total_line + tax_paise(total_line, gst)
    order = await place(
        client,
        bearer,
        world,
        lines=[
            {"sku_id": str(world.a.sku_id), "qty": "3.5", "unit_price_paise": unit},
        ],
        expected_total_paise=expected_total,
        fulfilment="delivery",
        notes="Deliver before Sunday",
    )
    assert order["status"] == "reserved" and order["channel"] == "officer"
    assert order["placed_by"] == str(officer.id)
    assert order["store_id"] == str(world.a.store_id)  # the demo farmer's village store
    assert order["fulfilment"] == "delivery"
    assert order["subtotal_paise"] == total_line
    assert order["total_paise"] == expected_total == order["subtotal_paise"] + order["tax_paise"]
    line = order["lines"][0]
    assert line["unit_price_paise"] == unit and line["gst_rate_bp"] == gst
    assert [e["to_status"] for e in order["events"]] == ["placed", "reserved"]
    # FEFO: whatever expires first is held first; our 2-day batch is fully taken.
    held = {r["batch_id"]: Decimal(r["qty"]) for r in order["reservations"]}
    assert sum(held.values()) == Decimal("3.5")
    assert held.get(soon["id"]) == 2
    assert all(r["status"] == "active" for r in order["reservations"])
    free_after = await available(db_session, world, world.a.sku_id, world.a.store_id)
    assert free_before - free_after == Decimal("3.5")
    assert late["id"] not in held or held[late["id"]] <= Decimal("1.5")
    # The store queue shows it.
    queue = await client.get(
        f"/v1/stores/{world.a.store_id}/order-queue",
        params={"limit": "100"},
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    assert queue.status_code == 200
    ids = [o["id"] for o in queue.json()["items"]]
    assert order["id"] in ids
    item = next(o for o in queue.json()["items"] if o["id"] == order["id"])
    assert len(item["lines"]) == 1
    # The farmer's login gets a notification; the placing officer (the actor) does not.
    farmer = demo_farmer(world.a)
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
    assert [(n.user_id, n.body_key) for n in notes] == [(farmer.user_id, "order.status.reserved")]
    assert notes[0].data["order_id"] == order["id"]
    # Farmer and officer both see the status (ST-005 acceptance on the read side).
    for role in ("farmer", "field_officer"):
        resp = await client.get(f"/v1/orders/{order['id']}", headers=bearer(world.a.user(role)))
        assert resp.status_code == 200 and resp.json()["status"] == "reserved", role


async def test_amounts_are_recomputed_server_side(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=10)
    unit, _ = await _unit_price(db_session, world)
    problem = await place(
        client,
        bearer,
        world,
        expect=409,
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1", "unit_price_paise": unit - 1}],
    )
    assert problem["code"] == "amount_mismatch"
    assert problem["errors"][0]["expected"] == unit
    assert problem["unit_prices_paise"] == {str(world.a.sku_id): unit}
    problem = await place(client, bearer, world, expect=409, expected_total_paise=1)
    assert problem["code"] == "amount_mismatch" and problem["total_paise"] > 1
    # Money is integer paise: a float or string price is a validation error.
    for price in (1.5, "100"):
        await place(
            client,
            bearer,
            world,
            expect=422,
            lines=[{"sku_id": str(world.a.sku_id), "qty": "1", "unit_price_paise": price}],
        )
    async with tenant_scope(db_session, world.a.tenant.id):
        placed = await db_session.scalar(
            select(Order)
            .where(Order.placed_by == world.a.user(UserRole.FIELD_OFFICER).id)
            .where(Order.status == "reserved")
        )
    assert placed is None  # nothing was written


async def test_insufficient_stock_reports_available_per_line(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=3)
    # An expired batch never counts.
    await receive(client, bearer, world, qty=50, expiry=today() - timedelta(days=1))
    free = await available(db_session, world, world.a.sku_id, world.a.store_id)
    problem = await place(
        client,
        bearer,
        world,
        expect=409,
        lines=[
            {"sku_id": str(world.a.sku_id), "qty": "1"},
            {"sku_id": str(world.a.sku_id), "qty": str(free + 5)},
        ],
    )
    assert problem["code"] == "insufficient_stock"
    assert len(problem["errors"]) == 1
    short = problem["errors"][0]
    assert short["index"] == 1 and short["sku_id"] == str(world.a.sku_id)
    assert Decimal(short["available"]) == free - 1  # after line 0 took one
    assert await available(db_session, world, world.a.sku_id, world.a.store_id) == free


async def test_who_orders_for_whom(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=30)
    demo = demo_farmer(world.a)
    officer = world.a.user(UserRole.FIELD_OFFICER)
    foreign = next(f for f in world.a.farmers if f.registered_by != officer.id)
    # Farmer app: the farmer orders for themselves (farmer_id optional).
    farmer_user = world.a.user(UserRole.FARMER)
    own = await place(client, bearer, world, actor=farmer_user, farmer_id=None)
    assert own["channel"] == "farmer_app" and own["farmer_id"] == str(demo.id)
    await place(client, bearer, world, actor=farmer_user, farmer=foreign, expect=404)
    # An officer only for their own farmers.
    await place(client, bearer, world, farmer=foreign, expect=404)
    problem = await place(client, bearer, world, farmer_id=None, expect=422)
    assert problem["code"] == "invalid_order"
    # Store staff at their own store, for any farmer of the tenant.
    manager = world.a.user(UserRole.STORE_MANAGER)
    pos = await place(client, bearer, world, actor=manager, farmer=foreign)
    assert pos["channel"] == "pos" and pos["store_id"] == str(world.a.store_id)
    north = await other_store(db_session, world, same_cluster=True)
    await place(client, bearer, world, actor=manager, store_id=str(north.id), expect=404)
    # Roles that do not place orders.
    for role in ("owner", "cluster_head", "agronomist", "auditor"):
        await place(client, bearer, world, actor=world.a.user(role), expect=403)
    # Another tenant's farmer / store are unknown.
    await place(client, bearer, world, farmer=world.b.farmer, expect=404)
    await place(client, bearer, world, store_id=str(world.b.store_id), expect=404)


async def test_invalid_skus_claims_and_duplicate_ids(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=20)
    problem = await place(
        client, bearer, world, expect=422, lines=[{"sku_id": str(uuid.uuid4()), "qty": "1"}]
    )
    assert problem["code"] == "invalid_order" and problem["errors"][0]["loc"] == [
        "lines",
        0,
        "sku_id",
    ]
    async with tenant_scope(db_session, world.a.tenant.id):
        claim = await db_session.scalar(
            select(LabelClaim).where(
                LabelClaim.sku_id == world.a.sku_id, LabelClaim.status == "approved"
            )
        )
        other_claim = await db_session.scalar(
            select(LabelClaim).where(LabelClaim.sku_id != world.a.sku_id)
        )
    assert claim is not None and other_claim is not None
    ok = await place(
        client,
        bearer,
        world,
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1", "label_claim_id": str(claim.id)}],
    )
    assert ok["lines"][0]["label_claim_id"] == str(claim.id)
    problem = await place(
        client,
        bearer,
        world,
        expect=422,
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1", "label_claim_id": str(other_claim.id)}],
    )
    assert problem["code"] == "invalid_order"  # DX-007: the claim must match the SKU
    client_id = str(uuid.uuid4())
    first = await place(client, bearer, world, id=client_id)
    assert first["id"] == client_id == first["client_order_id"]
    problem = await place(client, bearer, world, id=client_id, expect=409)
    assert problem["code"] == "order_exists"


# --------------------------------------------------------------------------- nearest store
async def test_nearest_store(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    batch = await receive(client, bearer, world, qty=7)
    demo = demo_farmer(world.a)
    officer = bearer(world.a.user(UserRole.FIELD_OFFICER))
    resp = await client.get(
        "/v1/stores/nearest",
        params={"farmer_id": str(demo.id), "sku_id": [str(world.a.sku_id), str(uuid.uuid4())]},
        headers=officer,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["store"]["id"] == str(world.a.store_id) and body["source"] == "village"
    assert body["distance_m"] is not None and body["distance_m"] >= 0
    stock = {s["sku_id"]: s for s in body["stock"]}
    assert Decimal(stock[str(world.a.sku_id)]["on_hand"]) >= Decimal(batch["qty"])
    assert Decimal(stock[str(world.a.sku_id)]["available"]) >= 7
    unknown = next(s for sid, s in stock.items() if sid != str(world.a.sku_id))
    assert [Decimal(unknown[k]) for k in ("on_hand", "reserved", "available")] == [0, 0, 0]
    # The farmer asks for themselves.
    own = await client.get("/v1/stores/nearest", headers=bearer(world.a.user(UserRole.FARMER)))
    assert own.status_code == 200 and own.json()["farmer_id"] == str(demo.id)
    # Staff must name the farmer; out-of-scope / other-tenant farmers are unknown.
    resp = await client.get("/v1/stores/nearest", headers=officer)
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_order"
    resp = await client.get(
        "/v1/stores/nearest", params={"farmer_id": str(world.b.farmer.id)}, headers=officer
    )
    assert resp.status_code == 404
    resp = await client.get(
        "/v1/stores/nearest",
        params={"farmer_id": str(demo.id)},
        headers=bearer(world.a.user(UserRole.AGRONOMIST)),
    )
    assert resp.status_code == 403
    # A village without a store: the closest store by distance, and orders default to it.
    async with tenant_scope(db_session, world.a.tenant.id):
        village = await db_session.get_one(Village, demo.village_id)
        village.store_id = None
        await db_session.flush()
    resp = await client.get(
        "/v1/stores/nearest", params={"farmer_id": str(demo.id)}, headers=officer
    )
    assert resp.status_code == 200 and resp.json()["source"] == "nearest"
    assert resp.json()["distance_m"] <= body["distance_m"] + 1


# --------------------------------------------------------------------------- sync
async def test_order_sync_op_offline_capture(
    client: AsyncClient, ctx: WriteCtx, bearer: Bearer, db_session: AsyncSession
) -> None:
    world = ctx.world
    await receive(client, bearer, world, qty=20)
    farmer = demo_farmer(world.a)
    payload: dict[str, Any] = {
        "farmer_id": str(farmer.id),
        "lines": [{"sku_id": str(world.a.sku_id), "qty": "2"}],
    }
    order_id = uuid.uuid4()
    officer_headers = bearer(world.a.user(UserRole.FIELD_OFFICER))
    body = await sync(
        client, ctx, [op("order", "create", payload, entity_id=order_id)], headers=officer_headers
    )
    result = body["results"][0]
    assert result["status"] == "applied", result
    assert result["server"]["id"] == str(order_id) and result["server"]["status"] == "reserved"
    # The same order again under a new op id: the server's order comes back as a conflict.
    body = await sync(
        client, ctx, [op("order", "create", payload, entity_id=order_id)], headers=officer_headers
    )
    assert body["results"][0]["status"] == "conflict"
    async with tenant_scope(db_session, world.a.tenant.id):
        orders = (
            (await db_session.execute(select(Order).where(Order.id == order_id))).scalars().all()
        )
        events = (
            (
                await db_session.execute(
                    select(OrderStatusEvent).where(OrderStatusEvent.order_id == order_id)
                )
            )
            .scalars()
            .all()
        )
        held = (
            (
                await db_session.execute(
                    select(StockReservation).where(StockReservation.order_id == order_id)
                )
            )
            .scalars()
            .all()
        )
    assert len(orders) == 1 and len(events) == 2 and sum(r.qty for r in held) == 2
    # A device total that differs, short stock, and edits are all rejected.
    ops = [
        op("order", "create", {**payload, "expected_total_paise": 1}),
        op(
            "order",
            "create",
            {**payload, "lines": [{"sku_id": str(world.a.sku_id), "qty": "99999"}]},
        ),
        op("order", "update", {"notes": "x"}, entity_id=order_id, base_version=1),
        op("order", "create", {"lines": []}),
    ]
    body = await sync(client, ctx, ops, headers=officer_headers)
    assert [r["status"] for r in body["results"]] == ["rejected"] * 4
    assert [r["error"]["code"] for r in body["results"]] == [
        "amount_mismatch",
        "insufficient_stock",
        "unsupported_action",
        "validation_error",
    ]
    assert body["results"][1]["error"]["errors"][0]["index"] == 0
    # The officer's change feed carries the new order.
    feed = await sync(client, ctx, [], headers=officer_headers)
    assert str(order_id) in {c["entity_id"] for c in feed["changes"] if c["entity"] == "order"}


async def test_order_of_other_tenant_is_invisible(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    await receive(client, bearer, world, qty=5)
    order = await place(client, bearer, world)
    resp = await client.get(f"/v1/orders/{order['id']}", headers=bearer(world.b.owner))
    assert resp.status_code == 404
    assert str(world.a.tenant.id) not in resp.text
