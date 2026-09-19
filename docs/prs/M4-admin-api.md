# M4 admin API — users, devices, fast revocation, step-up, remote wipe, typed settings, audit export

Branch `feat/M4-admin-api` (from `main` at `c2e85e0`). API half only; the console screens
(C101, C102, C103) and the mobile wipe are later tasks.

## Requirement IDs

- **WC-011** (P0) Users, roles, device binding, forced logout — API done: create, update
  (role / status / assignment), deactivate, force logout, device list / bind / report lost.
  **Acceptance "revoked user loses access within 5 min": met** — a disabled or force-logged-out
  user is rejected on the next request (0 s); a lost or unbound device within the device-status
  cache TTL (30 s default, at most 60 s); refresh fails immediately. Console C101 left.
- **WC-012** (P0) Settings — API done: typed `TenantSettings`, `GET /v1/settings`,
  `GET /v1/settings/public`, `PATCH /v1/settings`. **Acceptance "changes audited": met**
  (explicit `tenant_settings.update` with before / after of the changed keys, plus the FA-006
  `tenant.update` row). Console C102 (with the live preview) left.
- **WC-103** Audit log viewer — backend done: extra filters (`actor_role`, action prefix,
  free-text entity id `q`) and `GET /v1/audit-logs/export` (CSV, step-up, audited). Console
  C103 left.
- **SEC-020** Device-bound refresh for field agents — done: one active device per field
  officer (409 `device_not_bound`, admin rebind), `did` claim on device access tokens,
  `revoked_reason` on refresh tokens. Left from SEC-020: RS256 + JWKS, key rotation.
- **SEC-025** Remote wipe — server half done: 401 `device_wipe_required` and
  `GET /v1/devices/me/status`. The mobile wipe itself is a mobile task (contract below).
- **SEC-028** Admin re-auth — done: `POST /v1/auth/step-up/send` + `POST /v1/auth/step-up`,
  `X-Step-Up-Token` on every admin action, 401 `step_up_required`; all actions audited.

## What changed

**Migration `0020_admin_devices_settings`** (`down_revision = "0017"`, branch label `admin`;
the M4 integration merges the heads). Expand-only: new `device` table (RLS; unique
`(tenant, user, device_id)`; status `pending | active | revoked | lost`), backfilled from
`user.device_id` (the device each account last signed in from becomes its bound device);
`user.tokens_valid_after`; `refresh_token.revoked_reason`; `otp_challenge.purpose` gains
`step_up`. Downgrade drops them (deleting only short-lived `step_up` challenges).

**Code**
- `farmerapp/auth/devices.py` (new): `admit_login` (SEC-020 gate), `check_refresh`,
  `revoke_sessions`, `DeviceStatusCache` (TTL <= 60 s, per process).
- `farmerapp/auth/stepup.py` (new): step-up token (HS256, `typ=step_up`, 5 min, bound to user
  and tenant), `StepUp` dependency, `check_step_up`, `x-step-up` OpenAPI marker.
- `farmerapp/auth/`: `models.py` (`Device`, `DeviceStatus`, `RevokeReason`, new columns,
  `OtpPurpose.STEP_UP`), `tokens.py` (`did` / `iat` claims, revocation reasons, refresh answers
  `session_revoked` / `device_wipe_required`), `deps.py` (`get_current_user` checks
  `tokens_valid_after`, disabled + device -> wipe, device status via the cache), `router.py`
  (device admission at login, device meta at refresh, step-up endpoints), `schemas.py`
  (`platform`, `model`, `app_version` on verify; `app_version` on refresh), `errors.py`,
  `policy.py` (the two new 401 codes documented on every protected route).
- `farmerapp/users/`: router rewritten around the WC-011 actions; `device_router`
  (`/v1/devices/me/status`); schemas.
- `farmerapp/tenants/settings.py` (typed model covering every key in use, lenient loader,
  `get_tenant_settings` / `settings_from_tenant`), `farmerapp/tenants/settings_router.py` (new).
- Readers refactored to the one accessor without behaviour change: visits (`settings_of`,
  plus the tenant default meeting-point radius), policies / duty (`settings_for`), khata
  (`tenant_credit_settings`), payments (`day_close`, `webhooks`), invoices, farmers
  (consent version).
- `farmerapp/audit/router.py`: filters object shared by list and export, CSV export.
- `farmerapp/settings.py`: `STEP_UP_TOKEN_TTL_SECONDS` (300), `SECURITY_CACHE_TTL_SECONDS`
  (30, validated <= 60).
- Shared files, additive: `api/app.py` (two routers), `db/models/__init__.py` (`Device`),
  `tests/authz/test_matrix.py` (`RouteFixture.step_up` + fixtures for the new operations),
  `tests/authz/conftest.py` (`step_up` fixture).
