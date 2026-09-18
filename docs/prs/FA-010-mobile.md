# FA-010 (mobile half): duty toggle with foreground service, on-duty-only sampling, disclosure and device integrity (FA-011, FA-028, VV-001, VV-007, VV-009)

## Requirement IDs

- FA-010 (P0) Duty on/off toggle, location logging only while on duty, Android foreground service with a persistent notification — **mobile half done** (API half: `feat/FA-010-duty-location-api`). Acceptance: no location point is recorded while off duty (negative tests at controller and screen level: the sampler is never started before a session row exists and every fix is dropped after the end); the notification is visible for the whole shift.
- FA-011 (P0) First-run disclosure — **mobile half done**: A05 with the four points, "I agree", full policy sheet, read-aloud button; acceptance record with version, text hash, timestamp, device, app version stored locally and queued as `policy_acceptance`; the app blocks the duty toggle until the current version is accepted; a newer server version re-prompts.
- FA-028 (P0) Mock-location, rooted device, time-tamper detection — **done** (device-side detection; API columns since M2-KICKOFF): signals attached to every duty start and location point, banner only, never blocked.
- VV-001 (P0) On-duty sampling 2 min moving / 10 min stationary, batch upload every 15 min or on Wi-Fi / charging — **mobile half done** (battery budget on the reference device is the human gate).
- VV-007 (P0) Auto end of duty — **mobile half done**: local auto-end at the tenant time with the 10-minute prompt; server-owned `end_at` (idle rule) applied on arrival.
- VV-009 (P0) Play background-location declaration — **done** as a checklist (`docs/play/background-location-declaration.md`) plus the manifest; the Play Console submission is human.

PR title: `feat(FA-010): duty toggle with foreground service, on-duty-only sampling, disclosure and device integrity (FA-011, FA-028, VV-001, VV-007, VV-009)`

Branch `feat/FA-010-duty-mobile`. Only `apps/mobile`, `design/`, `docs/` touched (two API agents work in `apps/api` concurrently).

## Contract implemented (all writes through the existing `Outbox` / `/v1/sync`)

| Entity / endpoint | Shape |
|---|---|
| `duty_session` create | `{id, device_id, app_version, policy_version, start_at, start_point{lat,lon,accuracy_m}, integrity{is_mock,is_rooted,clock_drift_s}}` |
| `duty_session` update | `{end_at, end_point, end_reason: manual\|auto_time\|auto_idle}`; `rejected` `policy_not_accepted` / `duty_already_active` handled; `conflict` with a `server` row carrying `end_at` = server auto-ended → applied + notice |
| `location_batch` create | `{id, duty_session_id, device_id, sent_at, points[≤ 500]{ts, lat, lon, accuracy_m, speed_mps, bearing, battery_pct, is_mock, is_rooted, clock_drift_s, provider}}`; result `server: {accepted, rejected[{index, reason}]}` merged onto the local batch doc |
| `policy_acceptance` create | `{id, policy_key: "location_policy", version, text_hash, accepted_at, device_id, app_version}` |
| `GET /v1/policies/location` | `{version, text_hash, text{en,te,kn,hi,mr}}` cached in `kv`; bundled `2026-09-v1` copy in ARB + `design/copy/location_policy_en.md`; `text_hash = sha256(text_en.strip())` (test asserts the Dart constant equals the design copy) |
| `GET /v1/duty/policy` | `{moving_interval_s, stationary_interval_s, upload_interval_s, upload_on_wifi_or_charging}` (+ optional `auto_end_local_time`, `utc_offset_minutes`) cached; defaults 120 / 600 / 900 / true / 20:00 IST offline |

## What changed

### Core — `apps/mobile/packages/core`

