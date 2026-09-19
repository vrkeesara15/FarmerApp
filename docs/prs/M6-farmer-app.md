# M6 farmer app (Kisan) core — language and audio, consent, officer-registered profile, orders and UPI, khata, visit confirmation and rating, delete account, offline cache

Branch `feat/M6-farmer-app` (from `main` at `d6aedeb`). Mobile only (`apps/mobile`, `design/screens`,
`docs/`). The crop doctor (F20–F28) is a later task: "Check my crop" and the Crop doctor tab open a
placeholder route.

## Requirement IDs

- **FM-001** (done; human gates below) — F01 audio per language, F02/F03 login continuing straight to
  consent / welcome / home; the first run is measured in a widget test.
- **FM-002** (done, mobile) — F04 two separate consent cards with read-aloud; F70 consent settings
  withdraw offers.
- **FM-003** (done) — F05 officer-registered prefill with tap-only edits, or quick setup; F40 My crops.
- **FM-010** (done, mobile) — F30–F34 orders with UPI / pay at store / credit request, F50 khata with
  Pay now, F51 receipt.
- **FM-011** (done, mobile) — F60 prompt (push or sync feed), QR scan, F61 rating, F62 officer card.
- **FM-014** (done) — APK sizes below.
- **FM-015** (mobile half done) — F70 delete account against the `POST/GET /v1/me/deletion-request`
  contract (API in the diagnosis-API worktree).
- **NF-002** farmer-app half, **NF-009**, **NF-010** (farmer app parts; crop doctor screens later).

## Design

**Data layer (`packages/core/lib/src/kisan/`).** `KisanApi` (`HttpKisanApi` over `RestJsonClient`,
which gained `patch`; `FakeKisanApi` with the server rules the screens rely on: row versions,
`credit_limit_exceeded`, token checks, deletion ticket) and `KisanRepository`:

- the farmer id behind the login is `GET /v1/farmers?limit=1` (the farmer role sees only its own
  record), remembered in `kv`;
- profile (`GET /v1/farmers/{id}` with farms, plots and consents), orders, order details, the
  deletion ticket and pending visit prompts are JSON snapshots in the encrypted database
  (`KisanCache`: `kv` keys `kisan.cache.*` with their fetch time for the "as of" label); the khata
  reuses `KhataRepository` (`khata_snapshots`);
- consent and visit confirmations go online first and fall back to outbox creates
  (`consent_record`, `visit_confirmation`) that the sync engine pushes when the phone is online
  (`kisanFlushProvider`: after a queued write, on start and on reconnect — the farmer app has no
  background sync);
- profile edits, orders, payments and the deletion request need the network and say so.

`watchTables` (in `kisan_cache.dart`) opens the table-update subscription **before** the first read,
so a refresh started as a screen opens is never missed (the `async*` pattern used elsewhere could
miss it; `KhataRepository.watch` now uses it too).

**Audio (NF-009).** `AudioPrompt` interface (`FakeAudioPrompt`, `SilentAudioPrompt`) and the
`AudioButton` widget (speaker + label, 48 dp, "Audio unavailable" and disabled when the device has
no voice). The farmer app plugs `TtsAudioPrompt` (`flutter_tts`, `<lang>-IN` voice, slow rate);
recorded clips by native speakers replace it behind the same interface (`promptId` = clip name).
`LanguagePicker` gained `audioUnavailable` (the tile says so in its own language); `ConsentCard`
gained `readAloud` / `agreeLabel`. OTP resend row no longer overflows in Telugu.

**Screens (`apps/mobile/apps/farmer/lib/screens/`)**: F01, F02, F03 (auto-continue), F04, F05, F10
(tab scaffold with Home / Crop doctor / Orders / Me), crop-doctor placeholder, shop + F30, F31, F32
(`payByUpi`: `POST /v1/payments {…, mode: upi_qr}`, launch the `upi://pay` intent via
`url_launcher`, wait sheet polling with `UpiPoller`), F33, F34, F40, F50, F51, F60 + QR scan
(`mobile_scanner`), F61, F62, F70 + consent settings + delete account. Design specs in
`design/screens/F04.md`, `F05.md`, `F10.md`, `F30.md`–`F34.md`, `F50.md`, `F51.md`, `F60.md`–`F62.md`,
`F70.md`; `F01.md` updated. 172 new ARB keys in five languages (simple words).

