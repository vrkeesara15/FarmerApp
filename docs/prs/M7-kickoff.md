## Requirement IDs

- M7-KICKOFF Datastream -> BigQuery in dev, dbt staging + marts — done (IaC + dbt; first apply and replication setup human-gated)
- AN-010 CDC latency < 15 min, freshness test in dbt — done (dbt + IaC; measured once the stream runs)
- AN-012 dbt tests on every mart — done (`dbt build --target ci` green: 461 nodes)
- AN-013 BigQuery RLS by tenant and role (authorised views) — done (cluster head sees only own cluster, tested)
- AN-014 PII minimisation in marts — done (allowlisted replication, masking, tests)
- AN-004, AN-005, AN-006, AN-008 (placeholder), AN-009, AN-007 (server side) — marts and views done, dashboards still to wire (in-progress)

PR title: `feat(M7): Datastream to BigQuery in dev, dbt staging and KPI marts with tests, freshness, authorised views and PII masking (AN-010, AN-012, AN-013, AN-014)`

Scope: `infra/`, `dbt/`, `.github/workflows/ci-dbt.yml`, `docs/`, and the root `Makefile`
(`dbt` targets, `check-dbt` in `make check`). Nothing under `apps/` changed; the P0 console keeps
reading the API's Postgres replica (SPEC 5.3) and is wired to the views in a later M7 task.
Nothing was applied to any GCP project.

## What changed

### infra/modules/analytics (rewritten) and env wiring

- Datasets `farmerapp_raw` (Datastream), `farmerapp_staging` (new), `farmerapp_marts`,
  `farmerapp_views`, labelled, `delete_contents_on_destroy` only in dev.
- Service accounts: `farmerapp-dbt` (jobUser; dataViewer on raw; dataEditor on staging / views;
  WRITER on marts) and `farmerapp-bi-reader` (jobUser; dataViewer on views only). The views
  dataset is **authorised** on marts (`google_bigquery_dataset_access`, `target_types = VIEWS`);
  marts is managed only through `dataset_access` because dataset IAM resources would rewrite its
  access list and drop that entry. The console SA may impersonate the reader; WIF members and
  impersonators of the dbt SA are variables (empty by default).
- Datastream: PSC-interface private connection (subnet `farmerapp-<env>-datastream` 10.20.0.0/28
  + network attachment; VPC peering is not transitive to Cloud SQL's PSA range, and no proxy VM
  is needed), BigQuery profile, Postgres profile with TLS server verification against the
  instance's CA (`modules/sql` now outputs `server_ca_cert`), stream in **merge** mode (deletes
  propagate: data-subject erasure keeps working), `data_freshness = 600s`, and an explicit
  table **and column** allowlist from `replicated_columns.json` (26 tables, no PII).
- Gates: `datastream_enabled` (connectivity, destination; true in dev / stg / prd) and
  `datastream_stream_enabled` (source profile + stream; false everywhere until the runbook's
  one-time SQL). The password is `datastream-db-password` in Secret Manager (created empty by the
  secrets module, readable only by the Datastream service agent); a variable validation refuses
  anything that is not a secret version name.
- `modules/analytics/tests/analytics.tftest.hcl` (7 runs, mock providers): gates, allowlist
  (every table, no PII column), merge mode, missing secret / CA fails, reader reads views only.
- `infra/scripts/datastream_sql.py`: prints the idempotent one-time SQL from the allowlist —
  `--part admin` (role `datastream` LOGIN REPLICATION, pgoutput slot) and `--part owner`
  (column-level SELECT, `datastream_read` RLS policy per table, publication with column lists).
- envs (byte-identical main / variables / outputs): new variables, outputs `analytics`.

### dbt/

- uv project (`pyproject.toml` / `uv.lock`: dbt-core 1.11.15, dbt-duckdb 1.11.0, dbt-bigquery
  1.12.1); no dbt packages. Profiles: `ci` (DuckDB) and `dev` / `stg` / `prd` (BigQuery, optional
  impersonation, `maximum_bytes_billed`).
