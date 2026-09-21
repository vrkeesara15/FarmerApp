"""WC-014: one call provisions a tenant that is ready to work in."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.models import CropTaskTemplate
from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.flags.models import RuleTenantOverride
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID, PlatformTenant, TenantStatus
from farmerapp.platform_admin.plans import Metric
from farmerapp.platform_admin.usage import current
from farmerapp.tenants.models import Cluster, Store
from farmerapp.tenants.settings import settings_from_tenant
from tests.platform.conftest import TENANT_BODY


async def _count(session: AsyncSession, model: Any, tenant_id: uuid.UUID) -> int:
    async with tenant_scope(session, tenant_id):
        value = await session.scalar(
            select(func.count()).select_from(model).where(model.tenant_id == tenant_id)
        )
    return int(value or 0)


async def test_create_provisions_everything_a_tenant_needs(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    tenant_id = uuid.UUID(body["tenant"]["id"])

    assert body["tenant"]["slug"] == "nava"
    assert body["tenant"]["status"] == TenantStatus.ACTIVE
    assert body["tenant"]["plan"] == "pilot"
    assert body["created"]["crops"] == 6
    assert body["created"]["pest_master"] > 0
    assert body["created"]["calendar_templates"] > 0
    assert body["created"]["users"] == 1

    assert await _count(db_session, Cluster, tenant_id) == 1
    assert await _count(db_session, Store, tenant_id) == 1
    assert await _count(db_session, Crop, tenant_id) == 6
    assert await _count(db_session, PestOrDisease, tenant_id) > 0
    assert await _count(db_session, CropTaskTemplate, tenant_id) > 0

    # The first user is a tenant_admin with the primary contact's phone; nothing else exists.
    async with tenant_scope(db_session, tenant_id):
        users = (
            (await db_session.execute(select(User).where(User.tenant_id == tenant_id)))
            .scalars()
            .all()
        )
        assert [u.role for u in users] == [UserRole.TENANT_ADMIN]
        assert users[0].phone == TENANT_BODY["primary_contact_phone"]
        assert users[0].language == "te"
    await set_tenant(db_session, PLATFORM_TENANT_ID)


async def test_settings_start_with_resolved_defaults(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    body = {**TENANT_BODY, "slug": "defaults", "languages": ["en", "te"], "default_language": "te"}
    resp = await client.post("/v1/admin/tenants", json=body, headers=as_platform)
    assert resp.status_code == 201, resp.text
    tenant_id = uuid.UUID(resp.json()["tenant"]["id"])
    async with tenant_scope(db_session, tenant_id):
        tenant = await db_session.get(Tenant, tenant_id)
        assert tenant is not None
        settings = settings_from_tenant(tenant)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    assert settings.languages_enabled == ["en", "te"]
    assert settings.default_language == "te"
    assert settings.geofence_radius_m == 150  # a documented default, resolved not empty
    assert settings.legal_name == body["name"]
    # VA-F04: the service area is derived from the placeholder store, so the rule can run.
    assert settings.service_area.districts


async def test_disabled_rules_become_tenant_overrides(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    body = {**TENANT_BODY, "slug": "norules", "disabled_rules": ["VA-E06", "NOT-A-RULE"]}
    resp = await client.post("/v1/admin/tenants", json=body, headers=as_platform)
    assert resp.status_code == 201, resp.text
    tenant_id = uuid.UUID(resp.json()["tenant"]["id"])
    async with tenant_scope(db_session, tenant_id):
        rows = (
            (
                await db_session.execute(
                    select(RuleTenantOverride).where(RuleTenantOverride.tenant_id == tenant_id)
                )
            )
            .scalars()
            .all()
        )
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    assert [(r.rule_id, r.enabled) for r in rows] == [("VA-E06", False)]


async def test_usage_counters_start_at_the_provisioned_reality(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(resp.json()["tenant"]["id"])
    async with tenant_scope(db_session, tenant_id):
        assert await current(db_session, tenant_id, Metric.STORES) == 1
        assert await current(db_session, tenant_id, Metric.FARMERS) == 0
        assert await current(db_session, tenant_id, Metric.OFFICERS) == 0
    await set_tenant(db_session, PLATFORM_TENANT_ID)


async def test_slug_is_taken_once(
    client: AsyncClient, as_platform: dict[str, str], created_tenant: dict[str, Any]
) -> None:
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    assert resp.status_code == 409, resp.text
    assert resp.json()["code"] == "tenant_slug_taken"


@pytest.mark.parametrize(
    ("field", "value"),
    [("plan", "platinum"), ("region", "europe-west1"), ("slug", "Not A Slug")],
)
async def test_invalid_create_is_rejected(
    client: AsyncClient, as_platform: dict[str, str], field: str, value: str
) -> None:
    resp = await client.post(
        "/v1/admin/tenants", json={**TENANT_BODY, field: value}, headers=as_platform
    )
    assert resp.status_code == 422, resp.text


async def test_create_needs_step_up(client: AsyncClient, platform_admin: User, bearer: Any) -> None:
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=bearer(platform_admin))
    assert resp.status_code == 401
    assert resp.json()["code"] == "step_up_required"


async def test_registry_row_mirrors_the_tenant_row(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(resp.json()["tenant"]["id"])
    registry = (
        await db_session.execute(
            select(PlatformTenant).where(PlatformTenant.subject_tenant_id == tenant_id)
        )
    ).scalar_one()
    async with tenant_scope(db_session, tenant_id):
        tenant = await db_session.get(Tenant, tenant_id)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    assert tenant is not None
    assert registry.status == tenant.status
    assert registry.plan == tenant.plan
    assert registry.slug == tenant.slug