- **Drift schema v4** (`db/app_database.dart`): `duty_sessions` (typed, `SyncedRow`; start/end, points, policy version, device, app version, integrity JSON, client `distance_m`, `auto_ended`, `extra` JSON for server fields such as `km` / `stops`), `location_buffer` (VV-002 fields + `batch_id`; index `(session_id, ts)`), `sync_docs` (generic JSON rows with sync flags for `location_batch` and `policy_acceptance`). Migration v3 → v4 additive; `LocalEntities` routes the three new writable entities (`SyncEntities.dutySession / locationBatch / policyAcceptance`), a `location_batch` doc stores `point_count` instead of the points.
- **Engine**: an `applied` result that echoes `server` fields merges them into the local row (batch `accepted` / `rejected`). `HttpSyncApi(onServerDate:)` reports the `Date` header of every response (FA-028 clock drift).
- **Duty module** `lib/src/duty/`:
  - `duty_models.dart`: `LocationPolicyDoc` (+ bundled copy and `policyTextHash`), `DutyPolicy` (+ `nextAutoEnd`), `DutyEndReason`, `LocationFix`, `IntegritySnapshot` (`hasIssues`: mock / rooted / |drift| > 300 s / jump), `maxPointsPerBatch = 500`.
  - `device_integrity.dart`: `DeviceIntegrityProbe` (`FakeDeviceIntegrityProbe`, `SafeDeviceIntegrityProbe` over `safe_device`: root + "allow mock locations"), `ClockDriftTracker` (`record(serverUtc, deviceUtc)` from the `Date` header, wall-vs-monotonic `checkpoint` detects jumps ≥ 60 s and folds them into the drift, persisted through `onChanged`), `DeviceIntegrity.snapshot(fixIsMock:)`.
  - `location_sampler.dart`: `LocationSampler` (`FakeLocationSampler` counts starts / stops and drops fixes while stopped; `GeolocatorLocationSampler` fused provider with `intervalDuration` = moving interval, `Position.isMocked`), `SamplingCadence` (pure VV-001 filter).
  - `duty_platform.dart` / `duty_platform_impl.dart`: `ForegroundDutyService` (`FlutterForegroundDutyService`, `flutter_foreground_task` 11, service type `location`, `stopWithTask: false`), `DutyAlerts` (`LocalDutyAlerts`, `flutter_local_notifications` 22, exact alarm with inexact fallback), `DeviceConditionsMonitor` (`PlusDeviceConditionsMonitor`: Wi-Fi from `connectivity_plus`, charging / level from `battery_plus`), `PermissionGate` (`PermissionHandlerGate`: background location only after foreground) — each with a fake.
  - `policy_api.dart`: `PolicyApi` (`FakePolicyApi`, `HttpPolicyApi` with bearer + refresh + `Date` observer).
  - `location_policy_controller.dart`: `LocationPolicyController` / `LocationPolicyState` (`accepted`, `needsReacceptance`; `load`, `accept` → `kv` + op, `refresh` → cached policy + duty settings, `markNotAccepted`).
  - `duty_repository.dart`: sessions, buffer (`insertPoint`, `pendingPoints`, `markBatched`, `purgeBatchedBefore`), batch docs, A10 `watchFarmersAdded`, A12 `day` / `watchDay` (`MyDay`, `DutySessionSummary`).
  - `duty_controller.dart`: `DutyController` / `DutyState` — `goOnDuty`, `goOffDuty`, `tick`, `flush`, `restore`, `dismissNotice`; session row + outbox watchers for the server-owned end and rejections; `DutyStartResult`, `DutyNotice`.
  - `duty_providers.dart`: `DutyCopy` (notification / prompt copy from ARB at the app locale), providers for every seam, `clockDriftTrackerProvider` + `restoreClockDrift`, `appVersionProvider`, `dutyTickerProvider` (30 s; empty in tests), `locationPolicyProvider`, `dutyControllerProvider`, `myDayProvider`, `istDayBounds`.
- **Widgets**: `DutyToggle` gains `blockedReason` / `blockedActionLabel` / `onBlockedAction` (FA-011); A64 labels for the three entities; `formatTimeIst`.
- **ARB**: +73 keys × 5 languages (`duty*`, `disclosure*`, `locationPolicyText`, `perm*`, `registered*`, `home*`, `stat*`, `nav*`, `myDay*`, `syncEntity*`); `build/untranslated.json` = `{}`.
- Dependencies: `flutter_foreground_task` 11, `permission_handler` 13, `battery_plus` 7, `flutter_local_notifications` 22 (+ `timezone`), `safe_device` 1.4.

### Agent app — `apps/mobile/apps/agent`

