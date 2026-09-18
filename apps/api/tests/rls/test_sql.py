"""SQL-level proof (FA-003): as the *app* role, tenant A cannot read or write tenant B rows.

Every statement here runs as the runtime role (``farmerapp_app`` in dev/CI) through plain
SQL, i.e. with no application filter in the way: the database alone enforces isolation.
"""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.otp import find_user_by_phone
from farmerapp.db.session import clear_tenant, set_tenant, tenant_scope
from tests.conftest import TEST_DATABASE_URL
from tests.rls.conftest import TABLES, TwoTenants

APP_ROLE = make_url(TEST_DATABASE_URL).username
SETTING = text("SELECT current_setting('app.tenant_id', true)")


async def _ids(session: AsyncSession, table: str) -> set[uuid.UUID]:
    rows = await session.execute(text(f'SELECT id FROM "{table}"'))
    return {r[0] for r in rows}


async def test_session_runs_as_the_app_role(db_session: AsyncSession) -> None:
    who = await db_session.scalar(text("SELECT current_user"))
    assert who == APP_ROLE
    flags = (
        await db_session.execute(
            text(
                "SELECT rolsuper, rolbypassrls, rolcreaterole, rolcreatedb FROM pg_roles "
                "WHERE rolname = current_user"
            )
        )
    ).one()
    assert tuple(flags) == (False, False, False, False)


@pytest.mark.parametrize("table", TABLES)
async def test_select_sees_only_the_bound_tenant(
    db_session: AsyncSession, two_tenants: TwoTenants, table: str
) -> None:
    await set_tenant(db_session, two_tenants.a.tenant_id)
    ids = await _ids(db_session, table)
    assert ids, f"tenant A must see its own {table} row"
    b_ids = {
        two_tenants.b.tenant_id,
        two_tenants.b.user_id,
        two_tenants.b.otp_id,
        two_tenants.b.refresh_id,
        two_tenants.b.audit_id,
    }
    assert not ids & b_ids, f"tenant B {table} rows leaked into tenant A"
    rows = await db_session.execute(text(f'SELECT DISTINCT tenant_id FROM "{table}"'))
    assert {r[0] for r in rows} == {two_tenants.a.tenant_id}


@pytest.mark.parametrize("table", TABLES)
async def test_no_tenant_bound_fails_closed(
    db_session: AsyncSession, two_tenants: TwoTenants, table: str
) -> None:
    """Without ``app.tenant_id`` the app role sees nothing, never everything."""
    await clear_tenant(db_session)
    assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0
    # An empty string (what a reset looks like) is not a valid tenant either.
    await db_session.execute(text("SELECT set_config('app.tenant_id', '', true)"))
    assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0


