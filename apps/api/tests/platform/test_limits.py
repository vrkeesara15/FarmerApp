"""WC-014 plan limits: every creation path checks, and says clearly what it checked."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID
from farmerapp.platform_admin.plans import Metric, PlanLimits, merge_limits, plan_by_name
from farmerapp.platform_admin.state import invalidate
from farmerapp.platform_admin.usage import check, current, record
from tests.platform.conftest import TENANT_BODY


async def _tenant_admin(session: AsyncSession, tenant_id: uuid.UUID) -> User:
    async with tenant_scope(session, tenant_id):
        user = (
            (await session.execute(select(User).where(User.tenant_id == tenant_id))).scalars().one()
        )
    return user


async def _set_limits(session: AsyncSession, tenant_id: uuid.UUID, **limits: int | None) -> None:
    async with tenant_scope(session, tenant_id):
        tenant = await session.get(Tenant, tenant_id)
        assert tenant is not None
        tenant.plan_limits = {**dict(tenant.plan_limits or {}), **limits}
        await session.flush()
    await set_tenant(session, PLATFORM_TENANT_ID)
    invalidate(tenant_id)


async def test_farmer_limit_is_enforced_with_a_useful_problem(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str], bearer: Any
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    await _set_limits(db_session, tenant_id, farmers=1)
    admin = await _tenant_admin(db_session, tenant_id)
    await set_tenant(db_session, tenant_id)

    # A provisioned tenant has a placeholder store but no villages yet; a farmer needs one.
    from farmerapp.tenants.models import Store, Village

    async with tenant_scope(db_session, tenant_id):
        store_id = await db_session.scalar(select(Store.id).where(Store.tenant_id == tenant_id))
        village = Village(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            name="Kothapally",
            district="Hyderabad",
            mandal="Hyderabad",
            state="Telangana",
            store_id=store_id,
            location="SRID=4326;POINT(78.4867 17.3850)",
        )
        db_session.add(village)
        await db_session.flush()
        village_id = village.id
    await set_tenant(db_session, tenant_id)

    headers = bearer(admin)
    body = {
        "phone": "+919000177101",
        "name": "First Farmer",
        "village_id": str(village_id),
    }
    first = await client.post("/v1/farmers", json=body, headers=headers)
    assert first.status_code == 201, first.text

    second = await client.post(
        "/v1/farmers", json={**body, "phone": "+919000177102"}, headers=headers
    )
    assert second.status_code == 409, second.text
    problem = second.json()
    assert problem["code"] == "plan_limit_exceeded"
    assert problem["metric"] == "farmers"
    assert problem["limit"] == 1
    assert problem["current"] == 1
    assert problem["plan"] == "pilot"


async def test_officer_limit_is_enforced_on_user_create(
    client: AsyncClient,
    db_session: AsyncSession,
    as_platform: dict[str, str],
    bearer: Any,
    step_up: Any,
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    await _set_limits(db_session, tenant_id, officers=0)
    admin = await _tenant_admin(db_session, tenant_id)
    await set_tenant(db_session, tenant_id)

    headers = {**bearer(admin), **step_up(admin)}
    body = {"phone": "+919000177201", "name": "Ravi", "role": "field_officer"}
    resp = await client.post("/v1/users", json=body, headers=headers)
    assert resp.status_code == 409, resp.text
    assert resp.json()["metric"] == "officers"

    # A non-officer staff role is not capped.
    ok = await client.post(
        "/v1/users",
        json={"phone": "+919000177202", "name": "Meena", "role": "auditor"},
        headers=headers,
    )
    assert ok.status_code == 201, ok.text


async def test_photo_limit_is_checked_before_the_bytes_are_spent(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str], bearer: Any
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    await _set_limits(db_session, tenant_id, photos_per_month=0)
    admin = await _tenant_admin(db_session, tenant_id)
    await set_tenant(db_session, tenant_id)
    resp = await client.post(
        "/v1/uploads",
        json={
            "sha256": "a" * 64,
            "size_bytes": 1024,
            "content_type": "image/jpeg",
            "purpose": "farm_photo",
            "chunk_size": 262144,
        },
        headers=bearer(admin),
    )
    assert resp.status_code == 409, resp.text
    assert resp.json()["metric"] == "photos"


async def test_unlimited_metric_never_raises(db_session: AsyncSession) -> None:
    limits = PlanLimits()  # every field None
    tenant_id = uuid.uuid4()
    assert await check(db_session, tenant_id, Metric.FARMERS, limits, plan="unlimited") == -1


async def test_plan_limits_merge_over_the_catalogue() -> None:
    base = plan_by_name("pilot").limits
    merged = merge_limits(base, {"farmers": 80_000, "not_a_limit": 1})
    assert merged.farmers == 80_000
    assert merged.officers == base.officers  # untouched
    assert merged.stores == base.stores


@pytest.mark.parametrize("delta", [1, 5])
async def test_counters_move_by_one_statement(
    db_session: AsyncSession, as_platform: dict[str, str], client: AsyncClient, delta: int
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    async with tenant_scope(db_session, tenant_id):
        before = await current(db_session, tenant_id, Metric.PHOTOS)
        await record(db_session, tenant_id, Metric.PHOTOS, delta)
        await record(db_session, tenant_id, Metric.PHOTOS, delta)
        after = await current(db_session, tenant_id, Metric.PHOTOS)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    assert after == before + 2 * delta


async def test_a_counter_never_goes_negative(
    db_session: AsyncSession, as_platform: dict[str, str], client: AsyncClient
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    async with tenant_scope(db_session, tenant_id):
        await record(db_session, tenant_id, Metric.OFFICERS, -5)
        assert await current(db_session, tenant_id, Metric.OFFICERS) == 0
    await set_tenant(db_session, PLATFORM_TENANT_ID)