- `screens/onboarding/disclosure_screen.dart` A05, `permissions_screen.dart` A06, `device_registered_screen.dart` A07; `screens/home/home_screen.dart` A10 (DutyToggle, notice + integrity banners, stats, next up, quick actions, bottom nav), `my_day_screen.dart` A12 shell.
- `router.dart`: `/onboarding/disclosure`, `/onboarding/permissions`, `/onboarding/done`, `/home`, `/home/day`, `/home/policy`; A04 gains "Continue" → A05 after the OTP is verified.
- `main.dart`: real seams wired (`GeolocatorLocationSampler`, `FlutterForegroundDutyService`, `LocalDutyAlerts`, `PlusDeviceConditionsMonitor`, `PermissionHandlerGate`, `SafeDeviceIntegrityProbe`, `HttpPolicyApi`, shared `ClockDriftTracker` fed by both HTTP clients); `restore()` on start, policy `refresh()` when online.
- `AndroidManifest.xml`: `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK` with comments; `<service … foregroundServiceType="location">`. The farmer app declares no location permission.

### Design and docs

- `design/screens/A05.md`, `A06.md`, `A07.md`, `A10.md`, `A12.md`; `design/components/DutyToggle.md` (blocked state); `design/copy/location_policy_en.md` (shared hashed copy).
- `docs/play/background-location-declaration.md` (VV-009). `docs/progress.md` rows FA-010, FA-011, VV-001, VV-007 (mobile half), FA-028, VV-009 (done).

## Decisions and assumptions

- **Foreground service package**: `flutter_foreground_task` (maintained, typed service support for Android 14, no `FlutterFragmentActivity` requirement). The service keeps the process alive and owns the notification; the sampling loop runs in the app isolate (`DutyController`) which the service protects. A user swipe-kill therefore pauses sampling until the next launch, where `restore()` resumes the open session; moving the loop into the service isolate is a follow-up if the reference-device robustness test asks for it (noted in progress.md).
- **Root / mock detection**: `safe_device` (2026-07 release; su binaries, test-keys, Magisk paths, `isMockLocation` covering "allow mock locations" and mock providers) rather than the unmaintained `flutter_jailbreak_detection`. Per-fix `Position.isMocked` is OR-ed in.
- **Clock drift**: the server does not expose a time endpoint; the `Date` header of every API response is enough (1 s resolution, well under the 300 s VV-004 threshold). Monotonic jumps adjust the drift locally until the next response corrects it, so a tampered clock shows on the very next point.
- **Server-owned end**: the client never sends an end op once the server ended the session; the engine's existing `conflict` handling writes the server row, the controller reacts to `end_at` on the row.
- **Rejected start** (`duty_already_active`, `policy_not_accepted`): the local session is discarded (nothing exists server-side) rather than left as a "failed" item on A64.
- **Points kept two days** after batching so A12 can draw today's track; batch docs purged after seven days.
- **Auto-end without the app running**: the local notification prompt fires from the OS; the end itself needs the app process (tick) or the server's idle / day-end job — the server job is authoritative (VV-007 API half).
- **Read-aloud** on A05 is a visible button that reports "Coming soon" until the TTS work (NF-010).

## Screenshots / goldens

New: `apps/agent/test/goldens/goldens/a05_disclosure`, `a06_permissions`, `a07_registered`, `a10_home_blocked`, `a10_home_off`, `a10_home_on`, `a12_my_day` × `{light,sunlight}` (14); regenerated `packages/core/test/goldens/goldens/duty_toggle_{light,sunlight}.png` (fourth card: blocked). All other goldens unchanged.

## Migration notes

- [x] Drift v3 → v4 additive (`duty_sessions`, `location_buffer` + index, `sync_docs`); `test/db/migration_test.dart` covers v1 → v4, a genuine v2 file, a genuine v3 file (villages and outbox rows kept, no point buffered by the migration), fresh at v4, reopen.
- [ ] Alembic — n/a (mobile loop)
- [ ] RLS — n/a (device DB)
- [x] Dependencies: `flutter_foreground_task` (MIT), `permission_handler` (MIT), `battery_plus` (BSD-3), `flutter_local_notifications` (BSD-3) + `timezone`, `safe_device` (MIT). Android plugins only; no new native code in the repo.

## Test evidence

