"""Fixtures for the M1 entity tests: a tiny graph (tenant, store, village, officer, crops,
one farmer with one farm) written through the app role under RLS, plus a second tenant."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from decimal import Decimal

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import PILOT_CROPS, Crop
from farmerapp.db.geo import point_wkt
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.farmers.models import Farm, Farmer
from farmerapp.tenants.models import Cluster, Store, Village
from tests.authz.conftest import bearer, world  # noqa: F401  (fixtures re-exported)

M1_TABLES = ("cluster", "store", "village", "crop", "farmer", "farm", "crop_plot", "consent_record")


@dataclass(frozen=True)
class Graph:
    tenant_id: uuid.UUID
    cluster: Cluster
    store: Store
    village: Village
    officer: User
    crops: dict[str, Crop]
    farmer: Farmer
    farm: Farm
    other_tenant_id: uuid.UUID
    other_village: Village


async def _tenant(session: AsyncSession, label: str) -> tuple[uuid.UUID, Village]:
    tid = uuid.uuid4()
    async with tenant_scope(session, tid):
        session.add(Tenant(id=tid, name=f"Graph {label}", slug=f"graph-{label}-{tid.hex[:6]}"))
        await session.flush()
        cluster = Cluster(tenant_id=tid, name="North")
        session.add(cluster)
        await session.flush()
        store = Store(
            tenant_id=tid,
            code="WGL",
            name="Warangal",
            cluster_id=cluster.id,
            district="Warangal",
            location=point_wkt(79.5941, 17.9689),
        )
        session.add(store)
        await session.flush()
        village = Village(
            tenant_id=tid,
            name="Hasanparthy",
            district="Warangal",
            mandal="Hasanparthy",
            store_id=store.id,
            location=point_wkt(79.55, 18.02),
        )
        session.add(village)
        await session.flush()
    return tid, village


@pytest.fixture
async def graph(db_session: AsyncSession) -> Graph:
    other_id, other_village = await _tenant(db_session, "b")
    tid, village = await _tenant(db_session, "a")
    await set_tenant(db_session, tid)
    store = await db_session.get_one(Store, village.store_id)
    cluster = await db_session.get_one(Cluster, store.cluster_id)
    officer = User(
        tenant_id=tid,
        phone="+919000000404",
        name="Officer A",
        role=UserRole.FIELD_OFFICER,
        store_id=store.id,
        cluster_id=cluster.id,
    )
    db_session.add(officer)
    crops = {
        code: Crop(tenant_id=tid, code=code, name=name, names=dict(names), duration_days=days)
        for code, name, names, days in PILOT_CROPS
    }
    db_session.add_all(crops.values())
    await db_session.flush()
    farmer = Farmer(
        tenant_id=tid,
        phone="+919000100001",
        phone_last4="0001",
        name="Mallesh Goud",
        village_id=village.id,
        registered_by=officer.id,
    )
    db_session.add(farmer)
    await db_session.flush()
    farm = Farm(tenant_id=tid, farmer_id=farmer.id, name="Farm 1", area_acres=Decimal("1.5"))
    db_session.add(farm)
    await db_session.flush()
    return Graph(
        tenant_id=tid,
        cluster=cluster,
        store=store,
        village=village,
        officer=officer,
        crops=crops,
        farmer=farmer,
        farm=farm,
        other_tenant_id=other_id,
        other_village=other_village,
    )
