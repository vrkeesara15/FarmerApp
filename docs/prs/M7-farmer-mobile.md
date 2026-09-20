# M7 farmer app — crop calendar, weather, alerts and the push inbox (mobile half)

Branch `feat/M7-farmer-mobile` (from main `f9d2b8d`). Requirements: FM-007, FM-008,
FM-009 (SPEC 2.4) and FA-007 for the farmer app (SPEC 2.1), with NF-002, NF-009 and
NF-010. Screens: F40, F41, F42, F43, F44 (SPEC 13.3) plus the FA-007 inbox; F27 is
surfaced on F44 as well as F10.

API contracts consumed: docs/prs/M7-farmer-p1-api.md (calendar, weather, alerts,
`crop_plot_task` sync) and docs/prs/M7-field-p1-api.md (push token, notification
inbox, deep-link routes).

## What was built

### packages/core/lib/src/advisory/ (new, farmer-facing; no officer-app files touched)

| File | What |
|---|---|
| `advisory_models.dart` | `CropCalendar` / `CropPlotCalendar` / `CalendarTask` (+ `byWeek`, `nextTask`), `CalendarChange` and `diffPlotCalendar`, `FarmWeather` / `DailyForecast` / `SprayAdvice` / `SprayWindow` / `SprayThresholds`, `OutbreakAlert` with a derived `AlertSeverity`, `AppNotification` and `NotificationKinds` |
| `advisory_api.dart` | `AdvisoryApi` (calendar, task PATCH, weather, alerts, inbox, read, read-all, push-token register / remove), `HttpAdvisoryApi`, and a `FakeAdvisoryApi` that applies the server's rules (task versions, `version_conflict`, read stamps, and `moveSowingDate` which regenerates pending tasks the way the server does) |
| `advisory_repository.dart` | Online-first with the M6 `KisanCache` (`kisan.cache.calendar`, `…calendar_changes`, `…weather.<farmId>`, `…alerts`, `…alerts_dismissed`, `…inbox`), offline writes through the outbox, dismissals kept per phone, push rows filed straight into the inbox |
| `push_service.dart` | The `PushService` seam (`PushMessage`, `PushPermission`) with `NoPushService` and a scriptable `FakePushService`. **No Firebase in the core.** |
| `push_controller.dart` | Registers the token after login, re-registers on FCM rotation, files arriving messages, hands the deep link to the app, withdraws the token on logout / wipe |
| `advisory_providers.dart` | `advisoryApiProvider`, `advisoryRepositoryProvider`, `cropCalendarProvider`, `calendarChangeProvider`, `farmWeatherProvider`, `outbreakAlertsProvider`, `inboxProvider`, `inboxUnreadProvider`, `pushServiceProvider` overrides and `pushControllerProvider` |

### apps/farmer

| Screen | Route | Notes |
|---|---|---|
| F40 my crops | `/crops` | Farms with crops, stage and **next task** from the calendar; "Add a crop" FAB; chips to F43 and F44 |
| F41 add crop | `/crops/add` | Big crop tiles, an inline `CalendarDatePicker` for the sowing date, water and soil tiles; saves the crop plot and pulls the calendar again |
| F42 crop calendar | `/crops/<cropPlotId>/calendar` | Timeline by week, pictogram + title + one-line instruction in the farmer's language, audio per task, mark done, reminder on/off per task, "what changed" card after a sowing-date move; reads from the cache offline |
| F43 weather | `/weather` | 7 days with icon, temperature and rain chance; spray blocks for the next 3 days as good / avoid with the reason; "advice only" note with audio; "as of" and offline |
| F44 alerts | `/alerts` | District alerts with derived severity, "you grow this crop", the symptom checklist, "what to do" (crop doctor, store), dismiss; F27 updated-result cards on top |
| Inbox | `/inbox` | Every notification, unread marked, mark-all-read, tap opens the deep link; unread badge on F10's app bar |