`cd apps/mobile && ./tool/check.sh` — green: pub get, codegen, no untranslated messages, `dart format` clean, `flutter analyze` zero issues (core, agent, farmer), string lint clean (70 files), `flutter test`: core **407 passed** (351 before; +56), agent **61** (39 before; +22), farmer 9.

New tests:
- `packages/core/test/duty/duty_models_test.dart` (6) — bundled text = `design/copy/location_policy_en.md` and hash = sha256 of the stripped English text (whitespace-insensitive), doc round trip, `DutyPolicy` defaults / contract parse / `nextAutoEnd` (20:00 IST today, tomorrow after 20:00), end reasons, `IntegritySnapshot` shape and thresholds.
- `packages/core/test/duty/sampling_cadence_test.dart` (8) — first fix kept; moving 2-min cadence; > 50 m counts as moving; stationary 10-min despite 2-min fixes; walking resumes the moving rate; backwards clock dropped; seed after restart; tenant intervals.
- `packages/core/test/duty/device_integrity_test.dart` (8) — drift from the `Date` header (persisted), restore, monotonic backwards / forwards jumps ≥ 60 s fold into the drift and flag, noise ignored, next response resets; probes + per-fix mock + "allow mock locations"; probe cache; `reportServerDate` parsing.
- `packages/core/test/duty/location_policy_controller_test.dart` (7) — blocked at first; accept → `kv` + `policy_acceptance` op with version / hash / device / app version that syncs; survives restart; newer server version re-prompts and blocks, cached offline, re-accept sends the new hash; same version no re-prompt; offline keeps bundled; `markNotAccepted`.
- `packages/core/test/duty/duty_controller_test.dart` (23) — FA-011 gate (no op, sampler / service never started, fix dropped); duty on (session op payload with fix + integrity, service title / text, sampler policy, VV-007 prompt at 19:50 IST, typed row); double start; no fix → notice; elapsed / notification; fixes buffered with battery / provider / integrity, cadence, distance; **NEGATIVE: nothing buffered before start or after end**; 15-min tick flush in the contract shape (batch doc keeps `point_count`); Wi-Fi / charging immediate flush; tenant flag off; **1,200 points → 500 + 500 + 200**; 500th fix flushes at once; server `{accepted, rejected}` on A12 data; duty off (flush, end op with end fix, stop order, prompt cancelled, everything syncs clean); auto-end at 20:00 with `auto_time` + notice; start after 20:00 → tomorrow; tenant 18:30; **server-owned `end_at` via conflict ends locally** (no client end op, `extra.km` kept, no sampling after); `duty_already_active` and `policy_not_accepted` rejections; restore after "app killed" (resume, seeded cadence, prompt, flush) and restore with nothing open.
- `packages/core/test/db/migration_test.dart` (+1: genuine v3 file → v4 keeps villages and outbox rows, no point buffered), `test/sync/sync_engine_push_test.dart` (+2: applied echo merged; `duty_session` typed round trip with `extra`), `test/widgets/duty_toggle_test.dart` (+1 blocked).
- agent `test/duty/onboarding_flow_test.dart` (3) — **A05 → A06 → A07 → A10 end to end** (four points, sheet, read-aloud, agree → op with version / hash → permissions in order with background gated on location → registered → unblocked toggle); permanently denied → Open settings; newer version → "updated" box → re-accept → second op.
- agent `test/duty/home_duty_test.dart` (5) — blocked toggle (no session, no sampling); on → ops / service / sampler / elapsed / pending / auto-end caption → A12 active session with km → off → ops in order, everything stopped, fix dropped; notice + integrity banner; A12 empty; bottom nav.
- agent `test/goldens/duty_golden_test.dart` (14).

## Checklist

- [x] Tests written first; acceptance criteria covered (no points off duty, notification visible while on, acceptance record with version and timestamp, toggle blocked until accepted, mock / root / drift signals attached and flagged not blocked, 2 / 10 min cadence, 15-min / Wi-Fi flush, ≤ 500 per op, auto-end with prompt)
- [ ] Role + tenant authorisation tests — n/a on mobile
- [x] Strings externalised (73 keys × 5 languages); timestamps UTC; money only as ₹0 placeholder
- [x] No secrets in code, fixtures or logs
- [x] Location only on duty; no hidden tracking; farmer app has no location permission
- [x] docs/progress.md updated; OpenAPI untouched (API half owns it)
