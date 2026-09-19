# M4 integration — rules engine, analytics and admin APIs on `main`

`main` (from 9f93f9b) merges, in order, `feat/M4-rules-engine-flags` (d3868bd),
`feat/M4-analytics-api` (1078bdf) and `feat/M4-admin-api` (c96166e) with `--no-ff`, then closes
the gaps the three branches left between them. Requirement IDs: M4-KICKOFF, VA-F06, AN-001,
AN-002, WC-001, WC-012, SEC-028 (done), OPS / infra follow-ups below.

Branch docs: `docs/prs/M4-rules-engine.md`, `docs/prs/M4-analytics-api.md`,
`docs/prs/M4-admin-api.md`.

## Merges

| Merge | Conflicts | Resolution |
|---|---|---|
| `merge(M4): feat/M4-rules-engine-flags` | none | fast merge on 9f93f9b (the timezone fix in `tests/location/test_partitions.py` kept) |
| `merge(M4): feat/M4-analytics-api` | `api/app.py`, `tests/authz/test_matrix.py`, `apps/api/README.md`, `docs/progress.md`, `openapi.yaml` | both routers / both fixture sets / both README sections kept; progress rows take the newest status per ID; `openapi.yaml` regenerated with `make openapi` |
| `merge(M4): feat/M4-admin-api` | `docs/progress.md`, `openapi.yaml` | same rules; `app.py`, `db/models/__init__.py`, `settings.py`, `farmers/service.py`, the authz matrix merged cleanly |

The admin branch's settings refactor (one typed accessor) does not break the analytics readers:
they read `credit_due_days` through `khata.ledger.credit_settings` (still exported) and the
`targets` key from the raw `tenant.settings` (kept by `PATCH /v1/settings`, which merges into the
raw mapping). `uv.lock` did not conflict (`uv lock --check` clean).

## Alembic

- `0021_merge_m4_heads` — empty merge of `0018_flags_rules` (branch `flags`) and `0020`
  (branch `admin`); both expand-only on 0017 with disjoint objects.
- `0022_farmer_captured_at` — nullable `farmer.captured_at` (VA-F06 below); kept out of the
  merge revision so 0021 stays a pure merge.
- `alembic heads` → `0022 (head)`. Verified on a scratch database: `upgrade 0017` →
  `upgrade head` (flag, device, `farmer.captured_at` present) → `downgrade 0017` (all three
  gone) → `upgrade head`.

## Gaps closed

### Real flag counts in analytics (AN-001, AN-002, WC-001)

`farmerapp/flags/analytics.py::FlagTableCounts` implements the analytics `FlagCountsPort`;
`create_app` registers it on `app.state.flag_counts` (the null adapter remains the fallback).

- **Open as of T** (`created_at < T` and not resolved by T), so the owner-home trend buckets and
  "same period last year" are historical; without T the unresolved statuses.
- **Severity**: `open_total`, `open_high`; the owner home lists open high-severity flags newest
  first (farmer id for farmer flags, the store of the flag, the officer).
- **Per officer** (scorecard `flags` column): employee flags about the officer and flags on
  their visits.
- **Role scope**: `FlagQuery.viewer` applies the WC-010 inbox rule (`flags.service.flag_filters`),
  so a store manager counts only their store's farmer-data flags, a cluster head their cluster,
  a field officer flags about themselves; the analytics narrowing (stores in view, officers in
  view; `officer_only` for an officer row or `officer_id` filter) applies on top.
- `notes.open_flags = "pending_flags_branch"` is gone (the null adapter still sets it).
- Tests: `tests/analytics/test_flag_counts.py` (exact counts, trend, last year, high list,
  scorecard, every reader role, filters, adapter without a time, other tenant).

### Rules in the images (VA-001, follow-up of the rules branch)

The api, worker and jobs images are now built from the **repository root**; a root
`.dockerignore` admits only `apps/api` (sources, lockfile, Alembic) and `rules/`. Each
Dockerfile copies `rules/` to `/app/rules` and sets `RULES_DIR=/app/rules`.
`validate_rules()` (API / worker start) now logs `rules_loaded` with the directory and ids.

