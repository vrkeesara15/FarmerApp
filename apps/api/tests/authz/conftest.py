"""Authz fixtures (SEC-006).

``world`` seeds both demo tenants through the real seed job (``fcc`` = tenant A, ``gfl`` =
tenant B) with the ``SMALL`` profile: one active user per role each (plus the extra field
officers, stores, villages and a few farmers with farms), and ``bearer`` mints access tokens
directly through the token service so the matrix does not pay for an OTP round trip per case.
``SeededTenant.user(role)`` is the *role user* (lowest phone number of that role); every
account of the tenant is in ``everyone``.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass, replace

import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import LabelClaim, Sku
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.jobs.seed import DEMO_TENANTS, SMALL, seed_demo
from farmerapp.orders.models import Order, OrderChannel
from farmerapp.platform_admin.provisioning import ensure_platform_admin
from farmerapp.visits.models import Visit

ROLES: tuple[str, ...] = tuple(r.value for r in UserRole)
#: The roles a customer tenant has. WC-014's ``platform_admin`` is not one of them: it only
#: exists in the platform tenant, and the ``world`` fixture injects that one account into both
#: tenants' role maps so the SEC-006 matrix can still drive every route as every role.
TENANT_ROLES: frozenset[UserRole] = frozenset(UserRole) - {UserRole.PLATFORM_ADMIN}


@dataclass(frozen=True)
class SeededTenant:
    tenant: Tenant
    users: dict[UserRole, User]  # the role user per role (first by phone)
    everyone: tuple[User, ...] = ()  # every account of the tenant (role users + officers)
    farmers: tuple[Farmer, ...] = ()  # seeded farmers, oldest registration first
    farm_id: uuid.UUID | None = None  # a farm of ``farmer`` (route fixtures)
    crop_plot_id: uuid.UUID | None = None  # a crop plot of that farm
    crop_id: uuid.UUID | None = None  # a crop of the tenant
    visit_id: uuid.UUID | None = None  # a visit by the role officer to ``farmer`` (M2 routes)
    store_id: uuid.UUID | None = None  # the store of the role store manager (M3 routes)
    sku_id: uuid.UUID | None = None  # a SKU with an approved label claim (M3 routes)
    order_id: uuid.UUID | None = None  # an order placed by the role officer (M3 routes)
    product_id: uuid.UUID | None = None  # the product of ``sku_id`` (WC-005 writes)
    sku_barcode: str | None = None  # the barcode of ``sku_id`` (POS lookup)
    claim_id: uuid.UUID | None = None  # an approved label claim of ``sku_id`` (WC-005)
    pest_id: uuid.UUID | None = None  # the problem of ``claim_id``

    def user(self, role: str | UserRole) -> User:
        return self.users[UserRole(role)]

    @property
    def owner(self) -> User:
        return self.users[UserRole.OWNER]

    @property
    def farmer(self) -> Farmer:
        return self.farmers[0]


@dataclass(frozen=True)
class World:
    a: SeededTenant  # Future Crop Care (fcc)
    b: SeededTenant  # Green Fields (gfl)
    #: WC-014: the one ``platform_admin``, in the platform tenant (neither a nor b).
    platform_admin: User | None = None


async def _load_tenant(session: AsyncSession, slug: str) -> SeededTenant:
    demo = next(t for t in DEMO_TENANTS if t.slug == slug)
    async with tenant_scope(session, demo.id):  # RLS: rows are only visible in their tenant
        tenant = (await session.execute(select(Tenant).where(Tenant.slug == slug))).scalar_one()
        users = sorted(  # SEC-026: phones are encrypted, so order in Python
            (await session.execute(select(User).where(User.tenant_id == tenant.id))).scalars(),
            key=lambda u: u.phone,
        )
        farmers = (
            (
                await session.execute(
                    select(Farmer)
                    .where(Farmer.tenant_id == tenant.id)
                    .order_by(Farmer.created_at, Farmer.id)
                )
            )
            .scalars()
            .all()
        )
        farm = (
            (
                await session.execute(
                    select(Farm)
                    .where(Farm.farmer_id == farmers[0].id)
                    .order_by(Farm.created_at, Farm.id)
                )
            )
            .scalars()
            .first()
        )
        plot = (
            (
                await session.execute(
                    select(CropPlot).where(CropPlot.farm_id == farm.id).order_by(CropPlot.id)
                )
            )
            .scalars()
            .first()
            if farm is not None
            else None
        )
        crop = (await session.execute(select(Crop).order_by(Crop.code))).scalars().first()
        visit = (
            (
                await session.execute(
                    select(Visit.id)
                    .where(Visit.farmer_id == farmers[0].id)
                    .order_by(Visit.checkin_at, Visit.id)
                )
            )
            .scalars()
            .first()
        )
        claim = await session.scalar(
            select(LabelClaim).order_by(LabelClaim.created_at, LabelClaim.id).limit(1)
        )
        sku = claim.sku_id if claim is not None else None
        sku_row = await session.get(Sku, sku) if sku is not None else None
        order = await session.scalar(
            select(Order.id)
            .where(Order.channel == OrderChannel.OFFICER.value)
            .order_by(Order.created_at, Order.id)
            .limit(1)
        )
    by_role: dict[UserRole, User] = {}
    for u in users:
        by_role.setdefault(UserRole(u.role), u)
    assert set(by_role) == TENANT_ROLES, f"seed for {slug} must have one user per tenant role"
    assert farmers, f"seed for {slug} must have farmers"
    assert farm is not None and plot is not None and crop is not None
    assert visit is not None, f"seed for {slug} must visit its first farmer"
    assert sku is not None and order is not None, f"seed for {slug} must have M3 data"
    return SeededTenant(
        tenant=tenant,
        users=by_role,
        everyone=tuple(users),
        farmers=tuple(farmers),
        farm_id=farm.id,
        crop_plot_id=plot.id,
        crop_id=crop.id,
        visit_id=visit,
        store_id=by_role[UserRole.STORE_MANAGER].store_id,
        sku_id=sku,
        order_id=order,
        product_id=sku_row.product_id if sku_row is not None else None,
        sku_barcode=sku_row.barcode if sku_row is not None else None,
        claim_id=claim.id if claim is not None else None,
        pest_id=claim.pest_or_disease_id if claim is not None else None,
    )


PLATFORM_ADMIN_PHONE = "+919999900001"


@pytest.fixture
async def world(db_session: AsyncSession) -> World:
    """Both demo tenants (small profile) plus the WC-014 platform tenant and its one
    ``platform_admin``; the session is left bound to tenant A."""
    await seed_demo(db_session, SMALL)
    slugs = [t.slug for t in DEMO_TENANTS]
    assert slugs == ["fcc", "gfl"]
    platform_admin = await ensure_platform_admin(db_session, phone=PLATFORM_ADMIN_PHONE)
    a, b = await _load_tenant(db_session, "fcc"), await _load_tenant(db_session, "gfl")
    # The platform admin is nobody's tenant user; it is added to the role maps only so the
    # matrix can call every route as it and prove it is refused everywhere but /v1/admin.
    a = replace(a, users={**a.users, UserRole.PLATFORM_ADMIN: platform_admin})
    b = replace(b, users={**b.users, UserRole.PLATFORM_ADMIN: platform_admin})
    world = World(a=a, b=b, platform_admin=platform_admin)
    await set_tenant(db_session, world.a.tenant.id)
    return world


Bearer = Callable[[User], dict[str, str]]


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    services: AuthServices = app.state.auth

    def _mint(user: User) -> dict[str, str]:
        token = services.tokens.issue_access_token(user, services.clock.now())
        return {"Authorization": f"Bearer {token}"}

    return _mint


@pytest.fixture
def step_up(app: FastAPI) -> Bearer:
    """SEC-028: ``X-Step-Up-Token`` header for ``user`` (as if they had just re-entered an OTP)."""
    from farmerapp.auth.stepup import STEP_UP_HEADER, issue_step_up_token

    services: AuthServices = app.state.auth

    def _mint(user: User) -> dict[str, str]:
        return {STEP_UP_HEADER: issue_step_up_token(services.settings, user, services.clock.now())}

    return _mint
