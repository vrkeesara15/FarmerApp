# apps/api — FarmerApp backend package

One Python package, `farmerapp`, with three entrypoints:

| Entrypoint | Command | Deployable |
|---|---|---|
| `farmerapp.api.app:app` | `uvicorn farmerapp.api.app:app` | api (Cloud Run) |
| `farmerapp.worker.app:app` | `uvicorn farmerapp.worker.app:app` | worker (Cloud Run, Pub/Sub push) |
| `farmerapp.jobs` | `python -m farmerapp.jobs <job>` | jobs (Cloud Run Jobs) |

`apps/worker` and `apps/jobs` only hold a Dockerfile + README; they build from this directory.

## Layout

```
farmerapp/
  settings.py     pydantic-settings (env vars, see /.env.example)
  logging.py      structlog JSON logging, trace id per request
  api/            FastAPI app factory, /v1/health, RFC 9457 errors, CORS, scheduler ticker
  auth/           FA-001 phone + OTP login, JWT access/refresh (SEC-020/021), get_current_user,
                  SMS/WhatsApp provider adapters (fake, mockserver), delayed-task scheduler seam;
                  FA-002 policy.py (require_roles / PUBLIC, startup check, x-roles in OpenAPI),
                  scope.py (SPEC 2.6 matrix as SQLAlchemy filters)
  users/          /v1/users list/get/patch (minimal WC-011 slice; cursor pagination in api/pagination.py)
  audit/          GET /v1/audit-logs (FA-006 read endpoint for the WC-103 viewer)
  tenants/        models: cluster, store, village (M1-KICKOFF; SPEC 8.2 "store / cluster");
                  settings.py: typed tenant.settings with the M2 defaults (geofence, durations, policy)
  catalog/        crops.py: crop master + the six pilot crops (M3 adds products, SKUs, label claims)
  farmers/        models: farmer, farm (PostGIS boundary, generated centroid + area), crop_plot,
                  consent_record (append-only); schemas.py read models; GET /v1/farmers[/{id}] (WC-003 foothold)
  location/       models: duty_session, location_point (partitioned by day), location_daily_agg,
                  policy_acceptance (append-only); partitions.py (ensure / purge helpers over the SQL
                  functions); GET /v1/duty-sessions, GET /v1/officers/{id}/track (M2-KICKOFF)
  visits/         models: visit, visit_photo, visit_confirmation; scoring.py (VV-004 / VV-005);
                  GET /v1/visits[/{id}] (M2-KICKOFF)
  db/             async engine/session, tenant binding (set_tenant / tenant_scope / job_session),
                  rls.py (enable_rls for migrations, rls_violations for the meta-test), Base, models,
                  audit.py (FA-006 actor context + flush listener + redaction + audit.record),
                  geo.py (EWKT helpers, acres <-> m2; no shapely)
  worker/         Pub/Sub push receiver + dispatch table by topic (SPEC 9.2)
  jobs/           typer CLI (hello, seed = the Telangana demo tenant "fcc" + "gfl" (see "Seed data");
                  purge-audit-logs = NF-012 dry run; purge-expired; ensure-partitions and
                  purge-location-points = SPEC 2.6 location retention; auto-end-duty = VV-007;
                  officer-sync-silence = OPS-006); seed_m2.py = M2 rows
  duty/           FA-010 duty start / end service + /v1/duty routes, track.py (km, stops),
                  auto_end.py (VV-007 auto end + OPS-006 sync silence jobs)
  policies/       FA-011 / VV-010 location policy text (versioned JSON) + acceptance
  notifications/  notification table (FA-007 groundwork; rows written by the duty jobs)
alembic/          async Alembic env + migrations
scripts/          export_openapi.py (writes/checks openapi.yaml)
tests/            pytest (needs the compose db: `make db`; parallel, see "How the tests run")
```

## Everyday commands (from repo root)

```
make up          # db, pubsub, gcs, mockserver (also creates the farmerapp_app login, `make db-roles`)
make migrate     # alembic upgrade head as the owner (MIGRATION_DATABASE_URL)
make seed        # demo tenants, as the app role under RLS (DATABASE_URL)
make test-api    # pytest in parallel (pytest-xdist) with coverage >= 80%
make test-api-fast  # the same without coverage, for quick local iteration
make check-api   # ruff, mypy strict, pytest, openapi diff, bandit, pip-audit (prints wall clock)
make openapi     # regenerate apps/api/openapi.yaml (commit it)
```

Inside this directory: `uv sync`, then `uv run <cmd>`.

### How the tests run (ADR 0004)

`make test-api` / `make check-api` run pytest in two phases:

1. `pytest -n $(API_TEST_WORKERS) --dist worksteal -m "not serial"`: pytest-xdist, one worker
   per core by default (`API_TEST_WORKERS=auto`; override e.g. `make test-api API_TEST_WORKERS=6`,
   `0` runs this phase serially). Every worker has its **own database**
   `farmerapp_test_<checkout key>_gw0`, `…_gw1`, … created at worker start with
   `CREATE DATABASE … TEMPLATE farmerapp_test_<checkout key>_template` (a file copy, well under a
   second) and dropped at the end. The first worker that needs the template creates it and runs
   `alembic upgrade head` into it as the migrate role, under a Postgres advisory lock; the
   template is rebuilt from scratch whenever a file under `alembic/` changes (a fingerprint is
   kept as the database comment). The clone keeps everything inside the database (RLS policies,
   the `farmerapp_app` / `farmerapp_migrate` / `farmerapp_auth` grants and default privileges);
   the only database-level grant, `CONNECT` for the app role, is re-applied to each clone. The
   checkout key is a short hash of the checkout path, so worktrees on different branches never
   share (or drop) each other's databases. Tests use exactly the same two roles as before: the
   app role (RLS applies) for sessions and the app, the migrate role for setup only.
