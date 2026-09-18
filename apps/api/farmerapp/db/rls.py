"""Row-level security and database roles (FA-003, SEC-011, SEC-012).

One definition, three consumers:

* **Migrations** call ``enable_rls(table)`` for every tenant table they create (0003 does it
  for the existing ones). It enables *and forces* RLS, installs the ``tenant_isolation``
  policy (``tenant_id = app_current_tenant()``, ``WITH CHECK`` included) and the
  ``maintenance`` policy for the migrate role, and grants DML to the app role.
* **Tests** (``tests/rls/test_meta.py``) call ``rls_violations`` for every table in
  ``Base.metadata`` so a new table that forgets ``enable_rls`` fails CI.
* **Runtime** binds the tenant per request (``farmerapp.db.session``); nothing here.

Roles (cluster-wide; created by 0003 when missing, login users are environment-specific):

``farmerapp_app``      runtime. DML on tenant tables only, ``NOBYPASSRLS``, no DDL. Dev/CI:
                       a login user from ``docker/postgres/initdb``; Cloud SQL: a NOLOGIN
                       group the IAM service-account users are granted.
``farmerapp_migrate``  owner/DDL. Runs Alembic; its ``maintenance`` policy sees every tenant
                       (backfills, seed as admin). Never granted to a runtime login.
``farmerapp_auth``     NOLOGIN, owns the two ``SECURITY DEFINER`` lookup functions login needs
                       before a tenant is known (phone -> ids, refresh hash -> ids) and has
                       column-level SELECT on ``user`` / ``refresh_token`` via ``auth_lookup``.
                       Nobody can ``SET ROLE`` to it; the app role may only EXECUTE the
                       functions.

Design record: docs/adr/0003-rls-design.md.
"""

from __future__ import annotations

from collections.abc import Iterable
from string import Template

from sqlalchemy import Connection, text

APP_ROLE = "farmerapp_app"
MIGRATE_ROLE = "farmerapp_migrate"
AUTH_ROLE = "farmerapp_auth"

TENANT_SETTING = "app.tenant_id"
TENANT_FUNCTION = "app_current_tenant"
ISOLATION_POLICY = "tenant_isolation"
MAINTENANCE_POLICY = "maintenance"
AUTH_POLICY = "auth_lookup"

#: Tables that are not tenant data and must stay owner-only.
NON_TENANT_TABLES = frozenset({"alembic_version", "spatial_ref_sys"})

#: Append-only tenant tables: the app role may SELECT and INSERT but never UPDATE or DELETE
#: (FA-006 audit trail; FM-002 consent records — a withdrawal is a new row). Purging past
#: retention is the migrate role's job (NF-012).
APPEND_ONLY_TABLES = frozenset({"audit_log", "consent_record"})


