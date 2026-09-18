"""FA-006 acceptance: an audit row exists for each mutation made through the API.

``PATCH /v1/users/{id}`` is the first mutating endpoint; the rows it produces carry the
actor, the request metadata (ip, device, user agent, trace id) and a before/after diff that
only lists the changed columns (plus ``id``).
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine

from farmerapp.api.app import create_app
from farmerapp.auth.models import User, UserRole
from farmerapp.db import audit
from farmerapp.db import session as session_mod
from farmerapp.db.models import AuditLog, Tenant
from farmerapp.db.session import job_session
from tests.audit.conftest import (
    CLIENT_IP,
    DEVICE,
    REQUEST_HEADERS,
    TRACE,
    USER_AGENT,
    audit_rows,
    one_audit_row,
)
from tests.authz.conftest import Bearer, World
from tests.conftest import TEST_DATABASE_URL


async def test_patch_user_writes_exactly_one_audit_row(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    owner, target = world.a.owner, world.a.user(UserRole.FIELD_OFFICER)
    seeded = await audit_rows(db_session, entity="user", entity_id=target.id)
    assert [r.action for r in seeded] == ["user.create"]  # from the seed, as the system
    old_name = target.name

    resp = await client.patch(
        f"/v1/users/{target.id}",
        json={"name": "Renamed Officer", "cluster_id": None},
        headers={**bearer(owner), **REQUEST_HEADERS},
    )
    assert resp.status_code == 200, resp.text

    rows = await audit_rows(db_session, entity="user", entity_id=target.id)
    assert [r.action for r in rows] == ["user.create", "user.update"]  # exactly one new row
    row = rows[-1]
    assert row.tenant_id == world.a.tenant.id
    assert row.actor_id == owner.id and row.actor_role == "owner"
    assert row.action == "user.update" and row.entity == "user"
    assert row.entity_id == target.id
    # Only the columns that actually changed, plus the id. cluster_id was already NULL.
    assert row.before == {"id": str(target.id), "name": old_name}
    assert row.after == {"id": str(target.id), "name": "Renamed Officer"}
    assert row.ip == CLIENT_IP
    assert row.device_id == DEVICE
    assert row.user_agent == USER_AGENT
    assert row.trace_id == TRACE
    assert isinstance(row.created_at, datetime) and row.created_at.tzinfo is not None


async def test_patch_with_no_effective_change_writes_no_row(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    target = world.a.user(UserRole.FIELD_OFFICER)
    before = len(await audit_rows(db_session, entity="user", entity_id=target.id))
    resp = await client.patch(
        f"/v1/users/{target.id}", json={"name": target.name}, headers=bearer(world.a.owner)
    )
    assert resp.status_code == 200, resp.text
    assert len(await audit_rows(db_session, entity="user", entity_id=target.id)) == before


async def test_device_falls_back_to_the_users_bound_device(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    """Without an ``X-Device-Id`` header the device bound at login is recorded."""
    owner, target = world.a.owner, world.a.user(UserRole.STORE_MANAGER)
    owner.device_id = "owner-phone-1"
    await db_session.flush()
    resp = await client.patch(
        f"/v1/users/{target.id}", json={"status": "disabled"}, headers=bearer(owner)
    )
    assert resp.status_code == 200, resp.text
    row = await one_audit_row(db_session, action="user.update", entity_id=target.id)
    assert row.device_id == "owner-phone-1"
    assert row.before == {"id": str(target.id), "status": "active"}
    assert row.after == {"id": str(target.id), "status": "disabled"}
    assert row.ip == "127.0.0.1"  # httpx ASGI transport's client address
    assert row.trace_id  # the middleware always assigns one


async def test_role_change_records_old_and_new_role(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    """SEC-028: admin actions (role change) are audited with the actor."""
    admin, target = world.a.user(UserRole.TENANT_ADMIN), world.a.user(UserRole.ACCOUNTANT)
    resp = await client.patch(
        f"/v1/users/{target.id}", json={"role": "auditor"}, headers=bearer(admin)
    )
    assert resp.status_code == 200, resp.text
    row = await one_audit_row(db_session, action="user.update", entity_id=target.id)
    assert row.actor_id == admin.id and row.actor_role == "tenant_admin"
    assert row.before == {"id": str(target.id), "role": "accountant"}
    assert row.after == {"id": str(target.id), "role": "auditor"}


async def test_soft_delete_is_recorded_as_delete(world: World, db_session: AsyncSession) -> None:
    target = world.a.user(UserRole.FARMER)
    when = datetime(2026, 9, 17, 10, 0, tzinfo=UTC)
    with audit.actor_scope(
        audit.Actor(tenant_id=world.a.tenant.id, actor_id=world.a.owner.id, actor_role="owner")
    ):
        target.deleted_at = when
        await db_session.flush()
    row = await one_audit_row(db_session, action="user.delete", entity_id=target.id)
    assert row.entity == "user" and row.actor_id == world.a.owner.id
    assert row.before == {"id": str(target.id), "deleted_at": None}
    assert row.after == {"id": str(target.id), "deleted_at": when.isoformat()}


async def test_rolled_back_mutation_leaves_no_audit_row(
    world: World, db_session: AsyncSession
) -> None:
    """The audit row is part of the mutation's transaction: no mutation, no row."""
    target = world.a.user(UserRole.AGRONOMIST)
    target_id = target.id  # the rollback expires the instance
    with pytest.raises(RuntimeError, match="boom"):
        async with db_session.begin_nested():
            target.name = "Never persisted"
            await db_session.flush()
            assert await audit_rows(db_session, action="user.update", entity_id=target_id)
            raise RuntimeError("boom")
    assert await audit_rows(db_session, action="user.update", entity_id=target_id) == []


