# M7 officer app: beat plan, day timeline, notifications inbox with push, performance, travel allowance, my flags, meetings, demo plots and voice input

Requirements: FA-005, FA-007, FA-018, FA-023, FA-024, FA-026, FA-027, VV-008, VA-005 (the mobile halves).
Branch `feat/M7-agent-mobile`. Screens A11, A12, A13, A35, A36, A60, A61, A62 (A64 already existed).

PR title: `feat(M7): officer beat plan, day timeline, notifications inbox with push, performance, travel allowance, my flags, meetings, demo plots and voice input (FA-005, FA-007, FA-018, FA-023, FA-024, FA-026, FA-027, VV-008, VA-005)`

## What changed

| ID | Screen | Mobile |
|---|---|---|
| FA-018 | A11 | Today's beat from the `beat_plan` sync entity: reason chips (follow-up due, pest alert, credit due, demo stage), drag-to-reorder with an explicit handle, add / remove farmers and villages, map toggle on the mobile `MapPanel`, "start visit" straight to A30. Every edit writes the whole ordered list through the outbox. Home's "Next up" reads the plan. |
| VV-008 | A12 | The device's own day (sessions, points, client km) **plus** the server's `GET /v1/me/day` (processed track, stops, visit pins, km) — the screen says which km it is showing. Every gap carries an add-reason sheet (network / personal break / vehicle / other + a voice note) queued as a `track_gap` op offline, and the screen says plainly that the cluster head reads them. |
| FA-007 | A13 | Inbox over the `notification` sync entity: offline list, unread badge on the Home AppBar and the Me tab, mark read / mark all read through the outbox, deep links to visit, order, diagnosis, flag, credit approval, travel claim, beat and duty. The server sends only i18n keys; `NotificationCopy` renders them. Push through a `PushService` seam (below). |
| FA-027 | A35 | Meetings at the village meeting point (the fix travels as `checkin_point`; the server evaluates the geofence on sync), attendance by farmer OTP (online) or by scanning the farmer app's signed QR (offline), attendance list, finish. |
| FA-026 | A36 | Demo plots: create on a crop plot with a baseline, stage observations with photos and voice notes, demo vs farmer-practice comparison with the gain, yield entry, and the `created → active → harvested → reported` lifecycle enforced on the device as well as the server. |
| FA-024 | A60 | Targets vs actual for the month (verified visits, new farmers, sales, collections) from `/v1/me/performance` + `/v1/targets`, incentive earned, confirmation rate, rank, and a 14-day verified-visit sparkline. |
| FA-023 | A61 | Km by day with the daily cap shown, TA and payable totals, claims with status, and "add expense" (type, amount, receipt photo through NF-004, voice note) queued offline. |
| VA-005 | A62 | Flags about this officer only. Open: outcome hidden, explanation field. Resolved: outcome shown, no field. Explaining needs connectivity and says so rather than queueing blind. |
| FA-005 | all | `VoiceTextField`: a microphone on every free-text field, in the app's current language, with a live recording state and partial results. Never required. |

## Architecture

**`packages/core/lib/src/field/` is new and self-contained** — models, API client, repository, providers, the push seam, the speech seam, the voice field and the notification copy. The only edits to shared core files are additive:

* `sync/sync_models.dart`: the eight M7 entities join `SyncEntities.writable`;
* `sync/local_entities.dart`: their conflict rules join `conflictRules`;
* `catalog/rest_json_client.dart`: a `put` method (`PUT /v1/me/beat?date=`);
* `widgets/app_text_field.dart`: a `maxLines` parameter (default 1);
* `farmerapp_core.dart`: eight export lines;
* the five ARB files: 173 new keys (and `visitVoiceInputSoon`, the A31 placeholder, retired).

**No schema migration.** None of the eight entities has a typed Drift table: they land in the existing `sync_docs` JSON store through the default branch of `LocalEntities`, and the read-only officer views (A12, A60, A61, A62) are cached as JSON blobs in `kv` under `field.*`. That keeps `app_database.dart` and its 28k-line generated file untouched, which matters while three agents are working in parallel.

