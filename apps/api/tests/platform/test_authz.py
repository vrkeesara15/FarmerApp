"""WC-014 authorisation: only a ``platform_admin`` in the platform tenant reaches /v1/admin.

The SEC-006 matrix already drives every platform route as all eleven roles and asserts 403 for
the ten tenant ones. This file proves the two things the matrix cannot: that the *tenant*
half of the guard is real (a user with the role string but in a customer tenant is still
refused), and that a tenant admin — the highest role inside a tenant — sees nothing of the
platform, not even that other tenants exist.
"""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID
from tests.platform.conftest import TENANT_BODY

PLATFORM_ROUTES: tuple[tuple[str, str], ...] = (
    ("GET", "/v1/admin/plans"),
    ("GET", "/v1/admin/tenants"),
    ("POST", "/v1/admin/tenants"),
)


async def _impostor(session: AsyncSession, tenant_id: uuid.UUID) -> User:
    """A user of a *customer* tenant carrying the ``platform_admin`` role string."""
    async with tenant_scope(session, tenant_id):
        user = User(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            phone="+919000199999",
            name="Would-be platform admin",
            role=UserRole.PLATFORM_ADMIN,
            language="en",
            status=UserStatus.ACTIVE,
        )
        session.add(user)
        await session.flush()
    return user


@pytest.mark.parametrize(("method", "path"), PLATFORM_ROUTES)
async def test_platform_admin_role_in_a_customer_tenant_is_refused(
    client: AsyncClient,
    db_session: AsyncSession,
    bearer: Any,
    step_up: Any,
    method: str,
    path: str,
) -> None:
    """The role alone is not enough: the caller must be in the platform tenant."""
    from farmerapp.jobs.seed import SMALL, demo_tenant_id, seed_demo

    await seed_demo(db_session, SMALL)
    tenant_id = demo_tenant_id("fcc")
    impostor = await _impostor(db_session, tenant_id)
    await set_tenant(db_session, tenant_id)
    headers = {**bearer(impostor), **step_up(impostor)}
    resp = await client.request(method, path, json=TENANT_BODY, headers=headers)
    assert resp.status_code == 403, resp.text
    assert resp.json()["code"] == "forbidden"


@pytest.mark.parametrize(("method", "path"), PLATFORM_ROUTES)
async def test_tenant_admin_never_reaches_the_platform(
    client: AsyncClient, db_session: AsyncSession, bearer: Any, step_up: Any, method: str, path: str
) -> None:
    from farmerapp.jobs.seed import SMALL, demo_tenant_id, seed_demo

    await seed_demo(db_session, SMALL)
    tenant_id = demo_tenant_id("fcc")
    async with tenant_scope(db_session, tenant_id):
        from sqlalchemy import select

        admin = (
            (
                await db_session.execute(
                    select(User).where(
                        User.tenant_id == tenant_id, User.role == UserRole.TENANT_ADMIN
                    )
                )
            )
            .scalars()
            .first()
        )
    await set_tenant(db_session, tenant_id)
    assert admin is not None
    headers = {**bearer(admin), **step_up(admin)}
    resp = await client.request(method, path, json=TENANT_BODY, headers=headers)
    assert resp.status_code == 403, resp.text


async def test_registry_is_invisible_from_inside_a_tenant(
    db_session: AsyncSession, client: AsyncClient, as_platform: dict[str, str]
) -> None:
    """RLS, not a role check: the registry rows belong to the platform tenant, so a session
    bound to a customer tenant simply does not see them."""
    from sqlalchemy import func, select

    from farmerapp.platform_admin.models import PlatformTenant

    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    async with tenant_scope(db_session, tenant_id):
        visible = await db_session.scalar(select(func.count()).select_from(PlatformTenant))
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    assert visible == 0
    # ... while the platform admin sees it.
    listed = await client.get("/v1/admin/tenants", headers=as_platform)
    assert [t["slug"] for t in listed.json()["items"]] == ["nava"]


async def test_platform_admin_reads_no_tenant_data(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    """SPEC 2.6 has no row for the platform role: it administers, it does not read."""
    from farmerapp.jobs.seed import SMALL, seed_demo

    await seed_demo(db_session, SMALL)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    auth = {"Authorization": as_platform["Authorization"]}
    for path in ("/v1/farmers", "/v1/visits", "/v1/users", "/v1/analytics/owner-home"):
        resp = await client.get(path, headers=auth)
        assert resp.status_code == 403, f"{path}: {resp.status_code} {resp.text}"
