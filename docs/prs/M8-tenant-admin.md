# M8 — WC-014 platform tenant administration, NF-007 scale evidence

Branch `feat/M8-tenant-admin`. API, infra and docs only; no console and no mobile work.

## What this adds

### WC-014 — tenant administration at the platform level

A new package, `apps/api/farmerapp/platform_admin/`, and one router mounted at `/v1/admin`.

**The role.** `platform_admin` is an eleventh `UserRole`, above `tenant_admin` and *outside*
every customer tenant: it exists only in a dedicated **platform tenant**
(`PLATFORM_TENANT_ID`, slug `platform`). The guard on every route checks the role **and** that
tenant, so a tenant that somehow wrote `role = 'platform_admin'` on one of its own users still
gets 403. Both halves are tested (`tests/platform/test_authz.py`), and the SEC-006 matrix
drives every platform route as all eleven roles.

**The registry, without a hole in the isolation model.** There is no table outside RLS. The
registry (`platform_tenant`) is an ordinary tenant table whose rows all belong to the platform
tenant, so only a platform-bound session sees them — a session bound to a customer tenant
counts zero of them, which is asserted, not assumed. Usage counters and billing statements
belong to the *subject* tenant, so the hot creation paths increment them on the connection and
binding they already hold. The platform routes reach a tenant the way a job does: `tenant_scope`.
There is no bypass mechanism, and none was added.

**Provisioning in one call.** `POST /v1/admin/tenants` creates the tenant row; its settings
with every documented default resolved (not an empty `{}`); a placeholder cluster and store at
the region's default point; the reference data (pilot crops, pest and disease master,
crop-calendar templates, the VA-F05 crop calendar, the VA-F04 service area derived from the
store); the tenant's rule-set overrides (`disabled_rules` → VA-006 `enabled = false` rows); the
first `tenant_admin` with an ordinary FA-001 OTP login; and the usage counters. The follow-up
`POST .../invite` sends that admin their first code.

**Lifecycle.** `suspend` (reversible; every live session revoked in the same transaction with
two bulk statements, no per-user loop), `resume`, `archive` (terminal — access ends, rows stay,
because NF-012 retention outlives the commercial relationship). `tenant.status` and
`platform_tenant.status` are written together and a test asserts they never disagree.
Enforcement is in `auth.deps` (a bearer token of a blocked tenant → 403 `tenant_suspended`) and
`auth.otp` (a blocked tenant sends no login code, so no session can be opened).

**Plans and limits.** The catalogue lives in code (`plans.py`: `pilot`, `growth`,
`enterprise`, `unlimited`) because a plan is a commercial contract reviewed like a rule set;
per-tenant deviations are a sparse override map on `tenant.plan_limits`. `growth` is sized at
the NF-007 average tenant (200 officers, 50,000 farmers) on purpose. Limits are enforced on
every creation path — farmers (`farmers.service.create_farmer`, so the sync registration path
too), field officers (`POST /v1/users` and role changes in `PATCH /v1/users/{id}`), photos
(checked at `POST /v1/uploads` *before* the device spends the bytes, counted at completion),
campaigns, LLM calls — and answer `409 plan_limit_exceeded` carrying `metric`, `limit`,
`current` and `plan`.

**Counters that do not count.** `usage_counter` is one row per (metric, period), moved with a
single `INSERT ... ON CONFLICT DO UPDATE SET count = count + delta`. Checking a limit is one
indexed read. Nothing on a request path runs `SELECT count(*)` over a tenant: at the NF-007
target that would be 40,000 farmers or 400,000 photos per registration. `usage-recount` (a
job) is the only place that counts, for backfilling a tenant that predates the counters — and
a test asserts the incremental value equals the counted one.

**Billing.** `POST .../statements` freezes a month: the counters as they stood, the plan and
its prices as they stood, the arithmetic done once. Money is integer paise. `GET .../statements`
lists them and `GET .../statements/{period}/csv` downloads one.

### NF-007 — scale evidence

`make scale-api` (excluded from the default run) seeds one tenant at **1/50th of the target** —
100 officers, 40,000 farmers, 40,000 visits, 400,000 photo rows, ~20,000 diagnoses and orders,
~105,000 location points — with set-based SQL in ~12 s, measures the hot paths, runs
`EXPLAIN (ANALYZE, BUFFERS)` over the big tables and **fails on a sequential scan** that reads
more than 5,000 rows of one. Full write-up, numbers, plans and extrapolation:
**`docs/perf/NF-007.md`**.