**Offline by default.** Every screen renders from the local store first and pulls in the background. Writes go through the outbox — with two deliberate exceptions the server has to arbitrate live: the attendance OTP (FA-016-style) and a flag explanation (VA-005: the server answers 409 on a resolved flag, so queueing one blind would lie to the officer).

**`saveBeat` queues before it writes.** `Outbox.enqueueUpdate` merges its payload into the local row, and the beat payload is the server's `BeatItemIn` shape (ids only). Writing the full plan afterwards puts the names and reasons back, so the screen keeps rendering while the op waits.

## Push without Firebase (FA-007)

`PushService` (core) is an interface with `NoopPushService` and `FakePushService`. The agent's `FirebasePushService.create()` calls `Firebase.initializeApp()` inside a try and returns `NoopPushService` when it throws — which is exactly what happens with no `android/app/google-services.json`. `firebase_core` still compiles, so **developer builds, CI and the reference device all build and run with push simply off**, and the inbox keeps filling over sync. Turning push on is three steps, documented in `apps/agent/lib/push.dart`: drop in `google-services.json`, apply the `com.google.gms.google-services` Gradle plugin, set `PUSH_PROVIDER=fcm` on the API.

`PushRegistrar` registers the token after login (`POST /v1/devices/me/push-token`), refreshes the inbox on a foreground data message, routes a tap through the same `deepLinkFor` the inbox uses, and clears the token on logout and on a SEC-025 wipe. A registration that cannot reach the server is not an error — the officer keeps their session, and the server disables a dead token itself once FCM rejects it.

A63 grew the "Log out" row this needed (`session.dart`: withdraw the token while the session still works, drop the `field.*` caches, clear the session) and a "My work" section linking A13, A11, A60, A61, A62, A35 and A36.

## Voice input (FA-005)

`SpeechService` (core) is the seam; `PluginSpeechService` (agent) is `speech_to_text` asked for `te_IN` / `kn_IN` / `hi_IN` / `mr_IN` / `en_IN` from the app's locale. `VoiceTextField` wraps `AppTextField` with a 48 dp microphone, shows partial results as they arrive, appends the final text to whatever is already typed (dictate, fix a word, dictate again), and on a phone with no speech service shows one line — `voiceUnavailable` — instead of failing silently. It replaced the disabled placeholder on A31 visit notes.

## Deep links

`deepLinkFor` (router.dart) maps the server's `route` to a screen: `/visits/{id}[/confirm]` and `/orders/{id}` pass through, `/diagnoses/{id}` → `/scouting/{id}`, `/credit-approvals/{id}` → the orders list, `/flags/{id}` → A62, `/travel/claims/{id}` → A61, `/beat/{date}` → A11, `/duty` → A12, **anything else → the inbox**, so a server kind this app version does not know still lands somewhere sensible.

## New dependencies (agent app only)

`firebase_core`, `firebase_messaging` and `speech_to_text` are in `apps/agent/pubspec.yaml`, not in `packages/core` — the farmer app's 25 MB APK budget is untouched (it still builds at 17.12 MB).

## Tests

