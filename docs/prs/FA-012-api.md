# FA-012 (API half): farmer registration API with sync batch endpoint and resumable uploads

## Requirement IDs

- FA-012 Farmer registration — API: `POST /v1/farmers` with nested farms / crop plots / consent, duplicate phone blocked (409), consent record created, phone OTP verification; **mobile wizard + offline capture pending (mobile agent)**
- FA-013 Multiple farms / crop plots — API: farmer with 2 farms + 3 crop plots in one POST and via sync ops
- FA-025 Offline-first sync — API: `POST /v1/sync`, op idempotency, conflict rule table, scoped change feed; **mobile sync engine pending**
- NF-003 Sync outbox, idempotency, resumable uploads — API: `Idempotency-Key`, chunked uploads, blob store; **device transport pending**
- VA-F01 / VA-F03 — the cheap inline checks (phone, duplicate, staff phone, polygon validity, area ±30 %, overlap > 20 %)
- SEC-016 — blob store seam with private URIs and 15-minute (fake) signed URLs; real V4 signing in M5

PR title: `feat(FA-012): farmer registration API with sync batch endpoint and resumable uploads (FA-013, FA-025, NF-003)`

Branch `feat/FA-012-farmer-registration-api`; the mobile agent implements the same contract in `apps/mobile` concurrently — nothing under `apps/mobile` or `apps/console` is touched here.

## What changed

- **Farmer writes** `apps/api/farmerapp/farmers/`:
  - `schemas.py`: write models `FarmerCreate` (phone, name, village_id, landmark, language, land_ownership, `farms[]`, `consents[]`, optional client `id`, optional `phone_verification_token`), `FarmCreate` (`boundary` as `GeoJsonPolygon` — one closed WGS84 ring, `area_acres`, soil / irrigation / ownership, `photos: [blob_uri]`, `crop_plots[]`), `CropPlotCreate`, `ConsentIn`, `FarmerUpdate` (`extra="forbid"`: no phone change), `FarmUpdate`, `CropPlotUpdate`, phone-verify request / response models. Read models gain `phone_verified`, `deleted_at`, `warnings`, `photos`, `subject_id` on consent.
  - `service.py`: the one write path shared by REST and sync — `create_farmer`, `update_farmer`, `add_farm`, `update_farm`, `delete_farm`, `add_crop_plot`, `update_crop_plot`, `delete_crop_plot`, `add_consent`, `mark_phone_verified`; scope lookups `visible_farmer` / `visible_farm` / `visible_crop_plot` (SPEC 2.6 via `farmer_filters`, 404 otherwise); VA-F01 `_check_phone` (duplicate → `409 farmer_phone_exists`, staff phone → `422 farmer_phone_is_staff`); VA-F03 `check_boundary` (`ST_IsValid` → `422 farm_boundary_invalid` with PostGIS' reason; `area_mismatch` / `farm_overlap` warnings computed in SQL); `farm_photo` rows from `photos[]` (sha256 copied from the completed `upload_session`; URI must be under the tenant's prefix); soft deletes cascade farm → crop plots; rows created in one request get a wall-clock `created_at` so listings keep insertion order.
  - `phone_verify.py`: `issue_token` / `verify_token` — HS256 JWT `typ=phone_verification` bound to tenant + phone, 30 min, checked against the auth clock.
  - `router.py`: `POST /v1/farmers` (201, `@idempotent`), `PATCH /v1/farmers/{id}`, `POST /v1/farmers/{id}/farms`, `POST /v1/farmers/{id}/consents`, `PATCH|DELETE /v1/farms/{id}`, `POST /v1/farms/{id}/crop-plots`, `PATCH|DELETE /v1/crop-plots/{id}`, `POST /v1/farmers/phone/verify/send|confirm`, `POST /v1/farmers/{id}/phone/verify/send|confirm`. Roles: create = field_officer, store_manager, cluster_head, tenant_admin; edits add the farmer on their own record. `GET /v1/farmers/{id}` now uses `service.farmer_detail`.
  - `errors.py`, `models.py` (`farmer.phone_verified`, `FarmPhoto`, `DEFAULT_CONSENT_VERSION` — the seed imports it).
