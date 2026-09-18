"""M3 money and stock entities at the model level: the ST-003 movement ledger (stock on hand
= sum of movements, batch cache in step), the FA-022 khata balance (= sum of entries),
append-only grants, order / payment / day-close CHECKs, and the sync contract (server wins,
writes not wired yet)."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import Sku
from farmerapp.db.session import tenant_scope
from farmerapp.khata.models import (
    EntryRef,
    EntryType,
    KhataEntry,
    balance_sql,
    khata_balance,
    khata_balances_by_store,
    overdue_paise,
)
from farmerapp.orders.models import Order, line_total_paise, tax_paise
from farmerapp.payments.models import DayClose, Payment, WebhookEvent
from farmerapp.stock.ledger import (
    InsufficientStockError,
    InvalidMovementError,
    apply_movement,
    check_sign,
    stock_on_hand,
    stock_on_hand_by_batch,
    stock_on_hand_by_sku,
)
from farmerapp.stock.models import MovementKind, StockBatch, StockMovement
from farmerapp.sync.models import SYNC_ENTITIES
from farmerapp.sync.service import CONFLICT_RULES, Strategy
from tests.authz.conftest import World
from tests.farmers.write_fixtures import WriteCtx
from tests.sync.conftest import op, sync

MONEY_ENTITIES = ("order", "order_line", "payment", "khata_entry")
TODAY = date(2026, 9, 18)


# --------------------------------------------------------------------------- helpers
def test_line_and_tax_rounding() -> None:
    assert line_total_paise(Decimal("3"), 26650) == 79950
    assert line_total_paise(Decimal("0.5"), 101) == 51  # half up
    assert tax_paise(10000, 1800) == 1800
    assert tax_paise(333, 500) == 17  # 16.65 -> 17
    assert tax_paise(1000, 0) == 0


@pytest.mark.parametrize(
    ("kind", "qty"),
    [
        (MovementKind.RECEIPT, Decimal(-1)),
        (MovementKind.TRANSFER_IN, Decimal(-1)),
        (MovementKind.SALE, Decimal(1)),
        (MovementKind.DAMAGE, Decimal(2)),
        (MovementKind.TRANSFER_OUT, Decimal(1)),
        (MovementKind.ADJUST, Decimal(0)),
    ],
)
def test_movement_sign_rules(kind: MovementKind, qty: Decimal) -> None:
    with pytest.raises(InvalidMovementError):
        check_sign(kind, qty)


# --------------------------------------------------------------------------- stock ledger
async def test_stock_on_hand_is_the_sum_of_movements(
    db_session: AsyncSession, world: World
) -> None:
    tid, store_id = world.a.tenant.id, world.a.store_id
    assert store_id is not None
    async with tenant_scope(db_session, tid):
        sku = await db_session.get_one(Sku, world.a.sku_id)
        before = await stock_on_hand(db_session, store_id, sku.id)
        batch = StockBatch(
            tenant_id=tid,
            store_id=store_id,
            sku_id=sku.id,
            batch_no="T-LEDGER-1",
            expiry=TODAY + timedelta(days=200),
            qty=Decimal(0),
            cost_paise=1000,
        )
        db_session.add(batch)
        await db_session.flush()
        await apply_movement(
            db_session, tenant_id=tid, store_id=store_id, sku_id=sku.id,
            kind=MovementKind.RECEIPT, qty=Decimal(20), batch=batch, ref_type="grn",
        )  # fmt: skip
        await apply_movement(
            db_session, tenant_id=tid, store_id=store_id, sku_id=sku.id,
            kind=MovementKind.SALE, qty=Decimal(-3), batch=batch, ref_type="order",
            ref_id=uuid.uuid4(),
        )  # fmt: skip
        await apply_movement(
            db_session, tenant_id=tid, store_id=store_id, sku_id=sku.id,
            kind=MovementKind.DAMAGE, qty=Decimal("-1.5"), batch=batch, note="broken",
        )  # fmt: skip
        await apply_movement(
            db_session, tenant_id=tid, store_id=store_id, sku_id=sku.id,
            kind=MovementKind.ADJUST, qty=Decimal("0.5"), batch=batch,
        )  # fmt: skip
        assert batch.qty == Decimal("16.000")
        assert await stock_on_hand(db_session, store_id, sku.id) == before + Decimal(16)
        by_batch = await stock_on_hand_by_batch(db_session, store_id)
        assert by_batch[batch.id] == batch.qty
        by_sku = await stock_on_hand_by_sku(db_session, store_id, [sku.id])
        assert by_sku[sku.id] == before + Decimal(16)
        assert await stock_on_hand_by_sku(db_session, store_id, []) == {}

        with pytest.raises(InsufficientStockError):
            await apply_movement(
                db_session, tenant_id=tid, store_id=store_id, sku_id=sku.id,
                kind=MovementKind.SALE, qty=Decimal(-17), batch=batch,
            )  # fmt: skip
        with pytest.raises(InvalidMovementError):  # batch of another store
            await apply_movement(
                db_session, tenant_id=tid, store_id=uuid.uuid4(), sku_id=sku.id,
                kind=MovementKind.RECEIPT, qty=Decimal(1), batch=batch,
            )  # fmt: skip
        assert batch.qty == Decimal("16.000")  # refused moves changed nothing
        # The database refuses a wrong sign even without the helper.
        with pytest.raises(IntegrityError):
            async with db_session.begin_nested():
                db_session.add(
                    StockMovement(
                        tenant_id=tid,
                        store_id=store_id,
                        sku_id=sku.id,
                        kind=MovementKind.SALE,
                        qty=Decimal(5),
                    )
                )
                await db_session.flush()


async def test_seeded_batch_cache_matches_ledger(db_session: AsyncSession, world: World) -> None:
    async with tenant_scope(db_session, world.a.tenant.id):
        batches = (await db_session.execute(select(StockBatch))).scalars().all()
        assert batches
        for store_id in {b.store_id for b in batches}:
            ledger = await stock_on_hand_by_batch(db_session, store_id)
            for batch in (b for b in batches if b.store_id == store_id):
                assert ledger.get(batch.id, Decimal(0)) == batch.qty, batch.batch_no


# --------------------------------------------------------------------------- khata
async def test_khata_balance_equals_sum_of_entries(db_session: AsyncSession, world: World) -> None:
    """FA-022 acceptance groundwork: the balance is the ledger, never a counter."""
    tid, store_id = world.a.tenant.id, world.a.store_id
    farmer = next(f for f in world.a.farmers if f.user_id is not None)  # the demo farmer login
    assert store_id is not None
    async with tenant_scope(db_session, tid):
        seeded = (
            (await db_session.execute(select(KhataEntry).where(KhataEntry.farmer_id == farmer.id)))
            .scalars()
            .all()
        )
        assert len(seeded) == 2  # SMALL: one credit sale, one part repayment
        assert await khata_balance(db_session, farmer.id) == balance_sql(list(seeded)) > 0

        base = datetime(2026, 9, 1, tzinfo=UTC)
        new = [
            KhataEntry(tenant_id=tid, farmer_id=farmer.id, store_id=store_id,
                       type=EntryType.DEBIT, amount_paise=500000, ref_type=EntryRef.ORDER,
                       due_date=TODAY - timedelta(days=100), created_at=base),
            KhataEntry(tenant_id=tid, farmer_id=farmer.id, store_id=store_id,
                       type=EntryType.DEBIT, amount_paise=120050, ref_type=EntryRef.ORDER,
                       due_date=TODAY + timedelta(days=60), harvest_month=date(2026, 11, 1),
                       created_at=base + timedelta(days=1)),
            KhataEntry(tenant_id=tid, farmer_id=farmer.id, store_id=store_id,
                       type=EntryType.CREDIT, amount_paise=200000, ref_type=EntryRef.PAYMENT,
                       created_at=base + timedelta(days=2)),
        ]  # fmt: skip
        db_session.add_all(new)
        await db_session.flush()
        entries = [*seeded, *new]
        expected = sum(
            e.amount_paise if e.type == EntryType.DEBIT else -e.amount_paise for e in entries
        )
        total = await db_session.scalar(
            select(func.sum(KhataEntry.amount_paise)).where(
                KhataEntry.farmer_id == farmer.id, KhataEntry.type == "debit"
            )
        )
        credits = await db_session.scalar(
            select(func.sum(KhataEntry.amount_paise)).where(
                KhataEntry.farmer_id == farmer.id, KhataEntry.type == "credit"
            )
        )
        assert (
            await khata_balance(db_session, farmer.id)
            == expected
            == int(total or 0) - int(credits or 0)
        )
        assert await khata_balance(db_session, farmer.id, store_id) == expected
        assert await khata_balances_by_store(db_session, farmer.id) == {store_id: expected}
        assert await khata_balance(db_session, farmer.id, uuid.uuid4()) == 0
        assert await khata_balance(db_session, farmer.id, as_of=base + timedelta(hours=1)) == (
            balance_sql([e for e in entries if e.created_at <= base + timedelta(hours=1)])
        )
        overdue = await overdue_paise(db_session, farmer.id, TODAY)
        seeded_overdue = sum(
            e.amount_paise
            for e in seeded
            if e.type == EntryType.DEBIT and e.due_date and e.due_date < TODAY
        )
        seeded_credit = sum(e.amount_paise for e in seeded if e.type == EntryType.CREDIT)
        assert overdue == max(500000 + seeded_overdue - seeded_credit - 200000, 0)
        assert await overdue_paise(db_session, farmer.id, TODAY, uuid.uuid4()) == 0

        for bad in ({"amount_paise": 0}, {"type": "refund"}, {"harvest_month": date(2026, 11, 5)}):
            with pytest.raises(IntegrityError):
                async with db_session.begin_nested():
                    fields = {
                        "tenant_id": tid, "farmer_id": farmer.id, "store_id": store_id,
                        "type": "debit", "amount_paise": 1, "ref_type": "order", **bad,
                    }  # fmt: skip
                    db_session.add(KhataEntry(**fields))
                    await db_session.flush()


@pytest.mark.parametrize("table", ["khata_entry", "stock_movement"])
@pytest.mark.parametrize("statement", ["UPDATE {t} SET note = 'x'", "DELETE FROM {t}"])
async def test_ledgers_are_append_only(
    db_session: AsyncSession, world: World, table: str, statement: str
) -> None:
    async with tenant_scope(db_session, world.a.tenant.id):
        with pytest.raises(DBAPIError, match="permission denied"):
            async with db_session.begin_nested():
                await db_session.execute(text(statement.format(t=table)))


async def test_rls_hides_other_tenant_money(db_session: AsyncSession, world: World) -> None:
    async with tenant_scope(db_session, world.a.tenant.id):
        mine = int(await db_session.scalar(select(func.count()).select_from(Order)) or 0)
        tenants = set((await db_session.execute(select(Order.tenant_id))).scalars())
    assert mine > 0 and tenants == {world.a.tenant.id}
    async with tenant_scope(db_session, uuid.uuid4()):
        for model in (Order, Payment, KhataEntry, StockBatch, WebhookEvent, DayClose):
            assert await db_session.scalar(select(func.count()).select_from(model)) == 0


# --------------------------------------------------------------------------- constraints
async def test_order_payment_day_close_checks(db_session: AsyncSession, world: World) -> None:
    tid, store_id = world.a.tenant.id, world.a.store_id
    manager = world.a.user("store_manager")
    async with tenant_scope(db_session, tid):

        async def refused(obj: object) -> None:
            with pytest.raises(IntegrityError):
                async with db_session.begin_nested():
                    db_session.add(obj)
                    await db_session.flush()

        base = {"tenant_id": tid, "store_id": store_id, "channel": "pos", "status": "placed",
                "fulfilment": "pickup"}  # fmt: skip
        await refused(Order(**base, subtotal_paise=1000, discount_paise=0, tax_paise=180,
                            total_paise=1000))  # fmt: skip
        await refused(Order(**{**base, "channel": "phone"}, subtotal_paise=0, discount_paise=0,
                            tax_paise=0, total_paise=0))  # fmt: skip
        ok = Order(**base, subtotal_paise=1000, discount_paise=100, tax_paise=162,
                   total_paise=1062)  # fmt: skip
        db_session.add(ok)
        await db_session.flush()

        pay = {"tenant_id": tid, "store_id": store_id, "order_id": ok.id, "amount_paise": 1062}
        await refused(Payment(**pay, mode="cash", provider="razorpay", status="paid"))
        await refused(Payment(**pay, mode="upi_qr", provider="none", status="pending"))
        await refused(Payment(**{**pay, "order_id": None}, mode="cash", provider="none",
                              status="paid"))  # fmt: skip
        await refused(Payment(**{**pay, "amount_paise": 0}, mode="cash", provider="none",
                              status="paid"))  # fmt: skip
        first = Payment(**pay, mode="upi_qr", provider="razorpay", status="paid",
                        provider_ref="pay_T1", provider_event_id="evt_T1")  # fmt: skip
        db_session.add(first)
        await db_session.flush()
        # SEC-023: the same provider event can never mark a second payment.
        await refused(Payment(**pay, mode="upi_qr", provider="razorpay", status="paid",
                              provider_event_id="evt_T1"))  # fmt: skip
        event = {"tenant_id": tid, "provider": "razorpay", "signature_ok": True, "payload": {}}
        db_session.add(WebhookEvent(**event, event_id="evt_T1", status="processed"))
        await db_session.flush()
        await refused(WebhookEvent(**event, event_id="evt_T1", status="received"))

        close = {"tenant_id": tid, "store_id": store_id, "closed_by": manager.id,
                 "closed_at": datetime.now(UTC)}  # fmt: skip
        await refused(DayClose(**close, business_date=date(2026, 1, 1), cash_expected_paise=100,
                               cash_counted_paise=90, variance_paise=0))  # fmt: skip
        db_session.add(DayClose(**close, business_date=date(2026, 1, 1), cash_expected_paise=100,
                                cash_counted_paise=90, variance_paise=-10))  # fmt: skip
        await db_session.flush()
        await refused(DayClose(**close, business_date=date(2026, 1, 1), cash_expected_paise=0,
                               cash_counted_paise=0, variance_paise=0))  # fmt: skip


# --------------------------------------------------------------------------- sync
def test_money_entities_are_synced_server_wins() -> None:
    for entity in MONEY_ENTITIES:
        assert entity in SYNC_ENTITIES
        assert CONFLICT_RULES[entity] == Strategy.SERVER_WINS
    assert set(CONFLICT_RULES) == set(SYNC_ENTITIES)


async def test_money_sync_writes_are_not_wired_yet(client: AsyncClient, ctx: WriteCtx) -> None:
    """Lines travel inside the ``order`` create (FA-020, tests/orders/test_place.py);
    payments and khata entries have no device write path yet."""
    unwired = [e for e in MONEY_ENTITIES if e != "order"]
    ops = [op(entity, "create", {"amount_paise": 100}) for entity in unwired]
    body = await sync(client, ctx, ops)
    assert [r["status"] for r in body["results"]] == ["rejected"] * len(unwired)
    assert {r["error"]["code"] for r in body["results"]} == {"unsupported_action"}
    body = await sync(client, ctx, [op("order", "create", {"amount_paise": 100})])
    assert body["results"][0]["error"]["code"] == "validation_error"  # wired: FA-020


async def test_changes_feed_carries_own_orders_and_khata(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    """The officer's feed has the orders they placed, their lines, the payments they
    collected and their farmers' khata entries — as current state, never as deletes."""
    body = await sync(client, ctx, [])
    changes = body["changes"]
    by_entity: dict[str, list[dict[str, object]]] = {}
    for change in changes:
        by_entity.setdefault(str(change["entity"]), []).append(change)
    for entity in MONEY_ENTITIES:
        assert by_entity.get(entity), entity
        assert all(c["action"] == "create" for c in by_entity[entity]), entity
    officer_id = str(ctx.officer.id)
    assert all(c["data"]["placed_by"] == officer_id for c in by_entity["order"])  # type: ignore[index]
