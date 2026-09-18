"""M3 catalogue at the model level: money is integer paise everywhere, every M3 table is
under RLS (append-only ledgers included), the price resolver, label-claim constraints and
the audit trail."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

import pytest
from sqlalchemy import BigInteger, Float, Integer, Numeric, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

import farmerapp.db.models  # noqa: F401  (register every model)
from farmerapp.catalog.models import (
    SEED_SOURCE_REF,
    ClaimStatus,
    LabelClaim,
    PestOrDisease,
    PriceList,
    Product,
    ProductCategory,
    Sku,
)
from farmerapp.catalog.pricing import in_force, price_for, prices_for, resolve, resolved_price
from farmerapp.db.base import Base
from farmerapp.db.models import AuditLog
from farmerapp.db.rls import APPEND_ONLY_TABLES, rls_violations
from farmerapp.db.session import tenant_scope
from farmerapp.tenants.models import Store
from tests.authz.conftest import World

M3_TABLES = (
    "product",
    "sku",
    "price_list",
    "pest_or_disease",
    "label_claim",
    "stock_batch",
    "stock_movement",
    "order",
    "order_line",
    "payment",
    "webhook_event",
    "day_close",
    "khata_entry",
    "credit_limit",
)
#: Column-name fragments that mean money; such a column must be an integer type.
MONEY_WORDS = ("paise", "price", "amount", "mrp", "cost", "total", "tax", "discount", "limit")
TODAY = date(2026, 9, 18)


# --------------------------------------------------------------------------- money
def test_money_columns_are_integer_paise() -> None:
    """SPEC 8.2: money is integer paise — no numeric / float money column anywhere."""
    offenders: list[str] = []
    money_columns = 0
    for table in Base.metadata.sorted_tables:
        for column in table.columns:
            name = column.name
            if not any(word in name for word in MONEY_WORDS):
                continue
            if name.endswith(("_at", "_id", "_uri", "_text", "_note", "_bp", "_words")):
                continue
            money_columns += 1
            if isinstance(column.type, Numeric | Float) or not isinstance(
                column.type, Integer | BigInteger
            ):
                offenders.append(f"{table.name}.{name}: {column.type}")
            if not name.endswith("_paise"):
                offenders.append(f"{table.name}.{name}: money column not named *_paise")
    assert offenders == []
    # every M3 money column was inspected (update when adding one): 15 + 6 on invoice (0013)
    assert money_columns == 21


def test_every_m3_table_is_a_model_table() -> None:
    names = {t.name for t in Base.metadata.sorted_tables}
    assert set(M3_TABLES) <= names
    assert {"stock_movement", "khata_entry"} <= APPEND_ONLY_TABLES


async def test_m3_tables_are_isolated(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        problems = await conn.run_sync(rls_violations, list(M3_TABLES))
    assert problems == []


# --------------------------------------------------------------------------- pricing (pure)
@dataclass
class Row:
    sku_id: uuid.UUID
    store_id: uuid.UUID | None
    price_paise: int
    effective_from: date
    effective_to: date | None = None


SKU, STORE, OTHER = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()


def test_in_force_bounds() -> None:
    row = Row(SKU, None, 100, TODAY, TODAY + timedelta(days=2))
    assert in_force(row, TODAY) and in_force(row, TODAY + timedelta(days=2))
    assert not in_force(row, TODAY - timedelta(days=1))
    assert not in_force(row, TODAY + timedelta(days=3))
    assert in_force(Row(SKU, None, 1, TODAY), date(2030, 1, 1))  # open ended


def test_resolve_prefers_store_then_default_then_latest() -> None:
    rows = [
        Row(SKU, None, 1000, TODAY - timedelta(days=100)),
        Row(SKU, None, 1100, TODAY - timedelta(days=10)),  # newer default wins over older
        Row(SKU, STORE, 900, TODAY - timedelta(days=30)),
        Row(SKU, STORE, 800, TODAY - timedelta(days=90), TODAY - timedelta(days=40)),  # expired
        Row(SKU, OTHER, 500, TODAY - timedelta(days=5)),  # another store's override
    ]
    assert resolve(rows, STORE, TODAY) == 900
    assert resolve(rows, OTHER, TODAY) == 500
    assert resolve(rows, None, TODAY) == 1100
    assert resolve(rows, uuid.uuid4(), TODAY) == 1100  # store without override -> default
    assert resolve(rows, STORE, TODAY - timedelta(days=50)) == 800  # the override in force then
    assert resolve(rows, STORE, TODAY - timedelta(days=200)) is None
    assert resolve([], STORE, TODAY) is None
    assert resolved_price(None, 1234) == 1234 and resolved_price(999, 1234) == 999


# --------------------------------------------------------------------------- pricing (DB)
async def test_price_for_against_the_seed(db_session: AsyncSession, world: World) -> None:
    tid = world.a.tenant.id
    async with tenant_scope(db_session, tid):
        store = await db_session.get_one(Store, world.a.store_id)
        sku = await db_session.get_one(Sku, world.a.sku_id)
        default = await price_for(db_session, sku.id, store.id, TODAY)
        assert default is not None and 0 < default <= sku.mrp_paise
        db_session.add_all(
            [
                PriceList(
                    tenant_id=tid,
                    store_id=store.id,
                    sku_id=sku.id,
                    price_paise=default - 100,
                    effective_from=TODAY - timedelta(days=1),
                ),
                PriceList(
                    tenant_id=tid,
                    store_id=store.id,
                    sku_id=sku.id,
                    price_paise=1,
                    effective_from=TODAY - timedelta(days=30),
                    effective_to=TODAY - timedelta(days=20),
                ),
            ]
        )
        await db_session.flush()
        assert await price_for(db_session, sku.id, store.id, TODAY) == default - 100
        assert await price_for(db_session, sku.id, None, TODAY) == default
        assert await price_for(db_session, sku.id, store.id, TODAY - timedelta(days=25)) == 1
        assert await price_for(db_session, sku.id, store.id, date(2020, 1, 1)) is None
        assert await prices_for(db_session, [], store.id, TODAY) == {}


# --------------------------------------------------------------------------- constraints
async def test_product_sku_claim_constraints_and_audit(
    db_session: AsyncSession, world: World
) -> None:
    tid = world.a.tenant.id
    async with tenant_scope(db_session, tid):
        product = Product(
            tenant_id=tid,
            name="Test Imida",
            brand="TestCo",
            category=ProductCategory.PESTICIDE,
            hsn="3808",
            gst_rate_bp=1800,
        )
        db_session.add(product)
        await db_session.flush()
        sku = Sku(
            tenant_id=tid,
            product_id=product.id,
            pack_size_value=Decimal("250"),
            pack_size_unit="ml",
            barcode="8900000000001",
            mrp_paise=45000,
        )
        db_session.add(sku)
        await db_session.flush()
        assert sku.pack_label == "250 ml"
        audited = await db_session.scalar(
            select(AuditLog).where(AuditLog.entity == "product", AuditLog.entity_id == product.id)
        )
        assert audited is not None and audited.action == "product.create"

        pest = (await db_session.execute(select(PestOrDisease).limit(1))).scalar_one()
        claim = LabelClaim(
            tenant_id=tid,
            sku_id=sku.id,
            crop_id=world.a.crop_id,
            pest_or_disease_id=pest.id,
            dose_per_acre="50 ml/acre",
            dose_value=Decimal("50"),
            dose_unit="ml",
            source_ref=SEED_SOURCE_REF,
        )
        db_session.add(claim)
        await db_session.flush()
        assert claim.status == ClaimStatus.DRAFT

        async def violates(**changes: object) -> None:
            with pytest.raises(IntegrityError):
                async with db_session.begin_nested():
                    for key, value in changes.items():
                        setattr(claim, key, value)
                    await db_session.flush()
            await db_session.refresh(claim)

        await violates(status="approved")  # approved needs approved_at
        await violates(status="published")
        await violates(dose_unit="bucket")
        claim.status, claim.approved_at = ClaimStatus.APPROVED, datetime.now(UTC)
        await db_session.flush()
        assert claim.approved

        for bad in (
            {"category": "snacks"},
            {"gst_rate_bp": 12000},
        ):
            with pytest.raises(IntegrityError):
                async with db_session.begin_nested():
                    db_session.add(
                        Product(
                            tenant_id=tid,
                            **{
                                "name": f"Bad {bad}",
                                "brand": "X",
                                "category": "seed",
                                "gst_rate_bp": 0,
                                **bad,
                            },
                        )
                    )
                    await db_session.flush()
        with pytest.raises(IntegrityError):  # barcode unique per tenant
            async with db_session.begin_nested():
                db_session.add(
                    Sku(
                        tenant_id=tid,
                        product_id=product.id,
                        pack_size_value=Decimal("1"),
                        pack_size_unit="l",
                        barcode="8900000000001",
                        mrp_paise=1,
                    )
                )
                await db_session.flush()
