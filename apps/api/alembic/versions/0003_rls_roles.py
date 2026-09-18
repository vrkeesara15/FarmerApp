"""row-level security per tenant; app / migrate / auth roles

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-17 00:00:00 UTC

FA-003 / SEC-011 / SEC-012. Backward compatible for the running API: no column changes; the
policies only restrict what a session sees, and the FA-001 API already binds the tenant on
every authenticated request. Requires the runtime to connect as (a member of)
``farmerapp_app`` and Alembic to run as the owner (``MIGRATION_DATABASE_URL``).

* roles ``farmerapp_app`` / ``farmerapp_migrate`` / ``farmerapp_auth`` (created when missing;
  login users are environment-specific: docker/postgres/initdb locally, IAM users in Cloud SQL)
* least-privilege grants for the app role (DML only; nothing on ``alembic_version``)
* ``app_current_tenant()`` + ENABLE/FORCE RLS + ``tenant_isolation`` / ``maintenance``
  policies on tenant, user, otp_challenge, refresh_token
* ``auth_find_user_by_phone(text)`` / ``auth_find_refresh_token(text)``: SECURITY DEFINER
  lookups owned by ``farmerapp_auth`` returning ids only (login before the tenant is known)

Every later migration calls ``farmerapp.db.rls.enable_rls(table)`` after ``create_table``;
``tests/rls/test_meta.py`` fails when one forgets.
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

from farmerapp.db.rls import (
    APP_ROLE,
    AUTH_POLICY,
    AUTH_ROLE,
    disable_rls,
    enable_rls,
    role_statements,
    schema_privilege_statements,
    tenant_function_statements,
)

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TENANT_TABLES: tuple[tuple[str, str], ...] = (
    ("tenant", "id"),
    ("user", "tenant_id"),
    ("otp_challenge", "tenant_id"),
    ("refresh_token", "tenant_id"),
)

USER_LOOKUP = "auth_find_user_by_phone(text)"
REFRESH_LOOKUP = "auth_find_refresh_token(text)"

AUTH_STATEMENTS = (
    # What the lookups may read: column-level SELECT through their own policy.
    f'GRANT SELECT (id, tenant_id, phone, deleted_at, created_at) ON "user" TO {AUTH_ROLE}',
    f"GRANT SELECT (id, tenant_id, token_hash) ON refresh_token TO {AUTH_ROLE}",
    f'CREATE POLICY {AUTH_POLICY} ON "user" AS PERMISSIVE FOR SELECT TO {AUTH_ROLE} USING (true)',
    f"CREATE POLICY {AUTH_POLICY} ON refresh_token AS PERMISSIVE FOR SELECT TO {AUTH_ROLE} "
    "USING (true)",
    # Phone -> (user_id, tenant_id); live accounts first, then oldest (WC-014: a phone in
    # several tenants will need a tenant picker; the app takes the first row until then).
    # Deleted accounts are returned too so their tenant can be bound and the caller can
    # answer "no account" / consume the challenge under RLS like any other login.
    """
CREATE OR REPLACE FUNCTION public.auth_find_user_by_phone(p_phone text)
RETURNS TABLE (user_id uuid, tenant_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT u.id, u.tenant_id
    FROM public."user" u
    WHERE u.phone = p_phone
    ORDER BY (u.deleted_at IS NOT NULL), u.created_at, u.id
$$
""".strip(),
    # Refresh token hash -> (token_id, tenant_id); revoked/expired rows included so rotation
    # can detect reuse inside the tenant scope.
    """
CREATE OR REPLACE FUNCTION public.auth_find_refresh_token(p_token_hash text)
RETURNS TABLE (token_id uuid, tenant_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT r.id, r.tenant_id FROM public.refresh_token r WHERE r.token_hash = p_token_hash
$$
""".strip(),
    # Owned by the auth role (transient CREATE is what ALTER ... OWNER requires), callable by
    # the app role only.
    f"GRANT CREATE ON SCHEMA public TO {AUTH_ROLE}",
    f"ALTER FUNCTION public.{USER_LOOKUP} OWNER TO {AUTH_ROLE}",
    f"ALTER FUNCTION public.{REFRESH_LOOKUP} OWNER TO {AUTH_ROLE}",
    f"REVOKE CREATE ON SCHEMA public FROM {AUTH_ROLE}",
    f"REVOKE ALL ON FUNCTION public.{USER_LOOKUP} FROM PUBLIC",
    f"REVOKE ALL ON FUNCTION public.{REFRESH_LOOKUP} FROM PUBLIC",
    f"GRANT EXECUTE ON FUNCTION public.{USER_LOOKUP} TO {APP_ROLE}",
    f"GRANT EXECUTE ON FUNCTION public.{REFRESH_LOOKUP} TO {APP_ROLE}",
)


def upgrade() -> None:
    for statement in role_statements():
        op.execute(statement)
    for statement in schema_privilege_statements():
        op.execute(statement)
    for statement in tenant_function_statements():
        op.execute(statement)
    for table, column in TENANT_TABLES:
        enable_rls(table, column)
    for statement in AUTH_STATEMENTS:
        op.execute(statement)


def downgrade() -> None:
    op.execute(f"DROP FUNCTION IF EXISTS public.{USER_LOOKUP}")
    op.execute(f"DROP FUNCTION IF EXISTS public.{REFRESH_LOOKUP}")
    op.execute(f'DROP POLICY IF EXISTS {AUTH_POLICY} ON "user"')
    op.execute(f"DROP POLICY IF EXISTS {AUTH_POLICY} ON refresh_token")
    for table, _ in reversed(TENANT_TABLES):
        disable_rls(table)
    op.execute("DROP FUNCTION IF EXISTS public.app_current_tenant()")
    # Roles and grants are cluster-level and harmless without policies; they stay.
