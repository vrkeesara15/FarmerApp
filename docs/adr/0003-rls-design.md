# ADR 0003: Row-level security design (FA-003, SEC-011, SEC-012)

Date: 2026-09-17. Status: accepted.

## Context

SPEC §0.2 locks shared-schema tenancy with `tenant_id` on every row and Postgres row-level
security keyed on `app.tenant_id` (SEC-012); SEC-011 wants the runtime DB user without DDL
rights and migrations on a separate role. FA-001 shipped with a placeholder
`app.bypass_rls` session setting so login could look a user up by phone before the tenant
is known. Any session-level "bypass" setting is a hole: whoever can run SQL as the app role
(a bug, an injection, a forgotten filter) can switch it on.

## Decision

**Roles** (created by migration 0003 when missing; login users are per environment):

| Role | Login | Rights |
|---|---|---|
| `farmerapp_app` | dev/CI: password user from `docker/postgres/initdb`; Cloud SQL: NOLOGIN group granted to the api/worker/jobs IAM users | `USAGE` on `public`, `SELECT/INSERT/UPDATE/DELETE` on tenant tables (also by default privilege for future tables), `EXECUTE` on the two lookup functions. `NOBYPASSRLS`, no `CREATE`, nothing on `alembic_version`. |
| `farmerapp_migrate` | dev/CI: the compose owner `farmerapp` (superuser); Cloud SQL: NOLOGIN group granted to the migrate job's SA only | Owner of every table (DDL). Its `maintenance` policy (`USING (true)`) makes backfills and admin seeds see every tenant; the owner could disable RLS anyway, so this adds no privilege but keeps dev (superuser) and Cloud SQL (non-superuser owner, `FORCE` applies) behaving the same. |
| `farmerapp_auth` | NOLOGIN, nobody may `SET ROLE` to it | Owns `auth_find_user_by_phone(text)` and `auth_find_refresh_token(text)` (`SECURITY DEFINER`, fixed `search_path`), which return **ids only** (`user_id`/`token_id`, `tenant_id`). Column-level `SELECT` on `user(id, tenant_id, phone, deleted_at, created_at)` and `refresh_token(id, tenant_id, token_hash)` through its own `auth_lookup` policy (`FOR SELECT`). |

**Policies** on every tenant table (`farmerapp.db.rls.enable_rls`): `ENABLE` + `FORCE ROW LEVEL
SECURITY`; `tenant_isolation FOR ALL TO PUBLIC USING (tenant_id = app_current_tenant()) WITH
CHECK (same)`; `maintenance FOR ALL TO farmerapp_migrate USING (true) WITH CHECK (true)`.
`app_current_tenant()` is `NULLIF(current_setting('app.tenant_id', true), '')::uuid`, so an
unbound session (NULL) or a reset (`''`) matches nothing (fail closed) and a non-uuid value
errors. The `tenant` table keys on `id`.

**Binding** is transaction-local (`set_config(..., true)`), done by the request session
dependency and by `get_current_user` *before* it loads the user, so a signed token with a
foreign `tid` finds nobody (401). Pooled connections cannot carry a tenant into the next
request (proved with a pool of one connection). Jobs and the worker use
`tenant_scope(session, tenant_id)` / `job_session(tenant_id)`; the seed iterates tenants
with fixed ids and runs as the app role. There is no bypass switch: `app.bypass_rls` is gone
and setting it does nothing.

**Login before the tenant is known** goes through the two lookup functions only: phone →
`(user_id, tenant_id)`, bind the tenant, then load the user under RLS (deleted accounts
resolve their tenant so the challenge is consumed and "no account" is answered inside it);
refresh-token hash → `(token_id, tenant_id)`, bind, then rotate/revoke under RLS. The OTP
scheduler payload carries the tenant.

**Enforcement of the rule "every table has RLS"**: `tests/rls/test_meta.py` runs
`rls_violations` over every table in `Base.metadata` (tenant column, enabled, forced,
`tenant_isolation`, app DML, not app-owned). A migration that creates a table without
`enable_rls` fails CI; the negative test creates such a table and shows the check catches it.

## Alternatives considered

* Keep `app.bypass_rls` and honour it in the policy — rejected: settable by the app role.
* `BYPASSRLS` on a dedicated auth login — rejected: Cloud SQL users cannot set it, and it
  would expose whole tables instead of two id lookups.
* Lookup functions owned by the migrate role — rejected: a `SECURITY DEFINER` body running
  as the DDL owner is a larger blast radius than a role that can only read five columns.
* Owner exempt from RLS (no `FORCE`) — rejected: dev's owner is a superuser and Cloud SQL's
  is not, so behaviour would differ; the `maintenance` policy keeps it explicit and equal.

## Consequences

* Two URLs: `DATABASE_URL` (app role, runtime) and `MIGRATION_DATABASE_URL` (owner, Alembic
  only). Production refuses to start if they use the same role.
* Every new tenant table: `enable_rls("table")` right after `op.create_table`.
* Every job/worker DB access states its tenant. Cross-tenant work is per tenant (loop with
  `tenant_scope`) or a migration.
* Cloud SQL: after the first `alembic upgrade` per environment an admin grants the IAM users
  membership in `farmerapp_app` (api/worker/jobs) and `farmerapp_migrate` (migrate job's SA);
  see `infra/modules/sql/main.tf`. A dedicated migrate service account is a follow-up (the
  migrate job currently runs as the jobs SA).
