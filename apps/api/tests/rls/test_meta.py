"""Every table is covered, automatically (SEC-012), and the app role has no DDL (SEC-011).

The catalogue checks live in ``farmerapp.db.rls.rls_violations`` so CI and this test share
one definition of "covered": ``tenant_id`` column, RLS enabled *and* forced, the
``tenant_isolation`` policy, and DML (never ownership) for the app role.
"""

from __future__ import annotations

import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

import farmerapp.db.models  # noqa: F401  (register every model)
from farmerapp.db.base import Base
from farmerapp.db.rls import APP_ROLE, AUTH_ROLE, MIGRATE_ROLE, rls_statements, rls_violations
from tests.conftest import TEST_DATABASE_URL

MODEL_TABLES = sorted(t.name for t in Base.metadata.sorted_tables)


def test_metadata_has_every_known_table() -> None:
    assert {"tenant", "user", "otp_challenge", "refresh_token"} <= set(MODEL_TABLES)
    assert "alembic_version" not in MODEL_TABLES


async def test_every_model_table_is_isolated(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        problems = await conn.run_sync(rls_violations, MODEL_TABLES)
    assert problems == []


async def test_catalogue_matches_expectations(migrate_engine: AsyncEngine) -> None:
    """Belt and braces next to ``rls_violations``: read pg_class / pg_policies directly."""
    async with migrate_engine.connect() as conn:
        rows = (
            await conn.execute(
                text(
                    "SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity "
                    "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
                    "WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = ANY(:t)"
                ),
                {"t": MODEL_TABLES},
            )
        ).all()
        assert sorted(r[0] for r in rows) == MODEL_TABLES
        assert all(r[1] and r[2] for r in rows), rows
        policies = (
            await conn.execute(
                text(
                    "SELECT tablename, policyname, roles, cmd, qual, with_check FROM pg_policies "
                    "WHERE schemaname = 'public' AND tablename = ANY(:t)"
                ),
                {"t": MODEL_TABLES},
            )
        ).all()
    by_table: dict[str, dict[str, tuple[str, ...]]] = {}
    for table, name, roles, *_ in policies:
        by_table.setdefault(table, {})[name] = tuple(roles)
    for table in MODEL_TABLES:
        assert by_table[table]["tenant_isolation"] == ("public",), table
        assert by_table[table]["maintenance"] == (MIGRATE_ROLE,), table
    assert by_table["user"]["auth_lookup"] == (AUTH_ROLE,)
    assert by_table["refresh_token"]["auth_lookup"] == (AUTH_ROLE,)
    isolation = {(t, q, w) for t, n, _, _, q, w in policies if n == "tenant_isolation"}
    for table, qual, with_check in isolation:
        column = "id" if table == "tenant" else "tenant_id"
        assert qual == f"({column} = app_current_tenant())", (table, qual)
        assert with_check == qual, (table, with_check)


async def test_new_table_without_enable_rls_is_reported(migrate_engine: AsyncEngine) -> None:
    """A migration that creates a tenant table and forgets ``enable_rls`` fails the meta-test."""
    async with migrate_engine.connect() as conn:
        await conn.execute(
            text(
                "CREATE TABLE scratch_no_rls (id uuid PRIMARY KEY, tenant_id uuid NOT NULL, "
                "version integer NOT NULL DEFAULT 1)"
            )
        )
        problems = await conn.run_sync(rls_violations, [*MODEL_TABLES, "scratch_no_rls"])
        assert problems and all("scratch_no_rls" in p for p in problems)
        assert any("row level security" in p for p in problems)
        assert any("tenant_isolation" in p for p in problems)
        for statement in rls_statements("scratch_no_rls"):
            await conn.execute(text(statement))
        assert await conn.run_sync(rls_violations, [*MODEL_TABLES, "scratch_no_rls"]) == []
        await conn.rollback()


async def test_table_without_tenant_id_is_reported(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        await conn.execute(text("CREATE TABLE scratch_no_tenant (id uuid PRIMARY KEY)"))
        problems = await conn.run_sync(rls_violations, ["scratch_no_tenant"])
        assert any("tenant_id" in p for p in problems)
        await conn.rollback()


async def test_alembic_version_is_owner_only(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        allowed = await conn.scalar(
            text(
                "SELECT bool_or(has_table_privilege(:r, 'alembic_version', p)) FROM "
                "unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) AS p"
            ),
            {"r": APP_ROLE},
        )
    assert allowed is False


# ------------------------------------------------------------------ SEC-011: no DDL for app
DDL = (
    "CREATE TABLE intruder (id uuid PRIMARY KEY)",
    'ALTER TABLE "user" ADD COLUMN backdoor text',
    'ALTER TABLE "user" DISABLE ROW LEVEL SECURITY',
    'ALTER TABLE "user" NO FORCE ROW LEVEL SECURITY',
    'DROP POLICY tenant_isolation ON "user"',
    'CREATE POLICY wide_open ON "user" USING (true)',
    'DROP TABLE "user"',
    "CREATE FUNCTION intruder() RETURNS int LANGUAGE sql AS 'SELECT 1'",
    "ALTER ROLE farmerapp_app BYPASSRLS",
    "ALTER FUNCTION auth_find_user_by_phone(text) OWNER TO farmerapp_app",
    "GRANT farmerapp_migrate TO farmerapp_app",
    "INSERT INTO alembic_version (version_num) VALUES ('9999')",
)


@pytest.mark.parametrize("statement", DDL)
async def test_app_role_has_no_ddl(db_session: AsyncSession, statement: str) -> None:
    assert (
        await db_session.scalar(text("SELECT current_user")) == make_url(TEST_DATABASE_URL).username
    )
    with pytest.raises(DBAPIError, match=r"permission denied|must be owner|must be superuser"):
        async with db_session.begin_nested():
            await db_session.execute(text(statement))
