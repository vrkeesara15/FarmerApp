# M7 screens merge: one push seam for both apps, farmer F40–F44 and the console growth screens on main

Merges `feat/M7-farmer-mobile` (5c63281) and `feat/M7-console-growth` (e61ed83)
onto main on top of the officer-app half (8b03186), and unifies what the three
parallel worktrees built twice.

PR title: `feat(M7): unify push notifications across both apps and land farmer and console M7 screens`

## What landed

| Branch | Content |
|---|---|
| `feat/M7-farmer-mobile` | F40 my crops, F41 add crop, F42 crop calendar, F43 weather, F44 alerts and the FA-007 farmer inbox; `packages/core/lib/src/advisory/`; `crop_plot_task` as a sync entity; the FCM adapter in `apps/farmer/lib/push.dart` (FM-007, FM-008, FM-009, FA-007) |
| `feat/M7-console-growth` | C62, C80–C82, C90, C91, C100, the crop-health map, model releases, C32 segments and the flags data-quality tab (WC-008, WC-009, WC-013, AN-004, AN-006..AN-009, DX-012, FA-023) |

The console branch conflicted only in `docs/progress.md` (resolved as the union
of the rows). Everything below is about the mobile halves.

## What was unified

### One push seam: `packages/core/lib/src/push/`

Both halves had written their own. They are now one module, used by both apps,
and neither `src/field/push_service.dart` nor `src/advisory/push_service.dart` /
`push_controller.dart` exists any more.

* **`push_service.dart`** — `PushMessage` (the union of both shapes: `kind`,
  `notificationId`, `titleKey`, `bodyKey`, `data`, and a non-null `route` that
  falls back to `PushMessage.inboxRoute` so a kind this app version does not
  know still lands somewhere), `PushPermission`, the `PushService` interface
  (`isAvailable`, `requestPermission`, `token`, `tokenRefreshes`, `messages`,
  `opened`, `initialMessage`, `deleteToken`), `NoPushService` (the officer's
  `NoopPushService` was renamed to it) and one scriptable `FakePushService`
  with both halves' test API (`deliver` / `deliverData`, `open` / `openData`,
  `rotate`, `permissionAsks`, `deletes`, `initial`).
* **`push_controller.dart`** — one `PushController` (the officer's
  `PushRegistrar` is gone): `signedIn()` asks for permission and registers the
  token, `listen()` subscribes to messages, taps and FCM rotations and follows
  the push the app was cold-started from (once — `openingMessage()` is
  idempotent), `signedOut()` withdraws the token on logout and on the SEC-025
  wipe. It depends on neither app's data layer: the endpoint is behind a
  `PushTokenRegistry` seam returning `PushRegistration { done, offline,
  refused }`.
* **`push_providers.dart`** — the one `pushServiceProvider`,
  `pushControllerProvider`, `pushTokenRegistryProvider`,
  `pushMessageHandlerProvider`, `pushRouteHandlerProvider`,
  `pushPlatformProvider`, `pushDeviceIdProvider`, `pushAppVersionProvider`.
  (Both branches had defined a `pushServiceProvider`.)

Per-app wiring is two exported override lists, spread by each app's `main.dart`
and its test harness:

* `fieldPushOverrides` (`src/field/field_providers.dart`) — token registration
  through `FieldPushRegistry` over `FieldApi` (`src/field/field_push.dart`), a
  foreground message refreshes the A13 inbox, the app version comes from
  `appVersionProvider`. `apps/agent/lib/main.dart` adds
  `pushRouteHandlerProvider` → `router.go(deepLinkFor(route))`.
* `advisoryPushOverrides` (`src/advisory/advisory_providers.dart`) —
  `AdvisoryRepository` *is* the `PushTokenRegistry` now (its `registerPushToken`
  / `clearPushToken` return `PushRegistration` instead of `KisanWrite`), and an
  arriving message is filed in the inbox and handed to the app on
  `pushOpenControllerProvider`, which navigates with `farmerDeepLink`.

Each app keeps only its thin FCM adapter — `apps/agent/lib/push.dart` and
`apps/farmer/lib/push.dart`, both `implements PushService`, both falling back to
`NoPushService` when `Firebase.initializeApp()` fails — and its own deep-link
map (`deepLinkFor` for the officer, `farmerDeepLink` for the farmer). The core
still has no Firebase dependency.

### One registration per sync entity