2. `pytest -n 1 -m serial --cov-append`: tests marked `serial` (the WC-001 3 s owner-home
   budget) run alone on an idle machine; a wall-clock budget is meaningless while other
   workers saturate the CPU. The coverage report and the 80% gate apply to the data of both
   phases combined (pytest-cov combines the workers' data).

A plain `uv run pytest` (no `-n`) still runs everything serially against `farmerapp_test`,
migrated in place, as before. `uv run pytest -n 8 --no-cov tests/visits` works for a subset.

Coverage stays on the C tracer with `branch = true` and `concurrency = ["greenlet", "thread"]`:
`COVERAGE_CORE=sysmon` cannot be used on Python 3.12 (coverage.py only supports branch
measurement with sys.monitoring from 3.14, and never with `concurrency = greenlet`), so it
silently falls back to the tracer. The speed-up comes from the workers.

### Local database image (ADR 0004)

`make db` / `make up` build `docker/postgres/Dockerfile`: the official multi-arch
`postgres:16-bookworm` image plus PostGIS 3.6 and pgvector 0.8 from PGDG (tag
`farmerapp/postgres:16-postgis3-pgvector-multiarch`, volume `farmerapp_pgdata_arm64`), so it
runs natively on Apple Silicon; CI builds the same Dockerfile on amd64. Alembic 0001 creates the
extensions. `make db` never recreates a running container (`--no-recreate`): after changing
`docker/postgres` run `make down` (volumes are kept) and `make db migrate seed`.

The old amd64 `postgis/postgis:16-3.4` volume `farmerapp_pgdata` is no longer used. Removing it
is an optional manual step once you no longer need its data:
`docker volume rm farmerapp_pgdata` (stop any container still using it first).

## Seed data (M1-KICKOFF, SPEC 10.5)

`make seed` (`python -m farmerapp.jobs seed [--small]`) upserts two demo tenants as the app role
under RLS, idempotently (stable `uuid5` ids; a second run creates nothing), in about a second:

| | `fcc` Future Crop Care (Telangana) | `gfl` Green Fields (Raichur, Karnataka) |
|---|---|---|
| role users | `+91900000000{1..10}`, one per role | `+91910000000{1..10}` |
| clusters | North Telangana (WGL, KNR, NZB), South Telangana (NLG, KMM) | Raichur |
| stores | WGL Warangal, KNR Karimnagar, NLG Nalgonda, KMM Khammam, NZB Nizamabad (real lat/lon) | RCR Raichur |
| field officers | 5, one per store: `+919000000004` (WGL) and `+91900000001{1..4}` | 1 (`+919100000004`) |
| store manager / cluster head | `+919000000003` → WGL, `+919000000002` → North Telangana | RCR / Raichur |
| villages | 40 (8 mandal-HQ villages per store, 6–22 km away, meeting point on every other one) | 8 |
| farmers | 200 (`+919000100001..200`, Telugu names, 40 per officer, 5 per village); farmer #1 is the demo farmer login `+919000000010` | 10 |
| farms | 1–2 per farmer, convex 0.5–5 acre polygons on a grid around the village (never overlapping), declared acres within ±7 % of `ST_Area` | same |
| crop plots | 1–2 per farm over the six pilot crops with variety, kharif 2026 (75 %) / rabi 2025-26, sowing date, stage, expected harvest | same |
| consent | `data` granted for all, `marketing` for ~60 % (8 % of those withdrawn as a second row); `farmer.consent_marketing` caches the latest | same |

The `SMALL` profile (`--small`; what the test fixtures use) keeps the structure with 15 + 4
farmers and 2 villages per store. Counts of the full profile: 3 clusters, 6 stores, 48 villages,
12 crops, 210 farmers, 285 farms, 403 crop plots, 338 consent records (`make seed` prints them).

M2 (`farmerapp/jobs/seed_m2.py`, since M2-KICKOFF): for every officer (5 + 1) a location policy
acceptance and, per duty day (`SeedProfile.duty_days`: 7 ending on 2026-09-18; `SMALL` 2), a duty
session 09:00-~18:00 IST from the store (one in seven auto-ended at 20:00), a track with a point
every 2 min moving / 10 min stationary carrying every VV-002 field (~150 points a day), 4-7 visits
(`SMALL` 2-3) to the officer's farmers — 80 % inside the farm geofence, some outside, some approved
overrides, meetings at the village meeting point — with 1-3 photos (EXIF near the check-in, a few
gallery / far ones), ~60 % confirmed by SMS OTP / push / QR, 15 % shorter than 5 minutes, a few
mock-location / clock-drift days, and scores + statuses from `farmerapp.visits.scoring`. Full
profile: 6 policy acceptances, 42 duty sessions, 216 visits, 400 visit photos, 137 confirmations, 6,108 location points; 2.0 s for the whole seed, 0.3 s when nothing is missing. The seed creates the daily `location_point` partitions it needs first.

## Farmers, farms, consent (M1 data model)

Tables `cluster`, `store`, `village`, `crop`, `farmer`, `farm`, `crop_plot`, `consent_record`
(Alembic `0005`), all with the base columns and RLS. Notes for the loop:

- `farmer` is unique on `(tenant_id, phone)` (FA-012); `phone_last4` is a searchable
  stand-in for when SEC-026 encrypts the number; `registered_by` (officer) and `user_id`
  (the farmer's own login) drive the SPEC 2.6 scope; `village.store_id` maps a farmer to a
  store, `store.cluster_id` to a cluster.
- `farm.boundary` is `geography(Polygon, 4326)` written as EWKT (`farmerapp.db.geo`);
  `farm.centroid` and `farm.area_acres_computed` are **stored generated columns** (`ST_Centroid`,
  `ST_Area / 4046.8564224`) loaded with `eager_defaults`, so VA-F02/VA-F03 checks (centroid
  within 50 m, declared vs measured acres, overlap) are SQL over indexed columns. Reads get
  `boundary_geojson`, `centroid_lat/lon` as column properties.
- `consent_record` is append-only (FM-002): a withdrawal is a new row with `withdrawn_at`;
  the newest row per `(subject_id, purpose)` is the state; `created_at` is the wall clock.
- `GET /v1/farmers` / `GET /v1/farmers/{id}` (farms with crop plots, consent history) use
  `farmerapp.auth.scope.farmer_filters(actor)`; the agronomist gets a masked phone and no
  landmark.

## Duty, location and visits (M2 data model)

Tables `duty_session`, `location_point`, `location_daily_agg`, `policy_acceptance`, `visit`,
`visit_photo`, `visit_confirmation` (Alembic `0007`), all with `tenant_id` and RLS. Notes for
the loop:

- `location_point` is **declaratively partitioned by day** (`PARTITION BY RANGE (ts)`, UTC
  days, primary key `(id, ts)`, no DEFAULT partition). Partitions `location_point_pYYYYMMDD`
  are created by the SQL function `ensure_location_partitions(from_day, to_day)` /
  `(days_ahead)` (SECURITY DEFINER, owned by the migrate role, EXECUTE granted to the app
  role) which also enables + forces RLS and installs both policies on each child: run
  `python -m farmerapp.jobs ensure-partitions` daily (yesterday .. today + 7). A point whose
  day has no partition fails loudly. Not audited, never in the sync feed; every point has
  `accuracy_m, speed_mps, bearing, battery_pct, is_mock, is_rooted, clock_drift_s, provider,
  received_at` (VV-002 / FA-028).
- Retention (SPEC 2.6): `python -m farmerapp.jobs purge-location-points` reports the
  partitions older than 180 days (dry run); `--apply` folds each into `location_daily_agg`
  (km from consecutive point distances, points, first / last ts per officer and day) and
  drops it. The function refuses a window under 180 days.
- `duty_session`: `end_reason` `manual | auto_time | auto_idle | forced` (VV-007; both
  `end_at` and `end_reason` or neither), `policy_version` = the accepted location policy
  (VV-010), `km` / `stops` filled by track processing (VV-006).
- `policy_acceptance` (FA-011 / VV-010) is append-only: a newer policy version is a new row;
  the latest per `(user_id, policy_key)` is the accepted version. The version the app must
  accept is the tenant setting `location_policy_version`.
- `visit`: `geofence_result` `inside | outside | meeting_point | override` (an override needs
  `override_note`; `override_approved_by` is the cluster head), generated `duration_s`,
  `score` / `score_components` / `status` from `farmerapp.visits.scoring.score_visit_row`
  (VV-004: geofence 30, confirmation 30, in-app photo with EXIF time within the visit
  window and GPS within 150 m 20, duration >= tenant `min_visit_duration_s` 10, device
  integrity 10; VV-005: verified >= 70, partial 40-69, unverified < 40, `open` until
  check-out), `device_integrity {is_mock, is_rooted, clock_drift_s}`, `client_visit_id`
  (device id, unique per tenant), `flags` (`under_minimum`, FA-017). The write endpoints are
  in "Visit flow" below.
- `visit_photo` keeps EXIF time + point, `taken_in_app`, device and server time, `sha256`
  and `phash` (VA-E08); `visit_confirmation` the channel, OTP challenge, farmer phone last4
  and confirming device (VA-E05), later the FM-011 rating.
- Tenant settings (`farmerapp/tenants/settings.py`, `tenant_settings(tenant.settings)`):
  `geofence_radius_m` 150, `min_visit_duration_s` 300, `auto_duty_end_local_time` "20:00",
  `idle_end_minutes` 60, `location_policy_version` "2026-09-v1" (TODO-LEGAL),
  `sampling.moving_s` 120 / `stationary_s` 600 / `upload_s` 900; `village.meeting_point_radius_m`
  overrides the radius per village.
- Reads: `GET /v1/visits` (`officer_id`, `farmer_id`, `from`, `to`, `status`; cursor) and
  `GET /v1/visits/{id}` (photos, confirmations, score components) scoped by
  `farmerapp.auth.scope.visit_filters`; `GET /v1/duty-sessions` and
  `GET /v1/officers/{id}/track?day=YYYY-MM-DD` (IST day) scoped by `TRACK_VISIBILITY`
  (SPEC 2.6 "Officer location track": owner / director / auditor / tenant admin all,
  cluster head own cluster, officer self only; store managers, accountants, agronomists and
  farmers are not on the routes).
- Sync: `visit`, `visit_photo`, `visit_confirmation`, `duty_session`, `policy_acceptance`
  are in `SYNC_ENTITIES` and the change feed (`location_batch` is write-only); conflict
  rules `merge_fields` for visit / duty_session with `SERVER_OWNED_FIELDS` (score, status,
  confirmation, geofence decision; km, stops, and the end of an auto-ended session),
  `server_wins` for photos, confirmations and acceptances. Visit ops are applied by
  `farmerapp/visits/sync_ops.py` ("Visit flow" below); duty sessions, acceptances and
  location batches by the FA-010 / FA-011 services (next section).

## Duty, location ingest and the location policy (FA-010 / FA-011 / VV-001 / VV-002 / VV-007 / VV-010)

Location is collected only on duty: the server never stores a point outside a duty
session's window, whatever a device sends.

- **Policy first** (`farmerapp/policies/`): `GET /v1/policies/location` (any role) returns
  `{version, text_hash, text: {en, te, kn, hi, mr}}` — the tenant's
  `location_policy_version` with the four points of `location_policy_texts.json`
  (TODO-LEGAL placeholder; a wording change is a new version, HR signs the same version
  string — VV-010). `POST /v1/policies/location/accept {version, text_hash, device_id,
  app_version}` (201) or the sync op `policy_acceptance create` (offline first run;
  `accepted_at` = `client_ts`) writes the append-only acceptance; a version / hash that is
  not the tenant's current one is `422 policy_version_stale`. Bumping the tenant setting
  invalidates every earlier acceptance.
- **Duty** (`farmerapp/duty/`): sync `duty_session create` = `POST /v1/duty/start` (201)
  with `{id, device_id, app_version, policy_version, start_at, start_point, integrity}`
  — `422 policy_not_accepted` (with `required_version`) until the current version is
  accepted, `409 duty_already_active` (with the open session id) unless that session is
  older than 24 h (then it is closed `forced` first). `duty_session update` =
  `POST /v1/duty/end` with `{end_at, end_point, end_reason manual|auto_time|auto_idle}`
  computes `km` and `stops` from the stored points (`duty/track.py`: points with accuracy
  > 100 m ignored, jumps > 90 km/h dropped, a stop is ≥ 5 min within 100 m); an end op on
  a session the server already ended is a `conflict` carrying the server state.
  `GET /v1/duty/current` → `{session | null, policy_version, policy_accepted}`,
  `GET /v1/duty/policy` → `{moving_interval_s, stationary_interval_s, upload_interval_s,
  upload_on_wifi_or_charging}` (VV-001, tenant settings). Roles: field_officer,
  cluster_head; sessions are always the caller's own.
- **Points** (`farmerapp/location/ingest.py`): sync `location_batch create` =
  `POST /v1/location/batch` (field_officer) with `{id, duty_session_id, device_id, sent_at,
  points[≤ 500]{ts, lat, lon, accuracy_m, speed_mps, bearing, battery_pct, is_mock,
  is_rooted, provider}}`. Each point is stored only when `ts` is inside
  `[start_at − 2 min, end_at (or now) + 2 min]` of the caller's own session; the result is
  `applied` with `server: {accepted, rejected: [{index, reason: off_duty | future |
  duplicate}], clock_drift_s, received_at}`. `clock_drift_s` = device `sent_at` − server
  `received_at` (rounded) is stored on every point (VV-002 / VA-E01). Duplicates by
  `(officer_id, ts)` are ignored. A replay (same `op_id` or `Idempotency-Key`) stores
  nothing twice.
- **Auto end** (`farmerapp/duty/auto_end.py`): `python -m farmerapp.jobs auto-end-duty
  --tenant-id <id> [--tenant-id …]` (Cloud Scheduler every 10 min) closes open sessions
  at the tenant's `auto_duty_end_local_time` (IST; the first cutoff after `start_at`) with
  `auto_time`, or after `idle_end_minutes` without movement (< 100 m across the window's
  points, window covered by data) within 200 m of `user.home_point` (migration 0008;
  fallback: the store's location) with `auto_idle`. Both write a `notification` row
  (`kind duty_auto_ended`, i18n keys `notification.duty_auto_ended.*`, `data
  {duty_session_id, end_reason, end_at}`) for the officer so the app can prompt (FA-007
  delivers). After the end the ingest rejects every later point: no tracking beyond auto
  end. `officer-sync-silence --tenant-id …` (OPS-006) notifies the cluster head(s) once per
  session when an officer on duty has sent no batch for 2 h (`received_at`).
- **Notifications** (`farmerapp/notifications/models.py`): `notification` (tenant, user,
  kind, title_key, body_key, data jsonb, created_at, read_at), RLS, not audited; the FA-007
  inbox and FCM delivery build on it.

## Visit flow (FA-014 .. FA-017, FA-028; VV-003 .. VV-005)

One write path, `farmerapp/visits/service.py`, behind the REST twins in
`farmerapp/visits/router.py` and the `POST /v1/sync` ops in `farmerapp/visits/sync_ops.py`
(the device queues exactly the REST bodies). Roles: field officer, cluster head and store
manager make visits and write only their **own** (anything else is 404); the farmer completes
push / QR confirmations on visits made to them; the cluster head of the officer's cluster
(or an owner / director / tenant admin) decides overrides. Migration `0009_visits_flow`
(branch `visits`, revises 0007; `0010` merges it with the duty head 0008).

- **Check-in** `POST /v1/visits/check-in` (201, `Idempotency-Key`; sync `visit.create`)
  `{id?, farmer_id, farm_id?, village_id?, purpose, checkin_at, checkin_point{lat,lon,accuracy_m},
  device_integrity{is_mock,is_rooted,clock_drift_s}, override_note?, client_visit_id?}`.
  VV-003 in PostGIS (`farmerapp/visits/geofence.py`): inside the farm polygon buffered by the
  tenant `geofence_radius_m` (150) -> `inside`; within the village meeting point's radius
  (`village.meeting_point_radius_m`, else the tenant default) -> `meeting_point`; otherwise
  `422 outside_geofence` with `detail`, `distance_m` (to the nearest target), `target`
  (`farm` / `meeting_point` / null) and `radius_m` -- unless `override_note` is present: the
  visit is created with `geofence_result: override`, an `override_request` row (pending,
  `approver_role: cluster_head`) and an `OverrideRequested` event. `POST
  /v1/visits/{id}/override/approve|reject {note?}` decides it; while pending or rejected the
  geofence component scores 0, approved earns 15 of 30 and rescores. A replayed check-in
  (same `id` / `client_visit_id`) returns the existing visit. `farm_id` null means only the
  meeting point counts; no boundary and no meeting point -> override needed.
- **FA-028** integrity is recorded on `visit.device_integrity` (`issues`:
  `mock_location | rooted_device | clock_drift` for drift > 300 s), exposed as
  `integrity_issues`, logged as WARNING `integrity_signal` and published as
  `IntegrityEvent` on `farmerapp.visits.events.bus` (M4 / VA-E01 subscribes). Never blocks;
  the integrity component of the score is 0.
- **Capture** `PATCH /v1/visits/{id} {notes?, crop_stage?, purpose?}` (sync `visit.update`;
  last writer wins). **Photos** `POST /v1/visits/{id}/photos` (201, sync `visit_photo.create`)
  `{id?, blob_uri, sha256?, exif_time?, exif_point?, taken_in_app, device_time?}`: the blob
  must be a completed upload under the tenant's prefix; `taken_in_app: false` ->
  `422 gallery_not_allowed`; the server stores `server_time`, its own `sha256`
  (`422 photo_sha_mismatch` if the client's differs), the perceptual hash `phash`
  (`imagehash.phash`, 16 hex chars; null for undecodable bytes) and, when the payload has no
  EXIF, the JPEG's `DateTimeOriginal` / GPS (times without an offset are read as IST).
  VA-E08 evidence goes to `photo_flags` (`exif_time_missing`, `exif_time_mismatch` > 30 min
  outside check-in .. check-out, `exif_gps_missing`, `exif_gps_mismatch` > 300 m from the
  check-in, `duplicate_photo` same sha256 / phash on another visit) -- never a rejection.
  Detail reads carry a 15-minute `signed_url` per photo.
- **Confirmation** (FA-016) `POST /v1/visits/{id}/confirm/request {channel}` (202):
  `sms_otp` sends a code to the farmer's phone through the FA-001 OTP service (purpose
  `farmer_confirm`, same 5-minute validity, 3 resends / 15 min, lockout after 5 misses;
  response has `phone_masked`, `expires_in`, `resends_left`); `app_push` needs a farmer with
  an app account (`422 confirmation_channel_invalid` otherwise) and publishes
  `ConfirmationRequested` with the token for FA-007 delivery; `qr` returns `token` to render
  as a QR. Tokens are HS256 JWTs `typ = visit_confirm` bound to tenant, visit and the
  pending `visit_confirmation` row (`token_hash`), valid `VISIT_CONFIRM_TOKEN_TTL_SECONDS`
  (24 h) so a QR scanned offline is validated when the farmer app is back online.
  Completion: `POST /v1/visits/{id}/confirm {channel: sms_otp, code}` on the officer's phone
  (wrong code -> `401 otp_invalid`, attempts counted; push / QR here ->
  `422 confirmation_channel_invalid`), `POST /v1/visits/{id}/farmer-confirm {token, rating?,
  reason?}` (role farmer, own visits; FM-011 rating stored on the row). The visit is
  `confirmed` only when one channel succeeds; a second channel afterwards is
  `409 visit_already_confirmed`; pending rows of other channels expire. Sync
  `visit_confirmation.create {visit_id, channel: sms_otp, code}` (officer; the code must
  still be valid when the batch arrives -- OTP needs connectivity by nature, the request
  itself has no sync op) or `{visit_id, channel: qr|app_push, token, rating?, reason?}`
  (farmer).
- **Check-out** `POST /v1/visits/{id}/check-out {checkout_at, checkout_point?}` (sync
  `visit.update` with those keys): `duration_s` is generated, a duration under the tenant
  `min_visit_duration_s` (300) sets `flags: ["under_minimum"]` without rejecting
  (`422 checkout_before_checkin`, `409 visit_already_checked_out` for a different time),
  then `rescore` writes `score`, `score_components` and `status` (VV-004: geofence 30,
  confirmation 30, in-app photo with EXIF time in the window and GPS within 150 m 20,
  duration 10, integrity 10; VV-005: verified >= 70, partial 40-69, unverified < 40).
  `rescore` runs again on every later photo, confirmation or override decision and is
  idempotent (no version bump when nothing changed); while the visit is open the live
  components are stored and `score` / `status` stay null / `open`.
- Reads: `GET /v1/visits/{id}` returns photos (+ signed URLs, flags), confirmations
  (status / requested / expires), `override_request`, `score_components`,
  `integrity_issues` and `flags`.

## Catalogue, stock, orders, payments, khata (M3 data model)

Alembic `0011`; design notes in `docs/prs/M3-kickoff.md`. Money is `bigint` paise everywhere
(`tests/catalog/test_models.py` fails on any numeric / float money column); GST is
`gst_rate_bp` (1800 = 18 %).

| Package | Tables | Helpers |
|---|---|---|
| `catalog/` | `product`, `sku`, `price_list`, `pest_or_disease`, `label_claim` | `pricing.price_for(session, sku_id, store_id, day)` (store override, else tenant default, latest `effective_from` in force; `None` → use MRP) |
| `stock/` | `stock_batch` (qty = cache), `stock_movement` (append-only ledger) | `ledger.apply_movement(...)` (the only way to change stock: appends the movement and updates the batch in one flush, never below zero), `stock_on_hand(store, sku)` = sum of movements |
| `orders/` | `order`, `order_line` | `line_total_paise`, `tax_paise`; `order_line.label_claim_id` = why a SKU was recommended |
| `payments/` | `payment`, `webhook_event`, `day_close` | `provider_event_id` / `event_id` unique per tenant + provider (SEC-023 idempotency) |
| `khata/` | `khata_entry` (append-only), `credit_limit` | `khata_balance(session, farmer, store=None, as_of=None)` = debits − credits (FA-022), `overdue_paise` |

```python
# stock: never touch stock_batch.qty directly
await apply_movement(
    session,
    tenant_id=t,
    store_id=s,
    sku_id=k,
    kind=MovementKind.SALE,
    qty=Decimal(-2),
    batch=batch,
    ref_type="order",
    ref_id=order.id,
)
# khata: a correction is a new entry, never an update (the app role cannot UPDATE / DELETE)
balance = await khata_balance(session, farmer_id, store_id)
```

- **DX-007**: `label_claim.status` is `draft | approved | retired`; only approved claims are
  returned to anyone but the agronomist / owner / tenant admin, and only approved claims may back a
  recommendation. Seed claims carry `source_ref = SEED_SOURCE_REF` until the agronomist
  replaces them with CIB&RC data (human gate).
- Reads: `GET /v1/catalog/products` (`q`, `category`, `own_brand`, `store_id` adds price +
  stock), `GET /v1/catalog/skus/{id}`, `GET /v1/catalog/label-claims`,
  `GET /v1/stores/{id}/stock`, `GET /v1/orders[/{id}]`, `GET /v1/payments`,
  `GET /v1/farmers/{id}/khata`; scope helpers in `auth/scope.py` (`store_filters`,
  `order_filters`, `payment_filters`, `khata_farmer_filters`).
- Sync: `order`, `order_line`, `payment`, `khata_entry` are in the feed with `server_wins`;
  device writes: `order` create (FA-020) and `payment` create (FA-021) are live, `order_line`
  and `khata_entry` stay `unsupported_action` (lines travel inside the order).
- Seed: `jobs/seed_catalog.py` (static products, packs, problems, claims) and
  `jobs/seed_m3.py` (`M3_FULL` / `M3_SMALL` via `SeedProfile.m3`).

## Product master, label claims, price lists (WC-005)

Alembic `0014_catalog_writes` (branch `catalog`); design notes in `docs/prs/WC-005.md`.

- Writes: `POST/PATCH /v1/catalog/products`, `POST/PATCH /v1/catalog/skus` (owner, director,
  tenant admin). GST is one of 0 / 5 / 12 / 18 / 28 % (`gst_rate_bp` 0 / 500 / 1200 / 1800 /
  2800), HSN 4, 6 or 8 digits (422 `validation_error` naming the field), barcode unique per
  tenant (409 `barcode_exists`), brand + name unique (409 `product_exists`).
  `GET /v1/catalog/barcode/{code}` for POS scans; `GET /v1/catalog/crops|pests|stores`.
- Label claims: `POST /v1/catalog/label-claims` creates a `draft` (owner, tenant admin,
  agronomist); `POST .../{id}/approve` is **agronomist only** (SPEC 14.6 human gate:
  `approved_by` / `approved_at`); `POST .../{id}/retire`; `PATCH` edits a draft in place and
  turns an edit of an approved claim into a new draft with `supersedes_id` (approving it
  retires the old version); `GET .../{id}/history`. Validation: pest / disease claims only on
  pesticide, fungicide, herbicide or growth products (422 `claim_category_invalid`), the
  pest's crop must be the claim's crop (422 `pest_not_for_crop`), dose value > 0 with a unit,
  PHI >= 0, one approved claim per SKU x crop x pest (409 `claim_duplicate`; partial unique
  index `uq_label_claim_approved`).
- Price lists: `PUT /v1/catalog/price-lists` (bulk upsert for a store or the tenant default,
  keyed by SKU + `effective_from`, all or nothing): price <= MRP (422 `price_above_mrp`), no
  overlapping ranges per SKU + store (409 `price_overlap`; exclusion constraint
  `ex_price_list_no_overlap` as backstop); both carry `rows: [{index, sku_id, code}]`.
  `GET /v1/catalog/price-lists?store_id=&at=&sku_id=`.
- CSV: `POST /v1/catalog/import/products` and `/import/label-claims` (`{"csv": ..., "dry_run":
  true}` by default; row-level report; nothing written on any error; claims import as drafts
  only) and `GET /v1/catalog/export?kind=products|label_claims` (audited as `catalog.export`).

**The recommendation guardrail (DX-007).** Every recommendation draws from one function:

```python
from farmerapp.catalog.recommendable import assert_sku_recommendable, recommendable_skus

skus = await recommendable_skus(
    session, tenant_id=t, crop_id=crop, pest_or_disease_id=pest
)  # approved, live claims for exactly this crop x pest, with dose / tank / PHI / PPE / safety
await assert_sku_recommendable(
    session, tenant_id=t, sku_id=sku, label_claim_id=claim
)  # before attaching a label_claim_id to an order line: 422 sku_not_recommendable otherwise
```

`GET /v1/catalog/recommendable?crop_id=&pest_id=` wraps it (console C51 preview).

## Orders, stock movements, credit and khata (FA-020 / ST-003 / ST-005 / ST-007 / FA-022)

Alembic `0012_orders_stock_credit` (branch `orders`): `stock_reservation`, append-only
`order_status_event`, `credit_approval_request`, `stock_movement.reason` / `photo_uri`.
Design notes and the two shared functions: `docs/prs/FA-020-api.md`.

| Route | Roles | Notes |
|---|---|---|
| `POST /v1/orders` | field officer (own farmers), store manager / accountant (own store), farmer (self) | server prices (`price_for`), FEFO reservation, `payment_mode=credit` → credit gate (402) |
| `POST /v1/orders/{id}/status` | owner, director, tenant admin, cluster head, store manager, accountant (store scope) | ST-005 `TRANSITIONS`; 409 `invalid_transition` |
| `GET /v1/stores/{id}/order-queue` | store roles (store scope) | open statuses by default, `status=` repeatable |
| `GET /v1/stores/nearest?farmer_id=&sku_id=` | order placers + management | village store, else nearest by distance; availability per SKU |
| `POST /v1/stores/{id}/stock/receipts` · `/write-offs` | owner, director, cluster head, store manager | 409 `negative_stock` / `batch_mismatch` |
| `POST /v1/stock/transfers` | same | `transfer_out` + `transfer_in` atomically, batch identity kept |
| `POST /v1/stores/{id}/stock/adjustments` | store manager | counted qty, reason, `stock.adjustment` audit event |
| `PUT /v1/farmers/{id}/credit-limit` | store manager (≤ `store_manager_max_credit_limit_paise`), cluster head, owner, director | tenant setting default ₹50,000 |
| `GET /v1/credit-approvals`, `POST .../{id}/approve\|reject` | read: store roles; decide: cluster head, owner, director | approved request = that order proceeds once |
| `POST /v1/farmers/{id}/khata/entries` | store manager (own store) | manual adjustment, reason required, audited, append-only |

```python
# Stock: available = on hand (ledger sum) - active reservations. Reservations are rows in
# stock_reservation, not movements; handover turns them into sale movements.
from farmerapp.stock.service import allocate_fefo, consume_order, release_order

# Credit sales (orders and POS): the gate posts the khata debit itself when allowed.
from farmerapp.khata.credit import check_and_reserve_credit

decision = await check_and_reserve_credit(
    session,
    tenant_id=t,
    farmer_id=f,
    store_id=s,
    amount_paise=total,
    order_id=order_id,
    actor=user,
)
if not decision.allowed:
    ...  # answer 402 credit_limit_exceeded WITHOUT raising (the approval request must commit)

# Payments / repayments: a new credit row on the khata.
from farmerapp.khata.ledger import post_credit

await post_credit(
    session,
    tenant_id=t,
    farmer_id=f,
    store_id=s,
    amount_paise=amount,
    ref_type="payment",
    ref_id=payment.id,
    actor=user,
)
```

- Tenant settings read by `khata.ledger.CreditSettings`: `store_manager_max_credit_limit_paise`
  (default 5,000,000) and `credit_due_days` (default 90; due date of a credit sale without a
  known harvest).
- `GET /v1/farmers/{id}/khata` adds `open_debits` (FIFO-settled, due date, days overdue,
  bucket), `overdue_buckets` (`0_30` / `31_60` / `61_90` / `90_plus`, SPEC 5.2) and
  `payment_history`.
- Sync: `order` create = offline capture (entity id = order id; replay → `conflict`); a
  credit sale beyond the limit is `rejected` with `credit_limit_exceeded` (402) and the
  approval request id in `error.errors[0]`.

## Payments, webhooks, POS invoices and day close (FA-021 / SEC-023 / ST-001 / ST-002 / ST-006)

Alembic `0013_payments_invoices` (branch label `payments`, on `0011`); PR notes in
`docs/prs/FA-021-api.md`. Money is paise and **always recomputed server-side** (SEC-023).

| Route | Roles | What |
|---|---|---|
| `POST /v1/payments` | owner, accountant, cluster head, store manager, field officer, farmer (UPI / link only) | order (`order_id`) or khata dues (`farmer_id` + `store_id`); `upi_qr` -> `{qr_payload, expires_at}`, `payment_link` -> `{short_url}` sent by SMS / WhatsApp, `cash` needs `receipt_uri` (-> `pending_reconciliation`), `card_terminal` needs `reference_note`, `credit` calls the ledger port; a differing `amount_paise` is 422 `amount_mismatch` |
| `GET /v1/payments/{id}` | payment readers | `state` = waiting / paid / failed (A53 polls it) |
| `POST /v1/webhooks/razorpay` | public (`x-public`) | HMAC-SHA256 of the raw body (`X-Razorpay-Signature`, constant time; bad -> 401, attempt stored), replay window (tenant `webhook_replay_window_s`, default 300 s -> 400 `webhook_stale`), idempotent by `X-Razorpay-Event-Id`, stored in `webhook_event` then applied inline or published to `payment.webhook` |
| `POST /v1/stores/{id}/pos/sales` | store manager (own store), accountant | `pos` order handed over + stock sale movements (through `OrderPort`), GST invoice + PDF, payment — one transaction |
| `GET /v1/invoices/{id}`, `/pdf`, `POST .../share` | readers of the order; share: owner, accountant, cluster head, store manager | invoice JSON, signed PDF URL, WhatsApp / SMS link |
| `GET /v1/stores/{id}/day-summary?date=` | store readers | totals by mode, waiting, failed, refunds, expected cash (IST day) |
| `POST /v1/stores/{id}/day-close`, `.../day-close/{close_id}/reopen` | close: owner, accountant, cluster head, store manager; reopen: owner, director, cluster head | cash count, variance, deposit slip; over `day_close_variance_threshold_paise` (default Rs 500) notifies auditors + `CashVarianceDetected` |

```python
# providers: one protocol, three adapters (payments/providers.py)
provider: PaymentProvider = RazorpayProvider(
    base_url=..., key_id=..., key_secret=..., webhook_secret=...
)
qr = await provider.create_upi_qr(
    amount_paise=11800, reference=str(payment.id), description="Order", notes=notes, expires_at=exp
)
# ports the orders branch plugs into (payments/ports.py, invoices/ports.py)
decision = await services.ledger.check_and_reserve_credit(
    session, tenant_id=t, farmer_id=f, store_id=s, amount_paise=a, order_id=o, actor=actor
)
entry = await services.ledger.post_credit(
    session,
    tenant_id=t,
    farmer_id=f,
    store_id=s,
    amount_paise=a,
    ref_type="payment",
    ref_id=p,
    actor=actor,
)
# in-process events (payments/events.py): subscribe, never import payments internals
bus.subscribe(PaymentCaptured, on_payment_captured)
```

- Settings: `PAYMENT_PROVIDER` (`razorpay` | `fake`), `PAYMENT_WEBHOOK_DELIVERY` (`inline` |
  `pubsub`), `RAZORPAY_KEY_SECRET` / `RAZORPAY_WEBHOOK_SECRET` (Secret Manager in stg / prd;
  the prd guard rail refuses the dev defaults). Tenant keys (`payments/config.py`):
  `webhook_replay_window_s`, `day_close_variance_threshold_paise`, `legal_name`,
  `gstin_by_state` (placeholder GSTIN until the owner enters the real ones — human gate),
  `invoice_prefix`.
- Invoice numbers `FCC/KND/2026-27/000123`: gapless per store and financial year via the
  `invoice_counter` row locked `FOR UPDATE` (`invoices/numbering.py`); intra-state CGST +
  SGST at half the rate each, inter-state IGST, round-off to the rupee, total in words
  (Indian system); PDF by fpdf2 into the blob store.
- Sync: `payment` **create** is live (officer offline cash / credit; `entity_id` = payment id;
  UPI / link -> `rejected` `requires_network`).
- Job: `python -m farmerapp.jobs reconcile-payments --tenant-id <id> [--date YYYY-MM-DD]`
  (OPS-008 dry run: settlements vs paid payments; accountants notified on mismatches).

## M3 integration: credit, ledger, POS and payment events

Alembic `0015_merge_m3_heads` joins `0012` (orders), `0013` (payments) and `0014` (catalog)
into one head. Notes: `docs/prs/M3-integration.md`.

- **Credit** (`payment.mode = credit`, POS credit sales, the `payment` sync op) goes through
  the real `khata.credit.check_and_reserve_credit` via `payments.ports.KhataLedgerPort`
  (no 503 fallback). Allowed: the gate posted the debit, `payment.khata_entry_id` links it.
  Blocked: `CreditBlocked` is *returned* and the route answers 402 `credit_limit_exceeded`
  (`khata.credit.credit_blocked_response`) so the `credit_approval_request` commits. The POS
  asks the gate before it writes the order (pre-assigned order id), so a refused sale leaves
  no order, invoice number or stock movement behind.
- **Dues** paid in cash / card / webhook post their khata credit through the real
  `khata.ledger.post_credit` (balance = sum of entries).
- **POS orders**: the default `OrderPort` is `farmerapp.orders.pos.OrdersPosPort` (DX-007
  check, FEFO via `stock.service.allocate_fefo`, reservations consumed into `sale`
  movements, status event); `app.state.pos_orders` still swaps it.
- **Events**: `farmerapp.orders.payment_events` subscribes to `PaymentCaptured` with
  `bus.subscribe_async` (runs in the payment's transaction, in a savepoint). A prepaid order
  (`payment_mode` `upi_qr` / `payment_link`) is placed with its stock held and waits in
  `placed`; once fully paid it moves `placed -> reserved` and the farmer / placing user are
  notified. Registered by `create_app` and by the worker's `payment.webhook` handler.
- **DX-007**: every `order_line.label_claim_id` (REST order, `order` sync op, POS
  `lines[].label_claim_id`) is checked with `catalog.recommendable.assert_sku_recommendable`;
  otherwise 422 `sku_not_recommendable` with `errors[].loc = ["lines", i, "label_claim_id"]`.

## Validation agents: rules engine and flags (M4 / VA-001 .. VA-003 / VA-007 / WC-010 / OPS-010)

Alembic `0018_flags_rules` (branch label `flags`, on `0017`); PR notes in
`docs/prs/M4-rules-engine.md`; authoring guide in `rules/README.md`.

- **Rules** are `rules/<id>.yaml` at the monorepo root (VA-001), validated by
  `farmerapp/rules/schema.py` when the API, worker or a job starts (`validate_rules`; an
  invalid file refuses to start; a missing directory logs `rules_dir_missing` and runs no
  rules). `RULES_DIR` points elsewhere (containers). Each rule is one module
  `farmerapp/rules/checks/va_<id>.py` with `@rule("VA-F02")`, reading `ctx.param(...)`.
- **Runners** (SPEC 6.1, `farmerapp/rules/engine.py`): `run_inline` from the FA-012 write
  paths (registration, farmer name / village edits, farm add / boundary edit),
  `emit(session, tenant, topic, ids)` for event rules (registration emits
  `farmer.registered`; the worker's `visit.created` / `farmer.registered` / `payment.webhook`
  handlers call `rules.events.handle_event_message`; `payment.captured` runs in-process),
  `run_batch` from `python -m farmerapp.jobs run-rules --mode batch --tenant fcc` (nightly
  02:00 IST). A savepoint per rule: a failing rule is logged, never fails the write.
- **Flags** (`farmerapp/flags/`): `raise_flag` dedupes (`<rule>:<subject>:<id>:<key>`, partial
  unique index on unresolved flags; already reviewed under the same rule version -> not
  raised again), routes (VA-003: employee -> cluster head, farmer data -> store manager, high
  severity also auditors as `watchers`, fallback up the ladder), sets the SLA and notifies
  (`flag_assigned`). History in append-only `flag_event` (resolutions carry the VA-006
  `label`), thread in `flag_comment`.

| Route | Roles | What |
|---|---|---|
| `GET /v1/flags` | owner, director, auditor, tenant admin (tenant); cluster head (own cluster, owned / watched); store manager (own store's farmer-data flags, owned); field officer (flags about themselves) | filters `status` / `severity` (repeatable), `rule_id`, `subject_type`, `owner=me`, `overdue`; `counts` by severity and rule; cursor pagination, newest first |
| `GET /v1/flags/{id}` | same | evidence records with summaries (reviewers), map points / polygons, signed photo URLs, history, comments, `allowed_transitions` |
| `POST /v1/flags/{id}/transition` | reviewers (not field officers) | `open -> in_review -> resolved_valid / resolved_fixed / escalated`, `escalated -> resolved_fixed / resolved_action`; anything else 409 `invalid_transition`; resolutions and escalation need a note; escalating hands the flag to an auditor |
| `POST /v1/flags/{id}/comments` | all readers | the subject's comment is `is_subject_explanation` (VA-005); resolved -> 409 `flag_resolved` |
| `POST /v1/flags/{id}/assign` | reviewers | to an active reviewer of the tenant, never the subject (422 `assignee_invalid`) |

```python
# a new rule: rules/VA-E02.yaml + this module + rules/fixtures/VA-E02/{positive,negative}.yaml
@rule("VA-E02")
async def check(ctx: RuleContext) -> list[Finding]:
    limit = float(ctx.param("max_speed_kmh"))  # from the YAML (tenant overrides applied)
    ...  # read through ctx.session; ctx.subject_ids is None in batch
    return [Finding(subject_type=Subject.EMPLOYEE, subject_id=officer_id, key=day, title=t)]


# write paths and subscribers
await engine.run_inline(session, tenant_id, Subject.FARMER, [farmer.id])
await engine.emit(session, tenant_id, "farmer.registered", [farmer.id])
```

- Jobs: `python -m farmerapp.jobs run-rules --tenant <id|fcc|gfl> [--mode batch] [--rule ID]`,
  `python -m farmerapp.jobs flags-sla-escalation --tenant ...` (OPS-010, hourly: unresolved
  flags past their SLA move one level up with a fresh SLA and a `flag_escalated`
  notification), `python -m farmerapp.jobs validate-rules [--rules-dir]` (run by
  `make check-api`: YAML valid, every rule implemented, both fixtures present),
  `python -m farmerapp.jobs backfill-farm-photo-phash --tenant ... [--batch-size N]
  [--no-run-rules]` (VA-F08, once after Alembic 0023: computes `farm_photo.phash` from the
  blob store for rows without one, then runs VA-F08 on their farms; idempotent, missing /
  undecodable blobs stay NULL and are counted). New farm photos get their pHash on the
  write path (registration, farm add / edit, their sync ops; `farmers/photo_hash.py`).
- Tests: golden fixtures `tests/rules/test_fixtures.py` (harness `tests/rules/harness.py`),
  loader / tuning `tests/rules/test_loader.py`, runners `tests/rules/test_engine.py`, API
  `tests/flags/test_api.py`, routing / dedupe / SLA `tests/flags/test_service.py`.


## Analytics read API (AN-001 .. AN-003, AN-011, WC-001 .. WC-004)

`farmerapp/analytics/` serves the console dashboards from the live Postgres tables (SPEC
5.3: BigQuery / dbt are P1). Payloads for the console: `docs/prs/M4-analytics-api.md`.

- Routes (all `GET /v1/analytics/...`, read-only): `owner-home`, `field-team`,
  `officers/{id}`, `officers/{id}/day-replay?date=`, `farmers`, `farmers/{id}/360`,
  `stores`, `stores/{id}` (P&L by month). Roles per SPEC 2.6 in `analytics/router.py`.
- Filters (AN-011): every route takes `from` / `to` (IST dates, default last 30 days) and
  `cluster_id` / `store_id` / `officer_id` / `crop_id`; `filters.resolve_scope` narrows them
  by role (cluster head -> cluster, store manager -> store, field officer -> own figures),
  404s ids out of scope and 422s impossible combinations; responses echo `filters`.
- KPIs: `analytics/kpi.py` holds the SPEC 5.2 definitions as pure functions over fact
  records; `analytics/facts.py` loads the facts. Add a KPI there first, with a unit test.
- Open flags: read only through `analytics/ports.FlagCountsPort` (`app.state.flag_counts`;
  the null adapter answers zeros until the flags package registers its adapter).
- Store managers never receive location-derived figures (`km_per_day` is `null`).

```python
# a new dashboard endpoint: take the filter set, scope it, compute from facts
@router.get("/thing", response_model=ThingOut)
async def thing(actor: Annotated[User, require_roles(*ROLES)], session: DbSession,
                filters: Filters) -> ThingOut:
    scope = await resolve_scope(session, actor, filters)
    start, end = scope.filters.bounds          # UTC [start, end) of the IST days
    rows = await facts.sales_aggregate(session, scope, start, end, ["day", "own_brand"])
    return ThingOut(filters=scope.echo(), ...)
```

Performance: `tests/analytics/test_performance.py` times the owner home on a synthetic 50-store
tenant (WC-001 budget 3 s; ~1.2 s locally). Range aggregates run inside `facts.hash_joins` so
a freshly loaded, unanalysed table cannot push the planner into a nested loop.

## Farmer registration writes (FA-012 / FA-013)

`POST /v1/farmers` registers a farmer with nested `farms[{boundary GeoJSON, area_acres, soil,
irrigation, ownership, photos: [blob_uri], crop_plots[]}]` and `consents[{purpose, granted}]`
in one request (field officer, store manager, cluster head, tenant admin); then
`PATCH /v1/farmers/{id}`, `POST /v1/farmers/{id}/farms`, `PATCH|DELETE /v1/farms/{id}`,
`POST /v1/farms/{id}/crop-plots`, `PATCH|DELETE /v1/crop-plots/{id}` (soft deletes) and
`POST /v1/farmers/{id}/consents` (append a grant or withdrawal). Everything goes through
`farmerapp/farmers/service.py`, which `POST /v1/sync` shares. Inline checks (SPEC 6.2):

- VA-F01: E.164 Indian mobile (normalised), duplicate `(tenant, phone)` -> `409
  farmer_phone_exists`, staff phone -> `422 farmer_phone_is_staff`. Phone verification:
  `POST /v1/farmers/phone/verify/send {phone}` + `/confirm {phone, code}` return a 30-minute
  `phone_verification_token` (HS256 JWT bound to tenant + phone, `farmerapp/farmers/phone_verify.py`)
  that `POST /v1/farmers` or a sync `farmer.create` op presents to get `phone_verified: true`;
  without it the farmer is registered unverified (offline capture) and verified later with
  `POST /v1/farmers/{id}/phone/verify/send|confirm`. Same OTP limits/lockout as login
  (purpose `farmer_register`).
- VA-F03: `ST_IsValid` -> `422 farm_boundary_invalid` (detail carries PostGIS' reason);
  declared vs measured acres outside ±30 % -> `warnings: ["area_mismatch"]`; overlap with
  another farmer's farm above 20 % -> `warnings: ["farm_overlap"]`. Warnings never reject
  (per farm and as the union on the farmer response).

Every POST honours `Idempotency-Key` (`farmerapp/api/idempotency.py`): the response is stored
24 h per `(tenant, actor, key)` and replayed for the same body; a different body is
`422 idempotency_key_reuse`; errors are not cached. Decorate an endpoint with
`@idempotent(status_code=...)` under the route decorator (it needs `request`, `session`,
`actor` parameters).

## Sync (FA-025 / NF-003)

`POST /v1/sync {device_id, cursor, ops[]}` (field officer, store manager, cluster head,
farmer; ≤ 200 ops) applies outbox operations `{op_id, entity, action, entity_id,
base_version, payload, client_ts}` in order, each in its own SAVEPOINT, and returns
`results[]` (`applied | duplicate | conflict | rejected`, `version`, problem-style `error`,
`server` state) plus `changes[]` since the cursor. `farmerapp/sync/service.py`:

- `op_id` idempotency: results are stored in `sync_op`; a replay returns `duplicate` with
  the original result.
- Conflict rules `CONFLICT_RULES`: farmer / farm / crop_plot `last_writer_wins`
  (`base_version` mismatch is applied when `client_ts` is newer than `updated_at`, else
  `conflict` with the server state); `server_wins` reserved for khata / payments and used
  for the append-only consent record; `merge_fields` reserved.
- Change feed: `sync_change` (append-only, `seq` identity) is written by the flush hook
  `farmerapp/sync/changes.py` registered on the FA-006 audit listener, so REST, sync and
  jobs all feed it. Reads are scoped with `farmer_filters` (officer: own farmers' entities;
  farmer: own), collapsed to the latest state per entity, capped at 500 with `has_more`;
  soft-deleted rows come back as `action: delete` with `{id, deleted_at}`. The cursor is
  the base64 of the last `seq`.

## Uploads and blobs (NF-003 / SEC-016)

Resumable 256 KB chunked uploads: `POST /v1/uploads {sha256, size_bytes, content_type,
purpose, chunk_size: 262144}` -> `{upload_id, received_chunks, expires_at}`; `PUT
/v1/uploads/{id}/chunks/{index}` (raw body + `X-Chunk-Sha256`, any order, re-PUT is fine);
`GET /v1/uploads/{id}` for resume; `POST /v1/uploads/{id}/complete` verifies the whole-file
sha256 and returns `{blob_uri, sha256, size_bytes, content_type}`. Chunks are staged as
`bytea` in `upload_chunk` (15-minute TTL, `python -m farmerapp.jobs purge-expired
--tenant-id …` also drops expired idempotency keys). Blobs land in a `BlobStore`
(`farmerapp/uploads/blobstore.py`) under `gs://<bucket>/<tenant>/<purpose>/<sha256>`:
`BLOB_STORE=local` (directory; unit tests) or `BLOB_STORE=fake_gcs` (compose
`gcs` service, bucket `photos`; `pytest -m integration` covers it). `GET
/v1/blobs/signed-url?uri=` returns a 15-minute URL — a plain media URL for the fake / local
stores; real V4 signing is the `GcsBlobStore` seam for SEC-016 (M5). `farm_photo` rows
reference completed uploads (`photos: [blob_uri]` on a farm).

## Auth (FA-001)

```
make seed                      # tenant "Future Crop Care" (fcc) + users +91900000000{1..5}, +919000000010
uvicorn farmerapp.api.app:app  # then POST /v1/auth/otp/send {"phone": "+919000000004"}
curl localhost:8090/sms/messages?to=%2B919000000004   # read the code from the mockserver
```

With `OTP_DEV_CODE=123456` in `.env` (local/dev only) the fixed code is accepted as well.
Delayed OTP delivery checks (WhatsApp fallback after 30 s) run in-process locally
(`farmerapp.auth.scheduler.InProcessScheduler`); production will publish `notify.send`
(TODO OPS-004). Tests use `FakeProvider` + `FakeClock`; `pytest -m integration` also talks to
the compose mockserver when it is up.

## Authorisation (FA-002 / SEC-006)

Every route declares exactly one policy; the app refuses to start otherwise
(`farmerapp.auth.policy.install_policies`).

```python
from farmerapp.auth.policy import PUBLIC, Role, require_roles


@router.get("/health", dependencies=[PUBLIC])  # no token
async def health() -> ...: ...


@router.get("/farmers")  # role check, returns the user
async def list_farmers(actor: Annotated[User, require_roles(Role.OWNER, Role.CLUSTER_HEAD)]): ...


@router.get("/users/{id}")  # ... or the user themselves
async def get_user(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES, self_param="id")]
): ...
```

A denied call is `403` problem+json with code `forbidden` and a WARNING `authz_forbidden`
(actor id, role, tenant, method, route template; never phone or name). Row-level scope
(own cluster / own store / own records, SPEC 2.6) is `farmerapp.auth.scope.scope_filters`.

The policy is written into `openapi.yaml` as `x-roles` / `x-public` / `x-self`;
`tests/authz/test_matrix.py` parses that file and tests every operation for every role plus
cross-tenant access. New routes with path parameters or a body need a `RouteFixture` there.
Seed data: `make seed` creates tenants `fcc` (+91900000000{1..10}) and `gfl`
(+91910000000{1..10}), one user per role each.

## Tenant isolation (FA-003 / SEC-011 / SEC-012)

Two database roles, two URLs (design: `docs/adr/0003-rls-design.md`):

| Env var | Role | Used by |
|---|---|---|
| `DATABASE_URL` | `farmerapp_app` — DML only, `NOBYPASSRLS`, no DDL | api, worker, jobs, tests |
| `MIGRATION_DATABASE_URL` | owner (`farmerapp` locally; member of `farmerapp_migrate`) | `alembic upgrade`, `migrate_engine` test fixture |

Every tenant table has RLS enabled **and forced** with the `tenant_isolation` policy
(`tenant_id = app_current_tenant()`, `WITH CHECK` too). `app_current_tenant()` reads the
transaction-local setting `app.tenant_id`; unset means *no rows*. The request session binds it
from the access token before the user is loaded, so a foreign `tid` is a 401.

Rules for new code:

```python
# migrations: right after every op.create_table of a tenant table
from farmerapp.db.rls import enable_rls

enable_rls("farmer")  # tests/rls/test_meta.py fails otherwise

# jobs / worker: say which tenant you work for
from farmerapp.db import job_session, tenant_scope

async with job_session(tenant_id) as session:
    ...
async with tenant_scope(session, tenant_id):
    ...  # inside an existing transaction
```

Login before the tenant is known uses two `SECURITY DEFINER` lookups owned by the NOLOGIN
`farmerapp_auth` role — `auth_find_user_by_phone(phone)` and `auth_find_refresh_token(hash)`
— which return ids only; there is no bypass setting. Tests: `tests/rls/` (SQL-level as the app
role, API-level, catalogue meta-test, DDL denied, pool reuse).

Dev/CI login users come from `docker/postgres/initdb/10-roles.sql` (fresh volumes) or
`make db-roles` (existing volumes). Cloud SQL: IAM service-account users are created by
Terraform; after the first migration an admin grants them `farmerapp_app` (api/worker/jobs)
or `farmerapp_migrate` (migrate job) — see `infra/modules/sql/main.tf`.

## Audit trail (FA-006)

Every create / update / delete of a row with a `tenant_id` writes an `audit_log` row **in the
same flush** (so it commits or rolls back with the change): who (`actor_id`, `actor_role`;
NULL + `system` for jobs), what (`action` = `<table>.<create|update|delete>`, `entity`,
`entity_id`, `before` / `after` = the changed columns plus `id`; full row on create/delete;
setting `deleted_at` is a `delete`), and from where (`ip`, `device_id`, `user_agent`,
`trace_id`). The listener lives in `farmerapp/db/audit.py` and is installed for every
session; a model opts out with `__audit__ = False` (use it for high-volume telemetry only).

Actor context is a `ContextVar`:

```python
# requests: bound by get_current_user (nothing to do). Clients may send X-Device-Id.
# jobs / worker / scripts:
from farmerapp.db import audit

with audit.actor_scope(audit.system_actor(tenant_id)):
    async with job_session(tenant_id) as session:
        ...

# events that are not row changes (login, export...):
audit.record(
    session,
    action="auth.login",
    entity="user",
    entity_id=user.id,
    tenant_id=user.tenant_id,
    after={"device_id": device_id},
)
```

Redaction is configured once in `farmerapp/db/audit.py`: `REDACTED_COLUMNS` (`code_hash`,
`token_hash` — never recorded), `MASKED_COLUMNS` (`phone` → last four digits),
`EXCLUDED_COLUMNS` (`updated_at`, `version`). Add a column there before storing a new secret
or PII field.

The table is append-only for the app role (migration 0004 revokes UPDATE/DELETE; tests in
`tests/audit/test_rls_and_grants.py`) and tenant-scoped like every other table. Read it with
`GET /v1/audit-logs?entity=user&entity_id=…&actor_id=…&action=…&from=…&to=…` (owner,
director, auditor, tenant_admin; newest first, cursor pagination). Retention is one year
minimum (NF-012); `python -m farmerapp.jobs purge-audit-logs --tenant-id <uuid>` only reports
what a purge would remove (400-day default) until the archive + purge job lands under OPS.

## Administration: users, devices, step-up, settings (WC-011 / WC-012 / WC-103 / SEC-020 / SEC-025 / SEC-028)

Contracts for the console and the apps: `docs/prs/M4-admin-api.md`.

```python
# SEC-028: an admin action needs a fresh OTP. Declare StepUp *after* the role check.
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp


@router.post("/things/{id}/purge", openapi_extra=STEP_UP_OPENAPI)
async def purge(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(Role.OWNER)],
    _step_up: StepUp,  # 401 step_up_required without a valid X-Step-Up-Token
    session: DbSession,
) -> ...: ...


# WC-012: read tenant settings through the one accessor (typed, defaults, lenient load).
from farmerapp.tenants.settings import get_tenant_settings, settings_from_tenant

settings = await get_tenant_settings(session, tenant_id)
settings.geofence_radius_m, settings.ta_rate_per_km_paise, settings.branding.primary_colour
```

New keys go into `TenantSettings` and `SETTINGS_KEYS` (and `PUBLIC_KEYS` if the apps need
them); `PATCH /v1/settings` (owner, director, tenant admin per SPEC 2.6; step-up) validates
with the same model. Step-up guards every admin action and every bulk export
(`/v1/audit-logs/export`, `/v1/catalog/export`): a new export must declare `StepUp` too. Revocation (`farmerapp/auth/devices.py`):
user status and `tokens_valid_after` are checked on every request, device status (lost /
revoked) through a per-process cache (`SECURITY_CACHE_TTL_SECONDS`, 30 s, at most 60 s);
refresh answers `session_revoked` or `device_wipe_required`. Field officers are bound to one
device (409 `device_not_bound` until an admin binds the new one). In tests, send
`X-Step-Up-Token` with the `step_up` fixture (`tests/authz/conftest.py`) or set
`RouteFixture(step_up=True)` in the authz matrix.

