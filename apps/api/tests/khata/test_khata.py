"""FA-022 khata view: balance = sum of ledger entries, harvest-linked due dates, SPEC 5.2
overdue buckets, payment history, manual adjustments (append-only) and the shared
``post_credit`` contract used by payments (FA-021)."""

from __future__ import annotations

import inspect
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.models import AuditLog
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.khata.aging import bucket_for, effective_due_date, open_debits, overdue_buckets
from farmerapp.khata.ledger import (
    InvalidKhataEntryError,
    credit_due_date,
    credit_settings,
    post_credit,
    post_debit,
)
from farmerapp.khata.models import KhataEntry, khata_balance, overdue_paise
from tests.authz.conftest import Bearer, World
from tests.orders.helpers import demo_farmer, other_store, today


def _entry(
    type_: str, amount: int, *, due: date | None = None, created: datetime | None = None
) -> KhataEntry:
    return KhataEntry(
        id=uuid.uuid4(),
        tenant_id=uuid.uuid4(),
        farmer_id=uuid.uuid4(),
        store_id=uuid.uuid4(),
        type=type_,
        amount_paise=amount,
        due_date=due,
        ref_type="adjustment",
        created_at=created or datetime(2026, 1, 1, tzinfo=UTC),
    )


# --------------------------------------------------------------------------- ageing (pure)
@pytest.mark.parametrize(
    ("days", "bucket"),
    [(0, None), (1, "0_30"), (30, "0_30"), (31, "31_60"), (60, "31_60"), (61, "61_90"),
     (90, "61_90"), (91, "90_plus"), (400, "90_plus")],
)  # fmt: skip
def test_bucket_boundaries(days: int, bucket: str | None) -> None:
    assert bucket_for(days) == bucket


def test_credits_settle_the_earliest_due_debits_first() -> None:
    day = date(2026, 9, 18)
    old = _entry("debit", 1000, due=day - timedelta(days=100))
    mid = _entry("debit", 500, due=day - timedelta(days=45))
    new = _entry("debit", 700, due=day + timedelta(days=30))
    paid = _entry("credit", 1200)
    debits = open_debits([new, paid, mid, old], day, 90)
    assert [(d.entry_id, d.open_paise, d.bucket) for d in debits] == [
        (mid.id, 300, "31_60"),
        (new.id, 700, None),
    ]
    assert overdue_buckets(debits) == {"0_30": 0, "31_60": 300, "61_90": 0, "90_plus": 0}
    # Without a due date: end of the harvest month, else created + default days.
    harvest = _entry("debit", 1)
    harvest.harvest_month = date(2027, 2, 1)
    assert effective_due_date(harvest, 90) == date(2027, 2, 28)
    plain = _entry("debit", 1, created=datetime(2026, 1, 1, tzinfo=UTC))
    assert effective_due_date(plain, 30) == date(2026, 1, 31)
    assert credit_settings(None).credit_due_days == 90
    assert credit_settings({"credit_due_days": 45}).credit_due_days == 45


