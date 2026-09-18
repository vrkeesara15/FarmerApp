"""M3 demo seed (M3-KICKOFF): catalogue, label claims, stock, orders, payments, khata, credit
limits and day closes — counts, plausibility, internal consistency (ledger = cache, order
totals, khata balance), idempotency and the < 30 s budget together with M1 + M2."""

from __future__ import annotations

import time
from collections import Counter
from datetime import timedelta
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import (
    SEED_SOURCE_REF,
    LabelClaim,
    PestOrDisease,
    PriceList,
    Product,
    Sku,
)
from farmerapp.db.session import tenant_scope
from farmerapp.jobs.seed import FULL, SEED_TODAY, SEEDED_TABLES, SMALL, demo_tenant_id, seed_demo
from farmerapp.khata.models import CreditLimit, KhataEntry, khata_balance
from farmerapp.orders.models import Order, OrderLine
from farmerapp.payments.models import DayClose, Payment, WebhookEvent
from farmerapp.stock.ledger import stock_on_hand_by_batch
from farmerapp.stock.models import StockBatch, StockMovement
from farmerapp.tenants.models import Store

FCC = demo_tenant_id("fcc")
GFL = demo_tenant_id("gfl")
M3_TABLES = ("product", "sku", "price_list", "pest_or_disease", "label_claim", "stock_batch",
             "stock_movement", "order", "order_line", "khata_entry", "payment", "webhook_event",
             "credit_limit", "day_close")  # fmt: skip
GST_BY_CATEGORY = {"seed": {0}, "fertiliser": {500}, "pesticide": {1200, 1800},
                   "fungicide": {1800}, "herbicide": {1800}, "growth": {1800},
                   "tool": {1200, 1800}}  # fmt: skip


async def _count(session: AsyncSession, model: type) -> int:
    return int(await session.scalar(select(func.count()).select_from(model)) or 0)


