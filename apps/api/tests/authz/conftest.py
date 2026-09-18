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
from dataclasses import dataclass

import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.jobs.seed import DEMO_TENANTS, SMALL, seed_demo
from farmerapp.visits.models import Visit

ROLES: tuple[str, ...] = tuple(r.value for r in UserRole)


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


async def _load_tenant(session: AsyncSession, slug: str) -> SeededTenant:
    demo = next(t for t in DEMO_TENANTS if t.slug == slug)
    async with tenant_scope(session, demo.id):  # RLS: rows are only visible in their tenant
        tenant = (await session.execute(select(Tenant).where(Tenant.slug == slug))).scalar_one()
        users = (
            (
                await session.execute(
                    select(User).where(User.tenant_id == tenant.id).order_by(User.phone)
                )
            )
            .scalars()
            .all()
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
    by_role: dict[UserRole, User] = {}
    for u in users:
        by_role.setdefault(UserRole(u.role), u)
    assert set(by_role) == set(UserRole), f"seed for {slug} must have one user per role"
    assert farmers, f"seed for {slug} must have farmers"
    assert farm is not None and plot is not None and crop is not None
    assert visit is not None, f"seed for {slug} must visit its first farmer"
    return SeededTenant(
        tenant=tenant,
        users=by_role,
        everyone=tuple(users),
        farmers=tuple(farmers),
        farm_id=farm.id,
        crop_plot_id=plot.id,
        crop_id=crop.id,
        visit_id=visit,
    )


@pytest.fixture
async def world(db_session: AsyncSession) -> World:
    """Both demo tenants (small profile); the session is left bound to tenant A."""
    await seed_demo(db_session, SMALL)
    slugs = [t.slug for t in DEMO_TENANTS]
    assert slugs == ["fcc", "gfl"]
    world = World(a=await _load_tenant(db_session, "fcc"), b=await _load_tenant(db_session, "gfl"))
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