# --------------------------------------------------------------------------- the view
async def _khata(
    client: AsyncClient, headers: dict[str, str], farmer: Farmer, **params: str
) -> dict[str, Any]:
    resp = await client.get(
        f"/v1/farmers/{farmer.id}/khata", params={"limit": "100", **params}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    out: dict[str, Any] = resp.json()
    return out


async def test_khata_view_due_dates_buckets_and_payment_history(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    farmer = demo_farmer(world.a)
    manager = bearer(world.a.user(UserRole.STORE_MANAGER))
    # Old debits in each bucket (manual adjustments carry an explicit due date).
    for days, amount in ((10, 1000), (45, 2000), (75, 3000), (120, 4000)):
        resp = await client.post(
            f"/v1/farmers/{farmer.id}/khata/entries",
            json={
                "type": "debit",
                "amount_paise": amount,
                "reason": f"opening balance {days}d",
                "due_date": (today() - timedelta(days=days)).isoformat(),
            },
            headers=manager,
        )
        assert resp.status_code == 201, resp.text
    body = await _khata(client, bearer(world.a.user(UserRole.FARMER)), farmer)
    assert body["balance_paise"] == sum(e["signed_paise"] for e in body["entries"])
    async with tenant_scope(db_session, world.a.tenant.id):
        assert body["balance_paise"] == await khata_balance(db_session, farmer.id)
        overdue = await overdue_paise(db_session, farmer.id, today())
    buckets = body["overdue_buckets"]
    assert set(buckets) == {"0_30", "31_60", "61_90", "90_plus"}
    assert all(isinstance(v, int) for v in buckets.values())
    assert sum(buckets.values()) == body["overdue_paise"] == overdue
    # The seeded credit repayment settles the oldest-due debits first.
    assert sum(d["open_paise"] for d in body["open_debits"]) == body["balance_paise"]
    for debit in body["open_debits"]:
        due = date.fromisoformat(debit["due_date"])
        assert debit["days_overdue"] == max((today() - due).days, 0)
        assert debit["bucket"] == bucket_for(debit["days_overdue"])
    # Payment history: the farmer's cash repayment from the seed, not the credit sale.
    modes = {p["mode"] for p in body["payment_history"]}
    assert "credit" not in modes and body["payment_history"]
    assert all(p["farmer_id"] == str(farmer.id) for p in body["payment_history"])
    # A store filter narrows everything.
    elsewhere = await _khata(client, bearer(world.a.owner), farmer, store_id=str(uuid.uuid4()))
    assert elsewhere["open_debits"] == [] and elsewhere["payment_history"] == []
    assert elsewhere["overdue_buckets"] == {"0_30": 0, "31_60": 0, "61_90": 0, "90_plus": 0}


# --------------------------------------------------------------------------- adjustments
async def test_manual_entries_are_append_only_audited_and_store_manager_only(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    farmer = demo_farmer(world.a)
    manager = world.a.user(UserRole.STORE_MANAGER)
    url = f"/v1/farmers/{farmer.id}/khata/entries"
    before = (await _khata(client, bearer(world.a.owner), farmer))["balance_paise"]
    resp = await client.post(
        url,
        json={"type": "debit", "amount_paise": 2500, "reason": "sprayer rental"},
        headers=bearer(manager),
    )
    assert resp.status_code == 201, resp.text
    debit = resp.json()
    assert debit["ref_type"] == "adjustment" and debit["note"] == "sprayer rental"
    assert debit["store_id"] == str(world.a.store_id) and debit["created_by"] == str(manager.id)
    assert debit["due_date"] is not None  # harvest-linked or tenant default days
    async with tenant_scope(db_session, world.a.tenant.id):
        due, month = await credit_due_date(
            db_session, tenant_id=world.a.tenant.id, farmer_id=farmer.id, today=today()
        )
    assert debit["due_date"] == due.isoformat()
    assert debit["harvest_month"] == (month.isoformat() if month else None)
    # The correction of a wrong entry is the opposite entry, never an edit.
    resp = await client.post(
        url,
        json={"type": "credit", "amount_paise": 2500, "reason": "entered twice by mistake"},
        headers=bearer(manager),
    )
    assert resp.status_code == 201
    after = (await _khata(client, bearer(world.a.owner), farmer))["balance_paise"]
    assert after == before
    async with tenant_scope(db_session, world.a.tenant.id):
        events = (
            (
                await db_session.execute(
                    select(AuditLog).where(AuditLog.action == "khata_entry.adjustment")
                )
            )
            .scalars()
            .all()
        )
    assert len(events) == 2 and all(e.actor_id == manager.id for e in events)
    assert events[0].after is not None and events[0].after["amount_paise"] == 2500
    # Validation: a reason, positive integer paise.
    for bad in (
        {"type": "debit", "amount_paise": 100},
        {"type": "debit", "amount_paise": 0, "reason": "zero"},
        {"type": "debit", "amount_paise": 10.5, "reason": "float"},
        {"type": "debit", "amount_paise": "100", "reason": "string"},
        {"type": "refund", "amount_paise": 100, "reason": "bad type"},
    ):
        resp = await client.post(url, json=bad, headers=bearer(manager))
        assert resp.status_code == 422, bad
    # Only the store manager of the store writes; another store is unknown.
    for role in ("owner", "cluster_head", "field_officer", "farmer", "accountant"):
        resp = await client.post(
            url,
            json={"type": "credit", "amount_paise": 1, "reason": "role check"},
            headers=bearer(world.a.user(role)),
        )
        assert resp.status_code == 403, role
    north = await other_store(db_session, world, same_cluster=True)
    resp = await client.post(
        url,
        json={"type": "credit", "amount_paise": 1, "reason": "x-store", "store_id": str(north.id)},
        headers=bearer(manager),
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/farmers/{world.b.farmer.id}/khata/entries",
        json={"type": "credit", "amount_paise": 1, "reason": "x-tenant"},
        headers=bearer(manager),
    )
    assert resp.status_code == 404


# --------------------------------------------------------------------------- contract
def test_post_credit_signature_is_the_shared_contract() -> None:
    sig = inspect.signature(post_credit)
    assert list(sig.parameters)[:8] == [
        "session",
        "tenant_id",
        "farmer_id",
        "store_id",
        "amount_paise",
        "ref_type",
        "ref_id",
        "actor",
    ]
    assert all(
        p.kind == inspect.Parameter.KEYWORD_ONLY
        for name, p in sig.parameters.items()
        if name != "session"
    )


async def test_post_credit_and_debit_direct(db_session: AsyncSession, world: World) -> None:
    farmer = demo_farmer(world.a)
    store_id = world.a.store_id
    assert store_id is not None
    tid = world.a.tenant.id
    async with tenant_scope(db_session, tid):
        before = await khata_balance(db_session, farmer.id, store_id)
        payment_id = uuid.uuid4()
        credit = await post_credit(
            db_session,
            tenant_id=tid,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=1234,
            ref_type="payment",
            ref_id=payment_id,
            actor=world.a.user(UserRole.FIELD_OFFICER),
        )
        assert credit.type == "credit" and credit.ref_id == payment_id
        assert credit.created_by == world.a.user(UserRole.FIELD_OFFICER).id
        assert await khata_balance(db_session, farmer.id, store_id) == before - 1234
        debit = await post_debit(
            db_session,
            tenant_id=tid,
            farmer_id=farmer.id,
            store_id=store_id,
            amount_paise=1234,
            ref_type="order",
            ref_id=None,
            actor=None,
            today=today(),
        )
        assert debit.due_date is not None and debit.created_by is None
        assert await khata_balance(db_session, farmer.id, store_id) == before
        for amount, ref in ((0, "payment"), (-1, "payment"), (5, "refund")):
            with pytest.raises(InvalidKhataEntryError):
                await post_credit(
                    db_session,
                    tenant_id=tid,
                    farmer_id=farmer.id,
                    store_id=store_id,
                    amount_paise=amount,
                    ref_type=ref,
                    ref_id=None,
                    actor=None,
                )
