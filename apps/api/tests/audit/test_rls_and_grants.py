"""Audit rows are tenant-scoped under RLS and append-only for the app role."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from farmerapp.db.rls import APP_ROLE, APPEND_ONLY_TABLES, rls_violations
from farmerapp.db.session import clear_tenant, set_tenant, tenant_scope
from tests.rls.conftest import TwoTenants


async def test_tenant_a_cannot_see_tenant_b_audit_rows(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    await set_tenant(db_session, two_tenants.a.tenant_id)
    rows = (await db_session.execute(text("SELECT id, tenant_id FROM audit_log"))).all()
    assert rows, "tenant A must see its own audit rows"
    assert {r.tenant_id for r in rows} == {two_tenants.a.tenant_id}
    assert two_tenants.b.audit_id not in {r.id for r in rows}
    await clear_tenant(db_session)
    assert await db_session.scalar(text("SELECT count(*) FROM audit_log")) == 0


async def test_audit_row_for_a_foreign_tenant_is_rejected(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    await set_tenant(db_session, two_tenants.a.tenant_id)
    with pytest.raises(DBAPIError, match="row-level security"):
        async with db_session.begin_nested():
            await db_session.execute(
                text(
                    "INSERT INTO audit_log (tenant_id, actor_role, action, entity, entity_id) "
                    "VALUES (:t, 'system', 'x.create', 'x', :e)"
                ),
                {"t": two_tenants.b.tenant_id, "e": uuid.uuid4()},
            )


@pytest.mark.parametrize(
    "statement",
    [
        "UPDATE audit_log SET action = 'tampered' WHERE id = :i",
        "DELETE FROM audit_log WHERE id = :i",
        "TRUNCATE audit_log",
    ],
)
async def test_app_role_cannot_change_or_remove_audit_rows(
    db_session: AsyncSession, two_tenants: TwoTenants, statement: str
) -> None:
    async with tenant_scope(db_session, two_tenants.a.tenant_id):
        with pytest.raises(DBAPIError, match="permission denied"):
            async with db_session.begin_nested():
                await db_session.execute(text(statement), {"i": two_tenants.a.audit_id})
        still = await db_session.scalar(
            text("SELECT action FROM audit_log WHERE id = :i"), {"i": two_tenants.a.audit_id}
        )
        assert still == "user.create"


async def test_grants_are_select_and_insert_only(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        rows = (
            await conn.execute(
                text(
                    "SELECT p, has_table_privilege(:r, 'audit_log', p) FROM "
                    "unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) AS p"
                ),
                {"r": APP_ROLE},
            )
        ).all()
    assert {str(p): ok for p, ok in rows} == {
        "SELECT": True,
        "INSERT": True,
        "UPDATE": False,
        "DELETE": False,
        "TRUNCATE": False,
    }


async def test_meta_check_knows_audit_log_is_append_only(migrate_engine: AsyncEngine) -> None:
    assert "audit_log" in APPEND_ONLY_TABLES
    async with migrate_engine.connect() as conn:
        assert await conn.run_sync(rls_violations, ["audit_log"]) == []
        # Granting UPDATE back would be reported.
        await conn.execute(text(f"GRANT UPDATE ON audit_log TO {APP_ROLE}"))
        problems = await conn.run_sync(rls_violations, ["audit_log"])
        assert problems and all("append-only" in p for p in problems)
        await conn.rollback()
