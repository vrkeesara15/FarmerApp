## Requirement IDs

- M1-KICKOFF (SPEC 14.4) Alembic models for the M1 entities of SPEC 8.2 with RLS policies and the Telangana demo seed (5 stores, 5 officers, 200 farmers) — done
- FA-013 Multiple farms / crop plots — data model supports it (a farmer with 2 farms and 3 crop plots is created at the ORM level and read back through the API); the app flows are still to do
- FA-012 Farmer registration — data model (unique phone per tenant, consent record, boundary, crops, irrigation, soil, ownership, language) and read endpoints; registration write endpoint + mobile wizard still to do
- FM-002 Consent — data model done (append-only `consent_record`, withdrawal as a new row, marketing separate from data); the farmer-app screen stays in M6
- FA-014 / VV-003 — `village.meeting_point`, `store.geofence` and `farm.boundary` are in place for the geofence work in M2
- VA-F02 / VA-F03 — `farm.centroid` and `farm.area_acres_computed` are stored generated columns so the checks are plain SQL later
- WC-003 Farmers directory + 360 — `GET /v1/farmers` and `GET /v1/farmers/{id}` exist as the API foothold

PR title: `feat(M1): farmers, farms, crop plots, consent, stores and villages with RLS and Telangana demo seed`

## What changed

- **Models** (all on `BaseColumns` = id/tenant_id/created_at/updated_at/deleted_at/version, CHECK-constraint enums like `user.role`):
  - `apps/api/farmerapp/tenants/models.py`: `cluster(name, district, state, location geography(Point), geofence geography(Polygon))`, `store(code, name, cluster_id, district, state, location, geofence)` unique `(tenant_id, code)`, `village(name, district, mandal, state, store_id, location, meeting_point)` unique `(tenant_id, district, mandal, name)`.
  - `apps/api/farmerapp/catalog/crops.py`: `crop(code, name, names jsonb per language, duration_days, active)` unique `(tenant_id, code)`; `PILOT_CROPS` (paddy, cotton, chilli, maize, tomato, groundnut with te/hi/kn/mr names).
  - `apps/api/farmerapp/farmers/models.py`: `farmer(phone, phone_last4, name, village_id, landmark, language, consent_marketing, consent_version, registered_by → user, user_id → user, source officer|app|import, land_ownership own|leased)` unique `(tenant_id, phone)`, pg_trgm index on `name`; `farm(farmer_id, name, survey_no, boundary geography(Polygon,4326), area_acres numeric, soil, irrigation, ownership, centroid GENERATED ST_Centroid(boundary), area_acres_computed GENERATED ST_Area(boundary)/4046.8564224)` with GiST on boundary + centroid, `eager_defaults` so both are available right after flush, plus read column properties `boundary_geojson`, `centroid_lat`, `centroid_lon`; `crop_plot(farm_id, crop_id, variety, season kharif|rabi|zaid, sowing_date, stage, expected_harvest, area_acres)`; `consent_record` on the lean `TenantRow` (subject_type, subject_id, purpose data|marketing, version, language, granted_at, withdrawn_at, channel, recorded_by; CHECK exactly one of granted_at/withdrawn_at; wall-clock `created_at`).
  - `apps/api/farmerapp/db/geo.py`: EWKT helpers (`point_wkt`, `polygon_wkt`, `offset`, acres ↔ m²) — no shapely dependency; PostGIS does the geometry.
  - `apps/api/farmerapp/db/audit.py`: `jsonable` now handles `date`, `Decimal` and GeoAlchemy elements (WKT in / hex WKB back) so farm rows audit cleanly. `apps/api/farmerapp/db/rls.py`: `APPEND_ONLY_TABLES = {audit_log, consent_record}`.
