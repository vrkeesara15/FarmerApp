"""ST-003 stock write paths: goods receipt, transfer, write-off, adjustment. Acceptance:
"stock per SKU per batch correct after each movement" — after every write the batch cache
equals the sum of its movements and never goes negative (409 ``negative_stock``)."""

from __future__ import annotations

import random
import uuid
from datetime import timedelta
from decimal import Decimal
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.auth.models import UserRole
from farmerapp.db.models import AuditLog
from farmerapp.db.session import tenant_scope
from farmerapp.stock import service as stock_service
from farmerapp.stock.models import StockBatch, StockMovement
from farmerapp.stock.schemas import (
    AdjustmentIn,
    AdjustmentLineIn,
    BatchQtyIn,
    ReceiptIn,
    ReceiptLineIn,
    TransferIn,
    WriteOffIn,
    WriteOffLineIn,
)
from farmerapp.stock.service import LineDemand
from farmerapp.tenants.models import Store
from tests.authz.conftest import Bearer, World
from tests.orders.helpers import (
    assert_cache_matches_ledger,
    other_store,
    receive,
    today,
)


# --------------------------------------------------------------------------- receipt
async def test_goods_receipt_creates_and_tops_up_batches(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    expiry = today() + timedelta(days=200)
    first = await receive(client, bearer, world, qty="12.5", batch_no="GRN-A", expiry=expiry)
    assert Decimal(first["qty"]) == Decimal("12.5") == Decimal(first["available"])
    again = await receive(client, bearer, world, qty=5, batch_no="GRN-A", expiry=expiry)
    assert again["id"] == first["id"] and Decimal(again["qty"]) == Decimal("17.5")
    async with tenant_scope(db_session, world.a.tenant.id):
        moves = (
            (
                await db_session.execute(
                    select(StockMovement).where(StockMovement.batch_id == uuid.UUID(first["id"]))
                )
            )
            .scalars()
            .all()
        )
        assert [m.kind for m in moves] == ["receipt", "receipt"]
        assert all(m.ref_type == "receipt" and m.note == "GRN-TEST" for m in moves)
        await assert_cache_matches_ledger(db_session, [world.a.store_id])
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    # Same batch number with another expiry: a different lot, refused.
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/receipts",
        json={
            "lines": [
                {
                    "sku_id": str(world.a.sku_id),
                    "batch_no": "GRN-A",
                    "expiry": (expiry + timedelta(days=1)).isoformat(),
                    "qty": "1",
                    "cost_paise": 10,
                }
            ]
        },
        headers=headers,
    )
    assert resp.status_code == 409 and resp.json()["code"] == "batch_mismatch"
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/receipts",
        json={
            "lines": [{"sku_id": str(uuid.uuid4()), "batch_no": "X", "qty": "1", "cost_paise": 10}]
        },
        headers=headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_stock_request"
    zero_qty = {"sku_id": str(world.a.sku_id), "batch_no": "Y", "qty": "0", "cost_paise": 1}
    bad_bodies: list[dict[str, Any]] = [{"lines": []}, {"lines": [zero_qty]}]
    for bad in bad_bodies:
        resp = await client.post(
            f"/v1/stores/{world.a.store_id}/stock/receipts", json=bad, headers=headers
        )
        assert resp.status_code == 422, bad


