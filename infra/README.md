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
# … repeat for otp-provider, razorpay-key-id, razorpay-key-secret, razorpay-webhook-secret, llm-api-key
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
| Per-service SAs + observability roles | `iam` | api, worker, jobs, console, embed, pubsub-push, scheduler |
| Postgres 16, private IP, IAM auth, logical decoding, PITR/HA in prd, replica in prd | `sql` | SPEC 9.4 verbatim |
| Secrets, created empty | `secrets` | otp-provider, razorpay-*, llm-api-key, jwt-signing-key |
| photos / exports / corpus buckets with 9.2 lifecycle rules | `storage` | private, uniform access |
| api, console, worker, embed | `run_service` | ingress internal-LB (api/console) or internal (worker/embed) |
| migrate + 5 nightly jobs (02:00 IST onwards) | `run_job` | Cloud Scheduler, Asia/Kolkata |
| 7 topics, each with `.dlq` + push sub to worker | `pubsub` | 7-day retention, 5 attempts |
| HTTPS LB, managed cert, Cloud Armor (stg preview, prd enforce) | `lb` | SEC-014/015 |
| BigQuery datasets; Datastream CDC when enabled | `analytics` | `datastream_enabled=false` in dev until M7 |
| Uptime checks, OPS-003/004/005 alerts, audit log bucket (400 d), dashboard | `monitoring` | SEC-017 |

Open items to verify on the first real dev apply: worker → embed calls with `PRIVATE_RANGES_ONLY`
egress and `INGRESS_TRAFFIC_INTERNAL` (may need `egress = "ALL_TRAFFIC"` on the worker); Cloud Armor
bot management on OTP endpoints needs reCAPTCHA Enterprise keys (TODO in `modules/lb`).
