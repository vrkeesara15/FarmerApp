# M5 mobile security — encrypted database, certificate pinning, Play Integrity, remote wipe, device binding, tenant settings pull

Branch `feat/M5-mobile-security` (from `main` at `fbe0a91`). Mobile only (`apps/mobile`, `docs/`,
`design/screens/A08.md`). Server-side follow-ups are listed at the end.

## Requirement IDs

- **SEC-024** (done, human gates below) — SQLCipher database with the key in the Android
  Keystore and migration of the plain file; certificate pinning for the API domain; Play
  Integrity on login and sensitive actions (credit sale, payment collection, day close).
- **SEC-025** (done) — mobile remote wipe on 401 `device_wipe_required` and on the start-up
  `GET /v1/devices/me/status`, in both apps; A08 "Signed out by your administrator".
- **SEC-020** (client side done) — 409 `device_not_bound` at login has its own message;
  refresh stays bound to the device id already sent; `platform` / `app_version` sent on login,
  `app_version` on refresh. RS256 + JWKS still open (API).
- **SEC-008** (release hardening done, MobSF scan open) — R8 minify / shrink, never debuggable,
  `--obfuscate --split-debug-info`, `allowBackup="false"` with backup / data extraction rules,
  cleartext only to local hosts in debug; the merged manifest is checked after the build.
- **M2 follow-up / WC-012** — `GET /v1/settings/public` fills the local settings cache.

## Encrypted database (SEC-024)

**Choice.** The repo is on Drift 2.35 / `package:sqlite3` 3.6. Since sqlite3 3.x the native
library comes from the package's build hook, and `sqlite3_flutter_libs` /
`sqlcipher_flutter_libs` are end-of-life. The maintained path is the hook's user define in the
workspace `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlcipher
```

It links the prebuilt, sha256-pinned SQLCipher community build (4.19.0) on Android **and on the
test host** (macOS arm64 here), so the SQLCipher tests actually run in `flutter test`. SQLCipher
without a key behaves as plain SQLite, so the rest of the suite (in-memory databases through
the `DatabaseOpener` seam) is unchanged. SQLCipher links OpenSSL on Android (APK size below).