- `docker-compose.yml`: `api` builds with `context: .`, `dockerfile: apps/api/Dockerfile` and
  mounts `./rules` read-only next to the source mounts.
- `deploy.yml`: already built with context `.`; `jobs` joins the build matrix and a step runs
  `python -m farmerapp.jobs validate-rules` inside every api / worker / jobs image before the
  trivy scan.
- `ci-api.yml`: new `images` job builds api / worker / jobs from the repo root and validates the
  rules inside each image (`.dockerignore` added to the path filter).
- Verified locally: `docker compose build api`; `docker run farmerapp/api:local` logs
  `{"event": "rules_loaded", "rules_dir": "/app/rules", "count": 4, ...}` before "Uvicorn
  running"; the worker and jobs images pass `validate-rules`.

Assumption: a console image (the `console` entry of the deploy matrix has no Dockerfile yet)
will need `!apps/console` lines in `.dockerignore` or its own `Dockerfile.dockerignore`.

### SEC-028: step-up on the catalogue export

`GET /v1/catalog/export` declares `StepUp` (after the role check) and `x-step-up: true`; every
admin action and both exports (`/v1/audit-logs/export`, `/v1/catalog/export`) now need a fresh
OTP. Tests: `tests/admin/test_step_up.py` (protected action list + contract), the catalogue
export tests (401 without, 200 with), authz matrix fixture `step_up=True`. **SEC-028 done.**

Console impact: C-screens that download the catalogue CSV must run the step-up flow
(`401 step_up_required` → `/v1/auth/step-up/send` → `/v1/auth/step-up` → retry with
`X-Step-Up-Token`), as for the audit export.

### Director writes settings (SPEC 2.6, WC-012)

`PATCH /v1/settings` roles: owner, **director**, tenant admin (step-up still required). The
contract's `x-roles` drive the authz matrix; `tests/admin/test_settings_api.py` proves the
director needs step-up and then succeeds, and a store manager gets 403.

### VA-F06 capture time (offline registrations synced together)

- The sync `farmer` create passes the op's `client_ts` to `farmers.create_farmer`, stored as
  `farmer.captured_at` capped at the server time (a fast device clock cannot push it into
  the future). REST registrations leave it `NULL`.
- VA-F06 orders and windows registrations on `coalesce(captured_at, created_at)`; the look-back
  stays on `created_at` so a genuine burst synced days later is still examined.
- Fixtures: the VA-F06 negative fixture gains an officer with nine captures 15 minutes apart
  synced a minute ago (nine is the smallest burst under the shipped threshold of "more than 8
  in 30 minutes"); the harness accepts `captured:`.
- `tests/rules/test_va_f06_capture_time.py`: five captures over two hours synced in one batch
  with the threshold tuned to 4 → no flag; the same five without capture times → flag
  (control); five captures inside 30 minutes → flag with the capture time as `first_at`; the
  sync API end to end (nine captures over two hours → no flag and stored capture times, a
  future `client_ts` capped; a real burst synced → flag); online registration has no capture
  time.
- Residual risk: a device clock set back on purpose could spread a burst; VA-E01 (clock drift)
  is the check for that.

## Not done here / follow-ups

- Console screens for WC-001–004, WC-010–012, WC-103, AN-001–003, AN-011 (API done).
- Cloud Scheduler for `run-rules --mode batch` and `flags-sla-escalation`; nightly Cloud Run
  jobs still run the api image (which now carries the rules).
- VA-F08, VA-E01–E05, VA-E08 (another loop is adding them on the rules branch).
- `targets` (owner-home goals) is not in the typed `TenantSettings` yet, so `PATCH /v1/settings`
  cannot write it (WC-009).

## Tests

`SKIP_AUDIT=1 make check` from the repo root (API ruff / format / mypy strict / validate-rules /
pytest with coverage / OpenAPI check / bandit; console; mobile; infra) — counts in the commit
report. Run 1: API 2688 passed / 1 skipped (coverage 96.99 %), console 168 tests, mobile 13 + 541 + 190 + 9, infra checks passed; API run 2: 2688 passed / 1 skipped. `make openapi` leaves `openapi.yaml` unchanged.