- Existing tests updated for intended contract changes: role / status PATCH now sends a
  step-up token (`tests/authz/test_users.py`, `tests/audit/test_api_mutations.py`); a
  device-bound session of a disabled account now gets `device_wipe_required` instead of
  `user_disabled` (`tests/auth/test_me.py`, `tests/auth/test_tokens.py`); new columns in
  `tests/test_migrations.py`.

## Contract for the console (C101, C102, C103)

**Step-up (SEC-028).** Operations with `x-step-up: true` in `openapi.yaml` need
`X-Step-Up-Token`. Flow: on 401 `step_up_required` (the problem carries
`step_up_url: /v1/auth/step-up/send`) -> `POST /v1/auth/step-up/send` (202, same shape as
`sendOtp`: `phone_masked`, `expires_in`, `resend_after`, `resends_left`) -> ask for the code
-> `POST /v1/auth/step-up {code}` -> `{step_up_token, expires_in: 300}` -> retry with the
header. Keep the token in memory only and reuse it until it expires; the role check always runs
first (403 `forbidden` stays 403). Protected: `POST /v1/users`, `PATCH /v1/users/{id}` **when
the body has `role` or `status`**, `POST /v1/users/{id}/deactivate`,
`POST /v1/users/{id}/force-logout`, `POST /v1/users/{id}/devices/{device_id}/bind`,
`POST /v1/users/{id}/devices/{device_id}/report-lost`, `PATCH /v1/settings`,
`GET /v1/audit-logs/export`. Wrong code: 401 `otp_invalid` (with `attempts_left`), 423
`otp_locked`.

**C101 users and devices** (owner, director, tenant_admin write; cluster head and auditor read)

| Call | Notes |
|---|---|
| `GET /v1/users`, `GET /v1/users/{id}` | unchanged |
| `POST /v1/users {phone, name, role, store_id?, cluster_id?, language?}` | 201 `UserOut`; 409 `phone_taken`, 422 `invalid_assignment` (`field`), farmer role 422 |
| `PATCH /v1/users/{id}` | name / store / cluster freely; role / status need step-up; `status: disabled` = deactivate |
| `POST /v1/users/{id}/deactivate` | idempotent; signs out everywhere and wipes the apps |
| `POST /v1/users/{id}/force-logout` | `{user_id, revoked_sessions, tokens_valid_after}` |
| `GET /v1/users/{id}/devices` | `{items: [{device_id, platform, model, app_version, first_seen, last_seen, status, bound_at, revoked_at}]}`; `pending` = a refused sign-in waiting for "Bind this device" |
| `POST /v1/users/{id}/devices/{device_id}/bind` | field officers: the previous device becomes `revoked` and is signed out |
| `POST /v1/users/{id}/devices/{device_id}/report-lost` | status `lost`; that device's sessions end and its app wipes |

Guard rails: only an owner grants the owner role or changes / signs out an owner
(403 `role_not_grantable`); nobody changes their own role or status (403
`cannot_modify_self`).

**C102 settings** (read: owner, director, tenant_admin; write: owner, tenant_admin)

`GET /v1/settings` returns every key with its effective value (schema `TenantSettings` in
`openapi.yaml`, ranges in `farmerapp/tenants/settings.py`). `PATCH /v1/settings` takes any
subset; nested `sampling` and `branding` merge key by key; `null` resets a key to its default.
Out-of-range values: 422 `invalid_settings` with `errors: [{loc, msg, type}]`; unknown keys
or languages: 422 request validation. Keys: geofence radius, meeting-point radius default,
minimum visit time, auto duty end, idle end, location policy version, sampling, TA rate per
km (paise), store manager max credit limit (paise), credit due days, day-close variance
threshold (paise), webhook replay window, legal name, GSTIN per state, invoice prefix,
languages enabled (`en te kn hi mr`), default language, branding (`app_name_agent`,
`app_name_farmer`, `primary_colour` `#RRGGBB`, `logo_blob_uri` from `/v1/uploads`,
`support_phone`). The live preview of both apps renders from `GET /v1/settings/public`'s shape
applied to the unsaved form.

**C103 audit log viewer**: `GET /v1/audit-logs?entity=&entity_id=&actor_id=&actor_role=&action=&from=&to=&q=&cursor=&limit=`
— `action` ending in `.` is a prefix (`user.`), `q` is an entity id or its first characters
(hex and `-`, max 36). `GET /v1/audit-logs/export` takes the same filters, returns
`text/csv` (columns `created_at, action, entity, entity_id, actor_id, actor_role, ip,
device_id, user_agent, trace_id, before, after, id`; JSON cells; formula-looking cells prefixed
with `'`; at most 50,000 rows) and writes an `audit_log.export` row. Admin events to show:
`user.force_logout`, `device.bind`, `device.report_lost`, `tenant_settings.update`,
`auth.step_up`, `audit_log.export`, plus the generic `<table>.<create|update|delete>`.