- 25 staging views, 6 core tables, 16 marts, 16 authorised views; portable macros with BigQuery
  and DuckDB implementations; fixture seeds in the Datastream shape (older CDC versions, soft
  deletes, fake name / phone columns to prove they are dropped).
- Tests (372): generic AN-012 tests on every mart; 13 singular tests — 9 KPI reconciliations
  against hand-computed fixture values, AN-013 row scopes (any target) and viewer mapping,
  AN-014 PII columns in every built relation, AN-010 freshness contract.
- `scripts/check_replication.py` (allowlist = sources = fixtures, no PII), `scripts/gen_seed_types.py`.
- `README.md`: lineage, models, KPI definitions, the console's viewer-identity contract, how to
  add a mart or a replicated column.

### CI and Makefile

- `ci-dbt.yml`: `fixtures` job on every PR touching dbt (uv sync, allowlist check,
  `dbt build --target ci --fail-fast`); `bigquery-dev` job only with `vars.WIF_PROVIDER` and
  `vars.DBT_SA_DEV` (build + informational freshness).
- `make dbt | dbt-dev | dbt-freshness | check-dbt`; `check` now includes `check-dbt` (skips
  without uv).

### docs

- `docs/runbooks/datastream-cdc-setup.md` (new; listed in the runbook index): password, admin
  and owner SQL, verification, enabling the stream, freshness and lag, replication-slot safety,
  teardown.
- `docs/deploy/configuration.md` (analytics tfvars, the new secret), `docs/runbooks/observability.md`
  (OPS-011 / AN-010 row), `infra/README.md`, `docs/progress.md`.

## Design decisions

- **AN-013 via authorised views + a viewer column, not row access policies.** The console queries
  as one service account, so policies keyed on Google principals or `SESSION_USER()` cannot
  separate FarmerApp users. Each view returns `(viewer_user_id, row)` pairs from
  `dim_viewer_scope`; the console filters by the signed-in user's id, the same trust model as the
  API binding `app.tenant_id` for Postgres RLS. The views dataset is the reader's only grant.
- **PII stops at the source.** Allowlist in Datastream, column-level grants for the replication
  login and publication column lists — BigQuery never receives a name or a phone; staging masks
  `phone_last4` as defence in depth.
- **Merge mode** (not append-only): deletes propagate for erasure; staging still deduplicates by
  `source_timestamp` for backfill overlap.
- **DuckDB for CI**: the same SQL through dispatch macros; BigQuery rendering was compiled
  offline and every compiled file parsed with a BigQuery-dialect parser.

## Checks run

- `cd infra && ./scripts/check.sh` — fmt, validate (bootstrap + 3 envs), `terraform test` (analytics 7,
  db_budget 5, run_job 4, run_service 4), tflint, checkov 107 passed / 0 failed (no new skips): green.
- `make check-dbt` — allowlist check + `dbt build --target ci`: PASS=461 (26 seeds, 63 models, 372 tests) in ~8 s.
- Mutation checks: an unfiltered view fails both AN-013 tests; a `farmer_phone` / `officer_name`
  column fails AN-014; loosening freshness to 20 min fails AN-010; another as-of date fails the
  reconciliations.

## Human gates

1. First apply of `modules/analytics` (dev from CI once WIF is configured; stg / prd human-only).
2. Replication setup per `docs/runbooks/datastream-cdc-setup.md`: password secret version,
   `datastream_sql.py --part admin` (postgres) and `--part owner` (migrate owner), then
   `datastream_stream_enabled = true`.
3. BigQuery / Datastream cost sign-off (Datastream per-GB, merge staleness 600 s, dbt schedule).
4. `DBT_SA_DEV` repository variable + `dbt_workload_identity_members` for ci-dbt's BigQuery job.

## Follow-ups

- Console: read the `v_*` views as `farmerapp-bi-reader`, always with `viewer_user_id`.
- apps/api: codify the `datastream_read` policies in an Alembic migration (+ RLS meta-test).
- OPS-011: Cloud Monitoring alert on Datastream freshness; scheduled dbt job in stg / prd.
- Confirm segment / churn / outbreak thresholds with the owner; AN-008 once WC-008 lands;
  DX-011 test-set accuracy into BigQuery.
