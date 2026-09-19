"""Synthetic 50-store tenant for the WC-001 performance test ("loads in under 3 s for 50
stores").

Scale per store (``Scale``): 1 field officer, 2 villages, 40 farmers, 10 stocked SKUs,
``orders_per_day`` fulfilled orders with 1-3 lines over ``days`` days (10 % on credit: a khata
debit, half of them part-repaid), one duty session and ``visits_per_day`` scored visits per
officer-day, a refresh token for a tenth of the farmers. With the defaults that is 50
stores, 2,000 farmers, ~36,000 orders / ~72,000 lines, 15,000 visits, 3,000 duty sessions
and ~5,400 khata rows -- a full season of a 50-store chain's last two months.

Rows go in with Core ``INSERT ... executemany`` (no ORM units of work, no audit rows) under
the tenant's RLS binding, inside the test transaction (rolled back afterwards).
"""

from __future__ import annotations

import hashlib
import random
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

from sqlalchemy import insert
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import IST
from farmerapp.auth.models import RefreshToken, User, UserRole
from farmerapp.catalog.models import Product, Sku
from farmerapp.db.geo import offset, point_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant
from farmerapp.farmers.models import Farmer
from farmerapp.khata.models import KhataEntry
from farmerapp.location.models import DutySession
from farmerapp.orders.models import Order, OrderLine
from farmerapp.stock.models import StockBatch
from farmerapp.tenants.models import Cluster, Store, Village
from farmerapp.visits.models import Visit

CHUNK = 5_000


@dataclass(frozen=True)
class Scale:
    stores: int = 50
    stores_per_cluster: int = 5
    farmers_per_store: int = 40
    skus: int = 10
    days: int = 60
    orders_per_day: int = 12
    visits_per_day: int = 5


DEFAULT_SCALE = Scale()


@dataclass(frozen=True)
class Synthetic:
    tenant_id: uuid.UUID
    owner: User
    end: date
    counts: dict[str, int]


def _at(day: date, hour: int, minute: int) -> datetime:
    return datetime.combine(day, time(hour, minute), tzinfo=IST).astimezone(UTC)


async def _insert(session: AsyncSession, model: Any, rows: list[dict[str, Any]]) -> None:
    for i in range(0, len(rows), CHUNK):
        await session.execute(insert(model.__table__), rows[i : i + CHUNK])