async def test_full_seed_m3_counts_and_duration(db_session: AsyncSession) -> None:
    started = time.perf_counter()
    result = await seed_demo(db_session, FULL)
    elapsed = time.perf_counter() - started
    assert elapsed < 30, f"seed took {elapsed:.1f}s"
    for table in M3_TABLES:
        assert table in SEEDED_TABLES and result.created[table] == result.totals[table] > 0

    async with tenant_scope(db_session, FCC):
        products = (await db_session.execute(select(Product))).scalars().all()
        assert 40 <= len(products) <= 50
        own = [p for p in products if p.own_brand]
        assert 0.3 <= len(own) / len(products) <= 0.6
        assert all("FCC" in p.brand for p in own)
        for product in products:
            assert product.gst_rate_bp in GST_BY_CATEGORY[product.category], product.name
            assert product.hsn
        ingredients = " ".join(p.active_ingredient or "" for p in products)
        for ai in ("Imidacloprid", "Chlorpyrifos", "Mancozeb", "Carbendazim", "Lambda-cyhalothrin",
                   "Emamectin benzoate", "Azoxystrobin", "Copper oxychloride", "Azadirachtin",
                   "Spinosad"):  # fmt: skip
            assert ai in ingredients, ai
        assert {p.category for p in products} >= {"seed", "fertiliser", "pesticide", "fungicide"}
        skus = (await db_session.execute(select(Sku))).scalars().all()
        assert 70 <= len(skus) <= 90
        assert len({s.barcode for s in skus}) == len(skus)
        assert await _count(db_session, PriceList) >= len(skus)
        problems = (await db_session.execute(select(PestOrDisease))).scalars().all()
        assert 30 <= len(problems) <= 45
        assert {p.type for p in problems} == {"disease", "pest", "nutrient", "abiotic"}
        claims = (await db_session.execute(select(LabelClaim))).scalars().all()
        approved = [c for c in claims if c.status == "approved"]
        assert len(approved) >= 120
        assert {c.status for c in claims} == {"approved", "draft", "retired"}
        assert all(c.source_ref == SEED_SOURCE_REF for c in claims)
        assert all(c.dose_per_acre and c.dose_value for c in claims)
        assert all(c.approved_at is not None for c in approved)

        batches = (await db_session.execute(select(StockBatch))).scalars().all()
        stores = (await db_session.execute(select(Store))).scalars().all()
        assert {b.store_id for b in batches} == {s.id for s in stores}
        for store in stores:
            ledger = await stock_on_hand_by_batch(db_session, store.id)
            mine = [b for b in batches if b.store_id == store.id]
            assert all(ledger.get(b.id, Decimal(0)) == b.qty for b in mine)  # ST-003
            expiring = [b for b in mine if b.expiry and b.expiry <= SEED_TODAY + timedelta(days=30)]
            within_60 = [
                b for b in mine if b.expiry and b.expiry <= SEED_TODAY + timedelta(days=60)
            ]
            assert expiring and len(within_60) > len(expiring)  # ST-004 fixtures
        kinds = set((await db_session.execute(select(StockMovement.kind))).scalars())
        assert kinds >= {"receipt", "sale", "damage", "transfer_in", "transfer_out"}

        orders = (await db_session.execute(select(Order))).scalars().all()
        assert len(orders) == 150
        channels = Counter(o.channel for o in orders)
        assert set(channels) == {"pos", "officer", "farmer_app"}
        oldest = min(o.created_at for o in orders).date()
        assert oldest >= SEED_TODAY - timedelta(days=61)
        statuses = Counter(o.status for o in orders)
        assert statuses["delivered"] + statuses["handed_over"] > 75 and statuses["cancelled"] > 0
        lines = (await db_session.execute(select(OrderLine))).scalars().all()
        by_order: dict[object, list[OrderLine]] = {}
        for line in lines:
            by_order.setdefault(line.order_id, []).append(line)
        for order in orders:
            assert order.subtotal_paise == sum(x.line_total_paise for x in by_order[order.id])
            assert order.total_paise == (
                order.subtotal_paise - order.discount_paise + order.tax_paise
            )
        fulfilled = [o for o in orders if o.status in ("delivered", "handed_over")]
        assert all(o.invoice_no for o in fulfilled)
        claims_by_id = {c.id: c for c in claims}
        recommended = [(x, x.label_claim_id) for x in lines if x.label_claim_id is not None]
        assert recommended
        for line, claim_id in recommended:  # DX-007: a recommended line has an approved claim
            claim = claims_by_id[claim_id]
            assert claim.status == "approved" and claim.sku_id == line.sku_id

        payments = (await db_session.execute(select(Payment))).scalars().all()
        modes = Counter(p.mode for p in payments)
        assert set(modes) == {"cash", "upi_qr", "credit", "payment_link", "card_terminal"}
        provider = [p for p in payments if p.provider == "razorpay"]
        events = {e.event_id for e in (await db_session.execute(select(WebhookEvent))).scalars()}
        assert provider and {p.provider_event_id for p in provider if p.order_id} <= events

        entries = (await db_session.execute(select(KhataEntry))).scalars().all()
        overdue = [
            e for e in entries
            if e.type == "debit" and e.due_date and e.due_date < SEED_TODAY - timedelta(days=90)
        ]  # fmt: skip
        assert len(overdue) >= 8  # VA-F10 fixtures
        assert {e.type for e in entries} == {"debit", "credit"}
        for farmer_id in {e.farmer_id for e in entries}:
            expected = sum(
                e.amount_paise if e.type == "debit" else -e.amount_paise
                for e in entries
                if e.farmer_id == farmer_id
            )
            assert await khata_balance(db_session, farmer_id) == expected
        limits = (await db_session.execute(select(CreditLimit))).scalars().all()
        assert {(c.farmer_id, c.store_id) for c in limits} == {
            (e.farmer_id, e.store_id) for e in entries if e.type == "debit"
        }
        closes = (await db_session.execute(select(DayClose))).scalars().all()
        assert len(closes) == 3 * len(stores)
        assert any(c.variance_paise < 0 for c in closes)

    async with tenant_scope(db_session, GFL):
        assert await _count(db_session, Order) == 15
        products = (await db_session.execute(select(Product))).scalars().all()
        assert all("FCC" not in p.name for p in products)
        assert any("GFL" in p.brand for p in products)


async def test_small_seed_m3_counts(db_session: AsyncSession) -> None:
    result = await seed_demo(db_session, SMALL)
    for tid in (FCC, GFL):
        async with tenant_scope(db_session, tid):
            assert await _count(db_session, Product) == 5
            assert await _count(db_session, Sku) == 10
            assert await _count(db_session, LabelClaim) == 5
            stores = await _count(db_session, Store)
            assert await _count(db_session, StockBatch) == stores  # one batch per store
            assert await _count(db_session, Order) == 3
            assert await _count(db_session, KhataEntry) == 2
    second = await seed_demo(db_session, SMALL)
    assert all(second.created[t] == 0 for t in M3_TABLES)
    assert second.totals == result.totals


async def test_full_on_top_of_small_only_adds(db_session: AsyncSession) -> None:
    await seed_demo(db_session, SMALL)
    full = await seed_demo(db_session, FULL)
    assert full.totals["order"] == 6 + 165  # SMALL orders kept, FULL ones added
    again = await seed_demo(db_session, FULL)
    assert all(n == 0 for n in again.created.values())
