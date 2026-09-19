# M6 final: terraform tests in CI, database connection budget, on-device provenance sent by the apps

Branch `chore/M6-final` (from `main` at `9b84d26`). Closes the last M6 leftovers of
docs/prs/deploy-config-alignment.md (terraform test in CI, `DB_POOL_SIZE` x `max_instances`
over `max_connections`) and docs/prs/M6-api-gaps.md (apps send the `on_device` block).
Requirement IDs: SEC-005, OPS-003, NF-006, DX-001, DX-005.

## CI (SEC-005)

* `ci-infra.yml` `static` job: new step "terraform test (modules with tests/)", the same
  discovery as `infra/scripts/check.sh` (`find modules -mindepth 2 -maxdepth 2 -name tests`):
  run_service, run_job, db_budget. No new permissions (`contents: read`; mock providers or none,
  no id-token). actionlint and shellcheck clean.

## Connection budget (OPS-003, NF-006)

* `modules/sql`: `max_connections` database flag on primary and replica (a hot standby needs
  >= the primary's), from `var.sql_max_connections`; output `max_connections`.
* New `modules/db_budget` (no providers): `processes` = {instances, pool_size, max_overflow} per
  pooled process; output `env` (DB_POOL_SIZE / DB_MAX_OVERFLOW) with a precondition
  `sum(instances x (pool_size + max_overflow)) + reserve <= floor(max_connections x 80%)`;
  validation `pool_size + max_overflow >= 2` (a tenant-bound session plus the PII key load on a
  second connection). `terraform test`: 5 runs (fits, exactly at the ceiling, app defaults fail,
  one over fails, pool below 2 refused).
* `envs/*/main.tf` (still identical): `module.db_budget` fed by `module.sql.max_connections`,
  `var.max_instances.api` / `.worker` and `length(local.jobs)` (11 jobs, all assumed to overlap);
  api / worker / jobs env get `DB_POOL_SIZE` / `DB_MAX_OVERFLOW` from its output. New variable
  `db_pool` (no default: set per env); `sql_max_connections` has no default any more.
* Numbers (docs/deploy/configuration.md "Connection budget"):

| env | max_connections | api | worker | jobs | + reserve | ceiling (80%) |
|---|---|---|---|---|---|---|
| dev | 100 (flag; tier default 50 too small) | 3 x 3 = 9 | 2 x 2 = 4 | 11 x 2 = 22 | 55 | 80 |
| stg | 100 | 5 x 3 = 15 | 5 x 2 = 10 | 11 x 2 = 22 | 67 | 80 |
| prd | 200 | 20 x 3 = 60 | 20 x 2 = 40 | 11 x 2 = 22 | 142 | 160 |

  dev / stg tfvars now set `max_instances` (dev api 3 / worker 2, stg 5 / 5).
* Verified per env with `terraform console` on a backend-less copy (totals above), and a
  prd plan with api 5 + 10 fails: "api 300 + jobs 22 + worker 40 + reserve 20 = 382 > 80% of
  max_connections 200 (160)".
* `apps/api/scripts/terraform_env.py` renders `DB_POOL_SIZE` / `DB_MAX_OVERFLOW` from the env's
  tfvars; `tests/deploy/test_terraform_env.py`: wiring (sql flag, db_budget inputs, pools on
  api / worker / jobs, none on migrate) and the budget recomputed per env against the docs table.

## Mobile (DX-001, DX-005)

* `packages/core` `OnDeviceBlock.fromResults`: the `OnDeviceIn` block from the gate results of
  the accepted photos, sent with every diagnosis create (sync `diagnosis` create op through
  `DiagnosisRepository.submit`, used by the farmer and agent apps): `model`, `model_version`,
  `model_sha256` from the asset metadata, `plant_score`, `quality`, `crop_scores` (averaged,
  max 16), `latency_ms`; Laplacian fallback shape when the model did not answer. Legacy
  `on_device_model` still sent (= `model_version`); `crop_guess` only with the tenant flag.
* Tests: block shape / no extra keys / fallback, repository (in the op, survives the offline
  outbox and a database reopen), HTTP contract of the create body against `DiagnosisCreate` /
  `OnDeviceIn` read from `apps/api/openapi.yaml`, farmer and agent flows.

## Checks

`SKIP_AUDIT=1 make check`: api, console, mobile, infra green (counts in the commit message).
The owner-home 3 s and demo-seed 30 s timing tests passed in their phases; no marker change.

## Human gates

* Next stg / prd apply sets the `max_connections` flag (instance restart; prd HA failover
  window). Confirm with `SHOW max_connections` afterwards.
* Raising scale: raise `sql_max_connections` / tier first; the plan refuses pools that do not fit.