Both halves added `notification`. The entity names now live once on
`SyncEntities` (`notification`, `cropPlotTask`, `trackGap`, `beatPlan`,
`travelClaim`, `demoPlot`, `demoObservation`, `farmerMeeting`,
`meetingAttendance`); `FieldEntities` aliases them with the officer-side
documentation, and `LocalEntities.conflictRules` states each rule once.
`field_repository_test.dart` still asserts that every `FieldEntities` entity is
registered with the rule the server uses.

### ARB files: the union, no duplicates

The merged catalogues are the union of both halves — **1,516 message keys in
each of the five languages** (en 1,995 entries with its `@` metadata, the other
four 1,541) — and `flutter gen-l10n` reports nothing untranslated.

Eleven keys had been added by both halves with **different copy** — the officer
voice ("Notifications", "Order update") against the farmer voice ("Messages",
"Your order moved on"). Rather than flatten one app's wording (which would also
have broken its goldens), the officer keys stayed and the farmer's moved to
`farmerInboxTitle`, `farmerInboxEmpty`, `farmerInboxEmptyHelp`,
`farmerInboxUnread`, `farmerInboxMarkAllRead`, `farmerNotifOrderStatusTitle` /
`…Body`, `farmerNotifVisitConfirmTitle` / `…Body`, `farmerNotifGenericTitle` /
`…Body`. Both inboxes read exactly as their designers wrote them.

### Exports deduplicated

`farmerapp_core.dart` exports `src/push/{push_controller,push_providers,push_service}.dart`
and `src/field/field_push.dart`; the two old push exports are gone. Two
providers with the same name and different types also collided: the officer's
inbox provider is now `fieldInboxProvider` and the farmer's
`advisoryInboxProvider`.

## Checks

| Surface | Result |
|---|---|
| `cd apps/mobile && ./tool/check.sh` | green — l10n (nothing untranslated), `dart format`, `flutter analyze` with zero issues in all three packages, the string lint, and **core 679 + agent 259 + farmer 172 = 1,110 tests** |
| `APK_SIZE_CHECK=1 ./tool/check.sh` | green — farmer release APK **16.77 MB (armeabi-v7a) / 17.42 MB (arm64-v8a)** against the 25 MB budget (FM-014), 7.6 MB of headroom left; the agent release APK (no strict budget) 36.60 MB / 42.45 MB |
| `cd apps/console && npm run check` | green — lint, string lint, typecheck, **367 vitest in 58 files**, build |
| `cd apps/console && npm run test:e2e` | green — **36 Playwright tests** |

No test was deleted to make the merge simpler; the officer and farmer push tests
were rewritten onto the unified API and still assert the same behaviour
(registration after login, rotation, a refused permission, withdrawal on logout
and by the wipe step, every deep link, a build without Firebase, the offline
server, foreground refresh and tap routing).

## What remains

Recorded here, not built:

* **AN-005 store performance** — `GET /v1/analytics/stores` and `/stores/{id}`
  returned no new fields in M7, so C40 / C41 are unchanged. The API half has to
  expose what the marts already hold (category × brand margin from
  `mart_store_category_monthly`, stock turns and stockouts from
  `mart_store_snapshot`, the FIFO buckets of `mart_credit_accounts`) before the
  console can show them.
* **AN-004 farmer 360** — only the C32 segments entry point landed. The 360
  dashboard on `v_farmer_360` / `v_farmer_segments` (LTV, churn risk, segment
  membership) is still to build on that new data, and the segment / churn
  thresholds are working definitions the owner must confirm.
* **AN-009 summary endpoint** — the data-quality tab rolls `/v1/flags` up in the
  browser; a `mart_flags_weekly`-backed summary endpoint should replace it.
* **AN-008** — the dbt `mart_campaign_roi` body is still a placeholder; C82
  reads the API.
* **DX-012** — the console release view is in; the training image and the Vertex
  AI pipeline + monthly schedule are still a human gate.
* Mobile follow-ups carried over: A11 has no per-item note editor; the A61 claim
  date is always today; `GET /v1/me/day` is pulled for today only; the F41
  variety tile list; per-problem symptoms on `/v1/alerts`; a farmer sign-out
  entry point that calls `PushController.signedOut()` (today only the SEC-025
  wipe does).
* Human gates unchanged: a Firebase project and `android/app/google-services.json`
  (+ `PUSH_PROVIDER=fcm`) before push actually delivers — until then both apps
  run on `NoPushService` and both inboxes fill over sync; native-speaker review
  of the new Telugu, Hindi, Kannada and Marathi strings (NF-008); recorded audio
  clips (NF-009); `RECORD_AUDIO` in the A06 permissions explainer; the FA-023
  real-roads km comparison; DLT / WhatsApp template registration; the email
  provider and sending domain; the owner confirming incentive rules and targets.
