"""ST-007 credit approval: limits per farmer and store, the credit gate on credit sales and
the cluster-head approval flow. Acceptance: "sale beyond limit blocked without approval".
Also the shared ``check_and_reserve_credit`` contract the payments package codes against."""

from __future__ import annotations

import inspect
import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.audit import Actor as AuditActor
from farmerapp.db.models import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.khata.credit import CreditDecision, check_and_reserve_credit
from farmerapp.khata.ledger import next_harvest
from farmerapp.khata.models import (
    CreditApprovalRequest,
    CreditLimit,
    KhataEntry,
    khata_balance,
)
from farmerapp.orders.models import Order
from tests.authz.conftest import Bearer, World
from tests.farmers.write_fixtures import WriteCtx
from tests.orders.helpers import demo_farmer, other_store, place, receive, today
from tests.sync.conftest import op, sync


def _other_farmer(world: World) -> Farmer:
    """A farmer of the role officer without any khata (limit 0 until one is set)."""
    officer = world.a.user(UserRole.FIELD_OFFICER)
    demo = demo_farmer(world.a)
    return next(f for f in world.a.farmers if f.registered_by == officer.id and f.id != demo.id)


async def _set_limit(
    client: AsyncClient,
    bearer: Bearer,
    world: World,
    farmer: Farmer,
    limit: int,
    *,
    role: str = "store_manager",
    store_id: uuid.UUID | None = None,
    expect: int = 200,
) -> dict[str, Any]:
    resp = await client.put(
        f"/v1/farmers/{farmer.id}/credit-limit",
        json={"store_id": str(store_id or world.a.store_id), "limit_paise": limit},
        headers=bearer(world.a.user(role)),
    )
    assert resp.status_code == expect, resp.text
    out: dict[str, Any] = resp.json()
    return out