Also: F10 now shows the real weather strip and the top district alert instead of the
M6 placeholders, the per-crop "next task", and the inbox action with its badge;
`FarmSummaryCard` gained the next-task line and a calendar link;
`apps/farmer/lib/push.dart` is the FCM adapter; `security.dart` gained
`pushTokenWipeStep` so a remote wipe withdraws the token before the session is
cleared.

### Shared files touched (additive only)

* `packages/core/lib/farmerapp_core.dart` — six `export` lines for `src/advisory/`.
* `packages/core/lib/src/sync/sync_models.dart` — `SyncEntities.cropPlotTask` and
  `SyncEntities.notification`, both added to `writable`. Both land in the generic
  `sync_docs` table, so **no Drift schema change and no migration**.
* `packages/core/lib/src/sync/local_entities.dart` — their conflict rules
  (`merge_fields`, `last_writer_wins`).
* `packages/core/lib/src/kisan/kisan_api.dart` / `kisan_repository.dart` —
  `createCropPlot` (`POST /v1/farms/{id}/crop-plots`) and `KisanRepository.addCrop`
  for F41. Farmer-only files.
* `packages/core/lib/l10n/app_{en,te,hi,kn,mr}.arb` — 116 new keys each, appended.
* `apps/farmer/pubspec.yaml` — `firebase_core`, `firebase_messaging`.

## Duplication to reconcile (for the parent)

This branch was built in an isolated worktree off `f9d2b8d`, so it could not see the
officer-app half. If that half landed a push seam under
`packages/core/lib/src/field/`, the two must be merged into **one** `PushService`:
the seam here (`src/advisory/push_service.dart` + `push_controller.dart`) is
transport-agnostic and app-agnostic — only `PushController.platform`, `deviceId` and
`appVersion` differ per app — so the officer app should be able to move onto it (or
this one onto theirs) with an import change and the `pushServiceProvider` override.
The `notification` sync entity and its conflict rule are likewise likely to appear in
both branches as the same two lines.

## Decisions worth reviewing

* **The app re-checks the spray thresholds.** The server hides rainy and windy
  windows already, but `SprayWindow.blockingReasons` applies the same thresholds on
  the device, so a window that arrives labelled `good` while breaching rain or wind
  is still shown as "Do not spray" with the reason. The acceptance criterion is about
  what the farmer sees, and this makes it true whatever the server sends.
* **Alert severity is derived on the device** (`>= 3x` baseline or 10+ farmers =
  high, `>= 2x` or 5+ = medium, else low) because `OutbreakAlertOut` carries counts
  only. If the product wants a different cut, it belongs on the server — the rule is
  in one place (`OutbreakAlert.severity`) and documented in design/screens/F44.md.
* **"What changed" is computed on the device** by diffing the cached calendar against
  the freshly pulled one per plot. Nothing on the server tells the app that a
  regeneration happened.
* **Alert dismissal is per phone** (`kisan.cache.alerts_dismissed`), not sent to the
  server: there is no endpoint for it and an alert is district-wide, not personal.
* **F41 does not ask for the variety.** It is optional in `CropPlotCreate`, but there
  is no tap-only variety list and NF-010 forbids a text field. Follow-up.
* **The F44 symptom checklist is per problem *type***, not per problem: the alert
  payload has no symptoms. Follow-up: send the corpus's `visible_symptoms`.
* **Push is optional.** `FirebasePushService.create()` falls back to `NoPushService`
  when `Firebase.initializeApp()` fails (no `google-services.json`, no Play
  services), so the inbox, the badge and the deep links work on every build. The
  farmer app has no sign-out screen, so `PushController.signedOut()` is wired to the
  remote wipe (SEC-025) and is covered directly by a unit test; a sign-out entry
  point should call it too when one is added.
* `KisanApp` now arms the push listener on start, so every `ProviderScope` that
  builds it needs `appDatabaseProvider` — `app_test.dart` and `language_switch_test.dart`
  gained an in-memory database.

## Tests

`apps/farmer/test/` — 172 tests pass (was 116):