async def test_store_scope_of_stock_writes(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    north = await other_store(db_session, world, same_cluster=True)
    south = await other_store(db_session, world, same_cluster=False)
    body = {
        "lines": [{"sku_id": str(world.a.sku_id), "batch_no": "SCOPE", "qty": "1", "cost_paise": 1}]
    }
    cases = [
        ("store_manager", north.id, 404),
        ("cluster_head", north.id, 201),
        ("cluster_head", south.id, 404),
        ("owner", south.id, 201),
        ("director", south.id, 201),
        ("accountant", south.id, 403),
        ("field_officer", world.a.store_id, 403),
    ]
    for role, store_id, status in cases:
        resp = await client.post(
            f"/v1/stores/{store_id}/stock/receipts", json=body, headers=bearer(world.a.user(role))
        )
        assert resp.status_code == status, (role, resp.text)


# --------------------------------------------------------------------------- transfer
async def test_transfer_moves_batches_atomically_with_identity(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    north = await other_store(db_session, world, same_cluster=True)
    expiry = today() + timedelta(days=150)
    batch = await receive(
        client, bearer, world, qty=10, batch_no="TRF-1", expiry=expiry, cost_paise=4321
    )
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    resp = await client.post(
        "/v1/stock/transfers",
        json={
            "from_store_id": str(world.a.store_id),
            "to_store_id": str(north.id),
            "note": "rebalance",
            "lines": [{"batch_id": batch["id"], "qty": "4"}],
        },
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["ref_type"] == "transfer"
    kinds = {m["kind"]: m for m in body["movements"]}
    assert Decimal(kinds["transfer_out"]["qty"]) == Decimal(-4)
    assert Decimal(kinds["transfer_in"]["qty"]) == Decimal(4)
    assert {m["ref_id"] for m in body["movements"]} == {body["ref_id"]}
    states = {b["store_id"]: b for b in body["batches"]}
    src, dest = states[str(world.a.store_id)], states[str(north.id)]
    assert Decimal(src["qty"]) == 6 and Decimal(dest["qty"]) == 4
    assert dest["batch_no"] == "TRF-1" and dest["expiry"] == expiry.isoformat()
    async with tenant_scope(db_session, world.a.tenant.id):
        dest_row = await db_session.get_one(StockBatch, uuid.UUID(dest["id"]))
        assert dest_row.cost_paise == 4321 and dest_row.sku_id == world.a.sku_id
        await assert_cache_matches_ledger(db_session, [world.a.store_id, north.id])
    # A second transfer tops up the same destination batch.
    resp = await client.post(
        "/v1/stock/transfers",
        json={
            "from_store_id": str(world.a.store_id),
            "to_store_id": str(north.id),
            "lines": [{"batch_id": batch["id"], "qty": "1"}],
        },
        headers=headers,
    )
    assert resp.status_code == 201
    assert {b["id"] for b in resp.json()["batches"]} == {batch["id"], dest["id"]}
    # More than is there: nothing moves.
    resp = await client.post(
        "/v1/stock/transfers",
        json={
            "from_store_id": str(world.a.store_id),
            "to_store_id": str(north.id),
            "lines": [{"batch_id": batch["id"], "qty": "3"}, {"batch_id": batch["id"], "qty": "3"}],
        },
        headers=headers,
    )
    assert resp.status_code == 409, resp.text
    problem = resp.json()
    assert problem["code"] == "negative_stock"
    assert problem["errors"][0]["available"] == "5.000"
    for bad, status in (
        ({"to_store_id": str(world.a.store_id)}, 422),  # same store
        ({"to_store_id": str(uuid.uuid4())}, 404),
        ({"from_store_id": str(north.id)}, 403),  # not the manager's store
    ):
        payload = {
            "from_store_id": str(world.a.store_id),
            "to_store_id": str(north.id),
            "lines": [{"batch_id": batch["id"], "qty": "1"}],
            **bad,
        }
        resp = await client.post("/v1/stock/transfers", json=payload, headers=headers)
        assert resp.status_code == status, (bad, resp.text)
    async with tenant_scope(db_session, world.a.tenant.id):
        await assert_cache_matches_ledger(db_session, [world.a.store_id, north.id])


# --------------------------------------------------------------------------- write-off
async def test_write_off_with_reason_and_photo(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    batch = await receive(client, bearer, world, qty=8, batch_no="DMG-1")
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    photo = f"gs://local/{world.a.tenant.id}/damage/{'0' * 64}"
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/write-offs",
        json={
            "note": "rat damage",
            "photo_blob_uri": photo,
            "lines": [
                {"batch_id": batch["id"], "qty": "2", "reason": "damage"},
                {"batch_id": batch["id"], "qty": "1", "reason": "expiry"},
            ],
        },
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert [m["kind"] for m in body["movements"]] == ["damage", "damage"]
    assert [m["reason"] for m in body["movements"]] == ["damage", "expiry"]
    assert all(m["photo_uri"] == photo for m in body["movements"])
    assert Decimal(body["batches"][0]["qty"]) == 5
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/write-offs",
        json={"lines": [{"batch_id": batch["id"], "qty": "5.001"}]},
        headers=headers,
    )
    assert resp.status_code == 409 and resp.json()["code"] == "negative_stock"
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/write-offs",
        json={"lines": [{"batch_id": str(uuid.uuid4()), "qty": "1"}]},
        headers=headers,
    )
    assert resp.status_code == 404
    async with tenant_scope(db_session, world.a.tenant.id):
        await assert_cache_matches_ledger(db_session, [world.a.store_id])


# --------------------------------------------------------------------------- adjustment
async def test_adjustment_is_store_manager_only_and_audited(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    batch = await receive(client, bearer, world, qty=10, batch_no="CNT-1")
    other = await receive(client, bearer, world, qty=3, batch_no="CNT-2")
    body = {
        "reason": "cycle count",
        "lines": [
            {"batch_id": batch["id"], "counted_qty": "7.5"},
            {"batch_id": other["id"], "counted_qty": "3"},  # no difference: no movement
        ],
    }
    url = f"/v1/stores/{world.a.store_id}/stock/adjustments"
    for role in ("owner", "cluster_head", "accountant", "field_officer"):
        resp = await client.post(url, json=body, headers=bearer(world.a.user(role)))
        assert resp.status_code == 403, role
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    resp = await client.post(url, json=body, headers=headers)
    assert resp.status_code == 201, resp.text
    out = resp.json()
    assert len(out["movements"]) == 1
    move = out["movements"][0]
    assert move["kind"] == "adjust" and Decimal(move["qty"]) == Decimal("-2.5")
    assert move["note"] == "cycle count"
    async with tenant_scope(db_session, world.a.tenant.id):
        events = (
            (
                await db_session.execute(
                    select(AuditLog).where(
                        AuditLog.action == "stock.adjustment",
                        AuditLog.entity_id == uuid.UUID(batch["id"]),
                    )
                )
            )
            .scalars()
            .all()
        )
        assert len(events) == 1
        assert events[0].actor_id == world.a.user(UserRole.STORE_MANAGER).id
        assert events[0].before == {"qty": "10.000"}
        assert events[0].after is not None and events[0].after["qty"] == "7.500"
        await assert_cache_matches_ledger(db_session, [world.a.store_id])
    # Upwards works too; missing reason / duplicate batch are rejected.
    resp = await client.post(
        url,
        json={"reason": "found a box", "lines": [{"batch_id": batch["id"], "counted_qty": "9"}]},
        headers=headers,
    )
    assert resp.status_code == 201 and Decimal(resp.json()["movements"][0]["qty"]) == Decimal("1.5")
    resp = await client.post(
        url, json={"lines": [{"batch_id": batch["id"], "counted_qty": "1"}]}, headers=headers
    )
    assert resp.status_code == 422
    resp = await client.post(
        url,
        json={
            "reason": "twice",
            "lines": [
                {"batch_id": batch["id"], "counted_qty": "1"},
                {"batch_id": batch["id"], "counted_qty": "2"},
            ],
        },
        headers=headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_stock_request"


async def test_reserved_stock_cannot_be_written_off_or_counted_away(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    """Reserved quantities belong to open orders: outbound writes take only what's free."""
    from tests.orders.helpers import place

    batch = await receive(
        client, bearer, world, qty=3, batch_no="RSV-1", expiry=today() + timedelta(days=1)
    )
    order = await place(client, bearer, world)  # 2 units, FEFO -> this batch first
    held = [r for r in order["reservations"] if r["batch_id"] == batch["id"]]
    assert held and Decimal(held[0]["qty"]) == 2
    headers = bearer(world.a.user(UserRole.STORE_MANAGER))
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/write-offs",
        json={"lines": [{"batch_id": batch["id"], "qty": "2"}]},
        headers=headers,
    )
    assert resp.status_code == 409 and resp.json()["errors"][0]["available"] == "1.000"
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/stock/adjustments",
        json={"reason": "count", "lines": [{"batch_id": batch["id"], "counted_qty": "1"}]},
        headers=headers,
    )
    assert resp.status_code == 409 and resp.json()["code"] == "negative_stock"
    stock = await client.get(
        f"/v1/stores/{world.a.store_id}/stock",
        params={"sku_id": str(world.a.sku_id), "limit": "100"},
        headers=headers,
    )
    row = next(b for b in stock.json()["items"] if b["id"] == batch["id"])
    assert Decimal(row["on_hand"]) == 3 and Decimal(row["reserved"]) == 2
    assert Decimal(row["available"]) == 1


# --------------------------------------------------------------------------- property
async def _batches(
    db_session: AsyncSession, store_id: uuid.UUID, batch_nos: list[str]
) -> list[StockBatch]:
    rows = (
        (
            await db_session.execute(
                select(StockBatch)
                .where(StockBatch.store_id == store_id, StockBatch.batch_no.in_(batch_nos))
                .order_by(StockBatch.batch_no)
            )
        )
        .scalars()
        .all()
    )
    for row in rows:
        await db_session.refresh(row)
    return list(rows)


async def _snapshot(
    db_session: AsyncSession, stores: list[uuid.UUID], batch_nos: list[str]
) -> dict[tuple[uuid.UUID, str], Decimal]:
    out: dict[tuple[uuid.UUID, str], Decimal] = {}
    for store_id in stores:
        for b in await _batches(db_session, store_id, batch_nos):
            out[(b.store_id, b.batch_no)] = b.qty
    return out


@pytest.mark.parametrize("seed", [3, 17, 2026])
async def test_random_movement_sequences_keep_batches_consistent(
    db_session: AsyncSession, world: World, seed: int
) -> None:
    """Property-style: random receipts, FEFO sales, transfers, damage and counts over two
    stores never leave a batch negative, always keep ``batch.qty == sum(movements)`` per
    batch, and a refused step (409) changes nothing."""
    rng = random.Random(seed)
    manager = world.a.user(UserRole.STORE_MANAGER)
    sku_id, home_id = world.a.sku_id, world.a.store_id
    assert sku_id is not None and home_id is not None
    north = await other_store(db_session, world, same_cluster=True)
    batch_nos = [f"P{seed}-{i}" for i in range(4)]
    refused = applied = 0
    async with tenant_scope(db_session, world.a.tenant.id):
        home = await db_session.get_one(Store, home_id)
        stores = {home.id: home, north.id: north}
        ids = sorted(stores)
        for step in range(40):
            op = rng.choice(["receipt", "receipt", "sale", "transfer", "damage", "adjust"])
            store = stores[rng.choice(ids)]
            qty = Decimal(rng.randint(1, 12))
            before = await _snapshot(db_session, ids, batch_nos)
            existing = await _batches(db_session, store.id, batch_nos)
            try:
                async with db_session.begin_nested():
                    if op == "receipt" or not existing:
                        no = rng.choice(batch_nos)
                        await stock_service.receive(
                            db_session,
                            manager,
                            store,
                            ReceiptIn(
                                lines=[
                                    ReceiptLineIn(
                                        sku_id=sku_id,
                                        batch_no=no,
                                        expiry=today() + timedelta(days=100 + int(no[-1])),
                                        qty=qty,
                                        cost_paise=100,
                                    )
                                ]
                            ),
                        )
                    elif op == "sale":
                        await stock_service.consume_order(
                            db_session,
                            tenant_id=world.a.tenant.id,
                            order_id=uuid.uuid4(),
                            store_id=store.id,
                            demands=[LineDemand(0, sku_id, qty, line_id=uuid.uuid4())],
                            actor_id=manager.id,
                            today=today(),
                        )
                    elif op == "transfer":
                        target = next(s for sid, s in stores.items() if sid != store.id)
                        await stock_service.transfer(
                            db_session,
                            manager,
                            store,
                            target,
                            TransferIn(
                                from_store_id=store.id,
                                to_store_id=target.id,
                                lines=[BatchQtyIn(batch_id=rng.choice(existing).id, qty=qty)],
                            ),
                        )
                    elif op == "damage":
                        await stock_service.write_off(
                            db_session,
                            manager,
                            store,
                            WriteOffIn(
                                lines=[WriteOffLineIn(batch_id=rng.choice(existing).id, qty=qty)]
                            ),
                        )
                    else:
                        await stock_service.adjust(
                            db_session,
                            manager,
                            store,
                            AdjustmentIn(
                                reason="random count",
                                lines=[
                                    AdjustmentLineIn(
                                        batch_id=rng.choice(existing).id,
                                        counted_qty=Decimal(rng.randint(0, 15)),
                                    )
                                ],
                            ),
                        )
                applied += 1
            except AppError as exc:
                assert exc.code in ("negative_stock", "insufficient_stock"), (step, op, exc.code)
                refused += 1
                assert await _snapshot(db_session, ids, batch_nos) == before, (step, op)
            await assert_cache_matches_ledger(db_session, ids)
    assert applied > 0 and applied + refused == 40
