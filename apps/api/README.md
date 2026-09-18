# apps/api — FarmerApp backend package

One Python package, `farmerapp`, with three entrypoints:

| Entrypoint | Command | Deployable |
|---|---|---|
| `farmerapp.api.app:app` | `uvicorn farmerapp.api.app:app` | api (Cloud Run) |
| `farmerapp.worker.app:app` | `uvicorn farmerapp.worker.app:app` | worker (Cloud Run, Pub/Sub push) |
| `farmerapp.jobs` | `python -m farmerapp.jobs <job>` | jobs (Cloud Run Jobs) |

`apps/worker` and `apps/jobs` only hold a Dockerfile + README; they build from this directory.

## Layout

```
farmerapp/
  settings.py     pydantic-settings (env vars, see /.env.example)
  logging.py      structlog JSON logging, trace id per request
  api/            FastAPI app factory, /v1/health, RFC 9457 errors, CORS, scheduler ticker
  auth/           FA-001 phone + OTP login, JWT access/refresh (SEC-020/021), get_current_user,
                  SMS/WhatsApp provider adapters (fake, mockserver), delayed-task scheduler seam;
                  FA-002 policy.py (require_roles / PUBLIC, startup check, x-roles in OpenAPI),
                  scope.py (SPEC 2.6 matrix as SQLAlchemy filters)
  users/          /v1/users list/get/patch (minimal WC-011 slice; cursor pagination in api/pagination.py)
  audit/          GET /v1/audit-logs (FA-006 read endpoint for the WC-103 viewer)
  db/             async engine/session, tenant binding (set_tenant / tenant_scope / job_session),
                  rls.py (enable_rls for migrations, rls_violations for the meta-test), Base, models,
                  audit.py (FA-006 actor context + flush listener + redaction + audit.record)
  worker/         Pub/Sub push receiver + dispatch table by topic (SPEC 9.2)
  jobs/           typer CLI (hello, seed = tenants "fcc" + "gfl", one user per role each; runs as the app role;
                  purge-audit-logs = NF-012 dry run)
alembic/          async Alembic env + migrations
scripts/          export_openapi.py (writes/checks openapi.yaml)
tests/            pytest (needs the compose db: `make db`)
```

## Everyday commands (from repo root)

```
make up          # db, pubsub, gcs, mockserver (also creates the farmerapp_app login, `make db-roles`)
make migrate     # alembic upgrade head as the owner (MIGRATION_DATABASE_URL)
make seed        # demo tenants, as the app role under RLS (DATABASE_URL)
make test-api    # pytest with coverage
make check-api   # ruff, mypy strict, pytest, openapi diff, bandit, pip-audit
make openapi     # regenerate apps/api/openapi.yaml (commit it)
```

Inside this directory: `uv sync`, then `uv run <cmd>`.

## Auth (FA-001)

```
make seed                      # tenant "Future Crop Care" (fcc) + users +91900000000{1..5}, +919000000010
uvicorn farmerapp.api.app:app  # then POST /v1/auth/otp/send {"phone": "+919000000004"}
curl localhost:8090/sms/messages?to=%2B919000000004   # read the code from the mockserver
```

With `OTP_DEV_CODE=123456` in `.env` (local/dev only) the fixed code is accepted as well.
Delayed OTP delivery checks (WhatsApp fallback after 30 s) run in-process locally
(`farmerapp.auth.scheduler.InProcessScheduler`); production will publish `notify.send`
(TODO OPS-004). Tests use `FakeProvider` + `FakeClock`; `pytest -m integration` also talks to
the compose mockserver when it is up.

## Authorisation (FA-002 / SEC-006)

Every route declares exactly one policy; the app refuses to start otherwise
(`farmerapp.auth.policy.install_policies`).

```python
from farmerapp.auth.policy import PUBLIC, Role, require_roles


@router.get("/health", dependencies=[PUBLIC])  # no token
async def health() -> ...: ...


@router.get("/farmers")  # role check, returns the user
async def list_farmers(actor: Annotated[User, require_roles(Role.OWNER, Role.CLUSTER_HEAD)]): ...


@router.get("/users/{id}")  # ... or the user themselves
async def get_user(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES, self_param="id")]
): ...
```

A denied call is `403` problem+json with code `forbidden` and a WARNING `authz_forbidden`
(actor id, role, tenant, method, route template; never phone or name). Row-level scope
(own cluster / own store / own records, SPEC 2.6) is `farmerapp.auth.scope.scope_filters`.

