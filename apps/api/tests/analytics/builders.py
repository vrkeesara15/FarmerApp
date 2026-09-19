"""Hand-built analytics fixtures: a small tenant whose every figure is known in advance.

``Mini.create`` makes tenant ``an-<random>`` with two clusters (North: stores N1, N2;
South: store S1), one village per store, users for every role (cluster head of North, store
manager of N1, officers O1 at N1 and O2 at S1), two crops, an own-brand and a multi-brand
SKU with a batch at every store (cost 700 / 500 paise). The helpers add visits, sales,
khata rows, duty sessions with location points, refresh tokens and day closes with explicit
timestamps so tests can assert exact KPI values.
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import IST
from farmerapp.auth.models import RefreshToken, User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import Product, Sku
from farmerapp.db.geo import offset, point_wkt, polygon_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.khata.models import KhataEntry
from farmerapp.location import partitions
from farmerapp.location.models import DutySession, LocationPoint
from farmerapp.orders.models import Order, OrderLine
from farmerapp.payments.models import DayClose, Payment
from farmerapp.stock.models import StockBatch, StockMovement
from farmerapp.tenants.models import Cluster, Store, Village
from farmerapp.visits.models import Visit, VisitPhoto


def ist(day: date, hour: int, minute: int = 0) -> datetime:
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=IST).astimezone(UTC)


@dataclass
class Mini:
    session: AsyncSession
    tenant: Tenant
    clusters: dict[str, Cluster] = field(default_factory=dict)
    stores: dict[str, Store] = field(default_factory=dict)
    villages: dict[str, Village] = field(default_factory=dict)
    users: dict[str, User] = field(default_factory=dict)
    farmers: dict[str, Farmer] = field(default_factory=dict)
    crops: dict[str, Crop] = field(default_factory=dict)
    skus: dict[str, Sku] = field(default_factory=dict)
    batches: dict[tuple[str, str], StockBatch] = field(default_factory=dict)
    _n: int = 0

    @property
    def tid(self) -> uuid.UUID:
        return self.tenant.id

    def user(self, key: str) -> User:
        return self.users[key]

    def _phone(self) -> str:
        self._n += 1
        return f"+9198{self.tenant.id.int % 10**4:04d}{self._n:04d}"

    async def add(self, *rows: Any) -> None:
        self.session.add_all(rows)
        await self.session.flush()

    # ------------------------------------------------------------------ creation
    @classmethod
    async def create(cls, session: AsyncSession, settings: dict[str, Any] | None = None) -> Mini:
        tid = uuid.uuid4()
        await set_tenant(session, tid)
        tenant = Tenant(
            id=tid, name="Analytics Mini", slug=f"an-{tid.hex[:8]}", settings=settings or {}
        )
        session.add(tenant)
        await session.flush()
        m = cls(session=session, tenant=tenant)
        for key, name in (("north", "North"), ("south", "South")):
            m.clusters[key] = Cluster(tenant_id=tid, name=name)
        await m.add(*m.clusters.values())
        base = {
            "N1": (17.97, 79.59, "north"),
            "N2": (18.44, 79.13, "north"),
            "S1": (17.06, 79.27, "south"),
        }
        for code, (lat, lon, cluster) in base.items():
            m.stores[code] = Store(
                tenant_id=tid,
                code=code,
                name=f"Store {code}",
                district=f"District {code}",
                cluster_id=m.clusters[cluster].id,
                location=point_wkt(lon, lat),
            )
        await m.add(*m.stores.values())
        for code, store in m.stores.items():
            lat, lon, _ = base[code]
            m.villages[code] = Village(
                tenant_id=tid,
                name=f"Village {code}",
                district=f"District {code}",
                mandal=f"Mandal {code}",
                store_id=store.id,
                location=point_wkt(lon + 0.05, lat + 0.05),
            )
        await m.add(*m.villages.values())
        roles: dict[str, tuple[UserRole, str | None, str | None]] = {
            "owner": (UserRole.OWNER, None, None),
            "director": (UserRole.DIRECTOR, None, None),
            "auditor": (UserRole.AUDITOR, None, None),
            "accountant": (UserRole.ACCOUNTANT, None, None),
            "tenant_admin": (UserRole.TENANT_ADMIN, None, None),
            "agronomist": (UserRole.AGRONOMIST, None, None),
            "farmer_user": (UserRole.FARMER, None, None),
            "cluster_head": (UserRole.CLUSTER_HEAD, None, "north"),
            "store_manager": (UserRole.STORE_MANAGER, "N1", "north"),
            "o1": (UserRole.FIELD_OFFICER, "N1", "north"),
            "o2": (UserRole.FIELD_OFFICER, "S1", "south"),
        }
        for key, (role, store_code, cluster_key) in roles.items():
            m.users[key] = User(
                tenant_id=tid,
                phone=m._phone(),
                name=f"User {key}",
                role=role,
                store_id=m.stores[store_code].id if store_code else None,
                cluster_id=m.clusters[cluster_key].id if cluster_key else None,
            )
        await m.add(*m.users.values())
        for code in ("paddy", "cotton"):
            m.crops[code] = Crop(tenant_id=tid, code=code, name=code.title(), duration_days=120)
        await m.add(*m.crops.values())
        own = Product(
            tenant_id=tid, name="Own Guard", brand="FCC", own_brand=True, category="pesticide",
            gst_rate_bp=1800,
        )  # fmt: skip
        multi = Product(
            tenant_id=tid, name="Other Shield", brand="Other", own_brand=False,
            category="fungicide", gst_rate_bp=1800,
        )  # fmt: skip
        await m.add(own, multi)
        m.skus["own"] = Sku(
            tenant_id=tid,
            product_id=own.id,
            pack_size_value=Decimal(1),
            pack_size_unit="l",
            mrp_paise=1000,
        )
        m.skus["multi"] = Sku(
            tenant_id=tid,
            product_id=multi.id,
            pack_size_value=Decimal(500),
            pack_size_unit="ml",
            mrp_paise=800,
        )
        await m.add(*m.skus.values())
        for code, store in m.stores.items():
            for key, cost in (("own", 700), ("multi", 500)):
                m.batches[(code, key)] = StockBatch(
                    tenant_id=tid,
                    store_id=store.id,
                    sku_id=m.skus[key].id,
                    batch_no=f"B-{code}-{key}",
                    qty=Decimal(10),
                    cost_paise=cost,
                )
        await m.add(*m.batches.values())
        # Farmers: F1, F2 at N1 (by O1; F1 grows paddy), F3 at S1 (by O2, cotton).
        for key, home, officer, crop in (
            ("f1", "N1", "o1", "paddy"),
            ("f2", "N1", "o1", None),
            ("f3", "S1", "o2", "cotton"),
        ):
            await m.farmer(key, home, officer, crop)
        m.farmers["f1"].user_id = m.users["farmer_user"].id
        await session.flush()
        return m

    async def farmer(
        self,
        key: str,
        store: str,
        officer: str,
        crop: str | None,
        created_at: datetime | None = None,
        name: str | None = None,
    ) -> Farmer:
        phone = self._phone()
        at = created_at or datetime(2026, 1, 5, 6, tzinfo=UTC)
        farmer = Farmer(
            tenant_id=self.tid,
            phone=phone,
            phone_last4=phone[-4:],
            name=name or f"Farmer {key.upper()}",
            village_id=self.villages[store].id,
            registered_by=self.users[officer].id,
            created_at=at,
            updated_at=at,
        )
        await self.add(farmer)
        self.farmers[key] = farmer
        lon, lat = offset(79.5, 17.9, 0, 0)
        farm = Farm(
            tenant_id=self.tid,
            farmer_id=farmer.id,
            name="Home farm",
            area_acres=Decimal("2.50"),
            boundary=polygon_wkt([(lon, lat), (lon + 0.001, lat), (lon + 0.001, lat + 0.001)]),
        )
        await self.add(farm)
        if crop is not None:
            await self.add(
                CropPlot(
                    tenant_id=self.tid,
                    farm_id=farm.id,
                    crop_id=self.crops[crop].id,
                    season="kharif",
                    sowing_date=date(2026, 6, 20),
                    stage="vegetative",
                )
            )
        return farmer

    # ------------------------------------------------------------------ activity
    async def visit(
        self,
        officer: str,
        farmer: str,
        checkin: datetime,
        minutes: int | None = 20,
        score: int | None = 80,
        confirmed: bool = False,
        components: dict[str, int] | None = None,
        lat: float = 17.9,
        lon: float = 79.5,
    ) -> Visit:
        status = "open"
        if score is not None:
            status = "verified" if score >= 70 else "partial" if score >= 40 else "unverified"
        v = Visit(
            tenant_id=self.tid,
            officer_id=self.users[officer].id,
            farmer_id=self.farmers[farmer].id,
            purpose="advisory",
            checkin_at=checkin,
            checkout_at=checkin + timedelta(minutes=minutes) if minutes is not None else None,
            checkin_point=point_wkt(lon, lat),
            geofence_result="inside",
            score=score,
            status=status,
            score_components=components,
            confirmed_at=checkin + timedelta(minutes=5) if confirmed else None,
            confirmation_channel="sms_otp" if confirmed else "none",
        )
        await self.add(v)
        return v

    async def photo(self, visit: Visit) -> None:
        await self.add(
            VisitPhoto(
                tenant_id=self.tid,
                visit_id=visit.id,
                blob_uri=f"gs://local/{self.tid}/visit_photo/{uuid.uuid4().hex}",
            )
        )

    async def sale(
        self,
        store: str,
        farmer: str | None,
        at: datetime,
        lines: list[tuple[str, int, int]],
        *,
        discount: int = 0,
        status: str = "delivered",
        placed_by: str | None = None,
        batch: bool = True,
    ) -> Order:
        """``lines``: ``(sku key, qty, unit price paise)``."""
        subtotal = sum(q * p for _, q, p in lines)
        order = Order(
            tenant_id=self.tid,
            farmer_id=self.farmers[farmer].id if farmer else None,
            store_id=self.stores[store].id,
            channel="pos",
            status=status,
            subtotal_paise=subtotal,
            discount_paise=discount,
            tax_paise=0,
            total_paise=subtotal - discount,
            placed_by=self.users[placed_by].id if placed_by else None,
            placed_at=at,
        )
        await self.add(order)
        await self.add(
            *[
                OrderLine(
                    tenant_id=self.tid,
                    order_id=order.id,
                    sku_id=self.skus[sku].id,
                    batch_id=self.batches[(store, sku)].id if batch else None,
                    qty=Decimal(q),
                    unit_price_paise=p,
                    gst_rate_bp=0,
                    line_total_paise=q * p,
                )
                for sku, q, p in lines
            ]
        )
        return order

    async def khata(
        self,
        farmer: str,
        store: str,
        kind: str,
        amount: int,
        at: datetime,
        due: date | None = None,
    ) -> KhataEntry:
        e = KhataEntry(
            tenant_id=self.tid,
            farmer_id=self.farmers[farmer].id,
            store_id=self.stores[store].id,
            type=kind,
            amount_paise=amount,
            due_date=due,
            ref_type="adjustment" if kind == "debit" else "payment",
            created_at=at,
        )
        await self.add(e)
        return e

    async def payment(
        self, store: str, farmer: str, officer: str, amount: int, at: datetime
    ) -> None:
        await self.add(
            Payment(
                tenant_id=self.tid,
                farmer_id=self.farmers[farmer].id,
                store_id=self.stores[store].id,
                mode="cash",
                amount_paise=amount,
                status="reconciled",
                collected_by=self.users[officer].id,
                paid_at=at,
            )
        )

    async def duty(
        self,
        officer: str,
        start: datetime,
        end: datetime | None,
        km: str = "10.00",
        points: list[tuple[datetime, float, float]] | None = None,
    ) -> DutySession:
        ds = DutySession(
            tenant_id=self.tid,
            officer_id=self.users[officer].id,
            start_at=start,
            end_at=end,
            end_reason="manual" if end else None,
            km=Decimal(km),
            policy_version="2026-09-v1",
        )
        await self.add(ds)
        if points:
            days = sorted({p[0].date() for p in points})
            await partitions.ensure_partitions(
                self.session,
                from_day=days[0] - timedelta(days=1),
                to_day=days[-1] + timedelta(days=1),
            )
            await self.add(
                *[
                    LocationPoint(
                        tenant_id=self.tid,
                        officer_id=self.users[officer].id,
                        duty_session_id=ds.id,
                        ts=ts,
                        point=point_wkt(lon, lat),
                        accuracy_m=10.0,
                    )
                    for ts, lat, lon in points
                ]
            )
        return ds

    async def session_token(self, user: str, at: datetime) -> None:
        await self.add(
            RefreshToken(
                tenant_id=self.tid,
                user_id=self.users[user].id,
                family_id=uuid.uuid4(),
                token_hash=hashlib.sha256(uuid.uuid4().bytes).hexdigest(),
                expires_at=at + timedelta(days=30),
                created_at=at,
            )
        )

    async def day_close(self, store: str, day: date, expected: int, counted: int) -> None:
        await self.add(
            DayClose(
                tenant_id=self.tid,
                store_id=self.stores[store].id,
                business_date=day,
                cash_expected_paise=expected,
                cash_counted_paise=counted,
                variance_paise=counted - expected,
                closed_by=self.users["store_manager"].id,
                closed_at=ist(day, 20),
            )
        )

    async def write_off(self, store: str, sku: str, qty: int, at: datetime) -> None:
        await self.add(
            StockMovement(
                tenant_id=self.tid,
                store_id=self.stores[store].id,
                sku_id=self.skus[sku].id,
                batch_id=self.batches[(store, sku)].id,
                kind="damage",
                qty=Decimal(-qty),
                reason="damage",
                created_at=at,
            )
        )


__all__ = ["Mini", "ist"]