- **Idempotency-Key** `apps/api/farmerapp/api/idempotency.py`: `IdempotencyKey` table (`(tenant_id, actor_id, key)` unique, request hash, stored JSON response, 24 h `expires_at`) and the `@idempotent(status_code=…)` decorator: replay on same key + body, `422 idempotency_key_reuse` on a different body, errors never cached, replays run before the handler (no double write, no audit row).
- **Sync** `apps/api/farmerapp/sync/`: `models.py` (`sync_op`, append-only `sync_change` with `seq` identity), `changes.py` (flush hook), `schemas.py` (`SyncRequest` ≤ 200 ops, `SyncResult`, `SyncChangeOut`, `SyncResponse`), `service.py` (`apply_ops`: SAVEPOINT per op, `op_id` replay → `duplicate` with the original result, `pydantic` / `AppError` / `IntegrityError` → `rejected` with problem-style `error`; `CONFLICT_RULES` + `Strategy`; `changes_since`: scope filter in SQL, collapse to latest per entity, `MAX_CHANGES = 500`, `has_more`, base64 seq cursor, deletes as `{id, deleted_at}`), `router.py` (`POST /v1/sync`, roles field_officer / store_manager / cluster_head / farmer, `@idempotent`).
- **Audit plumbing** `apps/api/farmerapp/db/audit.py`: the detection in `_before_flush` is now `pending_changes(session) -> list[Change]` (obj, action, before, after, `version` after the flush) and `on_change(hook)` registers hooks that run in the same flush; `install_audit_listener` registers the sync hook. No second diff.
- **Uploads** `apps/api/farmerapp/uploads/`: `blobstore.py` (`BlobStore` protocol, `LocalBlobStore`, `FakeGcsBlobStore` over fake-gcs-server's JSON API, `build_blob_store(settings)`, URIs `gs://<bucket>/<tenant>/<purpose>/<sha256>`), `models.py` (`upload_session`, `upload_chunk` bytea), `schemas.py`, `service.py` (init, per-chunk sha + size checks, upsert re-PUT, status, complete with whole-file sha256, signed URL only for the tenant's completed blobs), `router.py` (`POST /v1/uploads`, `GET /v1/uploads/{id}`, `PUT /v1/uploads/{id}/chunks/{index}` raw body + `X-Chunk-Sha256`, `POST /v1/uploads/{id}/complete`, `GET /v1/blobs/signed-url?uri=`). `app.state.blobs` is built from `BLOB_STORE` (`local` default, `fake_gcs` in compose).
- **Jobs** `apps/api/farmerapp/jobs/purge_expired.py` + CLI `purge-expired --tenant-id`: deletes expired pending uploads (with chunks) and expired idempotency keys.
- **Migration** `apps/api/alembic/versions/0006_sync_uploads_idempotency.py`: `farmer.phone_verified`, `farm_photo`, `sync_op`, `sync_change` (append-only + sequence grant), `idempotency_key`, `upload_session`, `upload_chunk`; `enable_rls` on all six. `APPEND_ONLY_TABLES` gains `sync_change`.
- **Settings**: `BLOB_STORE`, `BLOB_LOCAL_DIR`, `UPLOAD_CHUNK_SIZE`, `UPLOAD_MAX_BYTES` (20 MB), `UPLOAD_TTL_SECONDS` (900), `SIGNED_URL_TTL_SECONDS` (900), `IDEMPOTENCY_TTL_SECONDS` (86 400), `PHONE_VERIFICATION_TTL_SECONDS` (1800). `docker-compose.yml`: api gets `BLOB_STORE=fake_gcs`, `PHOTOS_BUCKET=photos`. CORS allows `X-Chunk-Sha256`.
- `apps/api/openapi.yaml` regenerated (17 new operations with `x-roles`), `apps/api/README.md` (three new sections), `docs/progress.md`.