**Visit tokens.** The push payload (FA-007, not delivered yet: `KisanRepository.receivePush` is the
entry point) and the A32 QR carry the signed confirmation token; the phone reads the unverified
claims (`vid`, `cid`, `ch`, `exp`) to route, the server verifies. A sync-feed prompt has no token, so
"Yes" leads to the QR scan.

## Tests

Core `test/kisan/kisan_repository_test.dart` (9). Farmer app (95 tests):
`login_flow_test.dart` (first run F01 → F10: 5 screens, 8 actions, typing only phone + OTP, ≤ 2
decisions per screen; lockout; rate limit), `consent_test.dart`, `welcome_test.dart`,
`orders_test.dart` (UPI launch intent and paid, pay at store, credit 402, offline), `khata_test.dart`
(khata fetched the moment the payment is paid, receipt balance; failure; dues card),
`visit_test.dart` (push, sync feed, QR, invalid QR, No, offline outbox, call / WhatsApp),
`delete_account_test.dart`, `offline_cache_test.dart`, `audio_test.dart`, `no_typing_test.dart`
(walks every route: text input only on F02 / F03), goldens `test/goldens/kisan_golden_test.dart`
(F04 and F10 en + te, F05, F33, F50, F60, F61, F70; Light and Sunlight: 20 images).

## Results

`cd apps/mobile && APK_SIZE_CHECK=1 ./tool/check.sh`: green. Tests: core 600, agent 193, farmer 95,
workspace lint 13 (was core 591 / farmer 13 at `d6aedeb`); analyze zero issues; format clean;
no untranslated messages; string lint OK.

**FM-014 APK sizes (per ABI, release, obfuscated, R8):** arm64-v8a **11.87 MB**, armeabi-v7a
**11.29 MB**. New dependencies: `flutter_tts` (system TTS, tiny), `url_launcher`, `mobile_scanner`
with the **unbundled** ML Kit barcode model (`dev.steenbakker.mobile_scanner.useUnbundled=true` in
`android/gradle.properties`: no model or its native code in the APK; CameraX classes only). With the
native libraries stored uncompressed (as in M5) the same build measured 25.30 / 21.91 MB — over the
budget — so `packaging.jniLibs.useLegacyPackaging = true` now stores `libflutter.so`,
`libapp.so` and `libsqlcipher.so` compressed. Trade-off: Android extracts them at install (~17 MB
more on disk; fine on the 16 GB reference phones) and the file farmers side-load or download is
half the size. Play (AAB) compresses on the wire either way. `libapp.so` (Dart) is 7.3 MB of the
uncompressed total: the crop doctor screens must keep an eye on it.

## Human gates

- **FM-001 timing**: on a low-end reference phone (Itel / Realme, 2 GB, Android 8+), a new farmer
  goes from F01 to F10 in < 60 s: stopwatch from app open to home, 3 runs, 3G, OTP typed by hand.
- **Audio**: native speakers record the prompts (ids in the design specs) to replace TTS, and review
  every farmer-facing string in te / kn / hi / mr (NF-008). Check which phones lack a TTS voice for
  te / kn / mr (the button then says "Audio unavailable").
- **UPI**: an end-to-end payment with a real UPI app in Razorpay test mode (the intent opens the app
  chooser; the webhook moves the khata within 1 minute).
- **QR scan**: on a phone with Google Play services (unbundled ML Kit model downloads on first use).
- **Consent text**: legal review of the consent wording and version (TODO-LEGAL).

## API follow-ups (not in this branch)

- `GET /v1/farmers/{id}` for the farmer role: add `officer {id, name, phone}` (F05 "from Ramesh",
  F62 call / WhatsApp). The app reads it when present and falls back to "your field officer".
- FA-007 push delivery of `ConfirmationRequested` to the farmer app (payload `{type:
  visit_confirm, visit_id, token, officer_name, expires_at}`), and the same token on the pending
  `visit_confirmation` in the farmer's sync feed would let "Yes" work without a push.
- A "No, the officer did not visit" signal for the validation agents (the app only dismisses today).
- `POST/GET /v1/me/deletion-request` (in progress in the diagnosis-API worktree).
- Farmer-role sync feed: villages and crops for the quick setup (the app falls back to the pilot
  crop list and "your store will add it").
