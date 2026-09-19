# infra/ — FarmerApp Terraform

One GCP project per environment (`farmerapp-dev`, `farmerapp-stg`, `farmerapp-prd`)
plus the shared `farmerapp-ops` project for state, Artifact Registry and CI identity.
Layout is SPEC section 9.1; per-env sizing is SPEC 9.2 and lives in `envs/<env>/terraform.tfvars`.

```
infra/
  bootstrap/      ops project: tfstate bucket, Artifact Registry, WIF pool + GitHub OIDC,
                  deployer SAs, SA-key org policy           (run once, by a human)
  modules/        network sql run_service run_job pubsub storage lb secrets analytics monitoring iam
  envs/dev stg prd   main.tf (identical), variables.tf, terraform.tfvars (differs), backend.tf
  scripts/check.sh   fmt + validate (+ tflint/checkov when installed)
```

## Rules (SPEC 9.7, CLAUDE.md)

- `terraform fmt`, `validate`, `tflint`, `checkov` run on every PR touching `infra/` (`ci-infra.yml`);
  the dev plan is posted as a PR comment.
- **dev**: applied from CI on merge once WIF is configured.
- **stg / prd**: `terraform apply` is **human-only**, after review and approval. CI never plans-with-apply
  or applies these environments; `drift.yml` only runs `plan` and opens an issue.
- No secret values in state: `modules/secrets` creates secrets **empty**; an admin adds versions with
  `gcloud secrets versions add <id> --project <project> --data-file=-`.
- Images are set by CI (`deploy.yml`); `run_service`/`run_job` ignore later image changes.
- Data residency: everything in `asia-south1` (backups copied to `asia-south2` in prd).

## Bootstrap order (once)

Prerequisites: billing account, org/folder, and the `farmerapp-ops` project created by hand
(SPEC 9: "nothing is created by hand except billing and the org" — the ops project itself is the one exception).
The person running this needs Owner on `farmerapp-ops` and, for `create_projects = true`, Project Creator
on the folder and Billing User on the billing account.

```bash
cd infra/bootstrap
# edit terraform.tfvars: github_repository = "<org>/farmerapp"
terraform init -backend=false          # bucket does not exist yet → local state
terraform apply
terraform init -migrate-state          # move state into gs://farmerapp-ops-tfstate/bootstrap
rm -f terraform.tfstate*
terraform output                       # wif_provider, build_sa_email, deployer_sa_emails
```

Then set GitHub repository variables (Settings → Secrets and variables → Actions → Variables):

| Variable        | Value from `terraform output`      |
|-----------------|------------------------------------|
| `WIF_PROVIDER`  | `wif_provider`                     |
| `BUILD_SA`      | `build_sa_email`                   |
| `DEPLOY_SA_DEV` | `deployer_sa_emails["dev"]`        |
| `DEPLOY_SA_STG` | `deployer_sa_emails["stg"]`        |
| `DEPLOY_SA_PRD` | `deployer_sa_emails["prd"]`        |

Every GCP step in the workflows is guarded with `if: vars.WIF_PROVIDER != ''`, so nothing talks to
GCP until these exist. Create GitHub environments `dev`, `staging`, `production` and `play-internal`;
add required reviewers on `staging`, `production` and `play-internal`.

Then the first dev apply (human, once; CI takes over afterwards):

```bash
cd infra/envs/dev
terraform init
terraform apply
openssl rand -base64 48 | gcloud secrets versions add jwt-signing-key --project farmerapp-dev --data-file=-
# … and otp-pepper, pii-hash-pepper (>= 32 chars each), otp-sms-provider-url, otp-whatsapp-provider-url,
# razorpay-key-id, razorpay-key-secret, razorpay-webhook-secret, anthropic-api-key: every mounted secret
# needs a version before its service / job can start (docs/deploy/configuration.md)
```

Point DNS `api.dev.farmerapp.in` and `console.dev.farmerapp.in` at `terraform output lb_ip`; the managed
certificate provisions after DNS resolves.

## Day to day

```bash
cd infra && ./scripts/check.sh      # what CI runs: fmt, validate ×4, tflint, checkov (SKIP if absent)
make plan-dev                       # = cd infra/envs/dev && terraform plan (needs gcloud auth + bucket access)
```

`make plan-dev` needs `gcloud auth application-default login` with an identity that can read the state
prefix `envs/dev/` and `roles/viewer` on `farmerapp-dev`.

Tooling: `brew install terraform tflint` and `pipx install checkov`. `check.sh` prints `SKIP` for
tools that are missing so it still passes locally; CI always runs all four.

## What each env creates (envs/*/main.tf)