- **Migration** `apps/api/alembic/versions/0005_m1_farmers_farms_stores.py`: eight tables, FK indexes, GiST indexes, `enable_rls` on each (`append_only=True` for `consent_record`). Backward compatible: nothing existing is touched (`user.store_id` / `user.cluster_id` keep their plain uuid type; FKs to `store`/`cluster` are a later expand step). Downgrade exercised on the dev DB (0005 → 0004 → 0005).
- **Scope + API** `apps/api/farmerapp/auth/scope.py` `farmer_filters(actor)` (SPEC 2.6 "Farmer profile": tenant-wide roles; cluster head via village → store → cluster; store manager via village → store; field officer via `registered_by`; farmer via `user_id`; agronomist tenant-wide crop data), `FARMER_VISIBILITY`. `apps/api/farmerapp/farmers/schemas.py` read models (`FarmerOut`, `FarmerDetailOut` with farms → crop plots and consent history, `FarmOut` with GeoJSON boundary + centroid lat/lon + computed acres, `CropPlotOut`, `ConsentRecordOut`). `apps/api/farmerapp/farmers/router.py`: `GET /v1/farmers` (owner, director, tenant_admin, auditor, cluster_head, store_manager, field_officer, agronomist; filters `village_id`, `registered_by`; cursor pagination) and `GET /v1/farmers/{id}` (same + farmer); the agronomist gets `phone` masked and no `landmark`; soft-deleted rows hidden. `openapi.yaml` regenerated (`x-roles` on both).
- **Seed** `apps/api/farmerapp/jobs/seed.py` rewritten: `SeedProfile` (`FULL` for `make seed`, `SMALL` for fixtures), deterministic `uuid5` ids + fixed RNG → idempotent; per tenant under `actor_scope(system_actor)` + `tenant_scope`; one flush per table. `fcc`: 2 clusters, 5 stores in Warangal/Karimnagar/Nalgonda/Khammam/Nizamabad (real coordinates), 5 officers (existing `+919000000004` at Warangal + 4 new), store manager / cluster head placed, 40 mandal-HQ villages 6–22 km from their store, 200 farmers with Telugu names (40 per officer, 5 per village; farmer #1 linked to the demo farmer login), 1–2 farms each as convex quadrilaterals on a non-overlapping grid (0.5–5 acres; declared within ±7 % of measured), 1–2 crop plots per farm with variety/season/sowing/stage/harvest, consent rows (data for all, marketing ~60 %, a few withdrawn as second rows). `gfl`: 1 store (Raichur), 1 officer, 10 farmers. CLI prints per-table created/total and the duration (`--small` flag). `apps/api/README.md` documents it.
- **Tests** (details below), `docs/progress.md`, this file.

Design decisions and assumptions:
- Generated columns instead of triggers or Python geometry: PostGIS `ST_Centroid(geography)` and `ST_Area(geography)` are IMMUTABLE on PostGIS 3.4, so `GENERATED ALWAYS … STORED` works, is indexable and needs no shapely on the API side. SQLAlchemy `Computed` + `eager_defaults` handles it cleanly (RETURNING on insert/update).
- Enumerations are CHECK constraints (expand-only), same as `user.role`.
- `farmer.language` is the preferred language (SPEC 8.2 column name); no separate `preferred_language` column.
- Accountant is not on the farmers routes (SPEC 2.6 has no accountant column for the farmer profile); the users-route assumption (tenant-wide) stays as documented in FA-002.
- The consent text version is a placeholder (`2026-09-v1`, TODO-LEGAL; human gate SPEC 14.6).
- The `world` test fixture now seeds the `SMALL` profile (15 + 4 farmers) so the SEC-006 matrix stays fast; `SeededTenant.user(role)` is the role user (lowest phone), `everyone` holds all 14 / 10 accounts, `farmers` the seeded farmers.

## Screenshots / goldens (UI changes)

None (API + database).

## Migration notes

- [x] Alembic migration added — `0005_m1_farmers_farms_stores` (run as the owner). Backward compatible; deploy order migrate → api.
- [x] RLS policy + tenant_id on every table — all eight isolated and forced; `consent_record` append-only; meta-test covers them automatically
- [x] Data backfill / retention impact — none; consent records are kept (NF-013), retention class to be defined with NF-012
- [ ] Cloud SQL: nothing new

## Test evidence

`SKIP_AUDIT=1 make check-api` — green: ruff, ruff format, mypy strict, pytest `379 passed` (95.9% coverage; 315 tests, 95% before), `openapi.yaml` up to date, bandit clean. `make check-infra` — passed (fmt + validate + tflint; checkov not installed locally). `make migrate && make seed` on the compose DB: 0.85 s, then 0.19 s creating nothing on the second run; 3 clusters, 6 stores, 48 villages, 12 crops, 210 farmers, 285 farms, 403 crop plots, 338 consent records.

New tests:
- `tests/farmers/test_models.py` — FA-013 farmer with 2 farms and 3 crop plots; duplicate phone rejected in the tenant but allowed in another; `area_acres_computed` / `centroid` generated by the DB and loaded eagerly, GeoJSON + lat/lon properties, VA-F03 ratio and overlap and VA-F02 `ST_DWithin` in SQL, boundary added later; geometry rows audited as JSON (WKT in, WKB back, generated columns not diffed); crop plot FKs and season/soil/irrigation/ownership/source checks; consent withdrawal as a new row, one-event check, UPDATE/DELETE/TRUNCATE denied for the app role (SQL and ORM); village meeting point + store mapping; RLS on every M1 table (visible only in own tenant, nothing unbound, foreign insert rejected); seed writes attributed to the system actor.
- `tests/farmers/test_api.py` — owner lists everything with stable cursor pagination and the full row shape; filters; field officer sees own farmers only (404 otherwise); store manager via villages (nothing without a store); cluster head sees the 3 North Telangana stores; agronomist reads crop data with masked phone and no landmark; farmer reads own record only and cannot list; farmer 360 shape (GeoJSON polygon, centroid, computed acres, plots, consents); unknown / other-tenant 404 without leaks; soft-deleted hidden; bad cursor / limit.
- `tests/seed/test_seed_demo.py` — full profile counts and < 30 s; idempotent (twice small, then full on top adds only what is missing, then nothing); result shape; polygons valid, closed, 0.4–5.5 acres, declared within ±30 %, no overlaps, centroid inside, villages 5–25 km from the store, farms within 3 km of the village; farmers/farms/plots/consents details; tenants do not see each other.
- Updated: `tests/authz/conftest.py` (small profile, `everyone`, `farmers`), `tests/authz/test_matrix.py` (`GET /v1/farmers/{id}` fixture, leak check over every account and farmer — the generated matrix now covers the two new routes × 10 roles, cross-tenant, no token), `tests/authz/test_users.py`, `tests/auth/test_seed.py` (24 users, placements), `tests/audit/test_mechanism.py`, `tests/audit/test_api_mutations.py`, `tests/audit/test_read_endpoint.py`, `tests/rls/test_api.py`, `tests/test_jobs.py` (CLI table + `--small`).

## Checklist

- [x] Tests written first; acceptance criteria covered (FA-013 "farmer with 2 farms and 3 crop plots can be created"; seed 5 stores / 5 officers / 200 farmers)
- [x] Role + tenant authorisation tests for every new endpoint (SEC-006, SEC-012)
- [x] Strings externalised; money in integer paise; timestamps UTC — seed fixtures only; UTC `timestamptz`; no money yet
- [x] No secrets in code, fixtures or logs — reserved test phone numbers only
- [x] OpenAPI (`apps/api/openapi.yaml`) and `docs/progress.md` updated in this PR
- [x] Logs / metrics / alerts — `seed_done` log event with counts and duration
- [x] Runbook updated — `apps/api/README.md` "Seed data" and "Farmers, farms, consent"
- [ ] `infra/`, `rules/`, payments or auth code: 2 reviewers (CODEOWNERS) — `auth/scope.py` touched (filters only)

### Mobile releases only

- [ ] VV-009 / disclosure copy: unchanged (no release in this PR)
