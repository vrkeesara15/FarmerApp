# M4 kickoff — YAML rules engine, flags with routing and SLA, farmer-data rules

Branch `feat/M4-rules-engine-flags` (on `main` c2e85e0). Requirement IDs: M4-KICKOFF,
VA-001, VA-002, VA-003, VA-007, VA-F01, VA-F02, VA-F03, VA-F06 (done); WC-010 (API done,
console pending); OPS-010 (job done, scheduling / delivery pending).

SPEC 14.4 M4 kickoff: "Implement the rules engine: load rules/*.yaml, run inline/event/batch
modes per SPEC 6.1, store flags per VA-002. Add positive and negative fixtures for each P0
rule." This change does that for the farmer-data P0 rules; VA-F08, VA-E01–E05 and VA-E08
follow in the next loop iteration as one module + YAML + two fixtures each.

## What changed

### Rules (VA-001, VA-007)

- `rules/VA-F01.yaml`, `VA-F02.yaml`, `VA-F03.yaml`, `VA-F06.yaml` and
  `rules/fixtures/<id>/{positive,negative}.yaml`; `rules/README.md` rewritten as the
  authoring guide (the M0 placeholder layout with subdirectories and JSON fixtures is gone).
- `apps/api/farmerapp/rules/`:
  - `schema.py` — strict `RuleConfig` (`extra="forbid"`): id pattern, version, subject,
    mode (one or a list), event `triggers`, severity, `owner_role`, `sla_hours`, `params`,
    `enabled`, `tenant_overrides` by slug (override keys must exist, same type).
  - `loader.py` — `load_rules` (file name = id, every problem listed), cached
    `get_rule_set` from `RULES_DIR` (default the monorepo `rules/`), `validate_rules` (called
    by `create_app` of the API and the worker: invalid YAML refuses to start),
    `check_registry`, `check_fixtures`.
  - `registry.py` — `@rule(id)`, `RuleContext` (session bound to the tenant, resolved
    params, mode, now, subject ids), `Finding`, `Evidence` (records, map points / polygons,
    photos, metrics).
  - `engine.py` — `run_rules` / `run_inline` / `emit` / `run_batch`; savepoint per rule.
  - `events.py` — worker entry (`handle_event_message`) and the in-process `PaymentCaptured`
    subscriber; `jobs.py` — batch job and SLA job.
  - `checks/va_f01.py`, `va_f02.py`, `va_f03.py`, `va_f06.py`.
- `python -m farmerapp.jobs validate-rules` runs in `make check-api` (before pytest);
  `tests/rules/test_fixtures.py` enumerates YAML + registry and fails a rule missing either
  fixture, then runs each fixture through the real engine (batch fixtures twice).

### Flags (VA-002, VA-003, OPS-010)

- Migration `0018_flags_rules` (branch `flags`, `down_revision = "0017"`, expand-only):
  `flag`, append-only `flag_event` (added to `APPEND_ONLY_TABLES`), `flag_comment`, all
  under RLS and audited. Verified on a scratch database: upgrade -> downgrade 0017 ->
  upgrade.
- `farmerapp/flags/routing.py` — scope of the subject (employee: cluster / store; farmer:
  village store and its cluster; visit: its officer; store), owner by the rule's
  `owner_role` with fallback up the ladder store manager -> cluster head -> auditor ->
  owner, auditors as `watchers` on high severity.
- `farmerapp/flags/service.py` — `raise_flag` (dedupe, route, SLA, `created` event,
  `flag_assigned` notifications), `transition` (SPEC 6.1; notes required to resolve or
  escalate; labels `false_positive` for `resolved_valid`, `true_positive` for
  `resolved_fixed` / `resolved_action`; escalation reassigns to an auditor),
  `add_comment`, `assign`, `escalate_overdue` (OPS-010), `flag_filters` (inbox scope).
- `notification.kind` gains `flag_assigned` / `flag_escalated` (i18n keys
  `notification.flag_*.title|body`).