# --------------------------------------------------------------------------- real commit path
@pytest.fixture
async def committed_tenant(migrated_database: str) -> AsyncIterator[tuple[Tenant, User]]:
    """A tenant + owner committed through the real session factory, removed afterwards."""
    session_mod.get_engine.cache_clear()
    session_mod.get_session_factory.cache_clear()
    tenant_id = uuid.uuid4()
    with audit.actor_scope(audit.system_actor(tenant_id)):
        async with job_session(tenant_id) as session:
            tenant = Tenant(id=tenant_id, name="Commit Path Co", slug=f"cp-{tenant_id.hex[:8]}")
            session.add(tenant)
            owner = User(
                tenant_id=tenant_id, phone="+919000000777", name="Committed Owner", role="owner"
            )
            session.add(owner)
            await session.flush()
    try:
        yield tenant, owner
    finally:
        await session_mod.get_engine().dispose()
        session_mod.get_engine.cache_clear()
        session_mod.get_session_factory.cache_clear()
        cleanup = create_async_engine(TEST_DATABASE_URL.replace("farmerapp_app:", "farmerapp:"))
        async with cleanup.begin() as conn:
            await conn.execute(
                text("SELECT set_config('app.tenant_id', :t, true)"), {"t": str(tenant_id)}
            )
            for table in ("audit_log", "refresh_token", "otp_challenge", '"user"', "tenant"):
                await conn.execute(
                    text(f"DELETE FROM {table} WHERE tenant_id = :t"), {"t": tenant_id}
                )
        await cleanup.dispose()


async def _rows_for(tenant_id: uuid.UUID, entity_id: uuid.UUID) -> list[AuditLog]:
    async with job_session(tenant_id) as session:
        rows = (
            (
                await session.execute(
                    select(AuditLog)
                    .where(AuditLog.entity_id == entity_id)
                    .order_by(AuditLog.created_at)
                )
            )
            .scalars()
            .all()
        )
        return list(rows)


async def test_audit_row_is_committed_with_the_request_transaction(
    committed_tenant: tuple[Tenant, User], monkeypatch: pytest.MonkeyPatch
) -> None:
    """No dependency override: the real ``get_session`` commits the audit row with the change,
    and rolls both back when the handler fails after the flush."""
    tenant, owner = committed_tenant
    app = create_app()
    services: Any = app.state.auth
    token = services.tokens.issue_access_token(owner, services.clock.now())
    headers = {"Authorization": f"Bearer {token}", **REQUEST_HEADERS}
    transport = ASGITransport(app=app, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.patch(
            f"/v1/users/{owner.id}", json={"name": "Renamed"}, headers=headers
        )
        assert resp.status_code == 200, resp.text
        rows = await _rows_for(tenant.id, owner.id)
        updates = [r for r in rows if r.action == "user.update"]
        assert len(updates) == 1
        assert updates[0].actor_id == owner.id and updates[0].trace_id == TRACE
        assert updates[0].before == {"id": str(owner.id), "name": "Committed Owner"}
        creates = [r for r in rows if r.action == "user.create"]
        assert len(creates) == 1 and creates[0].actor_role == "system"

        # Now fail after the flush: the handler's log call raises -> 500 -> rollback.
        class _Boom:
            def info(self, *_: object, **__: object) -> None:
                raise RuntimeError("log sink down")

        monkeypatch.setattr("farmerapp.users.router.log", _Boom())
        resp = await client.patch(f"/v1/users/{owner.id}", json={"name": "Lost"}, headers=headers)
        assert resp.status_code == 500
    rows = await _rows_for(tenant.id, owner.id)
    assert [r.action for r in rows if r.action == "user.update"] == ["user.update"]
    async with job_session(tenant.id) as session:
        fresh = await session.get(User, owner.id)
        assert fresh is not None and fresh.name == "Renamed"


async def test_audit_engine_check(migrate_engine: AsyncEngine) -> None:
    """Sanity: the migrate engine sees the audit table (used by cleanup above)."""
    async with migrate_engine.connect() as conn:
        assert await conn.scalar(text("SELECT to_regclass('public.audit_log') IS NOT NULL"))