def _q(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


# --------------------------------------------------------------------------- roles
# Plain templates (no f-strings): the only substitutions are the role constants above.
_ROLE_BOOTSTRAP = Template(
    """
DO $$$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$app_role') THEN
        CREATE ROLE $app_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$migrate_role') THEN
        CREATE ROLE $migrate_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$auth_role') THEN
        CREATE ROLE $auth_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
    END IF;
    IF NOT pg_has_role(current_user, '$migrate_role', 'SET') THEN
        EXECUTE format('GRANT $migrate_role TO %I WITH SET TRUE, INHERIT TRUE', current_user);
    END IF;
    IF NOT pg_has_role(current_user, '$auth_role', 'SET') THEN
        EXECUTE format('GRANT $auth_role TO %I WITH SET TRUE, INHERIT TRUE', current_user);
    END IF;
END $$$$
""".strip()
)


def role_statements() -> list[str]:
    """Create the three NOLOGIN roles when missing; make the migrating role a member of
    ``farmerapp_migrate`` and ``farmerapp_auth`` (needed to own objects as them)."""
    return [
        _ROLE_BOOTSTRAP.substitute(
            app_role=APP_ROLE, migrate_role=MIGRATE_ROLE, auth_role=AUTH_ROLE
        )
    ]


_TABLE_GRANTS = Template(
    """
DO $$$$
DECLARE t record;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables
             WHERE schemaname = 'public' AND tableowner = current_user
               AND tablename <> ALL (ARRAY['alembic_version', 'spatial_ref_sys'])
    LOOP
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO $app_role',
                       t.tablename);
    END LOOP;
    FOR t IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
    LOOP
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO $app_role',
                       t.sequencename);
    END LOOP;
END $$$$
""".strip()
)


def schema_privilege_statements() -> list[str]:
    """Least privilege for the app role: usage (no CREATE) on ``public``, DML on tables the
    migrating role owns, DML by default on tables it creates later; nothing on
    ``alembic_version``."""
    return [
        "REVOKE CREATE ON SCHEMA public FROM PUBLIC",
        f"GRANT USAGE ON SCHEMA public TO {APP_ROLE}, {AUTH_ROLE}",
        f"""
DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO {APP_ROLE}', current_database());
END $$
""".strip(),
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA public "
        f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO {APP_ROLE}",
        f"ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO {APP_ROLE}",
        "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC",
        _TABLE_GRANTS.substitute(app_role=APP_ROLE),
        f"REVOKE ALL ON TABLE alembic_version FROM {APP_ROLE}, {AUTH_ROLE}",
    ]


# --------------------------------------------------------------------------- tenant
def tenant_function_statements() -> list[str]:
    """``app_current_tenant()``: the bound tenant or NULL (unset / empty), so an unbound
    session matches no row (fail closed) and a reset can be an empty string."""
    return [
        f"""
CREATE OR REPLACE FUNCTION public.{TENANT_FUNCTION}() RETURNS uuid
LANGUAGE sql STABLE PARALLEL SAFE
SET search_path = pg_catalog, public
AS $$ SELECT NULLIF(current_setting('{TENANT_SETTING}', true), '')::uuid $$
""".strip(),
        f"REVOKE ALL ON FUNCTION public.{TENANT_FUNCTION}() FROM PUBLIC",
        f"GRANT EXECUTE ON FUNCTION public.{TENANT_FUNCTION}() TO {APP_ROLE}, {MIGRATE_ROLE}, "
        f"{AUTH_ROLE}",
    ]


def rls_statements(
    table: str, tenant_column: str = "tenant_id", *, append_only: bool = False
) -> list[str]:
    """Statements that put ``table`` under tenant isolation (idempotent).

    ``append_only`` grants the app role SELECT + INSERT only and revokes the UPDATE/DELETE it
    would otherwise get from the 0003 default privileges.
    """
    t = _q(table)
    predicate = f"{_q(tenant_column)} = {TENANT_FUNCTION}()"
    grants = (
        [
            f"REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON {t} FROM {APP_ROLE}",
            f"GRANT SELECT, INSERT ON {t} TO {APP_ROLE}",
        ]
        if append_only
        else [f"GRANT SELECT, INSERT, UPDATE, DELETE ON {t} TO {APP_ROLE}"]
    )
    return [
        f"ALTER TABLE {t} ENABLE ROW LEVEL SECURITY",
        f"ALTER TABLE {t} FORCE ROW LEVEL SECURITY",
        f"DROP POLICY IF EXISTS {ISOLATION_POLICY} ON {t}",
        f"CREATE POLICY {ISOLATION_POLICY} ON {t} AS PERMISSIVE FOR ALL TO PUBLIC "
        f"USING ({predicate}) WITH CHECK ({predicate})",
        f"DROP POLICY IF EXISTS {MAINTENANCE_POLICY} ON {t}",
        f"CREATE POLICY {MAINTENANCE_POLICY} ON {t} AS PERMISSIVE FOR ALL TO {MIGRATE_ROLE} "
        f"USING (true) WITH CHECK (true)",
        *grants,
    ]


def enable_rls(table: str, tenant_column: str = "tenant_id", *, append_only: bool = False) -> None:
    """Alembic helper: call right after ``op.create_table`` of every tenant table.

    ``tenant_column`` is ``"id"`` for the ``tenant`` table itself. ``append_only=True`` for
    tables listed in ``APPEND_ONLY_TABLES`` (the meta-test checks both agree).
    """
    from alembic import op

    for statement in rls_statements(table, tenant_column, append_only=append_only):
        op.execute(statement)


def disable_rls(table: str) -> None:
    """Alembic helper for downgrades (policies dropped, RLS off)."""
    from alembic import op

    t = _q(table)
    for statement in (
        f"DROP POLICY IF EXISTS {ISOLATION_POLICY} ON {t}",
        f"DROP POLICY IF EXISTS {MAINTENANCE_POLICY} ON {t}",
        f"ALTER TABLE {t} NO FORCE ROW LEVEL SECURITY",
        f"ALTER TABLE {t} DISABLE ROW LEVEL SECURITY",
    ):
        op.execute(statement)


# --------------------------------------------------------------------------- audit
_TABLE_STATE = text(
    """
SELECT c.relname AS name,
       c.relrowsecurity AS enabled,
       c.relforcerowsecurity AS forced,
       pg_get_userbyid(c.relowner) AS owner,
       EXISTS (SELECT 1 FROM pg_attribute a
               WHERE a.attrelid = c.oid AND a.attname = :column AND NOT a.attisdropped)
           AS has_tenant_column,
       (SELECT array_agg(p.polname::text) FROM pg_policy p WHERE p.polrelid = c.oid)
           AS policies,
       has_table_privilege(:app_role, c.oid, 'SELECT')
           AND has_table_privilege(:app_role, c.oid, 'INSERT') AS app_read_write,
       has_table_privilege(:app_role, c.oid, 'UPDATE')
           OR has_table_privilege(:app_role, c.oid, 'DELETE')
           OR has_table_privilege(:app_role, c.oid, 'TRUNCATE') AS app_update_delete
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND c.relname = :table
"""
)


def rls_violations(
    conn: Connection, tables: Iterable[str], tenant_column: str = "tenant_id"
) -> list[str]:
    """Why each of ``tables`` is *not* isolated (empty list = all good).

    Checks, per table: it exists; it has ``tenant_column`` (``id`` counts for ``tenant``);
    RLS is enabled and forced; the ``tenant_isolation`` policy exists; the app role has DML
    (SELECT + INSERT only for ``APPEND_ONLY_TABLES``, all four otherwise) and is not the
    owner. Meant for ``Base.metadata`` tables, i.e. ``alembic_version`` and extension tables
    are the caller's business to exclude.
    """
    problems: list[str] = []
    for table in tables:
        column = "id" if table == "tenant" else tenant_column
        row = conn.execute(
            _TABLE_STATE, {"table": table, "column": column, "app_role": APP_ROLE}
        ).first()
        if row is None:
            problems.append(f"{table}: table does not exist")
            continue
        if not row.has_tenant_column:
            problems.append(f"{table}: no {column} column")
        if not row.enabled:
            problems.append(f"{table}: row level security is not enabled")
        if not row.forced:
            problems.append(f"{table}: row level security is not forced (owner exempt)")
        policies = set(row.policies or ())
        if ISOLATION_POLICY not in policies:
            problems.append(f"{table}: no {ISOLATION_POLICY} policy")
        if not row.app_read_write:
            problems.append(f"{table}: {APP_ROLE} lacks SELECT/INSERT privileges")
        if table in APPEND_ONLY_TABLES:
            if row.app_update_delete:
                problems.append(f"{table}: append-only table but {APP_ROLE} may UPDATE/DELETE")
        elif not row.app_update_delete:
            problems.append(f"{table}: {APP_ROLE} lacks UPDATE/DELETE privileges")
        if row.owner == APP_ROLE:
            problems.append(f"{table}: owned by the app role (DDL rights)")
    return problems


__all__ = [
    "APPEND_ONLY_TABLES",
    "APP_ROLE",
    "AUTH_POLICY",
    "AUTH_ROLE",
    "ISOLATION_POLICY",
    "MAINTENANCE_POLICY",
    "MIGRATE_ROLE",
    "NON_TENANT_TABLES",
    "TENANT_FUNCTION",
    "TENANT_SETTING",
    "disable_rls",
    "enable_rls",
    "rls_statements",
    "rls_violations",
    "role_statements",
    "schema_privilege_statements",
    "tenant_function_statements",
]