async def test_garbage_tenant_setting_is_not_a_tenant(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    await db_session.execute(text("SELECT set_config('app.tenant_id', 'not-a-uuid', true)"))
    with pytest.raises(DBAPIError):
        await db_session.scalar(text('SELECT count(*) FROM "user"'))


async def test_update_and_delete_of_other_tenant_affect_zero_rows(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    await set_tenant(db_session, two_tenants.a.tenant_id)
    for table, other_id in (
        ("user", two_tenants.b.user_id),
        ("otp_challenge", two_tenants.b.otp_id),
        ("refresh_token", two_tenants.b.refresh_id),
        ("tenant", two_tenants.b.tenant_id),
    ):
        updated = await db_session.execute(
            text(f'UPDATE "{table}" SET version = version + 1 WHERE id = :i RETURNING id'),
            {"i": other_id},
        )
        assert updated.all() == [], table
        deleted = await db_session.execute(
            text(f'DELETE FROM "{table}" WHERE id = :i RETURNING id'), {"i": other_id}
        )
        assert deleted.all() == [], table
    # ... and unfiltered statements only touch tenant A.
    updated = await db_session.execute(text('UPDATE "user" SET name = name RETURNING tenant_id'))
    assert [r[0] for r in updated] == [two_tenants.a.tenant_id]
    async with tenant_scope(db_session, two_tenants.b.tenant_id):
        assert await db_session.scalar(text('SELECT version FROM "user"')) == 1


async def test_insert_with_foreign_tenant_id_is_rejected(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    await set_tenant(db_session, two_tenants.a.tenant_id)
    statements: dict[str, tuple[str, dict[str, Any]]] = {
        "user": (
            'INSERT INTO "user" (tenant_id, phone, name, role) VALUES (:t, :p, :n, :r)',
            {"t": two_tenants.b.tenant_id, "p": "+919000000099", "n": "Intruder", "r": "owner"},
        ),
        "otp_challenge": (
            "INSERT INTO otp_challenge (tenant_id, phone, purpose, code_hash, expires_at, "
            "window_started_at, channel) VALUES (:t, :p, 'login', 'x', now(), now(), 'sms')",
            {"t": two_tenants.b.tenant_id, "p": "+919000000099"},
        ),
        "refresh_token": (
            "INSERT INTO refresh_token (tenant_id, user_id, family_id, token_hash, expires_at) "
            "VALUES (:t, :u, :f, :h, now())",
            {
                "t": two_tenants.b.tenant_id,
                "u": two_tenants.b.user_id,
                "f": uuid.uuid4(),
                "h": uuid.uuid4().hex,
            },
        ),
        "tenant": (
            "INSERT INTO tenant (id, tenant_id, name) VALUES (:i, :i, 'Intruder')",
            {"i": uuid.uuid4()},
        ),
        "audit_log": (
            "INSERT INTO audit_log (tenant_id, actor_role, action, entity, entity_id) "
            "VALUES (:t, 'system', 'user.update', 'user', :u)",
            {"t": two_tenants.b.tenant_id, "u": two_tenants.b.user_id},
        ),
    }
    for table, (sql, params) in statements.items():
        with pytest.raises(DBAPIError, match="row-level security"):
            async with db_session.begin_nested():
                await db_session.execute(text(sql), params)
        assert table  # every table in TABLES is covered
    assert set(statements) == set(TABLES)


async def test_row_cannot_be_moved_to_another_tenant(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    await set_tenant(db_session, two_tenants.a.tenant_id)
    with pytest.raises(DBAPIError, match="row-level security"):
        async with db_session.begin_nested():
            await db_session.execute(
                text('UPDATE "user" SET tenant_id = :b WHERE id = :u'),
                {"b": two_tenants.b.tenant_id, "u": two_tenants.a.user_id},
            )


async def test_legacy_bypass_setting_has_no_effect(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    """The FA-001 placeholder ``app.bypass_rls`` is gone; setting it changes nothing."""
    await clear_tenant(db_session)
    await db_session.execute(text("SELECT set_config('app.bypass_rls', 'on', true)"))
    for table in TABLES:
        assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0
    await set_tenant(db_session, two_tenants.a.tenant_id)
    rows = await db_session.execute(text('SELECT DISTINCT tenant_id FROM "user"'))
    assert {r[0] for r in rows} == {two_tenants.a.tenant_id}


@pytest.mark.parametrize("role", ["farmerapp_migrate", "farmerapp_auth"])
async def test_app_role_cannot_assume_privileged_roles(db_session: AsyncSession, role: str) -> None:
    with pytest.raises(DBAPIError, match="permission denied"):
        async with db_session.begin_nested():
            await db_session.execute(text(f"SET ROLE {role}"))


async def test_auth_lookup_functions_return_ids_only(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    """The only sanctioned cross-tenant path: SECURITY DEFINER lookups that yield ids."""
    await clear_tenant(db_session)
    found = (
        await db_session.execute(
            text("SELECT * FROM auth_find_user_by_phone(:p)"), {"p": two_tenants.b.phone}
        )
    ).all()
    assert [tuple(r) for r in found] == [(two_tenants.b.user_id, two_tenants.b.tenant_id)]
    assert set(found[0]._fields) == {"user_id", "tenant_id"}

    found = (
        await db_session.execute(
            text("SELECT * FROM auth_find_refresh_token(:h)"), {"h": two_tenants.b.token_hash}
        )
    ).all()
    assert [tuple(r) for r in found] == [(two_tenants.b.refresh_id, two_tenants.b.tenant_id)]
    assert set(found[0]._fields) == {"token_id", "tenant_id"}

    unknown = await db_session.execute(text("SELECT * FROM auth_find_user_by_phone('+1')"))
    assert unknown.all() == []
    # Still nothing readable directly.
    assert await db_session.scalar(text('SELECT count(*) FROM "user"')) == 0


async def test_deleted_user_resolves_its_tenant_but_no_account(
    db_session: AsyncSession, two_tenants: TwoTenants
) -> None:
    """The lookup still names the tenant (so login can fail *inside* it); the app-level
    ``find_user_by_phone`` then finds no account."""
    async with tenant_scope(db_session, two_tenants.a.tenant_id):
        await db_session.execute(text('UPDATE "user" SET deleted_at = now()'))
    await clear_tenant(db_session)
    found = (
        await db_session.execute(
            text("SELECT * FROM auth_find_user_by_phone(:p)"), {"p": two_tenants.a.phone}
        )
    ).all()
    assert [tuple(r) for r in found] == [(two_tenants.a.user_id, two_tenants.a.tenant_id)]
    assert await find_user_by_phone(db_session, two_tenants.a.phone) is None
    assert await db_session.scalar(SETTING) == str(two_tenants.a.tenant_id)