| Piece | Module | Notes |
|---|---|---|
| VPC, subnet, Cloud NAT, PSA, deny-all ingress | `network` | Direct VPC egress from Cloud Run, no connector |
| Per-service SAs + observability roles | `iam` | api, worker, jobs, migrate (SEC-011 DDL identity), console, embed, pubsub-push, scheduler |
| Postgres 16, private IP only, TLS `ENCRYPTED_ONLY`, IAM auth (`cloudsql.iam_authentication=on`, `google_sql_user` per SA), logical decoding, PITR/HA in prd, replica in prd | `sql` | SPEC 9.4 verbatim; SEC-011 |
| Secrets, created empty | `secrets` | derived from the per-process mounts (`local.secret_env`): jwt-signing-key, otp-pepper, pii-hash-pepper, otp-sms/whatsapp-provider-url, razorpay-*, anthropic-api-key (worker only); otp-provider reserved |
| PII key-encryption key (SEC-026) | `kms` | key ring `farmerapp-<env>`, key `pii`, 90-day rotation, encrypter/decrypter for api / worker / jobs |
| photos / exports / corpus buckets with 9.2 lifecycle rules | `storage` | private, uniform access |
| api, console, worker, embed | `run_service` | ingress internal-LB (api/console, invoker IAM disabled: the LB is the only path, SEC-015) or internal-only (worker/embed); min 1/1 api/console in prd (NF-006) |
| migrate + 11 jobs (`python -m farmerapp.jobs <command>`) | `run_job` | Cloud Scheduler in Asia/Kolkata: run-rules 02:00, flags-sla hourly, sync-silence /15 min, auto-end-duty /10 min, ensure-partitions 00:30, purge-location-points 04:00 (`--apply` prd only), purge-expired hourly, store-day-watch 22:15, diagnosis-queue-age hourly, reconcile-payments 06:00, backfill-farm-photo-phash manual. Per-tenant jobs need `job_tenant_ids`. The migrate job runs as the `migrate` SA |
| 7 topics, each with `.dlq` + push sub to worker | `pubsub` | 7-day retention, 5 attempts |
| HTTPS LB, managed cert, Cloud Armor (OWASP CRS, OTP 5/min/IP, login 10/min/IP, India geo for field APIs; stg preview, prd enforce), optional console IAP | `lb` | SEC-014/015; reCAPTCHA bot management is a TODO needing keys |
| BigQuery datasets; Datastream CDC when enabled | `analytics` | `datastream_enabled=false` in dev until M7 |
| Uptime checks, OPS-001..005 alerts, SLOs + burn-rate alerts, log-based metrics, platform / business / cost dashboards, Data Access audit logs -> locked 400-day bucket | `monitoring` | SPEC 12, SEC-017; reference `docs/runbooks/observability.md` |

Database roles (SEC-011, FA-003): Terraform only creates the IAM users. Migration 0003
(`apps/api/alembic/versions/0003_rls_roles.py`, run by the `migrate` job as the owner) creates
the Postgres groups `farmerapp_app` (DML only, RLS) and `farmerapp_migrate` (DDL). Once per
environment an admin grants membership: api/worker/jobs SAs → `farmerapp_app`, the migrate
job's SA → `farmerapp_migrate` (statements in `modules/sql/main.tf`). The runtime must never
be a member of `farmerapp_migrate`. The app connects with the Cloud SQL Python Connector and IAM
auth (`DB_IAM_AUTH=true`, `DB_INSTANCE_CONNECTION_NAME`, `DB_USER`, `DB_NAME`); the migrate job
runs as its own `farmerapp-migrate` SA. No password URL is deployed anywhere.

App settings: every env var of api / worker / jobs / migrate, its source and per-env value is in
[docs/deploy/configuration.md](../docs/deploy/configuration.md). `local.required_env` in
`envs/*/main.tf` mirrors `CLOUD_REQUIRED_ENV` in `apps/api/farmerapp/settings.py`; the
`run_service` / `run_job` preconditions fail the plan when a service lacks one (or receives a
dev-only name), `terraform test` in those modules proves the preconditions, and
`apps/api/tests/deploy/test_terraform_env.py` fails when Terraform and `settings.py` drift apart.

Bootstrap also holds the SEC-018 project-level org policies (`bootstrap/security.tf`: India-only
resource locations on the env projects, `sql.restrictPublicIp`, `compute.requireOsLogin`,
domain-restricted sharing when `allowed_policy_member_customer_ids` is set) and the SEC-019 SCC
notification config (`scc_notifications_enabled`, off until SCC Standard is activated on the org).
They need `roles/orgpolicy.policyAdmin` / SCC org permissions, so a human applies them.

Open items to verify on the first real dev apply: `gcp.resourceLocations` may need `global`
added if a global resource is refused; `sql_max_connections` per env must match
`SHOW max_connections`; worker → embed calls with `PRIVATE_RANGES_ONLY`
egress and `INGRESS_TRAFFIC_INTERNAL` (may need `egress = "ALL_TRAFFIC"` on the worker); Cloud Armor
bot management on OTP endpoints needs reCAPTCHA Enterprise keys (TODO in `modules/lb`).
