# FA-010 (API half): duty sessions, on-duty-only location ingest, policy acceptance and auto end

## Requirement IDs

- FA-010 Duty toggle — API: sync entity `duty_session` (`create` = start, `update` = end) with REST twins `POST /v1/duty/start`, `POST /v1/duty/end`, `GET /v1/duty/current`; sync entity `location_batch` / `POST /v1/location/batch` that stores points **only inside a duty session's window** (no location points recorded while off duty — tests prove the table count is unchanged for batches before start, after end and after an auto end); **Android foreground service + toggle screen pending (mobile agent)**
- FA-011 First-run disclosure — API: `GET /v1/policies/location` (versioned text in en/te/kn/hi/mr), `POST /v1/policies/location/accept`, sync `policy_acceptance create`; duty start blocked `policy_not_accepted` until the current version is accepted; **screen A05 pending (mobile)**
- VV-001 On-duty sampling — API: `GET /v1/duty/policy` (tenant sampling intervals, upload on Wi-Fi/charging) and the ≤ 500-point batch upload; **device sampling / battery budget pending (mobile)**
- VV-002 Point metadata — done: every stored point carries accuracy, speed, bearing, battery, mock / root flags, provider, server `received_at` and the server-computed `clock_drift_s`
- VV-007 Auto end of duty — server done: `auto-end-duty` job (20:00 IST tenant-configurable, 60 min idle at home), notification row, no points after the end; **the app prompt pending (mobile)**
- VV-010 Employee location policy version — done (text placeholder TODO-LEGAL): acceptance references the tenant `location_policy_version`; bumping it invalidates earlier acceptances
- FA-028 groundwork: `duty_session.device_integrity`, per-point `is_mock` / `is_rooted` / `clock_drift_s` stored from the write path
- OPS-006 groundwork: `officer-sync-silence` job → notification to the cluster head; FA-007 groundwork: minimal `notification` table

PR title: `feat(FA-010): duty sessions, on-duty-only location ingest, policy acceptance and auto end (FA-011, VV-001, VV-002, VV-007, VV-010)`

Branch `feat/FA-010-duty-location-api`; the mobile agent implements the same contract in `apps/mobile` concurrently and the visit API lands on its own branch — nothing under `apps/mobile`, `apps/console`, `infra`, `.github` or `farmerapp/visits/` write paths is touched here.

## Contract (shared with the mobile agent)

All offline-capable writes go through `/v1/sync` ops; the REST twins exist for tests and the console.

| Sync entity / action | REST twin | Payload | Result |
|---|---|---|---|
| `duty_session` `create` | `POST /v1/duty/start` (201) | `{id, device_id, app_version, policy_version, start_at, start_point{lat,lon,accuracy_m}, integrity{is_mock,is_rooted,clock_drift_s}}` | `DutySessionOut`; `policy_not_accepted` (422, `required_version`) / `duty_already_active` (409, `duty_session_id`) |
| `duty_session` `update` | `POST /v1/duty/end` | `{end_at, end_point, end_reason: manual\|auto_time\|auto_idle}` | `DutySessionOut` with `km`, `stops`; `conflict` + server state when already ended; `no_active_duty` (409, REST) |
| — | `GET /v1/duty/current` | — | `{session \| null, policy_version, policy_accepted}` |
| — | `GET /v1/duty/policy` | — | `{moving_interval_s, stationary_interval_s, upload_interval_s, upload_on_wifi_or_charging: true}` |
| `location_batch` `create` | `POST /v1/location/batch` | `{id, duty_session_id, device_id, sent_at, points[≤500]{ts, lat, lon, accuracy_m, speed_mps, bearing, battery_pct, is_mock, is_rooted, provider}}` | `applied` + `server: {duty_session_id, accepted, rejected[{index, reason: off_duty\|future\|duplicate}], clock_drift_s, received_at}`; unknown / colleague's session `not_found` |
| `policy_acceptance` `create` | `POST /v1/policies/location/accept` (201) | `{version, text_hash, device_id, app_version}` (`accepted_at` = `client_ts` in sync) | `PolicyAcceptanceOut`; `policy_version_stale` (422, `current_version`) |
| — | `GET /v1/policies/location` | — | `{version, text_hash, text{en,te,kn,hi,mr}}` |

Roles: duty routes field_officer + cluster_head; `POST /v1/location/batch` field_officer only; policy routes any authenticated role. Both duty POSTs and the batch / accept POSTs are `@idempotent` (`Idempotency-Key`); sync ops are idempotent by `op_id`.

