"""``GET /v1/orders[/{id}]``, ``/v1/payments``, ``/v1/farmers/{id}/khata`` and
``/v1/stores/{id}/stock``: SPEC 2.6 scope per role on the SMALL seed.

The SMALL seed puts three orders in the demo farmer's store (WGL, North Telangana): a
delivered credit order placed by the role officer for the demo farmer (then partly repaid in
cash), a placed farmer-app order by the demo farmer login, and a walk-in cash sale at the
counter by the store manager.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.jobs.seed import SEED_TODAY
from farmerapp.khata.models import KhataEntry, khata_balance, overdue_paise
from farmerapp.orders.models import Order
from farmerapp.tenants.models import Store
from tests.authz.conftest import Bearer, World

WHOLE_TENANT = ("owner", "director", "tenant_admin", "auditor", "accountant")


async def _items(
    client: AsyncClient, path: str, headers: dict[str, str], **params: str
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(50):
        query = {"limit": "2", **params}
        if cursor:
            query["cursor"] = cursor
        resp = await client.get(path, params=query, headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        items.extend(body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            return items
    raise AssertionError("pagination did not terminate")


def _demo_farmer(world: World) -> Farmer:
    return next(f for f in world.a.farmers if f.user_id is not None)


async def _orders(db_session: AsyncSession, world: World) -> list[Order]:
    async with tenant_scope(db_session, world.a.tenant.id):
        return list((await db_session.execute(select(Order).order_by(Order.created_at))).scalars())


async def _other_store(db_session: AsyncSession, world: World, *, same_cluster: bool) -> Store:
    head = world.a.user(UserRole.CLUSTER_HEAD)
    async with tenant_scope(db_session, world.a.tenant.id):
        stores = (await db_session.execute(select(Store).order_by(Store.code))).scalars().all()
    return next(
        s
        for s in stores
        if s.id != world.a.store_id and (s.cluster_id == head.cluster_id) is same_cluster
    )


# --------------------------------------------------------------------------- orders
async def test_orders_scope_per_role(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    orders = await _orders(db_session, world)
    assert len(orders) == 3
    all_ids = {str(o.id) for o in orders}
    for role in (*WHOLE_TENANT, "cluster_head", "store_manager"):
        items = await _items(client, "/v1/orders", bearer(world.a.user(role)))
        assert {i["id"] for i in items} == all_ids, role
    officer = world.a.user(UserRole.FIELD_OFFICER)
    mine = await _items(client, "/v1/orders", bearer(officer))
    assert [i["placed_by"] for i in mine] == [str(officer.id)]
    assert mine[0]["channel"] == "officer" and mine[0]["status"] == "delivered"
    farmer = _demo_farmer(world)
    own = await _items(client, "/v1/orders", bearer(world.a.user(UserRole.FARMER)))
    assert len(own) == 2 and {i["farmer_id"] for i in own} == {str(farmer.id)}
    resp = await client.get("/v1/orders", headers=bearer(world.a.user(UserRole.AGRONOMIST)))
    assert resp.status_code == 403


async def test_order_filters_and_money_totals(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    headers = bearer(world.a.owner)
    items = await _items(client, "/v1/orders", headers)
    for item in items:
        assert item["total_paise"] == (
            item["subtotal_paise"] - item["discount_paise"] + item["tax_paise"]
        )
        assert all(isinstance(item[k], int) for k in ("subtotal_paise", "tax_paise"))
    pos = await _items(client, "/v1/orders", headers, channel="pos")
    assert len(pos) == 1 and pos[0]["farmer_id"] is None and pos[0]["invoice_no"]
    placed = await _items(client, "/v1/orders", headers, status="placed")
    assert [p["channel"] for p in placed] == ["farmer_app"] and placed[0]["invoice_no"] is None
    assert await _items(client, "/v1/orders", headers, store_id=str(uuid.uuid4())) == []
    farmer = _demo_farmer(world)
    assert len(await _items(client, "/v1/orders", headers, farmer_id=str(farmer.id))) == 2
    window = {"from": "2020-01-01T00:00:00Z", "to": "2100-01-01T00:00:00Z"}
    assert len(await _items(client, "/v1/orders", headers, **window)) == 3
    resp = await client.get("/v1/orders", params={"status": "lost"}, headers=headers)
    assert resp.status_code == 422


async def test_order_detail_scope(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    orders = await _orders(db_session, world)
    credit = next(o for o in orders if o.channel == "officer")
    walk_in = next(o for o in orders if o.channel == "pos")
    farmer = bearer(world.a.user(UserRole.FARMER))
    resp = await client.get(f"/v1/orders/{credit.id}", headers=farmer)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert len(body["lines"]) == 1 and len(body["payments"]) == 1
    line = body["lines"][0]
    assert line["line_total_paise"] == int(Decimal(line["qty"]) * line["unit_price_paise"])
    assert line["label_claim_id"] is not None  # officer lines carry the claim (DX-007)
    assert body["payments"][0]["mode"] == "credit"
    assert body["payments"][0]["khata_entry_id"] is not None
    for role in ("farmer", "field_officer"):
        resp = await client.get(f"/v1/orders/{walk_in.id}", headers=bearer(world.a.user(role)))
        assert resp.status_code == 404, role
    resp = await client.get(f"/v1/orders/{walk_in.id}", headers=bearer(world.a.owner))
    assert resp.status_code == 200 and resp.json()["payments"][0]["mode"] == "cash"


# --------------------------------------------------------------------------- payments
async def test_payments_scope_per_role(client: AsyncClient, world: World, bearer: Bearer) -> None:
    everything = await _items(client, "/v1/payments", bearer(world.a.owner))
    assert len(everything) == 3
    assert {p["mode"] for p in everything} == {"credit", "cash"}
    for role in (*WHOLE_TENANT, "cluster_head", "store_manager"):
        items = await _items(client, "/v1/payments", bearer(world.a.user(role)))
        assert len(items) == 3, role
    officer = world.a.user(UserRole.FIELD_OFFICER)
    collected = await _items(client, "/v1/payments", bearer(officer))
    assert len(collected) == 2 and {p["collected_by"] for p in collected} == {str(officer.id)}
    own = await _items(client, "/v1/payments", bearer(world.a.user(UserRole.FARMER)))
    assert len(own) == 2 and {p["farmer_id"] for p in own} == {str(_demo_farmer(world).id)}
    cash = await _items(client, "/v1/payments", bearer(world.a.owner), mode="cash")
    assert len(cash) == 2 and all(p["receipt_uri"] for p in cash)
    assert await _items(client, "/v1/payments", bearer(world.a.owner), status="failed") == []
    resp = await client.get("/v1/payments", headers=bearer(world.a.user(UserRole.AGRONOMIST)))
    assert resp.status_code == 403


# --------------------------------------------------------------------------- khata
async def test_khata_balance_is_the_sum_of_entries(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    farmer = _demo_farmer(world)
    resp = await client.get(
        f"/v1/farmers/{farmer.id}/khata", headers=bearer(world.a.user(UserRole.FARMER))
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    signed = sum(e["signed_paise"] for e in body["entries"])
    assert body["balance_paise"] == signed > 0
    assert [e["type"] for e in body["entries"]] == ["credit", "debit"]  # newest first
    async with tenant_scope(db_session, world.a.tenant.id):
        assert body["balance_paise"] == await khata_balance(db_session, farmer.id)
    debit = body["entries"][1]
    assert debit["ref_type"] == "order" and debit["due_date"] and debit["harvest_month"]
    assert body["balances"] == [
        {"store_id": str(world.a.store_id), "balance_paise": body["balance_paise"]}
    ]
    assert len(body["credit_limits"]) == 1
    assert body["credit_limits"][0]["limit_paise"] >= body["balance_paise"]
    today = datetime.now(UTC).date()
    async with tenant_scope(db_session, world.a.tenant.id):
        assert body["overdue_paise"] == await overdue_paise(db_session, farmer.id, today)
    if date.fromisoformat(debit["due_date"]) >= today:
        assert body["next_due_date"] == debit["due_date"]
    else:
        assert body["next_due_date"] is None
    # The same view limited to another store is empty.
    empty = await client.get(
        f"/v1/farmers/{farmer.id}/khata",
        params={"store_id": str(uuid.uuid4())},
        headers=bearer(world.a.owner),
    )
    assert empty.status_code == 200
    assert empty.json()["balance_paise"] == 0 and empty.json()["entries"] == []
    # Paging through the ledger returns every entry once.
    first = await client.get(
        f"/v1/farmers/{farmer.id}/khata", params={"limit": "1"}, headers=bearer(world.a.owner)
    )
    cursor = first.json()["next_cursor"]
    assert cursor
    second = await client.get(
        f"/v1/farmers/{farmer.id}/khata",
        params={"limit": "1", "cursor": cursor},
        headers=bearer(world.a.owner),
    )
    ids = [e["id"] for e in first.json()["entries"] + second.json()["entries"]]
    assert ids == [e["id"] for e in body["entries"]]


async def test_khata_scope_per_role(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    demo = _demo_farmer(world)
    officer = world.a.user(UserRole.FIELD_OFFICER)
    others = [f for f in world.a.farmers if f.id != demo.id]
    foreign = next(f for f in others if f.registered_by != officer.id)
    own_officer = next(f for f in others if f.registered_by == officer.id)
    cases: list[tuple[str, Farmer, int]] = [
        ("farmer", demo, 200),
        ("farmer", own_officer, 404),  # a farmer sees their own khata only
        ("field_officer", demo, 200),
        ("field_officer", own_officer, 200),
        ("field_officer", foreign, 404),
        ("store_manager", demo, 200),
        ("store_manager", foreign, 404),  # the other farmer lives in another store's village
        ("cluster_head", demo, 200),
        ("agronomist", demo, 403),
    ]
    cases += [(role, foreign, 200) for role in WHOLE_TENANT]
    for role, farmer, status in cases:
        resp = await client.get(
            f"/v1/farmers/{farmer.id}/khata", headers=bearer(world.a.user(role))
        )
        assert resp.status_code == status, (role, farmer.name, resp.text)
    empty = await client.get(f"/v1/farmers/{foreign.id}/khata", headers=bearer(world.a.owner))
    assert empty.json()["balance_paise"] == 0 and empty.json()["entries"] == []
    async with tenant_scope(db_session, world.a.tenant.id):
        stores = {
            s for s in (await db_session.execute(select(KhataEntry.store_id).distinct())).scalars()
        }
    assert stores == {world.a.store_id}


# --------------------------------------------------------------------------- stock
async def test_store_stock_scope_and_ledger(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    store_id = world.a.store_id
    south = await _other_store(db_session, world, same_cluster=False)
    north = await _other_store(db_session, world, same_cluster=True)
    cases: list[tuple[str, uuid.UUID, int]] = [
        ("store_manager", store_id, 200),  # type: ignore[list-item]
        ("store_manager", north.id, 404),
        ("cluster_head", north.id, 200),
        ("cluster_head", south.id, 404),
        ("field_officer", store_id, 403),  # type: ignore[list-item]
        ("farmer", store_id, 403),  # type: ignore[list-item]
        ("agronomist", store_id, 403),  # type: ignore[list-item]
    ]
    cases += [(role, south.id, 200) for role in WHOLE_TENANT]
    for role, sid, status in cases:
        resp = await client.get(f"/v1/stores/{sid}/stock", headers=bearer(world.a.user(role)))
        assert resp.status_code == status, (role, resp.text)
    items = await _items(
        client, f"/v1/stores/{store_id}/stock", bearer(world.a.user(UserRole.STORE_MANAGER))
    )
    assert len(items) == 1  # SMALL: one batch per store
    batch = items[0]
    assert Decimal(batch["on_hand"]) == Decimal(batch["qty"]) > 0
    # The first stocked SKU of every store expires 20 days after the seed day (ST-004).
    expiry = SEED_TODAY + timedelta(days=20)
    assert batch["expiry"] == expiry.isoformat()
    left = (expiry - datetime.now(UTC).date()).days
    assert batch["days_to_expiry"] == left
    headers = bearer(world.a.owner)
    soon = await _items(
        client, f"/v1/stores/{store_id}/stock", headers, expiring_within_days=str(max(left, 0) + 5)
    )
    assert [b["id"] for b in soon] == [batch["id"]]
    if left > 5:
        later = await _items(
            client, f"/v1/stores/{store_id}/stock", headers, expiring_within_days=str(left - 5)
        )
        assert later == []
    by_sku = await _items(client, f"/v1/stores/{store_id}/stock", headers, sku_id=batch["sku_id"])
    assert len(by_sku) == 1
    with_empty = await _items(client, f"/v1/stores/{store_id}/stock", headers, include_empty="true")
    assert len(with_empty) >= 1
    resp = await client.get(f"/v1/stores/{uuid.uuid4()}/stock", headers=headers)
    assert resp.status_code == 404