The policy is written into `openapi.yaml` as `x-roles` / `x-public` / `x-self`;
`tests/authz/test_matrix.py` parses that file and tests every operation for every role plus
cross-tenant access. New routes with path parameters or a body need a `RouteFixture` there.
Seed data: `make seed` creates tenants `fcc` (+91900000000{1..10}) and `gfl`
(+91910000000{1..10}), one user per role each.

## Tenant isolation (FA-003 / SEC-011 / SEC-012)

Two database roles, two URLs (design: `docs/adr/0003-rls-design.md`):

| Env var | Role | Used by |
|---|---|---|
| `DATABASE_URL` | `farmerapp_app` — DML only, `NOBYPASSRLS`, no DDL | api, worker, jobs, tests |
| `MIGRATION_DATABASE_URL` | owner (`farmerapp` locally; member of `farmerapp_migrate`) | `alembic upgrade`, `migrate_engine` test fixture |

Every tenant table has RLS enabled **and forced** with the `tenant_isolation` policy
(`tenant_id = app_current_tenant()`, `WITH CHECK` too). `app_current_tenant()` reads the
transaction-local setting `app.tenant_id`; unset means *no rows*. The request session binds it
from the access token before the user is loaded, so a foreign `tid` is a 401.

Rules for new code:

```python
# migrations: right after every op.create_table of a tenant table
from farmerapp.db.rls import enable_rls

enable_rls("farmer")  # tests/rls/test_meta.py fails otherwise

# jobs / worker: say which tenant you work for
from farmerapp.db import job_session, tenant_scope

async with job_session(tenant_id) as session:
    ...
async with tenant_scope(session, tenant_id):
    ...  # inside an existing transaction
```

Login before the tenant is known uses two `SECURITY DEFINER` lookups owned by the NOLOGIN
`farmerapp_auth` role — `auth_find_user_by_phone(phone)` and `auth_find_refresh_token(hash)`
— which return ids only; there is no bypass setting. Tests: `tests/rls/` (SQL-level as the app
role, API-level, catalogue meta-test, DDL denied, pool reuse).

Dev/CI login users come from `docker/postgres/initdb/10-roles.sql` (fresh volumes) or
`make db-roles` (existing volumes). Cloud SQL: IAM service-account users are created by
Terraform; after the first migration an admin grants them `farmerapp_app` (api/worker/jobs)
or `farmerapp_migrate` (migrate job) — see `infra/modules/sql/main.tf`.

## Audit trail (FA-006)

Every create / update / delete of a row with a `tenant_id` writes an `audit_log` row **in the
same flush** (so it commits or rolls back with the change): who (`actor_id`, `actor_role`;
NULL + `system` for jobs), what (`action` = `<table>.<create|update|delete>`, `entity`,
`entity_id`, `before` / `after` = the changed columns plus `id`; full row on create/delete;
setting `deleted_at` is a `delete`), and from where (`ip`, `device_id`, `user_agent`,
`trace_id`). The listener lives in `farmerapp/db/audit.py` and is installed for every
session; a model opts out with `__audit__ = False` (use it for high-volume telemetry only).

Actor context is a `ContextVar`:

```python
# requests: bound by get_current_user (nothing to do). Clients may send X-Device-Id.
# jobs / worker / scripts:
from farmerapp.db import audit

with audit.actor_scope(audit.system_actor(tenant_id)):
    async with job_session(tenant_id) as session:
        ...

# events that are not row changes (login, export...):
audit.record(
    session,
    action="auth.login",
    entity="user",
    entity_id=user.id,
    tenant_id=user.tenant_id,
    after={"device_id": device_id},
)
```

Redaction is configured once in `farmerapp/db/audit.py`: `REDACTED_COLUMNS` (`code_hash`,
`token_hash` — never recorded), `MASKED_COLUMNS` (`phone` → last four digits),
`EXCLUDED_COLUMNS` (`updated_at`, `version`). Add a column there before storing a new secret
or PII field.

The table is append-only for the app role (migration 0004 revokes UPDATE/DELETE; tests in
`tests/audit/test_rls_and_grants.py`) and tenant-scoped like every other table. Read it with
`GET /v1/audit-logs?entity=user&entity_id=…&actor_id=…&action=…&from=…&to=…` (owner,
director, auditor, tenant_admin; newest first, cursor pagination). Retention is one year
minimum (NF-012); `python -m farmerapp.jobs purge-audit-logs --tenant-id <uuid>` only reports
what a purge would remove (400-day default) until the archive + purge job lands under OPS.
