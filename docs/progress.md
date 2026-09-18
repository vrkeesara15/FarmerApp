# Progress by requirement ID

Status values: `todo` | `in-progress` | `done` | `blocked (reason)`.
Milestone column follows SPEC §14.1. Each row records files changed when done.

## M0 — Foundations (target 2026-10-09)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M0-KICKOFF | Scaffold monorepo, docker compose, Makefile, Terraform dev+bootstrap, CI skeletons, design system in Flutter + React | done | 2026-09-17. apps/api (FastAPI, Alembic 0001 extensions+tenant, worker/jobs entrypoints, 24 tests), docker/ + docker-compose.yml + Makefile, apps/console (Next.js 15, 23 DS components, 78 vitest + 4 Playwright), apps/mobile (pub workspace, farmerapp_core with 29 widgets + 5 ARB + 62 goldens, agent/farmer apps), infra/ (bootstrap + 11 modules + dev/stg/prd), .github/ (9 workflows). `make check` green. |
| FA-001 | Phone + OTP login | done | 2026-09-17. API: `farmerapp/auth/` (models user/otp_challenge/refresh_token, otp.py, tokens.py, deps.py get_current_user + tenant binding, providers fake/mockserver, scheduler seam, router `/v1/auth/otp/send|verify`, `/v1/auth/refresh|logout`, `/v1/me`), Alembic 0002, settings (OTP_*, JWT_*, CORS, prd guard rails), `jobs seed` (tenant fcc + 6 users), db `set_bypass_rls`, mockserver `/sms/status`, openapi.yaml; 62 75 pytest added under tests/auth (fake clock/provider, 1 `integration`) + 3 elsewhere; 102 total. Console: `lib/api.ts` auth+session, `app/api/session*` httpOnly refresh cookie, mock API in sync, LoginForm error states, +20 vitest, Playwright smoke green. Mobile: `HttpAuthApi`, `TokenStore` (secure storage, device_id), `AuthFailure` states, A03/A04 + F02/F03 wired, ARB en+te, +23 tests. PR: docs/prs/FA-001.md. Deferred: real SMS/WhatsApp adapters (human: DLT), Pub/Sub delayed check (OPS-004), phone in several tenants (WC-014). |
| FA-002 | Role-based access | done | 2026-09-17. `apps/api/farmerapp/auth/policy.py`: `Role` (= `UserRole`, 10 roles), `require_roles(*roles, self_param=)` dependency, `PUBLIC` marker, `install_policies()` startup check (app refuses to start if any route lacks a policy) that also writes `x-roles` / `x-public` / `x-self` and the 401/403 problems into `openapi.yaml`; 403 is problem+json `forbidden`, logged WARNING `authz_forbidden` (actor id, role, tenant, method, route template; no PII). `auth/scope.py`: SPEC 2.6 matrix as SQLAlchemy filters (`scope_filters`, `user_scope`; reusable for farmers/visits/khata). Policies: health + `/v1/auth/*` public, `/v1/me` all roles, new `farmerapp/users/` (`GET /v1/users` owner/director/cluster_head/auditor/tenant_admin with cluster scope + cursor pagination `api/pagination.py`; `GET /v1/users/{id}` same roles + self; `PATCH /v1/users/{id}` owner/director/tenant_admin: name/role/status/store_id/cluster_id). Disabled account with a valid access token is now 401 `user_disabled` (login stays 403). Seed: second tenant "Green Fields" (`gfl`), 10 users per tenant. `apps/api/README.md` section. PR: docs/prs/FA-002.md. |
| FA-003 | Tenant isolation (RLS) | done | 2026-09-17. Alembic `0003_rls_roles` (roles `farmerapp_app` DML-only / `farmerapp_migrate` owner / `farmerapp_auth` lookup owner; `app_current_tenant()`; ENABLE+FORCE RLS with `tenant_isolation` + `maintenance` policies on tenant/user/otp_challenge/refresh_token; `auth_find_user_by_phone` / `auth_find_refresh_token` SECURITY DEFINER id lookups; `app.bypass_rls` removed). `farmerapp/db/rls.py` (`enable_rls` for migrations, `rls_violations` meta-check), `db/session.py` (`tenant_scope`, `job_session`, `clear_tenant`), auth otp/tokens resolve the tenant via the lookups, seed with fixed tenant ids as the app role, settings `MIGRATION_DATABASE_URL`, `docker/postgres/initdb/10-roles.sql` + `make db-roles`, compose/CI/.env.example. 49 tests in `tests/rls/` (SQL as app role, API 404/401, catalogue meta-test incl. negative case, DDL denied, pool reuse); 262 total, 96.1% cov. ADR `docs/adr/0003-rls-design.md`; PR `docs/prs/FA-003.md`. Follow-ups: WC-014 tenant picker for a phone in several tenants. |
| FA-004 | Localisation, ARB files, no hard-coded strings | done | 2026-09-17. Mobile: `packages/core/lib/l10n/app_{te,kn,hi,mr}.arb` complete (196 keys each; `tool/check.sh` fails on any untranslated message), `state/settings.dart` (`SettingsStore`, `KvSettingsStore` over Drift `kv`, `settingsOverrides` loaded before first frame, `SettingsNotifier` persists), `db/open_database.dart`, `widgets/language_picker.dart` (tiles in their own language, Listen label, explicit a11y nodes, 144 dp), `widgets/language_setting_tile.dart`, A63/F70 `settings_screen.dart` shells + routes, `lib/string_lint.dart` + `tool/lint_strings.dart` (Text/label/tooltip/hintText/helperText/errorText/semanticsLabel, i18n-ignore, self-tested), tests: core 140 (+25: settings, ARB completeness, picker x5 locales, setting tile, Indic theme), agent 9 (+4), farmer 9 (+4), root lint 13. Console: `lib/i18n.ts` locale store + `useT()`/`useLocale()` (live switch, localStorage, `<html lang>` + init script), TopBar profile menu with 5 languages + sign out, all client components on `useT`, `PlaceholderPage`/`LoginHeader`/`SkipLink` client, `messages/{te,kn,hi,mr}.json` complete (142 keys), `scripts/lint-strings.mjs` takes paths + `lint-strings.test.ts`, vitest 114 (+16), Playwright +1 (5). Design: `design/screens/A02.md`, `F01.md`, `components/LanguagePicker.md`. PR: docs/prs/FA-004.md. Human gate: native-speaker review of translations (NF-008). |
| FA-006 | Audit trail | done | 2026-09-18. `apps/api/farmerapp/db/audit.py`: `Actor` ContextVar (bound by `get_current_user` from the request: ip = first `X-Forwarded-For` hop, `X-Device-Id` or the user's bound device, user agent, trace id; jobs/worker via `actor_scope(system_actor(tenant_id))`; unattributed writes = `system`), `before_flush` listener on every session writing an `audit_log` row in the same flush for each create/update/delete of any model with `tenant_id` (`__audit__ = False` opts out), diffs = changed columns + id, soft delete (`deleted_at`) = `<entity>.delete`, redaction in one place (`code_hash`/`token_hash` never, `phone` masked, `updated_at`/`version` excluded), `audit.record()` for explicit events (`auth.login`, `auth.logout` in `auth/router.py`). `db/models/audit_log.py` on lean `TenantRow` mixin (`db/base.py`); Alembic `0004_audit_log` (RLS, **append-only** grants for the app role, indexes; NF-012 retention note); `db/rls.py` `APPEND_ONLY_TABLES` + meta-check; `GET /v1/audit-logs` (`farmerapp/audit/`, owner/director/auditor/tenant_admin, filters entity/entity_id/actor_id/action/from/to, newest-first cursor via `PageRequest.before`); `jobs purge-audit-logs` dry run (400-day default, refuses < 365). 38 tests in `tests/audit/` (+ RLS matrix rows and the generated authz matrix for the new route); 315 total, 95% cov. PR: docs/prs/FA-006.md. Left: real purge/archive under OPS/NF-012, console viewer WC-103. |
| SEC-001 | Secret scanning (gitleaks) | done | 2026-09-17. security.yml: gitleaks on PR + nightly. GitHub-side secret scanning with push protection is a repo setting (human, once remote exists). CI not yet exercised: no GitHub remote configured. |
| SEC-002 | Static analysis (Semgrep, bandit) | done | 2026-09-17. security.yml semgrep p/python p/typescript p/owasp-top-ten; ci-api.yml bandit (also in `make check-api`). CI not yet exercised: no GitHub remote configured. |
| SEC-003 | Dependency vulnerabilities | done | 2026-09-17. ci-api pip-audit --strict; ci-console npm audit --audit-level=high; security.yml osv-scanner + trivy fs; dependabot.yml weekly for pip/npm/pub/actions/terraform. CI not yet exercised: no GitHub remote configured. |
| SEC-004 | Container image scanning (Trivy) | done | 2026-09-17. deploy.yml trivy image scan on built images; api/worker/jobs Dockerfiles python:3.12-slim with non-root USER app. CI not yet exercised: no GitHub remote configured. |
| SEC-005 | IaC misconfiguration (checkov, tflint) | done | 2026-09-17. ci-infra.yml tflint + checkov (infra/.tflint.hcl, infra/.checkov.yaml); security.yml trivy config on Terraform/Dockerfiles. CI not yet exercised: no GitHub remote configured. |
| SEC-006 | Authz test matrix per endpoint/role | done | 2026-09-17. `apps/api/tests/authz/test_matrix.py` is generated from `apps/api/openapi.yaml`: every non-public operation × 10 roles (allowed → not 401/403, denied → 403 `forbidden`), `x-self` access for every role, cross-tenant id → 404/403 with no tenant-B data in the body, collections never contain other tenants, no token → 401, unknown / disabled user → 401, forbidden call logged without PII (caplog); public operations need no token; `ROUTE_FIXTURES` table supplies path params/bodies for new routes. Plus `test_policy.py` (startup check, OpenAPI extensions), `test_scope.py`, `test_users.py`; fixtures seed both tenants and mint tokens directly. 110 tests (213 total, 97% coverage). |
| SEC-010 | One SA per deployable, no keys | done | 2026-09-17. infra/modules/iam: one `google_service_account` per deployable (api, console, worker, embed, jobs, scheduler…), bound to Cloud Run services/jobs; no default compute SA referenced. infra/bootstrap: `iam.disableServiceAccountKeyCreation` org policy on ops + env projects; CI uses WIF only. Apply is human-gated. |
| SEC-011 | Cloud SQL private IP, IAM auth, no DDL for app user | done | 2026-09-17. Terraform `infra/modules/sql` verified: `ipv4_enabled=false` + `private_network`, `ssl_mode=ENCRYPTED_ONLY`, `cloudsql.iam_authentication=on`, `google_sql_user` CLOUD_IAM_SERVICE_ACCOUNT for api/worker/jobs; SEC-011 notes + grant procedure in `main.tf`, `infra/README.md`. DDL separation by migration 0003 (`farmerapp_app` DML only, tested: 12 DDL/privilege statements denied, `alembic_version` unreadable); runtime `DATABASE_URL` vs Alembic `MIGRATION_DATABASE_URL` (prd refuses the same role). Human/one-off per env: `GRANT farmerapp_app TO <api,worker,jobs IAM users>`, `GRANT farmerapp_migrate TO <migrate SA>` after the first upgrade. Follow-up: dedicated migrate SA (migrate job runs as the jobs SA), IAM-token DB credentials in Cloud Run (`DB_IAM_AUTH` placeholder). |
| SEC-012 | Postgres RLS keyed on app.tenant_id, tested in CI | done | 2026-09-17. Transaction-local `set_config('app.tenant_id', ..., true)` per request (`get_session` + `get_current_user` before loading the user), `tenant_scope`/`job_session` for jobs/worker; policies fail closed when unset. `ci-api.yml` runs the suite as `farmerapp_app` (initdb role in the `docker/postgres` image) with the owner only for Alembic; `tests/rls/test_meta.py` fails any future table without `enable_rls`. See FA-003. |
| SEC-013 | Secrets in Secret Manager | done | 2026-09-17. infra/modules/secrets: secrets created empty with per-SA accessor bindings; values added via `gcloud secrets versions add` by an admin; `rotation_days`/`rotation_topic` inputs for 90-day rotation notifications (age alert tracked under OPS-014). No secrets in code: settings read env from Secret Manager `value_source`. |

## M1 — Farmers and farms (target 2026-10-30)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M1-KICKOFF | Alembic models for M1 entities, RLS, demo seed | done | 2026-09-18. Alembic `0005_m1_farmers_farms_stores`: `cluster`, `store`, `village` (`apps/api/farmerapp/tenants/models.py`), `crop` master + `PILOT_CROPS` (`farmerapp/catalog/crops.py`), `farmer`, `farm` (PostGIS boundary; `centroid` + `area_acres_computed` stored generated columns), `crop_plot`, append-only `consent_record` (`farmerapp/farmers/models.py`); `enable_rls` on all eight, FK + GiST + pg_trgm indexes; `db/geo.py` EWKT helpers; `db/audit.py` JSON for date/Decimal/geometry; `auth/scope.py` `farmer_filters`; `farmers/schemas.py` read models; `GET /v1/farmers` + `GET /v1/farmers/{id}` (§2.6 scope, cursor pagination, agronomist PII masked). Seed rewritten (`jobs/seed.py`, `SeedProfile` FULL/SMALL, uuid5 ids, idempotent, < 1 s): fcc 2 clusters, 5 Telangana stores, 5 officers, 40 villages, 200 farmers (Telugu names), 285 farms (non-overlapping 0.5–5 acre polygons), 403 crop plots, 338 consent rows; gfl 1 store / 1 officer / 10 farmers. Tests: `tests/farmers/` (models + API), `tests/seed/`; 379 total (315 before), 95.9% cov. README seed section. PR: docs/prs/M1-kickoff.md. |
| FA-012 | Farmer registration | done | 2026-09-18 Mobile: A20 farmer list (search name / phone digits / village, village + crop filters, FarmerCards offline, FAB), A21 wizard a–e (`apps/mobile/apps/agent/lib/screens/farmers/`, state `packages/core/lib/src/farmers/registration_notifier.dart`, draft in `kv` → resumes), OTP to the farmer via `/v1/farmers/phone/verify/*` (`HttpFarmerPhoneVerifyApi`) with offline "verify later", local duplicate block + server `farmer_phone_exists` → A64 + A22 "Duplicate — merge?" banner, `MapPanel` (flutter_map + OSM, walk-around GPS with accuracy / tap corners), pure-Dart geo (`lib/src/geo/geo.dart`: spherical area, centroid, self-intersection, GeoJSON), VA-F03 ±30 % warning + self-intersection block, camera-only farm photo through NF-004 → resumable upload, two ConsentCards with read-aloud button and notice in the farmer's language, save = one transaction of outbox ops (farmer, farms, plots, consents); A22 profile (overview, placeholder tabs / actions); Drift v3 `villages` table from the change feed; engine drops an expired verification token. 164 ARB keys × 5. Tests: core 351 (+68) / agent 39 (+28) incl. the end-to-end offline wizard → sync. PR: docs/prs/FA-012-mobile.md. Previously (API, 2026-09-18): `POST /v1/farmers` (nested farms / crop plots / consents, `Idempotency-Key`, duplicate phone -> 409 `farmer_phone_exists`, consent row with version from `tenant.settings.consent_version`), `PATCH /v1/farmers/{id}`, farms / crop-plots / consents endpoints, phone OTP verification (`/v1/farmers/phone/verify/*`, 30-min token; `farmer.phone_verified`), `farm_photo` table; `farmerapp/farmers/{service,schemas,router,phone_verify,errors}.py`, Alembic `0006`, tests `tests/farmers/test_write_api.py`, `test_phone_verify.py`. PR: docs/prs/FA-012-api.md. Data model + read endpoints since M1-KICKOFF. Follow-ups: API change feed to emit `village` / `crop` reference rows (mobile picker falls back to typed village + pilot crops until then); record-level phone verification from A22; merge of duplicates in the console (WC-104). |
| FA-013 | Multiple farms / crop plots | done | 2026-09-18 Mobile: the A21 wizard captures any number of farms ("Add another farm" on A21c / A21e, farm tabs) each with any number of crop plots; A23 (`farm_edit_screen.dart`) adds a farm to an existing farmer (`farm` + `crop_plot` creates) or edits one (farm update with `base_version`, plot update / create / delete). Proven end to end: `apps/agent/test/farmers/registration_flow_test.dart` (2 farms + 3 plots offline through the UI → 8 outbox ops → synced) and `packages/core/test/farmers/registration_notifier_test.dart`. API (2026-09-18): farmer with 2 farms + 3 crop plots in one `POST /v1/farmers` (`tests/farmers/test_write_api.py::test_farmer_with_two_farms_and_three_plots_in_one_post`) and via sync ops; model 1:n since M1-KICKOFF. |
| FA-025 | Offline-first sync engine | done | 2026-09-18 API: `POST /v1/sync` batch endpoint (`farmerapp/sync/`): `op_id` idempotency (`sync_op`), conflict rule table (`last_writer_wins` for farmer/farm/crop_plot via `client_ts` vs `updated_at`, `server_wins` reserved for khata/payments), problem-style rejections, scoped change feed from the append-only `sync_change` log written by the audit flush hook (`farmerapp/sync/changes.py`), base64 seq cursor, 500 cap + `has_more`. Tests `tests/sync/`. PR: docs/prs/FA-012-api.md. Mobile sync engine: mobile agent. Mobile: 2026-09-18. Mobile half in `apps/mobile/packages/core/lib/src/sync/` against the `/v1/sync` contract (API half by the API loop): Drift schema v2 (`db/app_database.dart`: `farmers`, `farms`, `crop_plots`, `consent_records` typed + `version`/`updated_at`/`dirty`/`deleted`, `outbox` (op_id PK, seq, base_version, payload JSON, client_ts, state queued\ |
| FM-002 | Consent data model | done | 2026-09-18 (M1-KICKOFF). `consent_record` (subject_type/subject_id, purpose `data` \| `marketing`, version, language, granted_at, withdrawn_at, channel, recorded_by) append-only for the app role (`APPEND_ONLY_TABLES`); withdrawal is a new row; `farmer.consent_marketing` / `consent_version` cache the latest; seed writes data + marketing grants and withdrawals. Consent text version `2026-09-v1` is a placeholder (TODO-LEGAL). The farmer-app consent screen is the M6 FM-002 row. |
| NF-002 | Offline 72 h | done (mobile half) | 2026-09-18 with FA-025. Capture never touches the network: every write goes through `Outbox` into the typed Drift tables + `outbox`, and the engine only ever drains it. Acceptance proven in `packages/core/test/sync/offline_72h_test.dart`: `FakeSyncApi` offline for 72 simulated hours (injected clock), 300 ops (60 farmers × create/update, farm create/update, crop plot create) across three days, WorkManager-style ticks every 15 min bounded by the backoff, two app "restarts" (new engine over the same DB), then online with the first response lost → all 300 applied exactly once (op_id idempotency, `duplicate` treated as success), per-entity order preserved, local rows clean and at the server versions. `OfflineBannerLive` over `offlineProvider` (`connectivity_plus`). Farmer-app caching of results / orders / calendar is the M6 half. |
| NF-003 | Sync outbox, idempotency, resumable uploads | done | 2026-09-18 API: `Idempotency-Key` on every POST (`farmerapp/api/idempotency.py`, 24 h per tenant+actor, `422 idempotency_key_reuse`), resumable 256 KB chunked uploads (`farmerapp/uploads/`: `upload_session` / `upload_chunk` bytea staging, `BlobStore` with `LocalBlobStore` + `FakeGcsBlobStore`, `GET /v1/blobs/signed-url`, `purge-expired` job), fake-GCS `integration` test. Outbox HTTP transport + WorkManager job: mobile agent. Previously: Chunk planner exists since NF-004 (2026-09-18): `packages/core/lib/src/photo/chunked_upload_planner.dart` (256 KB chunks, per-chunk + file sha256, resume from `lastAckedChunk`, JSON for the outbox row). Left: outbox table + idempotency keys, HTTP transport with backoff, WorkManager job. Mobile: 2026-09-18 with FA-025. Outbox table with uuid `op_id` idempotency keys and FIFO `seq` (`db/app_database.dart`), `Outbox` API, `duplicate` handled as success (`test/sync/sync_engine_push_test.dart`, lost-response case). Resumable uploads: `uploads` table (server upload_id, sha256, chunk_size, received chunks JSON, state pending\ |
| NF-004 | Image budget | done | 2026-09-18. Shared on-device photo pipeline in `apps/mobile/packages/core/lib/src/photo/`: `photo_processor.dart` (`PhotoProcessor.process` via `compute`, `processPhotoSync`: decode, EXIF orientation baked, long edge ≤ 1280 (average interpolation, never upscaled), JPEG q80 4:2:0, EXIF `DateTime`/`DateTimeOriginal`/`DateTimeDigitized` + `OffsetTime*=+00:00` + GPS IFD written with `package:image`, SHA-256; hard cap 300 KB → q70 → q60 with `quality`/`withinBudget` recorded; `PhotoExif`, `PhotoLocation`, `ProcessedPhoto.toJson` upload payload, `PhotoProcessor.readExif`), `photo_quality.dart` (`OnDeviceQualityModel` interface, default `LaplacianQualityModel`: variance of Laplacian + mean luminance on a 320 px gray copy, `PhotoQualityConfig` blur 40 / dark 0.15, tip keys `photo.tip.{blurry,dark,ok}`), `chunked_upload_planner.dart` (256 KB chunks with index/offset/sha256, whole-file sha256, resume from `lastAckedChunk`, JSON). Widgets: `PhotoReviewCard` (+13 ARB keys ×5), `CameraGuideOverlay(tipKey:)` lights the matching tip. Deps `image ^4.10.1`, `crypto`. Measured: 4000×3000 → 1280×960 ≈ 198 KB, textured 1280×960 ≈ 193 KB at q80; ladder case 342 → 328 → 220 KB (q60). Tests +62 (core 202): `test/photo/{photo_processor,photo_quality,chunked_upload_planner}_test.dart` with generated images, `test/widgets/{photo_review_card,camera_guide_overlay}_test.dart`, goldens `photo_review_card_*`, `camera_guide_overlay_tip_*`. Design: `design/components/PhotoReviewCard.md`, `CameraGuideOverlay.md`, `design/screens/A41.md`, `F22.md`. PR: docs/prs/NF-004.md. |

## M2 — Duty, location and visits (target 2026-11-20)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M2-KICKOFF | Alembic models for M2 entities | done | 2026-09-18. Alembic `0007_m2_duty_location_visits`: `duty_session`, `location_point` (**declaratively partitioned by day** on `ts`, PK `(id, ts)`, `__audit__ = False`, excluded from the sync feed; SQL functions `ensure_location_partitions(from_day, to_day | days_ahead)` create `location_point_pYYYYMMDD` with RLS enabled + forced + policies on every child, `purge_location_points(retention_days, dry_run)` aggregates into `location_daily_agg` and drops partitions older than 180 days), `location_daily_agg`, `policy_acceptance` (append-only), `visit` (generated `duration_s`, score / score_components / status, geofence_result, override note + approver, device_integrity, client_visit_id), `visit_photo`, `visit_confirmation`, `village.meeting_point_radius_m` (`farmerapp/location/models.py`, `farmerapp/visits/models.py`, `tenants/models.py`); `tenants/settings.py` (`TenantSettings`: geofence_radius_m 150, min_visit_duration_s 300, auto_duty_end_local_time 20:00, idle_end_minutes 60, location_policy_version 2026-09-v1, sampling 120/600/900); `visits/scoring.py` (`score_visit`, `score_visit_row`, `status_for`); `auth/scope.py` `visit_filters` / `officer_filters` / `duty_session_filters` (`TRACK_VISIBILITY`: store managers never); read endpoints `GET /v1/visits[/{id}]`, `GET /v1/duty-sessions`, `GET /v1/officers/{id}/track?day=` (`visits/router.py`, `location/router.py`, schemas); sync `SYNC_ENTITIES` + `CONFLICT_RULES` (visit / duty_session `merge_fields` with `SERVER_OWNED_FIELDS`, photo / acceptance `server_wins`, feed scope, M2 ops rejected `unsupported_action` until the write paths); jobs `ensure-partitions`, `purge-location-points` (dry run by default) in `location/partitions.py` + `jobs/cli.py`; seed `jobs/seed_m2.py` (5 officers × 7 days: duty sessions 09:00-18:00 IST, ~150 points/day with VV-002 fields, 4-7 visits/day with photos, ~60 % confirmations, VV-004 scores / VV-005 statuses, policy acceptances; FULL: 42 duty sessions, 6,108 points, 216 visits, 400 photos, 137 confirmations in 2.0 s; `SMALL` (test fixtures) stays cheap: 1 day, ~25 points and 2 fixed visits (verified + partial) per officer). Tests: `tests/visits/{test_scoring,test_models,test_read_api}.py`, `tests/location/test_partitions.py` (RLS on parent + children, purge dry run + aggregate), `tests/seed/test_seed_m2.py`, `tests/sync/test_m2_rules.py`, `tests/tenants/test_settings.py`; authz matrix + RLS meta-test cover the new routes / tables; 857 passed, 1 skipped in 6 min 16 s (678 before) total, 95.4% cov. PR: docs/prs/M2-kickoff.md. Left for the loop: the write endpoints (duty toggle + point upload FA-010 / VV-001, check-in FA-014, capture FA-015, confirmation FA-016, check-out FA-017), track processing VV-006, scheduling of the two jobs (OPS). |
| FA-010 | Duty toggle, foreground service | todo | Data model since M2-KICKOFF (2026-09-18): `duty_session` (start/end, points, km, stops, end_reason, policy_version, device, app version), `location_point` partitioned by day with the daily `ensure-partitions` job; `GET /v1/duty-sessions`. Left: `POST /v1/duty-sessions` start / end, point upload endpoint, the Android foreground service. |
| FA-011 | First-run disclosure | todo | Data model since M2-KICKOFF (2026-09-18): append-only `policy_acceptance` (user, policy_key, version, accepted_at, device_id, app_version, text_hash); tenant setting `location_policy_version` (`2026-09-v1`, TODO-LEGAL); sync entity + feed. Left: `POST /v1/policy-acceptances`, duty start blocked until the current version is accepted, the app screen. |
| FA-014 | Visit check-in geofence | todo | Data model since M2-KICKOFF (2026-09-18): `visit.geofence_result inside|outside|meeting_point|override`, `override_note` (CHECK) + `override_approved_by`, `checkin_point` / `checkin_accuracy_m`, `village.meeting_point_radius_m`, tenant `geofence_radius_m` 150. Left: `POST /v1/visits` check-in with PostGIS `ST_DWithin` against `farm.boundary` / `village.meeting_point`, override approval flow, app screen. |
| FA-015 | Visit capture | todo | Data model since M2-KICKOFF (2026-09-18): `visit.purpose`, `notes`, `crop_stage`, `visit_photo` (blob_uri, sha256, phash, exif_time, exif_point, taken_in_app, device_time, server_time). Photo pipeline ready since NF-004 (2026-09-18): `PhotoProcessor.process(bytes, captureTime:, location:)` embeds EXIF time + GPS and returns the `exif` payload for the API's `exif_time` / `exif_point`; design `design/screens/A41.md`. Left: A30-A33 screens, in-app camera (no gallery), server time on upload. |
| FA-016 | Farmer confirmation | todo | Data model since M2-KICKOFF (2026-09-18): `visit.confirmation_channel sms_otp|app_push|qr|none` + `confirmed_at` (server-owned in sync), `visit_confirmation` (channel, otp_challenge_id, farmer_phone_last4, confirmed_at, confirmed_via_device_id, rating for FM-011); `OtpPurpose.FARMER_CONFIRM` exists. Left: the confirmation endpoints and the farmer-app prompt / QR. |
| FA-017 | Check-out and duration | todo | Data model since M2-KICKOFF (2026-09-18): `visit.checkout_at` / `checkout_point`, **generated** `duration_s`, tenant `min_visit_duration_s` 300 (duration component of the score, never a rejection). Left: `POST /v1/visits/{id}/checkout` calling `score_visit_row`. |
| FA-028 | Mock-location / root / time-tamper detection | todo | Data model since M2-KICKOFF (2026-09-18): `location_point.is_mock / is_rooted / clock_drift_s` and `visit.device_integrity {is_mock, is_rooted, clock_drift_s}`; the integrity component of VV-004 (`DeviceIntegrity`, drift > 300 s fails); seed has flagged officer-days. Left: device-side detection and the VA-E01 flag. |
| VV-001 | On-duty sampling | todo | Tenant settings since M2-KICKOFF (2026-09-18): `sampling.moving_s` 120, `stationary_s` 600, `upload_s` 900; seed tracks follow that cadence. Left: the upload endpoint and the Flutter foreground service / battery budget. |
| VV-002 | Point metadata | todo | Fields present since M2-KICKOFF (2026-09-18) on every `location_point`: `accuracy_m, speed_mps, bearing, battery_pct, is_mock, is_rooted, clock_drift_s, provider, received_at`; `GET /v1/officers/{id}/track` returns them. Left: the write path (server computes `clock_drift_s` = device time − server time at upload). |
| VV-003 | Geofence per farm / meeting point | todo | Since M2-KICKOFF (2026-09-18): `village.meeting_point_radius_m` (NULL → tenant `geofence_radius_m` 150), `farm.boundary` + `village.meeting_point` since M1; the seed's inside / outside / meeting-point check-ins agree with `ST_DWithin`. Left: the geofence test on sample polygons in the check-in service. |
| VV-004 | Visit score | todo — scoring done, write path pending | 2026-09-18 (M2-KICKOFF): `farmerapp/visits/scoring.py::score_visit` — geofence 30 (override 15, assumption), confirmation 30, in-app photo with EXIF time inside the visit window ± 10 min and GPS within 150 m 20, duration ≥ minimum 10, device integrity 10 — components stored in `visit.score_components`, shown by `GET /v1/visits/{id}`; unit tests on fixtures (`tests/visits/test_scoring.py`); seed visits scored with it. Left: call `score_visit_row` from the FA-017 check-out / FA-016 confirmation write paths; console display (WC). |
| VV-005 | Visit status | todo — thresholds done, write path pending | 2026-09-18 (M2-KICKOFF): `status_for(score)`: verified ≥ 70, partial 40-69, unverified < 40, `open` until check-out (`visit.status` CHECK); boundary tests for 70 / 69 / 40 / 39; seed statuses consistent with scores; `GET /v1/visits?status=`. Left: set on check-out; incentive engine (M3+) counts `verified` only. |
| VV-007 | Auto end of duty | todo | Since M2-KICKOFF (2026-09-18): tenant settings `auto_duty_end_local_time` 20:00 / `idle_end_minutes` 60, `duty_session.end_reason auto_time|auto_idle|forced`, end fields server-owned in the sync merge once auto-ended; seed has auto-ended days. Left: the worker job that ends sessions and the app prompt. |
| VV-009 | Play Store background-location declaration | todo | |
| VV-010 | Employee location policy version | todo — table present | 2026-09-18 (M2-KICKOFF): `policy_acceptance` (append-only; version, accepted_at, device, app version, text_hash) and `duty_session.policy_version`; tenant `location_policy_version` `2026-09-v1` is a TODO-LEGAL placeholder until HR signs the written policy (SPEC 14.6 human gate). Left: the acceptance endpoint (FA-011) and the version check at duty start. |

## M3 — Catalogue, store mode, orders, payments, khata (target 2026-12-04)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M3-KICKOFF | Alembic models for M3 entities | todo | |
| FA-020 | Order capture | todo | |
| FA-021 | Payment collection | todo | |
| FA-022 | Khata view | todo | |
| ST-001 | Point of sale + GST invoice | todo | |
| ST-002 | Payment modes | todo | |
| ST-003 | Stock movements | todo | |
| ST-005 | Order queue | todo | |
| ST-006 | Day close | todo | |
| ST-007 | Credit approval | todo | |
| WC-005 | Product master + label claims | todo | |
| SEC-023 | Webhook HMAC + replay window | todo | |

## M4 — Console v1 and validation agents v1 (target 2026-12-11)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M4-KICKOFF | Rules engine (YAML), inline/event/batch modes, fixtures | todo | |
| WC-001 | Owner home | todo | |
| WC-002 | Field team | todo | |
| WC-003 | Farmers directory + 360 | todo | Read endpoints exist since M1-KICKOFF (2026-09-18): `GET /v1/farmers` (§2.6 scope per role, `village_id` / `registered_by` filters, cursor pagination) and `GET /v1/farmers/{id}` (farms with GeoJSON boundary, centroid, computed acres, crop plots, consent history). Left: search, console screens C-003/360. |
| WC-004 | Stores | todo | |
| WC-010 | Validation agent inbox | todo | |
| WC-011 | Users, roles, device binding, forced logout | todo | Minimal `/v1/users` list/get/patch (name, role, status, store_id, cluster_id) exist since FA-002 (2026-09-17) in `apps/api/farmerapp/users/`. Left: create/invite, device binding UI, forced logout (revoke refresh family when disabled; access tokens are already rejected on the next call), re-auth for role change (SEC-028), console screen. Audit rows for every change land automatically since FA-006 (2026-09-18). |
| WC-012 | Settings | todo | |
| WC-103 | Audit log viewer | todo | `GET /v1/audit-logs` (tenant-scoped, filters entity/entity_id/actor_id/action/from/to, cursor pagination, roles owner/director/auditor/tenant_admin) exists since FA-006 (2026-09-18) in `apps/api/farmerapp/audit/`; the console screen (C103) is left. |
| AN-001 | Owner home dashboard | todo | |
| AN-002 | Field team scorecard | todo | |
| AN-003 | Officer day replay | todo | |
| AN-011 | Dashboard filters in URL | todo | |
| VA-001 | Rules as versioned YAML | todo | |
| VA-002 | Flag contents | todo | |
| VA-003 | Routing | todo | |
| VA-007 | Golden fixtures per rule | todo | |
| VA-F01 | Phone format / OTP / staff blocklist | in-progress | 2026-09-18 inline part done with FA-012 API: E.164 normalisation, duplicate phone 409, staff phone `422 farmer_phone_is_staff`, OTP-verified `phone_verified` flag via `phone_verification_token`. Left: blocklist beyond staff accounts, batch agent (M4).  |
| VA-F02 | Duplicate farmer | todo | Groundwork since M1-KICKOFF (2026-09-18): unique `(tenant_id, phone)`, pg_trgm index on `farmer.name`, `farm.centroid` for the 50 m check. |
| VA-F03 | Farm polygon sanity | in-progress | 2026-09-18 inline part done with FA-012 API (`farmerapp/farmers/service.py::check_boundary`): `ST_IsValid` -> `422 farm_boundary_invalid`, area vs declared ±30 % -> `area_mismatch` warning, overlap > 20 % with another farmer's farm -> `farm_overlap` warning (response field, never a rejection). Left: review queue + batch agent (M4). Previously: Groundwork since M1-KICKOFF (2026-09-18): `farm.area_acres_computed` (ST_Area) and `farm.centroid` are stored generated columns with GiST index; overlap / ratio queries proven in `tests/farmers/test_models.py`. |
| VA-F06 | Registration burst | todo | |
| VA-F08 | Photo reuse | todo | |
| VA-E01 | Mock location / root / clock drift | todo | |
| VA-E02 | Impossible travel | todo | |
| VA-E03 | Clustered visits | todo | |
| VA-E04 | Short visits | todo | |
| VA-E05 | Confirmation anomalies | todo | |
| VA-E08 | Photo integrity | todo | |

## M5 — Pilot hardening (target 2026-12-18)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| OPS-001 | Uptime checks | todo | |
| OPS-002 | Error rate / crash-free | todo | |
| OPS-003 | Cloud SQL alerts | todo | |
| OPS-004 | Pub/Sub age / DLQ | todo | |
| OPS-005 | Job failures | todo | |
| OPS-006 | Officer sync silence | todo | |
| OPS-007 | Store zero sales / not closed | todo | |
| OPS-008 | Payment reconciliation | todo | |
| OPS-009 | Diagnosis queue age | todo | |
| OPS-010 | Flags past SLA | todo | |
| SEC-014 | Cloud Armor | todo | |
| SEC-015 | Ingress from LB only | todo | |
| SEC-016 | Private buckets, signed URLs | todo | |
| SEC-017 | Audit logs export | todo | |
| SEC-018 | Org policies | todo | |
| SEC-019 | SCC | todo | |
| SEC-024 | Mobile local DB encryption, pinning, Play Integrity | todo | Seam in place since FA-025 (2026-09-18): `packages/core/lib/src/db/open_database.dart` `DatabaseOpener` interface (`NativeDatabaseOpener`, `InMemoryDatabaseOpener`); the SQLCipher opener (key in Android Keystore) plugs in there without touching callers. Pinning and Play Integrity untouched. |
| SEC-025 | Remote wipe | todo | |
| SEC-026 | PII field-level encryption | todo | |
| NF-005 | Performance | todo | |
| NF-006 | Availability | todo | |

## M6 — Diagnosis engine + farmer app v1 (target 2027-02-26)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M6-KICKOFF | Diagnosis pipeline, pluggable encoder/LLM, HNSW index, eval script | todo | |
| DX-001 | On-device TFLite model | todo | Interface in place since NF-004 (2026-09-18): `OnDeviceQualityModel.evaluate(bytes) → PhotoQualityResult` with the `LaplacianQualityModel` heuristic as default (blur + darkness, ~100 ms at 1280 px). Left: TFLite model (< 8 MB) for leaf/plant present + crop class, 400 ms budget on a 2 GB device. |
| DX-002 | Server embedding, pgvector HNSW | todo | |
| DX-003 | Decision rule | todo | |
| DX-004 | LLM fallback | todo | |
| DX-005 | Result provenance | todo | |
| DX-006 | Agronomist review SLA | todo | |
| DX-007 | Treatment engine with label-claim filter | todo | |
| DX-008 | Ranking | todo | |
| DX-009 | Dosage and safety | todo | |
| DX-010 | Out-of-scope handling | todo | |
| FM-001 | Farmer login | todo | |
| FM-002 | Consent screen | todo | |
| FM-003 | Profile | todo | |
| FM-004 | Crop doctor camera | todo | On-device quality gate and review card exist since NF-004 (2026-09-18): `PhotoQualityCheck.evaluate` → blurry / dark / ok with retake tip keys, `PhotoReviewCard` (Use disabled for a rejected photo), `CameraGuideOverlay(tipKey:)`; design `design/screens/F22.md`. Left: F20/F21/F22/F23 screens, camera plugin, crop auto-detect (DX-001), up-to-3 flow. |
| FM-005 | Diagnosis result | todo | |
| FM-006 | One-tap actions | todo | |
| FM-010 | Orders, khata, pay dues | todo | |
| FM-011 | Visit confirmation + rating | todo | |
| FM-014 | App size < 25 MB | todo | |
| FM-015 | Delete account | todo | |
| FA-019 | Scouting | todo | |
| WC-006 | Agronomist review queue | todo | |
| WC-007 | Corpus manager | todo | |

## M7 — Analytics and growth (target 2027-05-14)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M7-KICKOFF | Datastream → BigQuery, dbt staging + marts | todo | |
| AN-004 | Farmer 360 and segments | todo | |
| AN-005 | Store performance | todo | |
| AN-006 | Crop health map | todo | |
| AN-007 | Diagnosis quality | todo | |
| AN-008 | Campaign ROI | todo | |
| AN-009 | Data quality | todo | |
| AN-010 | CDC latency | todo | |
| AN-012 | dbt tests | todo | |
| AN-013 | BigQuery RLS | todo | |
| AN-014 | PII minimisation in marts | todo | |
| AN-015 | Weekly owner email | todo | |
| WC-008 | Campaigns | todo | |
| WC-009 | Targets and incentives | todo | |
| WC-013 | Exports and scheduled reports | todo | |
| FM-007 | Crop calendar | todo | |
| FM-008 | Weather | todo | |
| FM-009 | Pest alerts | todo | |
| FA-018 | Beat plan | todo | |
| FA-023 | Travel allowance | todo | |
| FA-024 | My performance | todo | |
| FA-026 | Demo plots | todo | |
| FA-027 | Farmer meeting | todo | |
| DX-011 | Nightly evaluation | todo | |
| DX-012 | Retraining pipeline | todo | |
| DX-013 | Outbreak detection | todo | |
| VA-004 | Review agent summary | todo | |
| VA-005 | Employee sees own flags | todo | |
| VA-006 | Precision tracking | todo | |
| VA-F04 | Farm location plausibility | todo | |
| VA-F05 | Crop plausibility | todo | |
| VA-F07 | Ghost farmer | todo | |
| VA-F09 | Consent missing in segment | todo | |
| VA-F10 | Credit risk | todo | |
| VA-E06 | Duty with no activity | todo | |
| VA-E07 | TA claim vs km | todo | |
| VA-E09 | Sales anomalies | todo | |
| VA-E10 | Cash variance | todo | |
| VA-E11 | Performance drift | todo | |
| FA-005 | Voice input | todo | |
| FA-007 | Push notifications + inbox | todo | |
| ST-004 | Low-stock / expiry alerts | todo | |
| ST-008 | Tally/Zoho export | todo | |
| VV-006 | Track processing | todo | |
| VV-008 | Officer day timeline | todo | |
| SEC-007 | License compliance | todo | |
| SEC-008 | MobSF scan | todo | |
| SEC-020 | JWT lifetimes, rotation, reuse detection | todo | Partly done with FA-001 (2026-09-17): HS256 access 15 min, refresh 30 days rotated on every use, reuse revokes the family (`refresh_reused`), refresh bound to `device_id` for mobile clients, logout revokes the family; tests in apps/api/tests/auth/test_tokens.py. Left: RS256 + JWKS, key rotation, forced logout (WC-011). |
| SEC-021 | OTP hashing, velocity | todo | Partly done with FA-001 (2026-09-17): HMAC-SHA256 with server pepper bound to the challenge id, constant-time compare, single use, 5-attempt lockout (15 min), 3 resends / 15 min per phone, no code or full phone in logs. Left: per-country block, IP/ASN velocity (Cloud Armor SEC-014), provider-side SMS pumping controls. |
| SEC-022 | Input validation, CSP | todo | |
| SEC-027 | LLM calls: no PII | todo | |
| SEC-028 | Admin re-auth | todo | `PATCH /v1/users/{id}` (FA-002) changes roles without re-auth yet. The "audited" half is done with FA-006 (2026-09-18): every role/status change writes an `audit_log` row with actor, device, ip and old/new values; login/logout are audited too. Left: re-auth (fresh OTP) before role change, export and settings changes. |
| OPS-011 | Datastream lag / dbt failure | todo | |
| OPS-012 | Cost alerts | todo | |
| OPS-013 | Security alerts | todo | |
| OPS-014 | Cert / secret age | todo | |
| NF-001 | Devices | todo | |
| NF-008 | Localisation formats | todo | Indian number grouping, DD-MM-YYYY dates, acre/litre units done in M0 (`packages/core/lib/src/utils/format.dart`, console `lib/format.ts`). Five languages populated with FA-004 (2026-09-17). Left: review of all farmer-facing text by a native speaker per language (human gate) before pilot. |
| NF-009 | Accessibility | todo | |
| NF-010 | Literacy | todo | |
| NF-011 | Data residency | todo | |
| NF-012 | Retention | todo | Audit logs: 1 year minimum documented in Alembic 0004 (FA-006, 2026-09-18); `python -m farmerapp.jobs purge-audit-logs` is a dry run (400-day default, refuses < 365) — the real purge (archive to the exports bucket, delete as the migrate role) is still to do. Other retention classes untouched. |
| NF-013 | DPDP | todo | |
| NF-014 | Observability | todo | |
| NF-015 | Cost | todo | |
| NF-016 | Maintainability | todo | |

## M8 — SaaS readiness (target FY28 Q1)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| FA-008 | Tenant branding | todo | |
| WC-014 | Tenant admin | todo | |
| NF-007 | Scale target | todo | |
| AN-016 | NL questions over marts | todo | |
| FM-012 | Mandi prices | todo | |
| FM-013 | Referral | todo | |

## Open questions (SPEC §0.3) — not resolved; assumptions used
- Languages: all five (en, te, kn, hi, mr) populated (FA-004); native-speaker review pending (NF-008).
- Pilot crops: paddy, cotton, chilli, maize, tomato, groundnut (proposal accepted as default).
- TA rate: placeholder ₹4/km in tenant settings; incentive rules TBD.
- Payments: Razorpay test mode, Cashfree adapter interface only.
- Accounting sync: CSV export (ST-008) only.
- Product master ownership and CIB&RC source: seeded from a fixture; human to replace.
- Legal text for location policy / consent: placeholder copy marked TODO-LEGAL, versioned.
