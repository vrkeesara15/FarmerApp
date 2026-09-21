"""WC-014 lifecycle: suspend, resume, archive — and what each one really does."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID, PlatformTenant
from tests.platform.conftest import TENANT_BODY


async def _admin(session: AsyncSession, tenant_id: uuid.UUID) -> User:
    async with tenant_scope(session, tenant_id):
        user = (
            (await session.execute(select(User).where(User.tenant_id == tenant_id))).scalars().one()
        )
    await set_tenant(session, PLATFORM_TENANT_ID)
    return user


async def _statuses(session: AsyncSession, tenant_id: uuid.UUID) -> tuple[str, str]:
    """(tenant.status, platform_tenant.status) — they must always agree."""
    registry = (
        await session.execute(
            select(PlatformTenant).where(PlatformTenant.subject_tenant_id == tenant_id)
        )
    ).scalar_one()
    async with tenant_scope(session, tenant_id):
        tenant = await session.get(Tenant, tenant_id)
    await set_tenant(session, PLATFORM_TENANT_ID)
    assert tenant is not None
    return tenant.status, registry.status


async def test_suspend_resume_archive_keep_both_rows_in_step(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    assert await _statuses(db_session, tenant_id) == ("active", "active")

    suspended = await client.post(
        f"/v1/admin/tenants/{tenant_id}/suspend",
        json={"reason": "unpaid"},
        headers=as_platform,
    )
    assert suspended.status_code == 200, suspended.text
    assert suspended.json()["status"] == "suspended"
    assert suspended.json()["suspended_at"] is not None
    assert await _statuses(db_session, tenant_id) == ("suspended", "suspended")

    resumed = await client.post(f"/v1/admin/tenants/{tenant_id}/resume", headers=as_platform)
    assert resumed.status_code == 200, resumed.text
    assert await _statuses(db_session, tenant_id) == ("active", "active")
    assert resumed.json()["suspended_at"] is None

    archived = await client.post(f"/v1/admin/tenants/{tenant_id}/archive", headers=as_platform)
    assert archived.status_code == 200, archived.text
    assert await _statuses(db_session, tenant_id) == ("archived", "archived")
    assert archived.json()["archived_at"] is not None


async def test_archive_is_terminal(client: AsyncClient, as_platform: dict[str, str]) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = created.json()["tenant"]["id"]
    await client.post(f"/v1/admin/tenants/{tenant_id}/archive", headers=as_platform)
    for action in ("resume", "suspend"):
        resp = await client.post(f"/v1/admin/tenants/{tenant_id}/{action}", headers=as_platform)
        assert resp.status_code == 409, resp.text
        assert resp.json()["code"] == "invalid_tenant_state"


async def test_suspended_tenant_cannot_use_the_api(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str], bearer: Any
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    admin = await _admin(db_session, tenant_id)
    token = bearer(admin)

    await set_tenant(db_session, tenant_id)
    before = await client.get("/v1/me", headers=token)
    assert before.status_code == 200, before.text

    await set_tenant(db_session, PLATFORM_TENANT_ID)
    await client.post(f"/v1/admin/tenants/{tenant_id}/suspend", headers=as_platform)

    await set_tenant(db_session, tenant_id)
    after = await client.get("/v1/me", headers=token)
    assert after.status_code == 403, after.text
    assert after.json()["code"] == "tenant_suspended"


async def test_suspended_tenant_gets_no_login_code(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    await client.post(f"/v1/admin/tenants/{tenant_id}/suspend", headers=as_platform)
    await set_tenant(db_session, tenant_id)
    resp = await client.post(
        "/v1/auth/otp/send", json={"phone": TENANT_BODY["primary_contact_phone"]}
    )
    assert resp.status_code == 403, resp.text
    assert resp.json()["code"] == "tenant_suspended"


async def test_suspension_revokes_live_sessions(
    client: AsyncClient, db_session: AsyncSession, as_platform: dict[str, str]
) -> None:
    """Not just "new requests fail": the refresh families are revoked in the same
    transaction, with one bulk statement (no per-user loop)."""
    from datetime import UTC, datetime

    from farmerapp.auth.models import RefreshToken

    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = uuid.UUID(created.json()["tenant"]["id"])
    admin = await _admin(db_session, tenant_id)
    async with tenant_scope(db_session, tenant_id):
        token = RefreshToken(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            user_id=admin.id,
            family_id=uuid.uuid4(),
            token_hash="b" * 64,
            expires_at=datetime(2027, 1, 1, tzinfo=UTC),
        )
        db_session.add(token)
        await db_session.flush()
    await set_tenant(db_session, PLATFORM_TENANT_ID)

    await client.post(f"/v1/admin/tenants/{tenant_id}/suspend", headers=as_platform)

    async with tenant_scope(db_session, tenant_id):
        await db_session.refresh(token)
        await db_session.refresh(admin)
        assert token.revoked_at is not None
        assert admin.tokens_valid_after is not None
    await set_tenant(db_session, PLATFORM_TENANT_ID)


async def test_unknown_tenant_is_not_found(
    client: AsyncClient, as_platform: dict[str, str]
) -> None:
    missing = uuid.uuid4()
    for path in (f"/v1/admin/tenants/{missing}", f"/v1/admin/tenants/{missing}/usage"):
        resp = await client.get(path, headers=as_platform)
        assert resp.status_code == 404, resp.text


async def test_repeating_a_transition_is_a_no_op(
    client: AsyncClient, as_platform: dict[str, str]
) -> None:
    created = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    tenant_id = created.json()["tenant"]["id"]
    first = await client.post(f"/v1/admin/tenants/{tenant_id}/suspend", headers=as_platform)
    second = await client.post(f"/v1/admin/tenants/{tenant_id}/suspend", headers=as_platform)
    assert first.status_code == second.status_code == 200
    assert second.json()["status"] == "suspended"
