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
  tenants/        models: cluster, store, village (M1-KICKOFF; SPEC 8.2 "store / cluster")
  catalog/        crops.py: crop master + the six pilot crops (M3 adds products, SKUs, label claims)
  farmers/        models: farmer, farm (PostGIS boundary, generated centroid + area), crop_plot,
                  consent_record (append-only); schemas.py read models; GET /v1/farmers[/{id}] (WC-003 foothold)
  db/             async engine/session, tenant binding (set_tenant / tenant_scope / job_session),
                  rls.py (enable_rls for migrations, rls_violations for the meta-test), Base, models,
                  audit.py (FA-006 actor context + flush listener + redaction + audit.record),
                  geo.py (EWKT helpers, acres <-> m2; no shapely)
  worker/         Pub/Sub push receiver + dispatch table by topic (SPEC 9.2)
  jobs/           typer CLI (hello, seed = the Telangana demo tenant "fcc" + "gfl" (see "Seed data");
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

## Seed data (M1-KICKOFF, SPEC 10.5)

`make seed` (`python -m farmerapp.jobs seed [--small]`) upserts two demo tenants as the app role
under RLS, idempotently (stable `uuid5` ids; a second run creates nothing), in about a second:

| | `fcc` Future Crop Care (Telangana) | `gfl` Green Fields (Raichur, Karnataka) |
|---|---|---|
| role users | `+91900000000{1..10}`, one per role | `+91910000000{1..10}` |
| clusters | North Telangana (WGL, KNR, NZB), South Telangana (NLG, KMM) | Raichur |
| stores | WGL Warangal, KNR Karimnagar, NLG Nalgonda, KMM Khammam, NZB Nizamabad (real lat/lon) | RCR Raichur |
| field officers | 5, one per store: `+919000000004` (WGL) and `+91900000001{1..4}` | 1 (`+919100000004`) |
| store manager / cluster head | `+919000000003` → WGL, `+919000000002` → North Telangana | RCR / Raichur |
| villages | 40 (8 mandal-HQ villages per store, 6–22 km away, meeting point on every other one) | 8 |
| farmers | 200 (`+919000100001..200`, Telugu names, 40 per officer, 5 per village); farmer #1 is the demo farmer login `+919000000010` | 10 |
| farms | 1–2 per farmer, convex 0.5–5 acre polygons on a grid around the village (never overlapping), declared acres within ±7 % of `ST_Area` | same |
| crop plots | 1–2 per farm over the six pilot crops with variety, kharif 2026 (75 %) / rabi 2025-26, sowing date, stage, expected harvest | same |
| consent | `data` granted for all, `marketing` for ~60 % (8 % of those withdrawn as a second row); `farmer.consent_marketing` caches the latest | same |

The `SMALL` profile (`--small`; what the test fixtures use) keeps the structure with 15 + 4
farmers and 2 villages per store. Counts of the full profile: 3 clusters, 6 stores, 48 villages,
12 crops, 210 farmers, 285 farms, 403 crop plots, 338 consent records (`make seed` prints them).

## Farmers, farms, consent (M1 data model)

Tables `cluster`, `store`, `village`, `crop`, `farmer`, `farm`, `crop_plot`, `consent_record`
(Alembic `0005`), all with the base columns and RLS. Notes for the loop:

- `farmer` is unique on `(tenant_id, phone)` (FA-012); `phone_last4` is a searchable
  stand-in for when SEC-026 encrypts the number; `registered_by` (officer) and `user_id`
  (the farmer's own login) drive the SPEC 2.6 scope; `village.store_id` maps a farmer to a
  store, `store.cluster_id` to a cluster.
- `farm.boundary` is `geography(Polygon, 4326)` written as EWKT (`farmerapp.db.geo`);
  `farm.centroid` and `farm.area_acres_computed` are **stored generated columns** (`ST_Centroid`,
  `ST_Area / 4046.8564224`) loaded with `eager_defaults`, so VA-F02/VA-F03 checks (centroid
  within 50 m, declared vs measured acres, overlap) are SQL over indexed columns. Reads get
  `boundary_geojson`, `centroid_lat/lon` as column properties.
- `consent_record` is append-only (FM-002): a withdrawal is a new row with `withdrawn_at`;
  the newest row per `(subject_id, purpose)` is the state; `created_at` is the wall clock.
- `GET /v1/farmers` / `GET /v1/farmers/{id}` (farms with crop plots, consent history) use
  `farmerapp.auth.scope.farmer_filters(actor)`; the agronomist gets a masked phone and no
  landmark.

## Farmer registration writes (FA-012 / FA-013)

`POST /v1/farmers` registers a farmer with nested `farms[{boundary GeoJSON, area_acres, soil,
irrigation, ownership, photos: [blob_uri], crop_plots[]}]` and `consents[{purpose, granted}]`
in one request (field officer, store manager, cluster head, tenant admin); then
`PATCH /v1/farmers/{id}`, `POST /v1/farmers/{id}/farms`, `PATCH|DELETE /v1/farms/{id}`,
`POST /v1/farms/{id}/crop-plots`, `PATCH|DELETE /v1/crop-plots/{id}` (soft deletes) and
`POST /v1/farmers/{id}/consents` (append a grant or withdrawal). Everything goes through
`farmerapp/farmers/service.py`, which `POST /v1/sync` shares. Inline checks (SPEC 6.2):

- VA-F01: E.164 Indian mobile (normalised), duplicate `(tenant, phone)` -> `409
  farmer_phone_exists`, staff phone -> `422 farmer_phone_is_staff`. Phone verification:
  `POST /v1/farmers/phone/verify/send {phone}` + `/confirm {phone, code}` return a 30-minute
  `phone_verification_token` (HS256 JWT bound to tenant + phone, `farmerapp/farmers/phone_verify.py`)
  that `POST /v1/farmers` or a sync `farmer.create` op presents to get `phone_verified: true`;
  without it the farmer is registered unverified (offline capture) and verified later with
  `POST /v1/farmers/{id}/phone/verify/send|confirm`. Same OTP limits/lockout as login
  (purpose `farmer_register`).
- VA-F03: `ST_IsValid` -> `422 farm_boundary_invalid` (detail carries PostGIS' reason);
  declared vs measured acres outside ±30 % -> `warnings: ["area_mismatch"]`; overlap with
  another farmer's farm above 20 % -> `warnings: ["farm_overlap"]`. Warnings never reject
  (per farm and as the union on the farmer response).

Every POST honours `Idempotency-Key` (`farmerapp/api/idempotency.py`): the response is stored
24 h per `(tenant, actor, key)` and replayed for the same body; a different body is
`422 idempotency_key_reuse`; errors are not cached. Decorate an endpoint with
`@idempotent(status_code=...)` under the route decorator (it needs `request`, `session`,
`actor` parameters).

## Sync (FA-025 / NF-003)

`POST /v1/sync {device_id, cursor, ops[]}` (field officer, store manager, cluster head,
farmer; ≤ 200 ops) applies outbox operations `{op_id, entity, action, entity_id,
base_version, payload, client_ts}` in order, each in its own SAVEPOINT, and returns
`results[]` (`applied | duplicate | conflict | rejected`, `version`, problem-style `error`,
`server` state) plus `changes[]` since the cursor. `farmerapp/sync/service.py`:

- `op_id` idempotency: results are stored in `sync_op`; a replay returns `duplicate` with
  the original result.
- Conflict rules `CONFLICT_RULES`: farmer / farm / crop_plot `last_writer_wins`
  (`base_version` mismatch is applied when `client_ts` is newer than `updated_at`, else
  `conflict` with the server state); `server_wins` reserved for khata / payments and used
  for the append-only consent record; `merge_fields` reserved.
- Change feed: `sync_change` (append-only, `seq` identity) is written by the flush hook
  `farmerapp/sync/changes.py` registered on the FA-006 audit listener, so REST, sync and
  jobs all feed it. Reads are scoped with `farmer_filters` (officer: own farmers' entities;
  farmer: own), collapsed to the latest state per entity, capped at 500 with `has_more`;
  soft-deleted rows come back as `action: delete` with `{id, deleted_at}`. The cursor is
  the base64 of the last `seq`.

## Uploads and blobs (NF-003 / SEC-016)

Resumable 256 KB chunked uploads: `POST /v1/uploads {sha256, size_bytes, content_type,
purpose, chunk_size: 262144}` -> `{upload_id, received_chunks, expires_at}`; `PUT
/v1/uploads/{id}/chunks/{index}` (raw body + `X-Chunk-Sha256`, any order, re-PUT is fine);
`GET /v1/uploads/{id}` for resume; `POST /v1/uploads/{id}/complete` verifies the whole-file
sha256 and returns `{blob_uri, sha256, size_bytes, content_type}`. Chunks are staged as
`bytea` in `upload_chunk` (15-minute TTL, `python -m farmerapp.jobs purge-expired
--tenant-id …` also drops expired idempotency keys). Blobs land in a `BlobStore`
(`farmerapp/uploads/blobstore.py`) under `gs://<bucket>/<tenant>/<purpose>/<sha256>`:
`BLOB_STORE=local` (directory; unit tests) or `BLOB_STORE=fake_gcs` (compose
`gcs` service, bucket `photos`; `pytest -m integration` covers it). `GET
/v1/blobs/signed-url?uri=` returns a 15-minute URL — a plain media URL for the fake / local
stores; real V4 signing is the `GcsBlobStore` seam for SEC-016 (M5). `farm_photo` rows
reference completed uploads (`photos: [blob_uri]` on a farm).

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