### API (WC-010 backend)

`GET /v1/flags`, `GET /v1/flags/{id}`, `POST /v1/flags/{id}/transition`,
`POST /v1/flags/{id}/comments`, `POST /v1/flags/{id}/assign` — `x-roles` on each; matrix
fixtures added to `tests/authz/test_matrix.py`. See `apps/api/README.md` for the table.

### Wiring

- FA-012 write paths (`farmers/service.py`) run the inline rules after registration, farm
  add / boundary or acreage edit and farmer name / village edit; registration also emits
  `farmer.registered`. The existing 409 / 422 / warning responses are unchanged.
- Worker `dispatch.py`: `visit.created` and `farmer.registered` run their event rules;
  `payment.webhook` runs them after applying the webhook (none subscribe yet, so no
  database work). Malformed payloads are logged and acknowledged.
- Jobs: `run-rules --mode batch --tenant <id|fcc|gfl> [--rule]`, `flags-sla-escalation`,
  `validate-rules`.

## Decisions and assumptions

- **Dedupe**: an unresolved flag with the same key is never raised twice (partial unique
  index + check); a finding already *reviewed* under the same rule version is not raised
  again either, so a nightly batch does not re-open a flag a reviewer marked valid. Bumping
  the rule version re-evaluates.
- **SLA escalation** changes the owner, never the status (the reviewer still decides
  valid / fixed / escalated); each run moves an overdue flag one rung and restarts the SLA
  with the rule's `sla_hours`.
- **Inbox scope**: cluster heads see flags whose subject is in their cluster (employee and
  farmer data) plus any they own or watch; store managers only farmer-data flags of their
  store plus owned ones; field officers only flags about themselves (read, explain while
  open, no transitions); evidence summaries are omitted for the subject (ids only).
- **VA-F01** flags (does not reject) unverified phones only after a 72 h grace period, so
  offline captures that verify later are not flagged; staff phone and malformed phone
  rejections at registration are unchanged.
- **VA-F02** "same phone" compares the last ten digits (the `(tenant, phone)` unique
  constraint makes exact duplicates impossible); fuzzy branch: pg_trgm similarity >= 0.6
  in one village and farm centroids <= 50 m.
- **VA-F06** "many farmers sharing one device or phone": phones are unique per tenant, so
  the device half is implemented from the audit trail (`X-Device-Id` of `farmer.create`)
  as "one device registering farmers for more than one officer". Registration times are
  server times: offline captures synced together can look like a burst (tune
  `max_registrations` per tenant; VA-006 will measure it).
- The visits in-process bus (`IntegrityEvent`) is synchronous and has no session; VA-E01
  will add an async dispatch there when it lands. The payments bus is subscribed now.
- Tenants in jobs are given by id or demo slug: the app role cannot resolve an arbitrary
  slug before a tenant is bound (RLS).

## Follow-ups

- Container images: the API / worker / jobs Docker build context is `apps/api`, so
  `rules/` is not in the image yet; set `RULES_DIR` and copy the directory in the build
  (CI / infra change, not in this branch). Until then a deployed service logs
  `rules_dir_missing` and runs no rules.
- Cloud Scheduler: `run-rules --mode batch` nightly at 02:00 IST and
  `flags-sla-escalation` hourly (infra).
- Console C70 / C71 (WC-010), VA-005 officer view, VA-006 precision report (labels are
  recorded), VA-004 review agent summary.
- Next rules: VA-F08, VA-E01–E05, VA-E08.

## Tests

`tests/rules/` (fixtures, loader + YAML-only tuning + tenant overrides + CLI, runners:
inline via the API, event via the API and the worker handler, batch job idempotency, a
failing rule isolated) and `tests/flags/` (API, scope per role, state machine, comments,
assignment, routing, dedupe race, SLA ladder). ruff, ruff format, mypy strict, bandit,
OpenAPI check green; full suite and coverage in the commit report.
