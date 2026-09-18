"""Authz fixtures (SEC-006).

``world`` seeds both demo tenants through the real seed job (``fcc`` = tenant A, ``gfl`` =
tenant B) with one active user per role each, and ``bearer`` mints access tokens directly
through the token service so the matrix does not pay for an OTP round trip per case.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User, UserRole
from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.jobs.seed import DEMO_TENANTS, seed_demo

ROLES: tuple[str, ...] = tuple(r.value for r in UserRole)


@dataclass(frozen=True)
class SeededTenant:
    tenant: Tenant
    users: dict[UserRole, User]

    def user(self, role: str | UserRole) -> User:
        return self.users[UserRole(role)]

    @property
    def owner(self) -> User:
        return self.users[UserRole.OWNER]


@dataclass(frozen=True)
class World:
    a: SeededTenant  # Future Crop Care (fcc)
    b: SeededTenant  # Green Fields (gfl)


async def _load_tenant(session: AsyncSession, slug: str) -> SeededTenant:
    demo = next(t for t in DEMO_TENANTS if t.slug == slug)
    async with tenant_scope(session, demo.id):  # RLS: rows are only visible in their tenant
        tenant = (await session.execute(select(Tenant).where(Tenant.slug == slug))).scalar_one()
        users = (
            (await session.execute(select(User).where(User.tenant_id == tenant.id))).scalars().all()
        )
    by_role = {UserRole(u.role): u for u in users}
    assert set(by_role) == set(UserRole), f"seed for {slug} must have one user per role"
    return SeededTenant(tenant=tenant, users=by_role)


@pytest.fixture
async def world(db_session: AsyncSession) -> World:
    """Both demo tenants; the session is left bound to tenant A (tests mutate A's rows)."""
    await seed_demo(db_session)
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