## What changed

- **Migration** `apps/api/alembic/versions/0008_duty_notifications_home_point.py`: `user.home_point geography(Point) NULL` (VV-007 idle at home), `duty_session.device_integrity jsonb NOT NULL DEFAULT '{}'` (FA-028 flags at start), new table `notification` (id, tenant_id, created_at, user_id FK, kind, title_key, body_key, data jsonb, read_at; index `(tenant_id, user_id, created_at DESC)`; `enable_rls`). Backward compatible; downgrade exercised.
- **Policies** `apps/api/farmerapp/policies/`: `location_policy.py` (`known_versions()` from `location_policy_texts.json`, `policy_for(version)` — an unknown tenant version label serves the latest known text under that label, `text_hash` = sha256 of policy key + version + canonical JSON), `service.py` (`current_policy`, `accept_policy` → append-only row, `has_accepted` = an acceptance of exactly the current version exists, `require_accepted`, `settings_for`), `schemas.py`, `errors.py` (`policy_version_stale`, `policy_not_accepted`), `router.py` (`GET /v1/policies/location`, `POST /v1/policies/location/accept`).
- **Duty** `apps/api/farmerapp/duty/`: `service.py` (`start_duty`: policy gate, stale-session rule, `start_at` clamped to now + 2 min; `end_duty` / `close_session`: end fields + km / stops from `session_points`; `open_session`, `own_session`, `status`, `sampling_policy`, `session_window` = `[start − 2 min, end or now + 2 min]`), `track.py` (`summarise(points) -> TrackSummary(km, stops, kept)`: accuracy ≤ 100 m, drop points needing > 90 km/h, haversine sum, stops ≥ 5 min within 100 m of the run's first point with centroid / start / end / duration / points), `auto_end.py` (`auto_time_cutoff`, `idle_since`, `home_of`, `auto_end_duty`, `officer_sync_silence`, `run_auto_end`, `run_sync_silence`), `router.py` (`/v1/duty/start|end|current|policy`), `schemas.py`, `errors.py`.
- **Ingest** `apps/api/farmerapp/location/ingest.py` (`LocationBatchIn` ≤ 500 points with validated fields, `ingest_batch`: window check per point, future check (> now + 2 min), duplicate check against stored and in-batch `(officer_id, ts)`, `clock_drift_s` = round(`sent_at` − `received_at`) on every point, `received_at` = server clock) and `location/batch_router.py` (`POST /v1/location/batch`). `location/schemas.py`: `DutySessionOut.device_integrity`.
- **Sync** `apps/api/farmerapp/sync/`: `Entity` / `SYNC_ENTITIES` / `CONFLICT_RULES` gain `location_batch` (`server_wins`, write-only, never in the feed); `_ENTITIES_WITHOUT_WRITE_PATH` shrinks to `visit`, `visit_photo`; `_create` dispatches `duty_session` (existing id → `conflict` with the server state), `policy_acceptance` (existing id → `conflict`), `location_batch` (`applied` with the batch result as `server`); `_update` dispatches `duty_session` (already ended → `conflict`; payload passed through `merge_payload`, so `km` / `stops` / a server end are never taken from the device); `_update` takes the auth clock as `now`.
- **Models** `auth/models.py` (`User.home_point`), `location/models.py` (`DutySession.device_integrity`), `notifications/models.py` (`Notification`, `NotificationKind`), `db/models/__init__.py`.
- **Jobs** `jobs/cli.py`: `auto-end-duty --tenant-id …` and `officer-sync-silence --tenant-id …` (per-tenant `job_session` + system actor, like `purge-expired`).
- **App** `api/app.py` registers the three routers; `openapi.yaml` regenerated (7 new operations with `x-roles`).
- Tests (below), `tests/authz/test_matrix.py` (four `RouteFixture` bodies), `tests/sync/test_m2_rules.py` (duty / acceptance ops no longer `unsupported_action`), `tests/test_migrations.py` (`home_point`), `apps/api/README.md`, `docs/progress.md`, this file.

Design decisions and assumptions:
- **Off duty means no row, ever.** The window is enforced per point on the server against the officer's *own* session (a colleague's session id is a 404), with 2 minutes of slack on both ends because the app samples a fix just before the toggle lands and just after. A batch that is entirely off duty is still `applied` (with `accepted: 0`), so the outbox drains instead of retrying forever.
- `future` is checked before `off_duty`: a point past the server clock + 2 min is never stored whatever the session window says (a device clock far ahead would otherwise "extend" an open session).
- Duplicates are detected in Python by `(officer_id, ts)` rather than a unique index on the partitioned table, so a re-sent buffer is a per-point `duplicate` rather than a failed batch.
- Stale open session: an open session older than 24 h is a dead toggle (phone died); a new start closes it `forced` at the new start time and continues. Younger than that, the second start is `duty_already_active` and the app should resume the existing session (`GET /v1/duty/current`).
- `has_accepted` is "an acceptance of exactly the current version exists" (not "the latest acceptance names it"): append-only rows plus a version bump give the same invalidation, without depending on timestamp order when two acceptances land in one second.
- `policy_for(version)` serves the latest known text under any tenant version label: the wording HR signs may be identical across tenant-specific labels, and the hash still binds label + text, so a bump always re-prompts.
- Auto end at the *first* cutoff after `start_at`: a session started after 20:00 runs to the next evening rather than being closed one minute later.
- Idle rule: the last `idle_end_minutes` of points must all lie within 100 m of the first of them, the window must be covered by data (first point within one stationary interval + 5 min of the window start, last point as close to now), and their centroid must be within 200 m of home. Silence is *not* idleness (OPS-006 flags it instead); a long stop away from home is a visit, not an end. `end_at` is the first idle point, so the idle hour does not count as duty.
- Jobs take `--tenant-id` (repeatable) like `purge-expired`: the app role sees one tenant at a time under RLS; Cloud Scheduler passes the tenant list (OPS wires it).
- `notification` is not audited (`__audit__ = False`): it is derived from the audited duty-session change, not user data. FA-007 owns delivery and the inbox.
- Policy copy lives in a JSON file next to the module (an i18n file, versioned by key) rather than in Python strings; the seed's acceptances keep their own placeholder hash (only the version is checked at duty start; the hash is checked at acceptance time).