| File | Covers |
|---|---|
| `apps/agent/test/field/beat_plan_test.dart` | reasons and target; reorder persists, queues one op and reaches the server; remove; add a farmer; map toggle; start visit; offline from cache |
| `apps/agent/test/field/my_day_test.dart` | server track / stops / visits / processed km; a gap reason queues offline, shows at once and syncs later; the client estimate without a server day |
| `apps/agent/test/field/inbox_push_test.dart` | copy from keys; mark read + deep link; mark all read offline; badges; every deep link; token registered after login and cleared on logout; a build without Firebase; foreground refresh; tap routing; A63 log out |
| `apps/agent/test/field/performance_test.dart` | numbers against targets; the trend counts only verified visits per IST day; a tenant with no targets; empty |
| `apps/agent/test/field/travel_test.dart` | km by day with the cap; a claim with a receipt queues offline and syncs with a real `blob://`; empty |
| `apps/agent/test/field/my_flags_test.dart` | only own flags; open hides the outcome and takes an explanation; resolved shows it and takes none; offline says so; empty |
| `apps/agent/test/field/meetings_test.dart` | QR parsing; create with the check-in point; OTP attendance; OTP offline; QR attendance offline then finish; a non-attendance QR |
| `apps/agent/test/field/demo_plots_test.dart` | the whole lifecycle offline with a stage photo and the yield comparison, asserting the exact op sequence; a reported plot takes no more observations |
| `apps/agent/test/field/voice_input_test.dart` | dictation fills a field; partial results; appending; no speech service; the mic on A61 and A62 |
| `packages/core/test/field/field_repository_test.dart` | the sync registry; IST keys; a pull never undoes a queued receipt; gap create-then-update; queued claims in the statement; explanation caching; `clearCaches`; demo lifecycle; one attendance per farmer; the trend |
| `apps/agent/test/goldens/field_golden_test.dart` | A11, A13, A60, A61, A62 in Light and Sunlight (A12 stays in `duty_golden_test.dart`) |

`cd apps/mobile && ./tool/check.sh`: green — l10n with no untranslated messages, `dart format` clean, `flutter analyze` with zero issues in all three packages, the string lint, and **core 679 + agent 259 + farmer 123 = 1,061 tests**, of which 111 are new.

`APK_SIZE_CHECK=1 ./tool/check.sh`: green. Farmer release APK 16.42 MB (armeabi-v7a) / **17.12 MB (arm64-v8a)** against the 25 MB budget. The agent release APK (no strict budget) is 36.60 MB / **42.45 MB**; `firebase_core`, `firebase_messaging` and `speech_to_text` are the new weight.

## Edits to shared files (additive only)

`packages/core/lib/farmerapp_core.dart` (8 exports), `sync/sync_models.dart` (the entity set), `sync/local_entities.dart` (the conflict rules), `catalog/rest_json_client.dart` (`put`), `widgets/app_text_field.dart` (`maxLines`), the five ARB files, `apps/agent/lib/router.dart` (routes + `deepLinkFor`), `apps/agent/lib/main.dart` (three provider overrides + the push registrar), `apps/agent/lib/screens/home/home_screen.dart` (inbox action, badge, "Next up"), `apps/agent/lib/screens/settings_screen.dart` ("My work" + log out), `apps/agent/lib/screens/visits/visit_screen.dart` (the real voice field), `apps/agent/test/farmers/agent_harness.dart` and `apps/agent/test/store/store_harness.dart` (the new fakes; the store harness now shares the agent's barcode scanner instead of overriding the provider twice).

## Human gates and follow-ups

* **Firebase** — a Firebase project, `android/app/google-services.json`, the `com.google.gms.google-services` Gradle plugin and `PUSH_PROVIDER=fcm` before push does anything. Until then the app runs with `NoopPushService` and the inbox fills over sync.
* **Microphone permission** — `speech_to_text` asks for `RECORD_AUDIO` at first use; the A06 permissions explainer does not mention it yet.
* **FA-023 acceptance on real roads** (unchanged from the API PR): drive the test routes and compare the processed km with Google Maps.
* **Follow-ups**: the farmer app's own free-text fields still lack the microphone (FA-005 is officer-only so far); A11 has no per-item note editor yet (the model and the wire payload carry `note`); the A61 claim date is always today (the contract allows up to 90 days back); `GET /v1/me/day` is pulled for today only.

## Assumptions

* The A60 verified-visit trend is counted from the device's own synced `visits` rows rather than from a new endpoint: the officer's visit feed is already on the phone, so the sparkline renders offline and costs nothing. The headline numbers still come from `/v1/me/performance`, which is equal to the console by construction.
* A credit-approval push lands on the orders list: the payload carries `order_id`, but the route the server sends (`/credit-approvals/{id}`) has no officer screen of its own.
* A meeting is created offline with the phone's current fix; the server re-evaluates the meeting-point geofence when the op syncs and may reject it, exactly as it does a `meeting` visit check-in.