**Key.** 32 random bytes (`Random.secure`), hex, generated on first run and stored by
`SecureDatabaseKeyStore` in `flutter_secure_storage` 11. Jetpack `EncryptedSharedPreferences`
is deprecated upstream and flutter_secure_storage 10+ replaced it: the value is AES-256-GCM
encrypted with a key wrapped by an RSA-OAEP key that lives in the Android Keystore (the task's
intent — Keystore-backed encryption — is met by the plugin's current default). `resetOnError`
is off so a transient Keystore error does not silently rotate the key. The key is used raw
(`PRAGMA key = "x'…'"`): no PBKDF2 at open time, so cold start is unaffected (NF-005).

**Opener.** `EncryptedDatabaseOpener` (`packages/core/lib/src/db/encrypted_database.dart`)
opens `farmerapp_secure.db` in a background isolate; every connection gets the key and proves
it (`SELECT count(*) FROM sqlite_master`) and refuses to run if the linked library is not
SQLCipher (fail closed). Both apps and the WorkManager isolate use it.

**Migration.** A plain `farmerapp.db` from an earlier version is exported on first start
(`ATTACH … KEY` + `sqlcipher_export`, `user_version` carried over) into
`farmerapp_secure.db.migrating`, row counts of every table are compared, the file is renamed
into place and only then the plain file (and `-wal` / `-shm`) is deleted. A failed migration
keeps the plain file and opens it for this run (unsynced work is never lost) and retries on
the next start. An encrypted file without a stored key (Keystore reset, restored backup) is
unreadable forever and is recreated.

## Certificate pinning (SEC-024)

`createPinnedHttpClient` (`security/certificate_pinning.dart`): a `dart:io` `HttpClient` whose
`connectionFactory` opens the TLS socket itself, lets the normal chain validation run, then
compares the base64 SHA-256 of the server certificate's DER `SubjectPublicKeyInfo` with the
configured pins **before any request byte (bearer token included) is written**; proxies are not
used. Pins: `--dart-define=API_CERT_PINS=<primary>,<backup>` from
`apps/mobile/config/env/{dev,stg,prd}.json` (`tool/build_release.sh <app> <env>`). stg / prd
carry placeholders (`REPLACE_WITH_…`) because the domain does not exist yet — such a build
refuses every TLS connection to the API (fail closed); `dev` points at `http://10.0.2.2:8000`.
Local hosts (10.0.2.2, 10.0.3.2, localhost, 127.0.0.1, ::1) and plain HTTP are never pinned.

`dart:io` exposes only the leaf certificate on a socket, so the pin is the **leaf SPKI**;
the backup pin is the SPKI of a spare key pair generated offline. Consequence for infra: the
API certificate must keep its key across renewals (Google-managed certificates rotate keys —
use a self-managed certificate on the load balancer, or ship the next key's pin as the backup
before rotating). TLS failures (pin mismatch, handshake) surface as `http.ClientException`,
which every API client already handles as "offline".

## Play Integrity (SEC-024)

`DeviceAttestation` with `PlayIntegrityAttestation` (method channel `farmerapp/integrity`,
implemented in both apps' `MainActivity.kt` with `com.google.android.play:integrity:1.6.0`
standard requests: `prepareIntegrityToken` once per process, `request` per call) and
`FakeDeviceAttestation`. `SecureApiClient` decides per request (`sensitiveActionsOf`):

| Request | `X-Integrity-Action` |
|---|---|
| `POST /v1/auth/otp/verify` | `login` |
| `POST /v1/stores/{id}/pos/sales` with `mode: credit` | `credit_sale` |
| `POST /v1/stores/{id}/pos/sales` other modes, `POST /v1/payments[/…]` | `payment_collection` |
| `POST /v1/stores/{id}/day-close` | `day_close` |
| `POST /v1/sync` with an `order` op `payment_mode: credit` / a `payment` create op | `credit_sale`, `payment_collection` |

**Contract (server verification is an API follow-up).** Headers `X-Integrity-Action` (comma
list) and either `X-Integrity-Token` (standard token) or `X-Integrity-Status: unavailable`.
The token's `requestHash` = base64url, unpadded, of
`SHA-256(METHOD + "\n" + path + "\n" + hex(SHA-256(body)) + "\n" + actions)`; the server
recomputes it from the request it received, decodes the token with the Play Integrity API
(Google Cloud project linked in Play Console), checks `requestHash`, package name,
`appRecognitionVerdict`, `deviceRecognitionVerdict`, and **flags, never blocks** (FA-028,
VA-E01). No token within 3 s, not configured (`PLAY_INTEGRITY_PROJECT_NUMBER` = 0), no Play
services or a quota error → `unavailable`, logged, request sent unchanged. The WorkManager
isolate has no channel, so background syncs send `unavailable`.

## Remote wipe (SEC-025)

- **Trigger.** `SecureApiClient` reports any 401 whose problem code is `device_wipe_required`
  to the app's `WipeSignal` (sync engine, REST reads, refresh, login — every client goes
  through it; the response still reaches the caller). On start (when signed in and online, in
  the background so cold start never waits) `checkDeviceStatusOnStart` calls
  `GET /v1/devices/me/status` with `X-Device-Id`; `wipe_required: true` triggers it too.
  Offline / other failures do nothing.
- **Wipe.** `RemoteWipeCoordinator` shows a text-free spinner, waits for the sync run that saw
  the order, disposes the provider container, then runs `standardWipeSteps` (each step
  independent, failures logged): stop the duty foreground service and the sampler → forget the
  session (the device id is kept so the server still recognises a lost phone) → close the
  database, delete its files and key, open a fresh one holding only the language and the
  `security.wipe_notice` record → delete `<documents>/photos` (photos and chunked-upload
  sources) and the temporary directory → (officer app) cancel WorkManager jobs. It then starts
  the app again; the router opens **A08** while the notice exists (also after a restart).
  "Sign in again" clears it and goes to the language step. The farmer app runs the same steps
  without duty / WorkManager (`apps/farmer/lib/security.dart`).

## Device binding (SEC-020, client)

`OtpVerifyResult.deviceNotBound` / `AuthFailure.deviceNotBound` on 409 `device_not_bound`:
"This phone is not registered to you. Ask your administrator to approve it, then sign in
again." (5 languages); the phone number stays, no session is stored.

## Tenant settings pull (M2 follow-up)

`TenantSettingsSync` (`state/tenant_settings.dart`) fetches `GET /v1/settings/public` after a
successful login, on start when the last pull is older than 24 h, and whenever the network
comes back (daily throttle). It stores the settings in `kv` and fans them out to the caches the
features already read: `visits.settings` (geofence radius, tenant meeting-point radius,
minimum visit duration → A30 pre-check, proof checklist) and `duty.policy` (moving /
stationary / upload intervals, auto duty end → `DutyController`, `SamplingCadence`); the
`LocationPolicyController` state reloads immediately. Languages and branding are cached
(`tenantSettingsProvider`) for later UI use. Never fetched = SPEC defaults (150 m, 5 min, 20:00,
2 / 10 / 15 min).

