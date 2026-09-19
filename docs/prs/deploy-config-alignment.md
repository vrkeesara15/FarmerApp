# Deploy configuration alignment: Cloud Run env = Settings, IAM database auth, drift check (SEC-011, SEC-013, SEC-026, NF-014)

Branch `chore/deploy-config-alignment` (from `chore/M6-followups` at `6e39a62`). Resolves
M6-followups item 5: Terraform passed `DB_HOST` / `DB_NAME` / `ENV` / `DB_ROLE` / `PUBLIC_URL` /
`CORPUS_BUCKET` / `GCP_REGION` (none read by the app), mounted the `otp-provider` secret as
`OTP_PROVIDER` (a `mockserver | fake` literal: the api would not have started), and set no
`APP_ENV`, `DATABASE_URL`, `OTEL_EXPORTER`, `BLOB_STORE`, `PII_*`, `OTP_PEPPER`,
`PAYMENT_*`, `RAZORPAY_BASE_URL` or `CORS_ORIGINS`. The prd guard rails also applied every check
to every process, so the worker, jobs and migrate would have needed the api's JWT key.

The table of every setting (source, per-env value, process) is
[docs/deploy/configuration.md](../deploy/configuration.md).

## App (`apps/api`)

* **IAM database auth** — `farmerapp/db/connect.py`: with `DB_IAM_AUTH=true` the engine (and
  Alembic, `alembic/env.py`) connects through `cloud-sql-python-connector[asyncpg]` to
  `DB_INSTANCE_CONNECTION_NAME` over `DB_IP_TYPE` (private), as `DB_USER` on `DB_NAME`, with an
  IAM token of the runtime SA; the connector is created lazily in the running loop with
  `refresh_strategy="lazy"`. Without it, `DATABASE_URL` / `MIGRATION_DATABASE_URL` exactly as
  before (local, CI unchanged). New dependency: `cloud-sql-python-connector[asyncpg]`;
  dev: `python-hcl2`.
* **Contract** in `settings.py`: `CLOUD_REQUIRED_ENV` (per `SERVICE_NAME`: api, worker, jobs,
  migrate), `CLOUD_REQUIRED_JOB_ENV` (reconcile-payments: Razorpay keys),
  `CLOUD_FORBIDDEN_ENV` (+ `OTP_DEV_CODE` in stg / prd).
* **prd guard rails scoped** by `SERVICE_NAME` to what the process uses (unknown name = the
  api's full checks); new IAM checks: `DB_INSTANCE_CONNECTION_NAME` + `DB_USER` required, only
  the migrate job may (and must) log in as `farmerapp-migrate@…` (SEC-011). The two-URL role
  check still applies without IAM.
* `scripts/terraform_env.py`: reads the env maps from `infra/envs/<env>/main.tf` and prints a
  process's env (fake secrets) for `docker run --env-file`.
* Tests: `tests/test_db_connect.py` (URL mode unchanged, connector kwargs, one connector per
  process, engine URL without password, NullPool for Alembic, ip types, missing instance / user),
  `tests/deploy/test_terraform_env.py` (drift check, see below), guard-rail scoping and IAM
  tests in `tests/auth/test_settings.py`.

## Infra

* `envs/*/main.tf` (identical): `local.env_parts` (base / runtime / diagnosis / per process),
  `env_layers`, `service_env`; `secret_env` per process + `job_secret_env`; accessors of every
  secret derived from the mounts; `required_env` / `job_required_env` / `forbidden_env`. api,
  worker, migrate and every job get their maps, contract and identity.
* New secrets `otp-pepper`, `pii-hash-pepper`, `otp-sms-provider-url`,
  `otp-whatsapp-provider-url`; `otp-provider` kept (api) but no longer mounted (reserved for the
  DLT adapter). jobs no longer read `razorpay-key-*` except through `reconcile-payments`' mount
  (the jobs SA is still the accessor).
* New module `kms`: key ring `farmerapp-<env>`, key `pii` (90-day rotation, prevent_destroy),
  EncrypterDecrypter for api / worker / jobs; `cloudkms.googleapis.com` enabled.
* New SA `farmerapp-migrate` (cloudsql.client + instanceUser only) running the migrate job, with
  its IAM database user; bootstrap grants documented in `modules/sql/main.tf`.
* `embed` invokers: + jobs SA (corpus seed / image attach), so every process with
  `DIAGNOSIS_EMBED_URL` may call it.
* `modules/run_service` / `run_job` `contract.tf`: `required_env` / `forbidden_env` inputs and
  three preconditions (missing, forbidden, plain + secret duplicate) that fail `terraform plan`;
  `terraform test` (mock providers) proves each in both modules; `scripts/check.sh` runs them.
* New variables: `log_level`, `otel_sample_ratio`, `razorpay_base_url` (https only).
* `deploy.yml`: job image loop now covers `store-day-watch` and `diagnosis-queue-age` (a test
  keeps it equal to `local.jobs`); comment: deploys change images only.

## Checks

* `cd infra && ./scripts/check.sh`: fmt, validate x4, terraform test (run_service 4/4, run_job
  4/4), tflint clean, checkov green.
* `SKIP_AUDIT=1 make check-api`: green (see commit).
* Images: api / worker / jobs built; run with the prd env rendered from Terraform (fake secrets):
  `Settings` validates for every process; failures only on cloud-only dependencies with
  `DefaultCredentialsError` (Cloud Trace exporter at startup; with `OTEL_EXPORTER=none` api and
  worker serve `/v1/health` `env=prd`, the first DB call and `alembic upgrade head` stop in the
  Cloud SQL connector).

## Human gates / follow-ups

* Before the first apply of a service: versions for every mounted secret; the SQL grants in
  docs/deploy/configuration.md "First deploy" (migrate identity as owner, then `farmerapp_app`).
* Renaming / unmounting: `otp-provider` stops being mounted; `llm-api-key` was already gone.
* Real DLT SMS / WhatsApp adapter (FA-001): until then `OTP_PROVIDER=mockserver` posts to the
  gateway URLs in the two secrets.
* Verify in dev that api / worker / jobs reach the internal-only `embed` `run.app` URL with
  Direct VPC egress `PRIVATE_RANGES_ONLY` + Private Google Access; if Cloud Run treats it as
  external, switch those services' egress to `ALL_TRAFFIC`.
* Pre-existing, not changed: several modules key `for_each` on service-account emails, which are
  unknown before the first apply (a mock-provider plan of a whole env fails on them); the first
  apply of an env may need `-target=module.iam` first.
* `ci-infra.yml` does not run `terraform test` yet (outside this change's scope); check.sh does.
  Done in docs/prs/M6-final.md.
* `DB_POOL_SIZE` x `max_instances` can exceed `sql_max_connections` in prd (20 x 15 = 300 > 200).
  Done in docs/prs/M6-final.md (connection budget enforced by the plan).