## Screenshots / goldens (UI changes)

None (API + database).

## Migration notes

- [x] Alembic migration added — `0008_duty_notifications_home_point` (run as the owner). Backward compatible: two nullable / defaulted columns, one new table. Deploy order migrate → api → jobs.
- [x] RLS policy + tenant_id on every table — `notification` isolated and forced (meta-test); `user` / `duty_session` unchanged.
- [x] Data backfill / retention impact — none; `notification` retention is FA-007's call (small rows).
- [ ] Cloud Scheduler: `auto-end-duty` every 10 min and `officer-sync-silence` every 30 min with the tenant ids (OPS).

## Test evidence

Run from the worktree against an isolated test database (`TEST_DATABASE_URL=…/farmerapp_test_duty`), the individual `check-api` steps minus the compose `db` bring-up: ruff check + format --check clean, mypy strict clean (190 files), pytest **1005 tests collected, all passed** (60 new in `tests/duty`, `tests/location/test_batch.py`, `tests/policies`; the SEC-006 matrix grew with the seven new operations), coverage **95.85 %** (≥ 80 %), `openapi.yaml` up to date, bandit clean. Migration 0008 upgraded → downgraded to 0007 → upgraded again on a scratch database (`notification` RLS enabled + forced, `user.home_point` present). `make migrate` / `make seed` were not run on the shared dev DB.