## Contract for mobile (officer / store app; farmer app later)

**Login and refresh.** Always send `device_id` (already done by `HttpAuthApi`); also send
`platform`, `model`, `app_version` on `/v1/auth/otp/verify` and `app_version` on
`/v1/auth/refresh` (optional, shown in C101). New outcomes:

| Code | When | App behaviour |
|---|---|---|
| 409 `device_not_bound` (verify) | a field officer signs in from a device that is not their bound one | "This phone is not registered to you. Ask your administrator to approve it." Keep the phone number; retry login later |
| 422 `device_id_required` (verify) | officer login without a device id | never happens from the app |
| 401 `session_revoked` (any call, refresh) | forced logout, or this device was unbound | drop tokens, go to login (**no wipe**: unsynced outbox stays) |
| 401 `device_wipe_required` (any call, refresh, verify) | account disabled or device reported lost | **wipe**: delete the Drift database and its key, cached files and photos, tokens and `kv`; go to login |

**Remote wipe (SEC-025).** Any response with problem code `device_wipe_required` triggers the
wipe. On app start (before showing cached data) call `GET /v1/devices/me/status` with the
access token and `X-Device-Id`; `{"wipe_required": true}` also triggers it; a 401 with the
code above does too; other failures (offline) do not. Response:
`{device_id, status: pending|active|revoked|lost|unknown, wipe_required, user_status}`.

**Settings cache.** The app fills its local settings (geofence radius, meeting-point radius,
minimum visit duration, auto duty end, idle end, sampling intervals, location policy version,
languages, branding) from `GET /v1/settings/public` (every role) after login and on every
sync, replacing the hard-coded defaults. The server re-evaluates geofence and duration at
check-in / check-out, so a stale cache can only change what the app *shows*, never the
result. Shape: `{geofence_radius_m, meeting_point_radius_m|null, min_visit_duration_s,
auto_duty_end_local_time "HH:MM", idle_end_minutes, location_policy_version, sampling
{moving_s, stationary_s, upload_s}, languages_enabled [..], default_language, branding
{app_name_agent|null, app_name_farmer|null, primary_colour, logo_blob_uri|null,
support_phone|null}}`.

## Revocation: how fast, and why

| Change | Access token | Refresh |
|---|---|---|
| deactivate / `status: disabled` | next request (user row read each request) | immediately (families revoked, `user_disabled`) |
| force logout | next request (`iat <= tokens_valid_after`) | immediately (`force_logout`) |
| device reported lost | this instance at once (cache entry dropped); other instances within `SECURITY_CACHE_TTL_SECONDS` (30 s, max 60 s) | immediately (`device_lost`) |
| device unbound by a rebind | same as lost | immediately (`device_revoked`) |

Worst case is the cache TTL (<= 60 s), well within the 5-minute acceptance.
`tokens_valid_after` has one-second resolution: a token minted in the same second as the
revocation is also rejected (the user signs in again a second later).

## Assumptions / decisions

- The device table adds a `pending` status (a refused officer sign-in) so C101 can offer
  "Bind this device"; `active | revoked | lost` are as specified.
- Step-up is also required for creating users, deactivating and reporting a device lost (they
  grant access or destroy data like the listed actions). Renaming and store / cluster
  assignment are not.
- `PATCH /v1/settings` is owner and tenant_admin (as briefed); SPEC 2.6 lists owner /
  director as writers — directors read only for now. Flag if directors should write.
- TA rate default Rs 3 / km (300 paise) until the owner sets it (FA-023 not built yet).
- The existing catalogue CSV export (`GET /v1/catalog/export`, product data, no PII) is not
  behind step-up yet; future exports (WC-013) should use the `StepUp` dependency.
- Tenant settings load leniently (a stored bad key falls back to its default, logged as
  `tenant_settings_invalid`); writes are strict.

## Tests

`tests/admin/` (new): device binding (6 flows), revocation (force logout, disable, deactivate,
cache TTL for lost / revoked devices, worst-case bound), remote wipe, step-up on each of the
nine protected actions + OTP flow + expiry + binding, user creation and guard rails,
settings (defaults, public subset, merge, audit before / after, 14 validation cases, readers
through the accessor, lenient load), audit filters and CSV export. The authz matrix picks up
all new operations (step-up fixtures).
