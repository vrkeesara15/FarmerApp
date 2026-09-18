"""ST-007 "sale beyond limit blocked without approval" — and let through *with* one: a credit
sale retried with ``credit_approval_request_id`` after a cluster head approved it goes
through once; the request becomes ``consumed`` (REST order, ``order`` sync op, the gate)."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.audit import Actor as AuditActor
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.khata.credit import check_and_reserve_credit
from farmerapp.khata.models import CreditApprovalRequest, CreditLimit, khata_balance
from tests.authz.conftest import Bearer, World
from tests.farmers.write_fixtures import WriteCtx
from tests.khata.test_credit import _other_farmer, _set_limit
from tests.orders.helpers import demo_farmer, other_store, place, receive
from tests.sync.conftest import op, sync


async def _approve(
    client: AsyncClient, bearer: Bearer, world: World, request_id: str
) -> dict[str, Any]:
    resp = await client.post(
        f"/v1/credit-approvals/{request_id}/approve",
        headers=bearer(world.a.user(UserRole.CLUSTER_HEAD)),
    )
    assert resp.status_code == 200, resp.text
    out: dict[str, Any] = resp.json()
    return out


async def _request(
    db_session: AsyncSession, world: World, request_id: str | uuid.UUID
) -> CreditApprovalRequest:
    async with tenant_scope(db_session, world.a.tenant.id):
        row = await db_session.get_one(CreditApprovalRequest, uuid.UUID(str(request_id)))
        await db_session.refresh(row)
    return row


def _third_farmer(world: World, *not_these: Farmer) -> Farmer:
    """Another farmer of the role officer (not the demo farmer, not ``not_these``)."""
    officer = world.a.user(UserRole.FIELD_OFFICER)
    skip = {f.id for f in not_these} | {demo_farmer(world.a).id}
    return next(f for f in world.a.farmers if f.registered_by == officer.id and f.id not in skip)


async def test_approved_request_lets_a_retried_order_through_exactly_once(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=30)
    farmer = _other_farmer(world)
    await _set_limit(client, bearer, world, farmer, 100)  # ₹1: any sale is beyond it
    # Blocked without approval; the 402 names the request to retry with.
    problem = await place(client, bearer, world, farmer=farmer, payment_mode="credit", expect=402)
    assert problem["code"] == "credit_limit_exceeded"
    request_id = problem["approval_request_id"]
    assert request_id is not None and uuid.UUID(request_id)
    first_order_id = (await _request(db_session, world, request_id)).order_id
    # Retried with the request id while still pending: the same request, still blocked.
    again = await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        credit_approval_request_id=request_id,
        expect=402,
    )
    assert again["approval_request_id"] == request_id
    await _approve(client, bearer, world, request_id)
    # A retry without the key (new server order id) is still blocked: a new request.
    blocked = await place(client, bearer, world, farmer=farmer, payment_mode="credit", expect=402)
    assert blocked["approval_request_id"] != request_id
    # Retried with the key: goes through, the request is consumed by that order.
    order = await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        credit_approval_request_id=request_id,
    )
    assert order["status"] == "reserved" and order["id"] != str(first_order_id)
    used = await _request(db_session, world, request_id)
    assert used.status == "consumed" and used.consumed_at is not None
    assert used.consumed_by_order_id == uuid.UUID(order["id"]) and used.used_at is not None
    async with tenant_scope(db_session, world.a.tenant.id):
        assert await khata_balance(db_session, farmer.id, world.a.store_id) == order["total_paise"]
    listing = await client.get(
        "/v1/credit-approvals",
        params={"status": "consumed"},
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    (row,) = listing.json()["items"]
    assert row["id"] == request_id and row["consumed_by_order_id"] == order["id"]
    # A second reuse is blocked (and opens a fresh request); a consumed one cannot be decided.
    reuse = await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        credit_approval_request_id=request_id,
        expect=402,
    )
    assert reuse["approval_request_id"] not in (request_id, None)
    resp = await client.post(
        f"/v1/credit-approvals/{request_id}/reject",
        headers=bearer(world.a.user(UserRole.CLUSTER_HEAD)),
    )
    assert resp.status_code == 409 and resp.json()["code"] == "approval_not_pending"
    # Rejected requests never let a sale through either.
    rejected = reuse["approval_request_id"]
    resp = await client.post(
        f"/v1/credit-approvals/{rejected}/reject",
        headers=bearer(world.a.user(UserRole.CLUSTER_HEAD)),
    )
    assert resp.status_code == 200
    await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        credit_approval_request_id=rejected,
        expect=402,
    )


async def test_approval_must_cover_the_amount_farmer_and_store(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=30)
    farmer = _other_farmer(world)
    other = _third_farmer(world, farmer)
    for who in (farmer, other):
        await _set_limit(client, bearer, world, who, 100)
    small = await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1"}],
        expect=402,
    )
    request_id = small["approval_request_id"]
    await _approve(client, bearer, world, request_id)
    # More than was approved: blocked, the approval is kept for the right sale.
    bigger = await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        credit_approval_request_id=request_id,
        lines=[{"sku_id": str(world.a.sku_id), "qty": "3"}],
        expect=402,
    )
    assert bigger["approval_request_id"] != request_id
    # Another farmer cannot use it.
    await place(
        client,
        bearer,
        world,
        farmer=other,
        payment_mode="credit",
        credit_approval_request_id=request_id,
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1"}],
        expect=402,
    )
    # Another store cannot use it (the gate, as the POS / payments call it).
    north = await other_store(db_session, world, same_cluster=True)
    actor = AuditActor(tenant_id=world.a.tenant.id, actor_id=None, actor_role="system")
    async with tenant_scope(db_session, world.a.tenant.id):
        db_session.add(
            CreditLimit(
                tenant_id=world.a.tenant.id,
                farmer_id=farmer.id,
                store_id=north.id,
                limit_paise=100,
                set_by=world.a.user(UserRole.CLUSTER_HEAD).id,
            )
        )
        await db_session.flush()
        elsewhere = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=north.id,
            amount_paise=500,
            order_id=uuid.uuid4(),
            actor=actor,
            approval_request_id=uuid.UUID(request_id),
        )
        assert not elsewhere.allowed and elsewhere.approval_request_id != uuid.UUID(request_id)
        # An unknown id is simply not an approval.
        unknown = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=north.id,
            amount_paise=500,
            order_id=None,
            actor=actor,
            approval_request_id=uuid.uuid4(),
        )
        assert not unknown.allowed
    assert (await _request(db_session, world, request_id)).status == "approved"
    # The right farmer, store and amount: through, once.
    order = await place(
        client,
        bearer,
        world,
        farmer=farmer,
        payment_mode="credit",
        credit_approval_request_id=request_id,
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1"}],
    )
    consumed = await _request(db_session, world, request_id)
    assert consumed.status == "consumed"
    assert consumed.consumed_by_order_id == uuid.UUID(order["id"])


async def test_gate_consumes_a_named_approval_without_an_order_id(
    db_session: AsyncSession, world: World
) -> None:
    """Direct callers (no order id yet) consume a named approval the same way."""
    farmer = _other_farmer(world)
    store_id = world.a.store_id
    assert store_id is not None
    actor = AuditActor(tenant_id=world.a.tenant.id, actor_id=None, actor_role="system")
    async with tenant_scope(db_session, world.a.tenant.id):
        blocked = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=700,
            order_id=None,
            actor=actor,
        )
        assert blocked.approval_request_id is not None
        request = await db_session.get_one(CreditApprovalRequest, blocked.approval_request_id)
        request.status = "approved"
        request.decided_by = world.a.user(UserRole.CLUSTER_HEAD).id
        request.decided_at = request.created_at
        await db_session.flush()
        ok = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=700,
            order_id=None,
            actor=actor,
            approval_request_id=request.id,
        )
        assert ok.allowed and ok.approval_request_id == request.id
        await db_session.refresh(request)
        assert request.status == "consumed" and request.consumed_by_order_id is None


async def test_sync_order_retried_with_the_approval_goes_through(
    client: AsyncClient, ctx: WriteCtx, bearer: Bearer, db_session: AsyncSession
) -> None:
    world = ctx.world
    await receive(client, bearer, world, qty=10)
    farmer = _other_farmer(world)
    await _set_limit(client, bearer, world, farmer, 100)
    officer = bearer(world.a.user(UserRole.FIELD_OFFICER))
    payload = {
        "farmer_id": str(farmer.id),
        "payment_mode": "credit",
        "lines": [{"sku_id": str(world.a.sku_id), "qty": "1"}],
    }
    body = await sync(client, ctx, [op("order", "create", payload)], headers=officer)
    result = body["results"][0]
    assert result["status"] == "rejected"
    assert result["error"]["code"] == "credit_limit_exceeded"
    request_id = result["error"]["errors"][0]["approval_request_id"]
    await _approve(client, bearer, world, request_id)
    # The device re-captures the order (a new entity id) with the approval.
    entity_id = uuid.uuid4()
    body = await sync(
        client,
        ctx,
        [
            op(
                "order",
                "create",
                {**payload, "credit_approval_request_id": request_id},
                entity_id=entity_id,
            )
        ],
        headers=officer,
    )
    assert body["results"][0]["status"] == "applied", body
    consumed = await _request(db_session, world, request_id)
    assert consumed.status == "consumed" and consumed.consumed_by_order_id == entity_id
    # Replaying the approval for yet another order: rejected again.
    body = await sync(
        client,
        ctx,
        [op("order", "create", {**payload, "credit_approval_request_id": request_id})],
        headers=officer,
    )
    assert body["results"][0]["error"]["code"] == "credit_limit_exceeded"