New tests:
- `tests/duty/test_duty_api.py` — start refused `policy_not_accepted` after a setting bump, then accepted + started with the new version; stale app policy version refused; the session row and `GET /v1/duty/current` (`device_integrity`, start point, version 1); second start `duty_already_active`; a 25-hour-old open session is closed `forced` by a new start; future `start_at` clamped; end computes km (4 km road + 8-minute stop, an inaccurate and an implausible point ignored) and stops, `duration_s`, end point, version 2; end without a session 409; device-reported `auto_idle` end kept; `Idempotency-Key` replay; `GET /v1/duty/policy` from defaults and a tenant override; store manager / accountant / agronomist / farmer 403 on every duty, batch and track route; an officer sees only their own session (listing + current), the other officer nothing; sync `duty_session` create → applied / replay → duplicate / same id → conflict, batch then end op → km server-computed and `km` / `stops` in the payload ignored, end again → conflict; sync create without the policy → rejected `policy_not_accepted`, a colleague's end op → `not_found`; an end op after a server auto end → `conflict` with the server end.
- `tests/duty/test_auto_end.py` — `auto_time_cutoff` cases; `idle_since` rules (covered window, late start, silent device, moved 150 m, 500 m from home, inaccurate points, empty); auto end at 20:00 IST with an injected clock (19:59 open, 20:05 ended `auto_time` at 20:00, km, notification row with keys / data, second pass no-op, **a later batch stores only the point inside the window and the count is unchanged for the rest**, `current` null); tenant-configurable 18:30; a session started at 21:00 runs to the next evening; only the bound tenant is touched; idle at home 60 min → `auto_idle` at the first idle point with km and the notification, 30 min not enough; idle 2 km away or walking near home keeps duty; `home_of` falls back to the store (and `None` without a store); idle needs the window covered; OPS-006 silence: 90 min nothing, 121 min → one notification to the cluster head with `silent_minutes`, not repeated, a batch counts as contact; no cluster head → silence recorded, nobody notified; `run_auto_end` / `run_sync_silence` wrappers; every stored point lies inside the session window after the auto end.
- `tests/duty/test_track.py` — empty / single point; haversine km; inaccurate and implausible points skipped; unsorted input and duplicate timestamps; stops (6 min / 4 points and exactly 5 min / 3 points, centroid, start / end); a stop needs 5 minutes.
- `tests/duty/test_cli.py` — `auto-end-duty` and `officer-sync-silence` commands (required `--tenant-id`, output lines, help).
- `tests/location/test_batch.py` — no points without a session (REST 404 / sync rejected, count unchanged); before start (beyond the slack) and after end (beyond the slack, after a later flush) rejected `off_duty` with the count unchanged, an all-off-duty batch `applied` with `accepted 0` (and `future` for a point an hour ahead); every stored point carries accuracy, speed, bearing, battery, mock / root flags, provider, `received_at` = server clock and `clock_drift_s` = +37 / −400 as sent, visible on the track endpoint; future (> 2 min) and duplicate (in-batch and across batches) rejected; sync replay by `op_id` → `duplicate` with the same result and no new rows, no feed row; `Idempotency-Key` replay returns the same body and stores nothing, a different body with the same key is `idempotency_key_reuse`; 501 points / empty / negative accuracy / unknown provider 422, exactly 500 accepted; a colleague's session is `not_found` for REST and sync and nothing lands in either officer's track.
- `tests/policies/test_location_policy.py` — texts: four points in five languages, latest version; `text_hash` binds version and text; `GET` serves the tenant version to every role and follows a bump; accept stores version / timestamp / device / app version / hash; append-only, the latest counts; stale hash / old version / right-hash-wrong-version → `policy_version_stale` with `current_version`; `Idempotency-Key` replay; **setting bump**: accepted → bump → `policy_accepted false`, start 422, old hash for the new version stale, new acceptance → start 201; sync `policy_acceptance` create (accepted_at = `client_ts`, feed row), replay duplicate, same id conflict, stale hash rejected, a future `client_ts` recorded at server time, update rejected `unsupported_action`.
- Updated: `tests/authz/test_matrix.py` (the generated matrix now covers the seven new operations × 10 roles, cross-tenant and no-token), `tests/rls/test_meta.py` (auto-covers `notification`), `tests/sync/test_m2_rules.py`, `tests/test_migrations.py`.

## Checklist

- [x] Tests written first; acceptance criteria covered (FA-010 no points off duty; FA-011 acceptance record with version + timestamp, duty blocked until accepted; VV-002 fields on every point; VV-007 no tracking beyond auto end; VV-010 version match / bump)
- [x] Role + tenant authorisation tests for every new endpoint (SEC-006 matrix, SEC-012 RLS meta-test incl. `notification`)
- [x] Strings externalised; money in integer paise; timestamps UTC — policy copy in `location_policy_texts.json`, notification texts as i18n keys; no money; `timestamptz` everywhere
- [x] No secrets in code, fixtures or logs — device ids and placeholder policy copy only
- [x] OpenAPI (`apps/api/openapi.yaml`) and `docs/progress.md` updated in this PR
- [x] Logs / metrics / alerts — `duty_started`, `duty_ended` (reason, km, stops, points), `location_batch` (accepted / rejected / drift), `location_policy_accepted`, `duty_auto_end` (ended by reason), `officer_sync_silence` events
- [x] Runbook updated — `apps/api/README.md` "Duty, location ingest and the location policy"
- [ ] `infra/`, `rules/`, payments or auth code: 2 reviewers (CODEOWNERS) — `auth/models.py` gains a nullable column only

### Mobile releases only

- [ ] VV-009 / disclosure copy: unchanged (no release in this PR; the A05 copy comes from `GET /v1/policies/location`)
