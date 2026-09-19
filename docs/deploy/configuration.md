# Deployed configuration: api, worker, jobs, migrate

Every setting the backend reads (`apps/api/farmerapp/settings.py`, plus `ANTHROPIC_API_KEY`,
which the Anthropic SDK reads), where Cloud Run gets it, and which process needs it. A Cloud Run
revision of api / worker / every job starts in dev, stg and prd with **only Terraform variables
and Secret Manager values**: nothing is edited by hand, and deploys (`deploy.yml`) change images,
never env vars.

## How it stays true

| Layer | What it does |
|---|---|
| `settings.py` `CLOUD_REQUIRED_ENV` / `CLOUD_REQUIRED_JOB_ENV` / `CLOUD_FORBIDDEN_ENV` | The contract: names each process (by `SERVICE_NAME`) must receive in the cloud, and dev-only names it must not. |
| `settings.py` `_prd_guard_rails` | In prd the process refuses to start on a dev default, scoped to what it uses (`SERVICE_NAME`; an unknown name gets the api's full checks). |
| `infra/envs/*/main.tf` `local.env_parts` / `env_layers` / `secret_env` / `job_secret_env` | The only place values are set. Secret accessors (`local.secrets`) are derived from the mounts, so a process reads exactly the secrets it mounts. |
| `local.required_env` / `job_required_env` / `forbidden_env` + `modules/run_service`, `modules/run_job` `contract.tf` | Preconditions: `terraform plan` fails when a service or job lacks a required name, gets a forbidden one, or gets a name both plain and secret. Proved by `terraform test` in both modules (`infra/scripts/check.sh`). |
| `apps/api/tests/deploy/test_terraform_env.py` | Parses the HCL (python-hcl2): the Terraform lists equal `settings.py`; every process and every job gets every required name; every deployed name is a real setting (no more `DB_HOST` / `ENV`); modules are wired to the maps; the rendered env of each process builds `Settings` in prd mode; embed invokers = embed callers; `deploy.yml` updates every job; every setting has a row below. |

`cd apps/api && uv run python -m scripts.terraform_env <dev|stg|prd> <api|worker|jobs|migrate> [job]`
prints a process's env as Terraform renders it (fake secrets, stand-ins for plan-time values):
`docker run --env-file` with it reproduces a Cloud Run start locally (see "Local prd-like run").

## Sources

* **TF** — plain env set by Terraform (`local.env_parts`); the value is a literal, a variable
  (`terraform.tfvars` / `variables.tf` default) or another module's output.
* **SM `<id>`** — Secret Manager secret `<id>`, mounted as `latest` (created empty by Terraform;
  an admin adds versions: `gcloud secrets versions add <id> --data-file=-`). Every mounted
  secret needs a version before its service / job can start.
* **image** — set in the Dockerfile.
* **default** — not set in the cloud; the `Settings` default applies everywhere.
* **local** — local / CI only; Terraform must never set it (plan fails, `forbidden_env`).

Processes: **A** api, **W** worker, **J** jobs (every `python -m farmerapp.jobs` Cloud Run job),
**M** migrate job (`alembic upgrade head` from the api image). "Required" = in
`CLOUD_REQUIRED_ENV` (dev, stg and prd alike) and enforced by the plan preconditions; **prd
guard** = the process also refuses to start in prd without a real value.

## Runtime and identity

| Env var | Source | dev / stg / prd value | Needed by | Required |
|---|---|---|---|---|
| `APP_ENV` | TF `var.env` | `dev` / `stg` / `prd` | A W J M | yes |
| `SERVICE_NAME` | TF (per process) + image (worker, jobs) | `api` / `worker` / `jobs` / `migrate` | A W J M | yes (scopes the prd guard rails) |
| `LOG_LEVEL` | TF `var.log_level` | `INFO` | A W J M | no |
| `LOG_JSON` | TF | `true` | A W J M | yes |
| `GCP_PROJECT` | TF `var.project_id` | `farmerapp-dev` / `-stg` / `-prd` | A W J M | yes |
| `OTEL_EXPORTER` | TF | `gcp` (Cloud Trace; `roles/cloudtrace.agent` on every SA) | A W J M | yes |
| `OTEL_SAMPLE_RATIO` | TF `var.otel_sample_ratio` | `1` (default; lower in prd when volume grows) | A W J M | no |
| `RULES_DIR` | image | `/app/rules` | A W J | no |

## Database (SEC-011: private IP, IAM auth, separate migrate identity)

| Env var | Source | dev / stg / prd value | Needed by | Required |
|---|---|---|---|---|
| `DB_IAM_AUTH` | TF | `true` | A W J M | yes |
| `DB_INSTANCE_CONNECTION_NAME` | TF `module.sql.connection_name` | `farmerapp-<env>:asia-south1:farmerapp-<env>` | A W J M | yes (prd guard with IAM) |
| `DB_IP_TYPE` | TF | `private` | A W J M | yes |
| `DB_USER` | TF `local.db_users` (SA email minus `.gserviceaccount.com`) | `farmerapp-api@farmerapp-<env>.iam`, `farmerapp-worker@…`, `farmerapp-jobs@…`, `farmerapp-migrate@…` | A W J M | yes (prd guard: only `migrate` may be `farmerapp-migrate@…`, and it must be) |
| `DB_NAME` | TF `module.sql.database_name` | `farmerapp` | A W J M | yes |
| `DB_POOL_SIZE` / `DB_MAX_OVERFLOW` | TF `var.db_pool` through `module.db_budget` | api `2` / `1`, worker `2` / `0`, jobs `1` / `1` in every env (see "Connection budget") | A W J | no (the plan fails when the budget is exceeded) |
| `DB_ECHO` | default | `false` | A W J | no |
| `DATABASE_URL` / `MIGRATION_DATABASE_URL` | local | compose URLs with dev passwords | local, CI | **forbidden** in the cloud |

### Connection budget

Each api / worker instance and each job task opens its own SQLAlchemy pool of up to
`DB_POOL_SIZE + DB_MAX_OVERFLOW` connections (the app defaults 5 + 10 on 20 api instances alone
are 300 against prd's 200). `module.db_budget` (`infra/modules/db_budget`) sizes them per
environment from `var.db_pool` and fails `terraform plan` (precondition on its `env` output)
unless

```
  sum over api, worker, jobs of  instances x (pool_size + max_overflow)  +  reserve
      <=  floor(max_connections x 80 / 100)
```

* `instances` = `var.max_instances.api` / `.worker` (Cloud Run scale-out ceiling); for jobs,
  the number of Cloud Run jobs (`length(local.jobs)`, 11), each one task, all assumed to
  overlap. Console and embed hold no database pool.
* `reserve` = 20: the migrate job (NullPool, one connection), Datastream, Cloud SQL Studio,
  `gcloud sql connect` and admins.
* `max_connections` = `var.sql_max_connections`, now also set as the `max_connections`
  database flag on the primary and the replica (`modules/sql`), so the budget uses the value the
  instance really has; the OPS-003 alert still fires at 80% of it.
* `pool_size + max_overflow >= 2` per process (variable validation): a tenant-bound session
  holds one connection while `ensure_tenant_key` loads the tenant's data key on a second one
  (`farmerapp/pii/keys.py`).
* `terraform test` in `infra/modules/db_budget` proves the check (fits, exactly at the
  ceiling, the app defaults and one connection over fail, a pool below 2 is refused);
  `tests/deploy/test_terraform_env.py` recomputes each env from its tfvars and checks this
  table.

| env | max_connections | api | worker | jobs | reserve | total | 80% ceiling |
|---|---|---|---|---|---|---|---|
| dev | 100 (flag; the db-g1-small default of 50 cannot hold 11 jobs + the reserve) | 3 x (2 + 1) = 9 | 2 x (2 + 0) = 4 | 11 x (1 + 1) = 22 | 20 | 55 | 80 |
| stg | 100 | 5 x (2 + 1) = 15 | 5 x (2 + 0) = 10 | 11 x (1 + 1) = 22 | 20 | 67 | 80 |
| prd | 200 | 20 x (2 + 1) = 60 | 20 x (2 + 0) = 40 | 11 x (1 + 1) = 22 | 20 | 142 | 160 |

dev and stg now set `max_instances` in their tfvars (dev api 3 / worker 2, stg api 5 /
worker 5; console and embed lowered alike); prd keeps the defaults (api 20, worker 20). To scale
further, raise `sql_max_connections` (a flag change restarts the instance: human apply in stg /
prd) or the tier, then the pools; the plan tells you when a change does not fit. Setting the
flag is itself a restart on the first apply after this change.

The connector (`farmerapp/db/connect.py`, `cloud-sql-python-connector[asyncpg]`) is created
in the running event loop on the first connection, with lazy certificate refresh (Cloud Run CPU
throttling), and logs in with an IAM token of the runtime service account. Alembic uses the
same path when `DB_IAM_AUTH=true` (`alembic/env.py`). With `DB_IAM_AUTH` unset (local, CI) the
two URLs are used exactly as before.

## Storage, PII, payments, diagnosis (api, worker, jobs)

| Env var | Source | dev / stg / prd value | Needed by | Required |
|---|---|---|---|---|
| `BLOB_STORE` | TF | `gcs` | A W J | yes (prd guard) |
| `PHOTOS_BUCKET` | TF `module.storage` | `farmerapp-<env>-photos` | A W J | yes |
| `EXPORTS_BUCKET` | TF `module.storage` | `farmerapp-<env>-exports` | A W J | yes |
| `GCS_SIGNING_SERVICE_ACCOUNT` | TF `module.iam.emails.api` | `farmerapp-api@farmerapp-<env>.iam.gserviceaccount.com` (Token Creator on itself) | A | yes |
| `PUBSUB_EMULATOR_HOST` / `STORAGE_EMULATOR_HOST` / `BLOB_LOCAL_DIR` | local | emulators / temp dir | local | **forbidden** |
| `UPLOAD_CHUNK_SIZE` / `UPLOAD_MAX_BYTES` / `UPLOAD_TTL_SECONDS` / `SIGNED_URL_TTL_SECONDS` | default | 256 KB / 20 MB / 900 / 900 | A J | no |
| `IDEMPOTENCY_TTL_SECONDS` / `PHONE_VERIFICATION_TTL_SECONDS` / `VISIT_CONFIRM_TOKEN_TTL_SECONDS` | default | 86400 / 1800 / 86400 | A J | no |
| `PII_KEK_BACKEND` | TF | `kms` | A W J | yes (prd guard) |
| `PII_KMS_KEY_NAME` | TF `module.kms.pii_key_name` | `projects/farmerapp-<env>/locations/asia-south1/keyRings/farmerapp-<env>/cryptoKeys/pii` (EncrypterDecrypter: api, worker, jobs) | A W J | yes (prd guard) |
| `PII_HASH_PEPPER` | SM `pii-hash-pepper` | >= 32 random chars, per env; never rotated without a re-hash | A W J | yes (prd guard) |
| `PII_LOCAL_KEK` | local | dev key | local, CI | **forbidden** (prd guard) |
| `PII_PLAINTEXT_WRITES` | default | `false` | A W J | no (rollout switch, docs/runbooks/pii-encryption.md) |
| `PAYMENT_PROVIDER` | TF | `razorpay` | A W J | yes (prd guard refuses `fake`) |
| `PAYMENT_WEBHOOK_DELIVERY` | TF | `pubsub` (worker applies `payment.webhook`) | A W J | yes |
| `RAZORPAY_BASE_URL` | TF `var.razorpay_base_url` | `https://api.razorpay.com` | A W J | yes |
| `RAZORPAY_KEY_ID` | SM `razorpay-key-id` | `rzp_test_…` in dev / stg, live id in prd | A W, job `reconcile-payments` | yes |
| `RAZORPAY_KEY_SECRET` | SM `razorpay-key-secret` | test / live key secret | A W, job `reconcile-payments` | yes (prd guard: A W) |
| `RAZORPAY_WEBHOOK_SECRET` | SM `razorpay-webhook-secret` | Razorpay dashboard webhook secret | A W | yes (prd guard) |
| `PAYMENT_QR_TTL_SECONDS` | default | 900 | A | no |
| `MOCK_RAZORPAY_WEBHOOK_SECRET` / `MOCK_RAZORPAY_KEY_ID` | local (docker/mockserver) | test values | local | **forbidden** |
| `DIAGNOSIS_ENCODER` | TF | `remote` (the `embed` service; `fake` only locally) | A W J | yes (prd guard) |
| `DIAGNOSIS_ENCODER_NAME` / `DIAGNOSIS_ENCODER_VERSION` | TF `var.diagnosis_encoder_name` / `_version` | `siglip-base-patch16-224` / `2024-01` (also `EMBED_MODEL` / `EMBED_VERSION` on `embed`) | A W J | yes |
| `DIAGNOSIS_EMBED_URL` | TF `module.embed.uri` | `https://embed-…run.app` (internal ingress; invokers = api, worker, jobs SAs) | A W J | yes |
| `DIAGNOSIS_LLM` | TF `var.diagnosis_llm` | `claude` (or `off`; prd guard refuses `fake`) | A W J | yes |
| `DIAGNOSIS_LLM_MODEL` | TF `var.diagnosis_llm_model` | `claude-opus-5` | A W J | yes |
| `DIAGNOSIS_DELIVERY` | TF | `pubsub` (worker runs the pipeline) | A W J | yes |
| `ANTHROPIC_API_KEY` | SM `anthropic-api-key` | Anthropic key (read by the SDK) | W | yes |
| `DIAGNOSIS_EMBED_TIMEOUT_S` / `DIAGNOSIS_LLM_MAX_TOKENS` / `DIAGNOSIS_LLM_EFFORT` / `DIAGNOSIS_KNN_K` / `DIAGNOSIS_HNSW_EF_SEARCH` / `DIAGNOSIS_MAX_ATTEMPTS` | default | 20 / 16000 / `medium` / 20 / 40 / 5 | A W J | no |
| `PLAY_INTEGRITY_MODE` / `PLAY_INTEGRITY_PACKAGE_NAMES` / `PLAY_INTEGRITY_TIMEOUT_S` | default | `off` / both app ids / 2.0 (`google` is a human gate, SEC-024) | A | no |

## Auth and API edge (api)

| Env var | Source | dev / stg / prd value | Needed by | Required |
|---|---|---|---|---|
| `JWT_SIGNING_KEY` | SM `jwt-signing-key` | >= 32 random chars per env (`openssl rand -base64 48`) | A | yes (prd guard) |
| `OTP_PEPPER` | SM `otp-pepper` | >= 32 random chars per env | A | yes (prd guard) |
| `OTP_PROVIDER` | TF | `mockserver` = the generic HTTP adapter (the only non-test one today) | A | yes (prd guard refuses `fake`) |
| `SMS_PROVIDER_URL` | SM `otp-sms-provider-url` | the SMS gateway endpoint (may embed its auth key) | A | yes |
| `WHATSAPP_PROVIDER_URL` | SM `otp-whatsapp-provider-url` | the WhatsApp gateway endpoint | A | yes |
| `OTP_DEV_CODE` | local | `123456` locally | local (allowed, but not set, in dev) | **forbidden** in stg / prd (prd guard) |
| `OTP_TTL_SECONDS` / `OTP_MAX_ATTEMPTS` / `OTP_LOCKOUT_SECONDS` / `OTP_MAX_RESENDS` / `OTP_RESEND_WINDOW_SECONDS` / `OTP_RESEND_AFTER_SECONDS` / `OTP_WHATSAPP_FALLBACK_SECONDS` | default | 300 / 5 / 900 / 3 / 900 / 30 / 30 | A | no |
| `JWT_ALGORITHM` / `JWT_ISSUER` | default | `HS256` / `farmerapp` | A | no |
| `ACCESS_TOKEN_TTL_SECONDS` / `REFRESH_TOKEN_TTL_SECONDS` / `STEP_UP_TOKEN_TTL_SECONDS` / `SECURITY_CACHE_TTL_SECONDS` | default | 900 / 30 d / 300 / 30 | A | no |
| `CORS_ORIGINS` | TF | `["https://console.<domain>"]` | A | yes |

Worker Pub/Sub push auth: the worker has no setting for it. Each `<topic>.worker` push
subscription sends an OIDC token of `farmerapp-pubsub-push` with audience = the worker's
`run.app` URL (`modules/pubsub`); Cloud Run verifies it (worker ingress internal-only, invoker =
that SA only), so the app never sees an unauthenticated push.

Not app settings: the console (`API_URL`, `NEXT_PUBLIC_API_URL`, `ENV`) and `embed` (`ENV`,
`CORPUS_BUCKET`, `EMBED_MODEL`, `EMBED_VERSION`, port 8080) have their own env in `main.tf`.

## Secrets per environment (create a version of each before the first apply of a service)

| Secret | Readers (derived) | Content |
|---|---|---|
| `jwt-signing-key` | api | HS256 key, >= 32 chars |
| `otp-pepper` | api | OTP HMAC pepper, >= 32 chars |
| `pii-hash-pepper` | api, worker, jobs | phone-hash pepper, >= 32 chars (never change without a re-hash) |
| `otp-sms-provider-url` / `otp-whatsapp-provider-url` | api | gateway endpoints |
| `razorpay-key-id` / `razorpay-key-secret` | api, worker, jobs | Razorpay key pair (test mode outside prd) |
| `razorpay-webhook-secret` | api, worker | webhook HMAC secret |
| `anthropic-api-key` | worker | Anthropic API key |
| `otp-provider` | api (not mounted) | reserved for the DLT SMS / WhatsApp adapter config |

## First deploy of an environment (human; stg / prd apply is human-only)

1. `terraform apply` of the network, IAM, SQL, KMS and secrets (the services fail to create
   until their secrets have versions): add a version to every secret above.
2. As the instance's built-in `postgres` user (Cloud SQL Studio or `gcloud sql connect`), make the
   migrate identity the owner (statements in `infra/modules/sql/main.tf`):
   `GRANT cloudsqlsuperuser TO "farmerapp-migrate@<project>.iam"`,
   `ALTER DATABASE farmerapp OWNER TO "farmerapp-migrate@<project>.iam"`,
   `GRANT ALL ON SCHEMA public TO "farmerapp-migrate@<project>.iam"`.
3. Run the `migrate` job (deploy.yml does it on every deploy).
4. `GRANT farmerapp_app TO "farmerapp-api@<project>.iam", "farmerapp-worker@<project>.iam",
   "farmerapp-jobs@<project>.iam"`.
5. Deploy the images (deploy.yml): api, worker, console, jobs.

## Local prd-like run

```bash
docker build -f apps/api/Dockerfile -t farmerapp-api .
(cd apps/api && uv run python -m scripts.terraform_env prd api) > /tmp/api.env
docker run --rm --env-file /tmp/api.env -p 8000:8000 farmerapp-api
```

Result (2026-09-19): `Settings` validates in prd mode for api, worker, jobs (all 11) and
migrate. The only failures are the documented cloud-only dependencies, each with Google's
`DefaultCredentialsError` ("Your default credentials were not found"):

* `OTEL_EXPORTER=gcp` — the Cloud Trace exporter needs Application Default Credentials at
  startup (Cloud Run: the runtime SA via the metadata server);
* with `-e OTEL_EXPORTER=none` the api and worker start and `/v1/health` answers
  `{"status":"ok","env":"prd"}`; the first database call fails in the Cloud SQL connector
  (credentials, then the private IP only reachable from the VPC); `alembic upgrade head` of the
  migrate env fails the same way. Cloud KMS (tenant data keys) is next in line after the first
  tenant-bound query and needs the same runtime credentials.