# --------------------------------------------------------------------------- limits
async def test_store_manager_sets_limits_up_to_the_tenant_max(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    farmer = _other_farmer(world)
    manager = world.a.user(UserRole.STORE_MANAGER)
    row = await _set_limit(client, bearer, world, farmer, 5_000_000)  # ₹50,000: the default max
    assert row["limit_paise"] == 5_000_000 and row["set_by"] == str(manager.id)
    assert row["approved_by"] is None
    problem = await _set_limit(client, bearer, world, farmer, 5_000_001, expect=403)
    assert problem["code"] == "credit_limit_needs_cluster_head"
    assert problem["max_limit_paise"] == 5_000_000
    head = world.a.user(UserRole.CLUSTER_HEAD)
    row = await _set_limit(client, bearer, world, farmer, 9_000_000, role="cluster_head")
    assert row["approved_by"] == str(head.id) and row["version"] == 2  # same row, updated
    # The tenant setting moves the store manager's ceiling.
    async with tenant_scope(db_session, world.a.tenant.id):
        tenant = await db_session.get_one(Tenant, world.a.tenant.id)
        tenant.settings = {**tenant.settings, "store_manager_max_credit_limit_paise": 10_000_000}
        await db_session.flush()
    row = await _set_limit(client, bearer, world, farmer, 9_500_000)
    assert row["approved_by"] is None
    # Scope: a store manager for their store only; a cluster head for their cluster.
    north = await other_store(db_session, world, same_cluster=True)
    south = await other_store(db_session, world, same_cluster=False)
    await _set_limit(client, bearer, world, farmer, 100, store_id=north.id, expect=404)
    await _set_limit(
        client, bearer, world, farmer, 100, role="cluster_head", store_id=south.id, expect=404
    )
    await _set_limit(client, bearer, world, farmer, 100, role="owner", store_id=south.id)
    for role in ("field_officer", "accountant", "farmer", "auditor"):
        await _set_limit(client, bearer, world, farmer, 100, role=role, expect=403)
    resp = await client.put(
        f"/v1/farmers/{world.b.farmer.id}/credit-limit",
        json={"store_id": str(world.a.store_id), "limit_paise": 100},
        headers=bearer(manager),
    )
    assert resp.status_code == 404
    for bad in (-1, 1.5, "100"):
        resp = await client.put(
            f"/v1/farmers/{farmer.id}/credit-limit",
            json={"store_id": str(world.a.store_id), "limit_paise": bad},
            headers=bearer(manager),
        )
        assert resp.status_code == 422, bad


# --------------------------------------------------------------------------- the gate
async def test_credit_sale_within_limit_posts_a_harvest_linked_debit(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=10)
    farmer = demo_farmer(world.a)
    async with tenant_scope(db_session, world.a.tenant.id):
        before = await khata_balance(db_session, farmer.id, world.a.store_id)
        harvest = await next_harvest(db_session, farmer.id, today())
    await _set_limit(client, bearer, world, farmer, before + 10_000_000, role="cluster_head")
    order = await place(client, bearer, world, payment_mode="credit")
    async with tenant_scope(db_session, world.a.tenant.id):
        after = await khata_balance(db_session, farmer.id, world.a.store_id)
        debit = await db_session.scalar(
            select(KhataEntry).where(KhataEntry.ref_id == uuid.UUID(order["id"]))
        )
    assert after - before == order["total_paise"]
    assert debit is not None and debit.type == "debit" and debit.ref_type == "order"
    if harvest is not None:
        assert debit.due_date == harvest and debit.harvest_month == harvest.replace(day=1)
    else:
        assert debit.due_date is not None and (debit.due_date - today()).days == 90
    # Cancelling the order reverses the debit (append-only: a credit entry).
    await client.post(
        f"/v1/orders/{order['id']}/status",
        json={"status": "cancelled"},
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    async with tenant_scope(db_session, world.a.tenant.id):
        assert await khata_balance(db_session, farmer.id, world.a.store_id) == before
        rows = (
            (
                await db_session.execute(
                    select(KhataEntry).where(KhataEntry.ref_id == uuid.UUID(order["id"]))
                )
            )
            .scalars()
            .all()
        )
    assert sorted((r.type, r.ref_type) for r in rows) == [
        ("credit", "adjustment"),
        ("debit", "order"),
    ]


async def test_sale_beyond_limit_is_blocked_until_a_cluster_head_approves(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=20)
    farmer = _other_farmer(world)
    manager = world.a.user(UserRole.STORE_MANAGER)
    await _set_limit(client, bearer, world, farmer, 100)  # ₹1: any sale is beyond it
    order_id = str(uuid.uuid4())
    problem = await place(
        client, bearer, world, farmer=farmer, payment_mode="credit", id=order_id, expect=402
    )
    assert problem["code"] == "credit_limit_exceeded"
    assert problem["limit_paise"] == 100 and problem["balance_paise"] == 0
    request_id = problem["approval_request_id"]
    shortfall = problem["shortfall_paise"]
    assert request_id and shortfall > 0
    async with tenant_scope(db_session, world.a.tenant.id):
        assert await db_session.get(Order, uuid.UUID(order_id)) is None  # nothing sold
        request = await db_session.get_one(CreditApprovalRequest, uuid.UUID(request_id))
        assert request.status == "pending" and request.order_id == uuid.UUID(order_id)
        assert request.requested_by == world.a.user(UserRole.FIELD_OFFICER).id
        assert await khata_balance(db_session, farmer.id, world.a.store_id) == 0
    # Retrying the same order refreshes the same pending request.
    again = await place(
        client, bearer, world, farmer=farmer, payment_mode="credit", id=order_id, expect=402
    )
    assert again["approval_request_id"] == request_id
    # The queue: store staff see it; officers do not; only approvers decide.
    listing = await client.get(
        "/v1/credit-approvals", params={"status": "pending"}, headers=bearer(manager)
    )
    assert [r["id"] for r in listing.json()["items"]] == [request_id]
    officer_headers = bearer(world.a.user(UserRole.FIELD_OFFICER))
    resp = await client.get("/v1/credit-approvals", headers=officer_headers)
    assert resp.status_code == 403
    for role in ("store_manager", "field_officer", "accountant"):
        resp = await client.post(
            f"/v1/credit-approvals/{request_id}/approve", headers=bearer(world.a.user(role))
        )
        assert resp.status_code == 403, role
    head = world.a.user(UserRole.CLUSTER_HEAD)
    resp = await client.post(
        f"/v1/credit-approvals/{request_id}/approve",
        json={"note": "good harvest expected"},
        headers=bearer(head),
    )
    assert resp.status_code == 200, resp.text
    decided = resp.json()
    assert decided["status"] == "approved" and decided["decided_by"] == str(head.id)
    resp = await client.post(f"/v1/credit-approvals/{request_id}/reject", headers=bearer(head))
    assert resp.status_code == 409 and resp.json()["code"] == "approval_not_pending"
    # The same order now goes through, once.
    order = await place(client, bearer, world, farmer=farmer, payment_mode="credit", id=order_id)
    assert order["id"] == order_id and order["status"] == "reserved"
    async with tenant_scope(db_session, world.a.tenant.id):
        used = await db_session.get_one(CreditApprovalRequest, uuid.UUID(request_id))
        await db_session.refresh(used)
        assert used.used_at is not None
        assert await khata_balance(db_session, farmer.id, world.a.store_id) == order["total_paise"]
    # Another order is blocked again: approvals are per order and single use.
    problem = await place(client, bearer, world, farmer=farmer, payment_mode="credit", expect=402)
    assert problem["approval_request_id"] != request_id
    # A rejected request never lets the order through.
    resp = await client.post(
        f"/v1/credit-approvals/{problem['approval_request_id']}/reject", headers=bearer(head)
    )
    assert resp.status_code == 200 and resp.json()["status"] == "rejected"
    # Non-credit sales are not gated.
    cash = await place(client, bearer, world, farmer=farmer, payment_mode="cash")
    assert cash["status"] == "reserved"


async def test_approval_scope(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=5)
    farmer = _other_farmer(world)
    problem = await place(client, bearer, world, farmer=farmer, payment_mode="credit", expect=402)
    request_id = problem["approval_request_id"]
    # Cluster head of another cluster / another tenant: unknown request.
    south = await other_store(db_session, world, same_cluster=False)
    async with tenant_scope(db_session, world.a.tenant.id):
        other_head = await db_session.scalar(
            select(User).where(
                User.role == UserRole.CLUSTER_HEAD.value, User.cluster_id == south.cluster_id
            )
        )
    if other_head is not None:
        resp = await client.post(
            f"/v1/credit-approvals/{request_id}/approve", headers=bearer(other_head)
        )
        assert resp.status_code == 404
    resp = await client.post(
        f"/v1/credit-approvals/{request_id}/approve",
        headers=bearer(world.b.user(UserRole.CLUSTER_HEAD)),
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/credit-approvals/{request_id}/approve", headers=bearer(world.a.owner)
    )
    assert resp.status_code == 200
    everything = await client.get(
        "/v1/credit-approvals",
        params={"farmer_id": str(farmer.id), "store_id": str(world.a.store_id)},
        headers=bearer(world.a.owner),
    )
    assert [r["status"] for r in everything.json()["items"]] == ["approved"]


async def test_credit_blocked_through_sync_keeps_the_request(
    client: AsyncClient, ctx: WriteCtx, bearer: Bearer, db_session: AsyncSession
) -> None:
    world = ctx.world
    await receive(client, bearer, world, qty=5)
    farmer = _other_farmer(world)
    order_id = uuid.uuid4()
    body = await sync(
        client,
        ctx,
        [
            op(
                "order",
                "create",
                {
                    "farmer_id": str(farmer.id),
                    "payment_mode": "credit",
                    "lines": [{"sku_id": str(world.a.sku_id), "qty": "1"}],
                },
                entity_id=order_id,
            )
        ],
        headers=bearer(world.a.user(UserRole.FIELD_OFFICER)),
    )
    result = body["results"][0]
    assert result["status"] == "rejected"
    assert result["error"]["code"] == "credit_limit_exceeded" and result["error"]["status"] == 402
    request_id = result["error"]["errors"][0]["approval_request_id"]
    async with tenant_scope(db_session, world.a.tenant.id):
        request = await db_session.get_one(CreditApprovalRequest, uuid.UUID(request_id))
    assert request.order_id == order_id and request.status == "pending"


# --------------------------------------------------------------------------- contract
def test_check_and_reserve_credit_signature_is_the_shared_contract() -> None:
    sig = inspect.signature(check_and_reserve_credit)
    assert list(sig.parameters) == [
        "session",
        "tenant_id",
        "farmer_id",
        "store_id",
        "amount_paise",
        "order_id",
        "actor",
    ]
    assert all(
        p.kind == inspect.Parameter.KEYWORD_ONLY
        for name, p in sig.parameters.items()
        if name != "session"
    )
    decision = CreditDecision(allowed=True, approval_request_id=None, shortfall_paise=0)
    assert decision.khata_entry_id is None


async def test_check_and_reserve_credit_direct(db_session: AsyncSession, world: World) -> None:
    """The payments package calls it with an audit ``Actor`` (or a ``User``), with or
    without an order id; the debit is posted by the gate itself."""
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
            amount_paise=5000,
            order_id=None,
            actor=actor,
        )
        assert not blocked.allowed and blocked.shortfall_paise == 5000
        assert blocked.approval_request_id is not None and blocked.khata_entry_id is None
        db_session.add(
            CreditLimit(
                tenant_id=world.a.tenant.id,
                farmer_id=farmer.id,
                store_id=store_id,
                limit_paise=6000,
                set_by=world.a.user(UserRole.STORE_MANAGER).id,
            )
        )
        await db_session.flush()
        manager = world.a.user(UserRole.STORE_MANAGER)
        ok = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=5000,
            order_id=uuid.uuid4(),
            actor=manager,
        )
        assert ok.allowed and ok.shortfall_paise == 0 and ok.khata_entry_id is not None
        entry = await db_session.get_one(KhataEntry, ok.khata_entry_id)
        assert entry.amount_paise == 5000 and entry.created_by == manager.id
        edge = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=1001,  # 5000 + 1001 > 6000 by one rupee and one paisa
            order_id=None,
            actor=manager,
        )
        assert not edge.allowed and edge.shortfall_paise == 1
        exact = await check_and_reserve_credit(
            db_session,
            tenant_id=world.a.tenant.id,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=1000,  # exactly at the limit is allowed
            order_id=None,
            actor=manager,
        )
        assert exact.allowed
        for bad in (0, -5):
            try:
                await check_and_reserve_credit(
                    db_session,
                    tenant_id=world.a.tenant.id,
                    farmer_id=farmer.id,
                    store_id=store_id,
                    amount_paise=bad,
                    order_id=None,
                    actor=manager,
                )
            except ValueError:
                pass
            else:  # pragma: no cover
                raise AssertionError("non-positive amounts must be refused")