async def build_synthetic(
    session: AsyncSession, end: date, scale: Scale = DEFAULT_SCALE, seed: int = 50
) -> Synthetic:
    rng = random.Random(seed)  # nosec B311  (test data)
    tid = uuid.uuid4()
    await set_tenant(session, tid)
    await _insert(
        session,
        Tenant,
        [{"id": tid, "tenant_id": tid, "name": "Fifty", "slug": f"p-{tid.hex[:8]}"}],
    )
    counts: dict[str, int] = {}

    def row(**values: Any) -> dict[str, Any]:
        return {"id": uuid.uuid4(), "tenant_id": tid, **values}

    clusters = [row(name=f"Cluster {c}") for c in range(scale.stores // scale.stores_per_cluster)]
    stores, villages, officers = [], [], []
    for s in range(scale.stores):
        lon, lat = offset(78.0, 16.5, (s % 10) * 30_000, (s // 10) * 30_000)
        stores.append(
            row(
                code=f"P{s:02d}",
                name=f"Store {s:02d}",
                district=f"District {s // 5}",
                cluster_id=clusters[s // scale.stores_per_cluster]["id"],
                location=point_wkt(lon, lat),
            )
        )
        for v in range(2):
            villages.append(
                row(
                    name=f"Village {s}-{v}",
                    district=f"District {s // 5}",
                    mandal=f"Mandal {s}",
                    store_id=stores[-1]["id"],
                    location=point_wkt(lon + 0.05 * (v + 1), lat),
                )
            )
    owner = User(
        id=uuid.uuid4(), tenant_id=tid, phone="+919999000000", name="Owner", role=UserRole.OWNER
    )
    users = [
        {"id": owner.id, "tenant_id": tid, "phone": owner.phone, "name": "Owner", "role": "owner"}
    ]
    for s, store in enumerate(stores):
        officers.append(
            row(
                phone=f"+91999901{s:04d}",
                name=f"Officer {s:02d}",
                role=UserRole.FIELD_OFFICER.value,
                store_id=store["id"],
                cluster_id=store["cluster_id"],
            )
        )
    await _insert(session, Cluster, clusters)
    await _insert(session, Store, stores)
    await _insert(session, Village, villages)
    await _insert(session, User, users + officers)

    farmers: list[dict[str, Any]] = []
    farmer_users: list[dict[str, Any]] = []
    by_store: dict[int, list[dict[str, Any]]] = {}
    for s in range(scale.stores):
        for f in range(scale.farmers_per_store):
            phone = f"+9198880{s:02d}{f:03d}"
            user_id = None
            if f % 10 == 0:
                user_id = uuid.uuid4()
                farmer_users.append(
                    {"id": user_id, "tenant_id": tid, "phone": phone, "name": "F", "role": "farmer"}
                )
            farmers.append(
                row(
                    phone=phone,
                    phone_last4=phone[-4:],
                    name=f"Farmer {s}-{f}",
                    village_id=villages[2 * s + f % 2]["id"],
                    registered_by=officers[s]["id"],
                    user_id=user_id,
                )
            )
            by_store.setdefault(s, []).append(farmers[-1])
    await _insert(session, User, farmer_users)
    await _insert(session, Farmer, farmers)

    products = [
        row(
            name=f"Product {p}",
            brand="Own" if p % 2 == 0 else f"Brand {p}",
            own_brand=p % 2 == 0,
            category=("pesticide", "fungicide", "fertiliser", "seed", "herbicide")[p % 5],
            gst_rate_bp=1800,
        )
        for p in range(scale.skus)
    ]
    skus = [
        row(product_id=p["id"], pack_size_value=1, pack_size_unit="l", mrp_paise=50_000 + 5_000 * i)
        for i, p in enumerate(products)
    ]
    await _insert(session, Product, products)
    await _insert(session, Sku, skus)
    batches = {
        (s, k): row(
            store_id=store["id"],
            sku_id=sku["id"],
            batch_no=f"B{s}-{k}",
            qty=rng.randint(0, 200),
            cost_paise=sku["mrp_paise"] * 70 // 100,
        )
        for s, store in enumerate(stores)
        for k, sku in enumerate(skus)
    }
    await _insert(session, StockBatch, list(batches.values()))

    orders, lines, khata, visits, duty, tokens = [], [], [], [], [], []
    first = end - timedelta(days=scale.days - 1)
    for d in range(scale.days):
        day = first + timedelta(days=d)
        for s, store in enumerate(stores):
            officer = officers[s]
            start = _at(day, 9, rng.randint(0, 20))
            duty.append(
                row(
                    officer_id=officer["id"],
                    start_at=start,
                    end_at=start + timedelta(hours=9),
                    end_reason="manual",
                    km=round(rng.uniform(20, 60), 2),
                    policy_version="2026-09-v1",
                )
            )
            for v in range(scale.visits_per_day):
                farmer = rng.choice(by_store[s])
                checkin = start + timedelta(minutes=45 + 90 * v)
                score = rng.choice((90, 80, 75, 60, 30))
                visits.append(
                    row(
                        officer_id=officer["id"],
                        farmer_id=farmer["id"],
                        purpose="advisory",
                        checkin_at=checkin,
                        checkout_at=checkin + timedelta(minutes=rng.randint(10, 40)),
                        checkin_point=store["location"],
                        geofence_result="inside",
                        score=score,
                        status="verified"
                        if score >= 70
                        else "partial"
                        if score >= 40
                        else "unverified",
                        confirmed_at=checkin + timedelta(minutes=5) if score >= 75 else None,
                        confirmation_channel="sms_otp" if score >= 75 else "none",
                    )
                )
            for _ in range(scale.orders_per_day):
                buyer = rng.choice(by_store[s]) if rng.random() < 0.7 else None
                at = _at(day, rng.randint(9, 18), rng.randint(0, 59))
                order_id = uuid.uuid4()
                subtotal = 0
                for k in rng.sample(range(scale.skus), rng.randint(1, 3)):
                    qty = rng.randint(1, 4)
                    price = skus[k]["mrp_paise"]
                    subtotal += qty * price
                    lines.append(
                        row(
                            order_id=order_id,
                            sku_id=skus[k]["id"],
                            batch_id=batches[(s, k)]["id"],
                            qty=qty,
                            unit_price_paise=price,
                            gst_rate_bp=1800,
                            line_total_paise=qty * price,
                        )
                    )
                discount = subtotal // 20 if rng.random() < 0.2 else 0
                orders.append(
                    {
                        "id": order_id,
                        "tenant_id": tid,
                        "farmer_id": buyer["id"] if buyer else None,
                        "store_id": store["id"],
                        "channel": "pos",
                        "status": "handed_over",
                        "fulfilment": "pickup",
                        "subtotal_paise": subtotal,
                        "discount_paise": discount,
                        "tax_paise": 0,
                        "total_paise": subtotal - discount,
                        "placed_by": officer["id"] if rng.random() < 0.3 else None,
                        "placed_at": at,
                        "created_at": at,
                    }
                )
                if buyer is not None and rng.random() < 0.1:
                    khata.append(
                        {
                            "id": uuid.uuid4(),
                            "tenant_id": tid,
                            "farmer_id": buyer["id"],
                            "store_id": store["id"],
                            "type": "debit",
                            "amount_paise": subtotal - discount,
                            "due_date": day + timedelta(days=rng.choice((15, 30, 60, 90))),
                            "ref_type": "order",
                            "ref_id": order_id,
                            "created_at": at,
                        }
                    )
                    if rng.random() < 0.5:
                        khata.append(
                            {
                                "id": uuid.uuid4(),
                                "tenant_id": tid,
                                "farmer_id": buyer["id"],
                                "store_id": store["id"],
                                "type": "credit",
                                "amount_paise": (subtotal - discount) // 2,
                                "due_date": None,
                                "ref_type": "payment",
                                "ref_id": None,
                                "created_at": at + timedelta(days=rng.randint(1, 20)),
                            }
                        )
    for fu in farmer_users:
        tokens.append(
            {
                "id": uuid.uuid4(),
                "tenant_id": tid,
                "user_id": fu["id"],
                "family_id": uuid.uuid4(),
                "token_hash": hashlib.sha256(uuid.uuid4().bytes).hexdigest(),
                "expires_at": _at(end, 12, 0) + timedelta(days=30),
                "created_at": _at(end - timedelta(days=rng.randint(0, 50)), 8, 0),
            }
        )
    await _insert(session, DutySession, duty)
    await _insert(session, Visit, visits)
    await _insert(session, Order, orders)
    await _insert(session, OrderLine, lines)
    await _insert(session, KhataEntry, khata)
    await _insert(session, RefreshToken, tokens)
    counts.update(
        stores=len(stores),
        officers=len(officers),
        farmers=len(farmers),
        orders=len(orders),
        order_lines=len(lines),
        visits=len(visits),
        duty_sessions=len(duty),
        khata_entries=len(khata),
    )
    return Synthetic(tenant_id=tid, owner=owner, end=end, counts=counts)


__all__ = ["Scale", "Synthetic", "build_synthetic"]