Headline: with 40,000 farmers, every list, the login, the sync pull and a diagnosis create are
**p95 under 35 ms** — flat against the same endpoints at 200 farmers (NF-005). Six indexes were
added because the plans asked for them (Alembic `0042`). One finding is *not* an index problem
and is written up rather than hidden: `GET /v1/analytics/owner-home` spends ~900 ms of Python
materialising every visit and order in the range (Postgres does its part in 15 ms), which is
inside WC-001's 3 s one request at a time and outside it at four. The fix is to aggregate in
SQL; it is named in the suite's `KNOWN_WIDE` so it cannot be quietly forgotten.

### Hygiene at scale

* RLS covers the three new tables (`enable_rls` in `0042`, `tests/rls/test_meta.py`).
* Per-tenant jobs stream: `all_tenant_ids` pages the registry 200 at a time; `run_recount` and
  `run_statements` open one transaction per tenant.
* The connection budget now carries the SaaS shape: two `terraform test` cases show prd's
  `sql_max_connections = 250` refusing api 60 / worker 40 / 17 jobs, and fitting at 500.
  `docs/deploy/configuration.md` has the note and the human gate.
* **Not done here:** scheduling `usage-recount` and `billing-statements` as Cloud Run jobs.
  Adding them to `infra/envs/*/main.tf` also requires an entry in
  `.github/workflows/deploy.yml` (`test_deploy_workflow_updates_every_job_image` enforces
  that), and `.github/` is outside this change's file scope. The CLI commands exist and are
  tested; wiring the schedules is a one-line-per-env follow-up.

## Acceptance

**WC-014 — "a new tenant is usable in under 30 minutes".**
`tests/platform/test_onboarding.py` walks create → invite → OTP login → branding → store →
officer → farmer → visit entirely through the API and writes `apps/api/onboarding-report.md`.
Measured: **491 ms for 8 API steps**. What that proves is the part a test can prove: no manual
step, no configuration file edited, no code that knows this tenant's name. The 30 minutes is
the human budget around that half-second (see "Human gates").

**NF-007 — "50 tenants, 5,000 officers, 2 million farmers, 20 million photos without
re-architecture".** Measured at one tenant's share of that, which is what every request sees:
see `docs/perf/NF-007.md`.

## Payment port — what a human must decide

`billing.BillingPaymentPort` is a one-method seam (`charge(statement) -> provider reference`)
whose only implementation, `UnconfiguredBillingPort`, raises. Nothing in the API calls it, and
`billing_statement.external_invoice_ref` stays NULL. Before it can be implemented:

1. **The entity and the provider.** SPEC 0.2 names Razorpay for *farmer* payments (FA-021).
   Platform billing is a different contract with a different counterparty and may want a
   different provider (or an invoice-and-bank-transfer flow with no provider at all).
2. **The merchant account**, in the billing entity's name, and its credentials in Secret
   Manager (human-only, per CLAUDE.md).
3. **GST treatment of the platform fee** — rate, place of supply, whether the statement is the
   tax invoice or feeds one, and the invoice-numbering series.
4. **The dunning policy**: what happens on a failed charge, after how long, and whether it ends
   in `POST .../suspend` (the API is ready; the decision is not ours).

## Human gates

* **Time a real onboarding.** The automated path is 0.5 s; the SPEC's 30 minutes covers a human
  typing real names and waiting for a real SMS. Run it once with an operator.
* **Re-measure NF-007 in the cloud** — the five items in `docs/perf/NF-007.md`,
  "What must be re-measured in the cloud".
* **`sql_max_connections` for the SaaS shape** restarts the Cloud SQL primary and its replica:
  a maintenance window, already a documented human gate.
* **Plan prices** in `plans.py` are engineering placeholders tied to the NF-015 cost envelope,
  not commercial decisions. They need sign-off before a tenant is billed.
* **Decide the owner-home aggregation refactor** before onboarding a tenant with a full-size
  month of visits, or accept the Cloud Run concurrency cost.

## Files

API: `farmerapp/platform_admin/` (plans, models, state, usage, provisioning, lifecycle,
billing, jobs, deps, schemas, router, errors), Alembic `0042_tenant_admin`, additive edits to
`auth/{models,scope,deps,otp,policy}.py`, `db/models/tenant.py`, `api/app.py`,
`farmers/service.py`, `users/router.py`, `uploads/service.py`, `campaigns/router.py`,
`diagnosis/pipeline.py`, `retention/sweep.py`, `jobs/{seed,cli}.py`, `openapi.yaml`.
Tests: `tests/platform/` (7 files), `tests/scale/` (2 files), additive edits to
`tests/authz/{conftest,test_matrix}.py`.
Infra: `modules/db_budget/tests/budget.tftest.hcl`.
Docs: `docs/perf/NF-007.md`, `docs/deploy/configuration.md`, `docs/progress.md`, this file.