| File | Covers |
|---|---|
| `calendar_test.dart` (8) | Regeneration when the sowing date moves with **done tasks untouched** and their ids stable; the "what changed" note and its dismissal; the reminder toggle online (version sent, survives a refresh) and offline (applied locally, `crop_plot_task` update queued in the outbox); mark done; the F42 screen by week with audio and toggles; offline from the cache; F40's next task and the link to F42 |
| `weather_test.dart` (6) | The spray rule on the fixture forecast — one good window, a rainy one and a windy one hidden, and a window the fixture labels `good` with 21 km/h of wind still excluded with `wind_high`; the three-day blocks; the F43 screen with seven days, one good and three avoid blocks, the reasons and the "advice only" note; the cache with "as of" surviving offline; the empty state; the F10 strip |
| `alerts_test.dart` (6) | The derived severity table; the list most-severe-first with the per-type checklist and both actions; dismiss that survives a refresh; F27 on the list; the empty state; the F10 banner |
| `push_inbox_test.dart` (9) | Token registered after login (platform, device id, remembered) and cleared on logout; re-registered on rotation; nothing registered when permission is refused; withdrawn by the wipe step; the deep-link table for all seven kinds; the inbox with the unread badge and mark-all-read; a reminder row opening F42; a push arriving through the transport opening F44 by itself and landing in the inbox; offline reading from the cache with a queued `notification` update |
| `add_crop_test.dart` (3) | F41 saves crop + sowing date + season and pulls the calendar again; no `EditableText` anywhere on the screen; the save button waits for a crop and a date; F40 opens F41 |
| `no_typing_test.dart` | Extended to walk the six new routes (`/crops/add`, `/crops/<id>/calendar`, `/weather`, `/alerts`, `/inbox`): still no text input outside F02 and F03 |
| `goldens/advisory_golden_test.dart` (12) | F40, F42 (English **and Telugu**), F43, F44 and the inbox in Light and Sunlight |

M6 goldens `f05_welcome` and `f10_home_{en,te}` were regenerated: the welcome card now
carries the next-task line and F10 has the weather strip, the alert banner and the
inbox badge.

`packages/core` 667 and `apps/agent` 201 tests still pass.

## Checks

`cd apps/mobile && ./tool/check.sh` — green (format, analyze x3, i18n lint, no
untranslated messages in any of the five ARB files, all tests).

`APK_SIZE_CHECK=1 ./tool/check.sh` — green (FM-014, budget 25 MB per ABI):

| ABI | Before this branch | After |
|---|---|---|
| armeabi-v7a | 16.42 MB | **16.76 MB** |
| arm64-v8a | 17.12 MB | **17.42 MB** |

`firebase_core` + `firebase_messaging` and the five new screens together cost about
0.3 MB per ABI (R8 and the Dart tree shaker drop most of the Firebase surface, since
only `FirebaseMessaging` is referenced). 7.6 MB of headroom is left, so nothing had
to be excluded.

## Human gates and follow-ups

* **TODO-HUMAN (FA-007)**: a Firebase project and `android/app/google-services.json`
  before push actually delivers; without it the app runs on `NoPushService` and only
  the inbox fills (the API half has the same gate).
* **TODO-HUMAN (NF-008)**: a native speaker must review the 116 new strings in
  Telugu, Hindi, Kannada and Marathi. They were written to be short and plain, but
  they are not reviewed.
* **TODO-HUMAN (NF-009)**: the audio is device TTS behind the `AudioPrompt` seam.
  Recorded clips by native speakers replace it per `promptId` (`f41_help`,
  `f42_help`, `f42_changed`, `task_<taskKey>`, `f43_advice_only`, `f44_alert`).
* Follow-ups: the variety tile list for F41; per-problem symptoms on `/v1/alerts`;
  a server-side severity if the product wants one; SMS reminders for farmers without
  an app login (API half's follow-up); a sign-out entry point that calls
  `PushController.signedOut()`.