## SEC-008 Android release hardening (both apps)

`android/app/build.gradle.kts` release: `isDebuggable = false`, `isMinifyEnabled = true`,
`isShrinkResources = true`, `proguard-rules.pro` (Gson generics of
flutter_local_notifications, Play Integrity). Manifest: `allowBackup="false"`,
`fullBackupContent` / `dataExtractionRules` excluding every domain (the database lives in the
file domain), `networkSecurityConfig`: `src/main` TLS only, `src/debug` overlay allows cleartext
to 10.0.2.2 / localhost / 127.0.0.1 only. The farmer manifest now declares `INTERNET` (release
builds could not reach the API before). Dart: `--obfuscate --split-debug-info` in
`tool/apk_size_check.sh` and the new `tool/build_release.sh`; `tool/check_release_manifest.sh`
dumps the built APK's manifest with `aapt2` and fails on debuggable, backup, missing rules or
cleartext. `apk_size_check.sh`: fixed a flaky "Android toolchain not available" under
`pipefail` (`flutter doctor | grep -q` SIGPIPE).

## Tests

- core: `test/db/encrypted_database_test.dart` (key; SQLCipher group — encrypted header, wrong
  / missing key fails, upgrade migration with row counts and plain file deleted, export
  function, failed migration keeps the plain file, key-less file recreated, destroy; the group
  is skipped with a printed reason where the host library is plain SQLite),
  `test/security/certificate_pinning_test.dart` (fixture CA + RSA / EC server certificates
  generated with the `openssl` CLI in the test: SPKI pin equals openssl's; TLS server reached
  with the primary or backup pin; wrong pin fails with zero requests on the server; no pins =
  refused; local hosts exempt), `test/security/device_attestation_test.dart`,
  `test/security/remote_wipe_test.dart` (trigger from an ordinary API call, from the sync
  engine, from the start-up check; wipe removes every store, keeps the language, failing step
  isolation), `test/state/tenant_settings_test.dart`, `test/visits/visit_flow_test.dart` (the
  pre-check uses the fetched radius).
- agent: `test/security_test.dart` (A08, A04 device-not-bound copy, end-to-end wipe from a
  sync 401). farmer: `test/security_test.dart` (A08 in Telugu, wipe from refresh and from the
  start-up check).

## Results

`APK_SIZE_CHECK=1 ./tool/check.sh` green: lint 13, core 591 (541 before; the SQLCipher group
ran on the host, SQLCipher 4.19.0 community, nothing skipped), agent 193, farmer 12. Farmer
release APKs (obfuscated, R8, SQLCipher): arm64-v8a 23.07 MB, armeabi-v7a 19.55 MB (budget
25 MB; `libsqlcipher.so` is ~5 MB uncompressed per ABI). Merged manifests of the farmer split
APKs and of `tool/build_release.sh agent dev apk` pass `check_release_manifest.sh`
(`allowBackup=false`, backup / extraction rules, network security config, not debuggable).

Build fixes found by the first real release build of the farmer app: `compileSdk` 37
(`permission_handler_android` 14 requires it; `targetSdk` unchanged) and core library
desugaring (`flutter_local_notifications`), both apps.

## Human gates

1. Real certificate pins (primary + backup SPKI) for stg / prd in `config/env/*.json`, and a
   certificate whose key is stable across renewals (or a pre-shipped backup pin).
2. Play Integrity: link a Google Cloud project in Play Console, set
   `PLAY_INTEGRITY_PROJECT_NUMBER`, implement server-side token verification (API follow-up,
   contract above), service account for the decode call.
3. SQLCipher verified on a reference device (NF-001: migration from a plain database of a
   pilot build, cold start < 3 s, WorkManager isolate opening the same file).
4. MobSF scan of the release APK (SEC-008), release signing config (still debug keys).

## API follow-ups

- Verify `X-Integrity-Token` (see contract), record `X-Integrity-Status: unavailable` as a
  VA-E01 signal; add the headers to `openapi.yaml` (not touched here: API files are owned by
  another branch).
- `GET /v1/settings/public` is read by the farmer app too (role `farmer` included in
  `require_roles(*Role)`).