Design decisions and assumptions:
- Conflict strategy per entity lives in `CONFLICT_RULES`; `server_wins` is wired but only used by the append-only consent record until khata / payments land (M3).
- The change log is written by the **same** flush listener as the audit trail (`before_flush`) rather than a separate `after_flush` listener: one detection pass, rows commit with the mutation, and the version is derived deterministically (creates 1, updates +1, hard deletes keep the version, tables without `version_id_col` report 1).
- Change feed scope is evaluated in SQL at read time (visible farmers → their farms → plots / consents) instead of denormalising a `farmer_id` onto `sync_change`; the feed returns the *current* state of each entity (what an offline client needs), collapsed per entity within the page.
- Chunks are staged as `bytea` (the contract allowed it); a pending upload holds at most 20 MB for 15 minutes and `purge-expired` cleans up.
- Consent `channel` uses the existing CHECK values: `officer` when staff records it, `app` when the farmer does (the contract's `officer_app` label would need a constraint change; the field is output-only for the apps).
- OTP purpose reuses the existing `farmer_register` value (already in the CHECK constraint) instead of adding `farmer_verify`.
- `photos[]` URIs must be `gs://` under the tenant's prefix; if no completed `upload_session` matches (e.g. a photo uploaded from another session), the row is kept with `sha256 = NULL` rather than rejected.
- `blob_store` defaults to `local` so a bare laptop / CI without the emulator env still starts; the prd guard rail for the real adapter comes with SEC-016.

## Screenshots / goldens (UI changes)

None (API + database).

## Migration notes

- [x] Alembic migration added — `0006_sync_uploads_idempotency` (run as the owner). Backward compatible: additive tables + one defaulted column; deploy order migrate → api.
- [x] RLS policy + tenant_id on every table — six new tables isolated and forced (`tests/sync/test_rls_and_grants.py` + the metadata meta-test); `sync_change` append-only for the app role
- [x] Data backfill / retention impact — none; `sync_change` retention to be set with NF-012; `upload_chunk` / `idempotency_key` purge via `purge-expired`
- [ ] Cloud SQL: nothing new

## Test evidence

`SKIP_AUDIT=1 make check-api` — green: ruff, ruff format, mypy strict, pytest `678 passed, 1 skipped` (95.1% coverage; 379 tests before), `openapi.yaml` up to date, bandit clean. `pytest -m integration tests/uploads/test_blobstore.py` against the compose `gcs` service: passed.

New tests:
- `tests/farmers/test_write_api.py` — registration creates the row + consent (+ audit row), phone normalised / rejected, duplicate phone 409 (own and seeded), staff phone 422, unknown / foreign village 404, consent version from tenant settings, **2 farms + 3 plots in one POST**, client ids honoured, self-intersecting polygon 422 with reason, malformed GeoJSON 422, area mismatch warning (and not at +20 %), overlap warning (and none for own farms), idempotency replay / reuse / per-actor scoping / errors not cached, PATCH + scope 404s + no phone change + version conflict, farm / crop plot lifecycle with soft deletes, consent grant + withdrawal appended, tenant admin and store manager may register.
- `tests/farmers/test_phone_verify.py` — token flow gives `phone_verified: true`, token bound to phone / tenant, expires after 30 min (fake clock), wrong codes count and lock like login, verify later on the record (scope 404 for others), no code in responses.
- `tests/sync/test_sync_api.py` — registration via op (server state, `sync_op` row, changes feed), duplicate phone rejected without aborting the batch, validation rejections with details and unsupported actions, replayed `op_id` → `duplicate` identical (also for rejected results), **last-writer-wins on farmer.name** (older `client_ts` loses with server state, newer wins, matching version applies), conflict rule table, farm / plot ops + soft delete + not-found after delete, create of an existing id → conflict, farmer role limited to own record, batch limit + batch-level idempotency key, changes feed scoped per officer with an advancing cursor and collapsed updates, cap + `has_more`, bad cursor 400, change rows written by REST too.
- `tests/sync/test_rls_and_grants.py` — new tables mapped, `__audit__` flags, RLS meta-check, rows invisible outside their tenant, `sync_change` append-only.
- `tests/uploads/test_upload_api.py` — out-of-order chunks, idempotent re-PUT, incomplete complete 409 with `missing_chunks`, resume via GET, complete + blob content + idempotent complete + chunks dropped, whole-file sha mismatch 422 (still resumable), per-chunk validation (sha, header, index, size, empty), init validation, private to the owner, expiry 410 + `purge-expired`, signed URL (15 min) with foreign / unknown URIs 404.
- `tests/uploads/test_blobstore.py` — URI helpers, local store round trip + root escape, factory from settings, fake-GCS round trip (`integration`, skipped when the emulator is down).
- Updated: `tests/authz/test_matrix.py` (route fixtures for the 17 new operations; the generated SEC-006 matrix now covers them × 10 roles, cross-tenant and no-token), `tests/authz/conftest.py` (`farm_id`, `crop_plot_id`, `crop_id` on `SeededTenant`), `tests/farmers/conftest.py` (`ctx` fixture), `tests/conftest.py` (`BLOB_STORE=local` in a temp dir).

## Checklist

- [x] Tests written first; acceptance criteria covered (FA-012 duplicate phone blocked + consent record created, FA-013 2 farms / 3 plots, FA-025 conflict resolution, NF-003 idempotency + resumable uploads)
- [x] Role + tenant authorisation tests for every new endpoint (SEC-006 matrix, SEC-012 RLS)
- [x] Strings externalised; money in integer paise; timestamps UTC — problem `detail`s are developer text (client copy lives in the apps' ARB / i18n); no money; UTC `timestamptz`
- [x] No secrets in code, fixtures or logs — reserved test phones only; OTP codes never in responses
- [x] OpenAPI (`apps/api/openapi.yaml`) and `docs/progress.md` updated in this PR
- [x] Logs / metrics / alerts — `sync_ops_applied` (counts per status), `purge_expired`, `sync_op_integrity_error`
- [x] Runbook updated — `apps/api/README.md` sections "Farmer registration writes", "Sync", "Uploads and blobs"
- [ ] `infra/`, `rules/`, payments or auth code: 2 reviewers (CODEOWNERS) — `auth/deps.py` untouched; `db/audit.py` refactored (hooks), `farmers/phone_verify.py` issues signed tokens

### Mobile releases only

- [ ] VV-009 / disclosure copy: unchanged (no release in this PR)
