# M8 — tenant branding across both apps and the console (FA-008), server-processed km on the officer day timeline (VV-006)

Branch `feat/M8-branding`. No API change and no migration: the branding row
(`tenant.branding`, `GET /v1/settings/public`, `PATCH /v1/settings`) and the VV-006 processing
columns (`duty_session.km` / `km_raw` / `km_source` / `processed_at`, `track_gap`) were both
delivered by the API half in M4 and M7. This is the client half of both, plus the contrast
machinery that makes a tenant colour safe to apply.

## FA-008 — what a tenant now gets

| Surface | What the brand changes |
|---|---|
| Officer app | Splash (logo + app name), A10 home header (logo + app name), the window title, every `color.primary.*` in both themes, the A63 "call support" row |
| Farmer app | F10 home header (logo + app name), the window title, every `color.primary.*`, the F70 "call support" row |
| Console | Side-nav header and TopBar (logo + tenant name), `--color-primary*` in the Light and Dark themes, a "Call support" item in the profile menu |
| C102 preview | Repainted from the same derivation, so the preview is the derived colour, not the typed swatch |

All four values come from `GET /v1/settings/public` — the endpoint every signed-in role may
read — so the console, the officer app and the farmer app cannot disagree about a tenant. The
apps cache them in Drift and read the branding out of that cache *before the first frame*
(`brandingOverrides`, the same shape FA-004 uses for the saved language); the console caches in
`localStorage` per tenant id. A cold start with no network opens already branded; a fresh
install shows the shipped tokens until the first pull.

How a tenant sets its brand, and the full field table, is **docs/branding.md**.

### The colour derivation (NF-009)

A tenant supplies one colour; hover, container and on-primary are derived with a WCAG check at
each step, so a brand cannot ship an unreadable screen:

1. **primary** darkened (lightened in Dark) in 1 % lightness steps until it reaches its theme's
   minimum against *both* surface and background — 4.5:1 in Light and Dark, **7:1 in
   Sunlight**, which must stay the strongest of the three (`contrast_test.dart` pins that
   relation for the shipped tokens; `brand_test.dart` now pins it for derived ones).
2. **on-primary** white or `#0B1A10`, whichever wins; the primary is pushed further if neither
   reaches 4.5:1.
3. **hover** 20 % darker (lighter in Dark), kept at 4.5:1 under on-primary.
4. **container** the primary mixed into the surface until the primary reads on it at 4.5:1;
   Sunlight keeps plain white (SPEC 13.1: no tinted containers there).

The NF-009 contrast helper moved out of `test/theme/contrast_test.dart` into
`packages/core/lib/src/theme/contrast.dart`, because the check now runs in the app and not only
in CI; the test imports it instead of carrying its own copy. `apps/console/lib/brand.ts` is a
line-for-line port, and both test suites assert the same hex values for the same input
(`#3B4BD8` → `#3B4BD8` / `#2533B7` / `#E7E9FA` / `#FFFFFF` in Light, `#6B7BE4` … in Dark). An
orange that fails on white (`#E0651B`, 3.0:1) becomes `#B85514` on every surface including the
console preview.

### Deliberately not branded

The **Android application label and launcher icon stay per app**. They are compiled into the
APK a Play listing points at; one build serves every tenant and a store listing cannot vary per
tenant. The tenant's name and logo appear the moment the app opens. Documented in
docs/branding.md; changing it would mean a per-tenant build and a per-tenant Play listing.

The console's name for a tenant is `app_name_agent`: the brand row carries one name per app and
no separate console name.

### Acceptance ("a second test tenant renders with its brand without a code change")

Two fixture tenants with the same values on both sides — indigo *Harvest* and terracotta
*Bhoomi* (`TestBrands` in Dart, the table in `lib/brand-context.test.tsx` in TypeScript). Each
drives the same widget tree twice with nothing changing but the branding object:

* `apps/agent/test/branding_test.dart` (9 tests), `apps/farmer/test/branding_test.dart` (6)
* `apps/agent/test/goldens/branding_golden_test.dart` and the farmer equivalent — 12 new
  `fa008_*` goldens (splash / home / Me, Light and Sunlight, both tenants)
* `apps/console/lib/brand-context.test.tsx` — the brand is switched through `PATCH /v1/settings`
  on the settings API mock (with a real step-up token) and read back from
  `GET /v1/settings/public`, then rendered
* `packages/core/test/theme/brand_test.dart` (33) and `apps/console/lib/brand.test.ts` (21) hold
  the derivation to AA for six brand colours, two of them chosen to be hostile

## VV-006 — the mobile half

The API half (M7) stores processed km, stops and gaps per duty session. The officer app now
shows the server's figures **only once they are the processed ones**, and says which it is
showing.

`DayTimeline` gained `duty_sessions[]` (`DaySession`: id, start, end, km, end reason) and a
`processed` getter: the day came from `/v1/me/day` **and** every session has ended and carries
a `km`. `duty_session.km` is written by `duty/processing.py` and nothing else, so a null km on
an ended session means "not processed yet".

* **A12 my day** used to treat `km > 0` as "processed". That was wrong in both directions: a
  processed day with no movement read as an estimate, and — worse — the replay's haversine
  fallback for an *unprocessed* session read as "Processed by the server" although the
  officer's travel allowance is later computed from a different number. It now keys off
  `DayTimeline.processed`, and the caption (`my-day-km-source`) says
  `myDayKmProcessed` / `myDayKmEstimated` for the km, stops and gaps together.
* **A61 travel allowance** gained the same caption (`travel-km-source`) over the month, plus a
  per-day note on any day whose duty session is still open (`TravelDayOut.open_session`), ahead
  of the cap warning. The officer is paid on the processed figure, so a running estimate is
  never shown as if it were settled.

Tests cover both states on both screens (`my_day_test.dart`, `travel_test.dart`);
`seedFieldCaches(processed: false)` leaves the day's session open.

## Files

**Mobile core**: `theme/contrast.dart` (new), `theme/brand.dart` (new: `AppBrand`,
`BrandSurface`, `brandedPalette`), `theme/app_theme.dart` (`AppTheme.build(..., brand:)`),
`state/branding.dart` (new: `brandingProvider`, `appBrandProvider`, `supportPhoneProvider`,
`brandLogoLoaderProvider`, `brandingOverrides`), `state/test_brands.dart` (new fixture),
`widgets/brand_logo.dart` (new), `field/field_models.dart` (`DaySession`,
`DayTimeline.processed`, `TravelDay.processed`, `TravelStatement.processed`),
`store/store_providers.dart` (`telUri` moved here from the farmer app).

**Officer app**: `app.dart`, `main.dart`, `screens/splash_screen.dart`,
`screens/home/home_screen.dart`, `screens/home/my_day_screen.dart`,
`screens/field/travel_screen.dart`, `screens/settings_screen.dart`.

**Farmer app**: `app.dart`, `main.dart`, `widgets/kisan_widgets.dart`,
`screens/home_screen.dart`, `screens/settings_screen.dart`, `screens/officer_screen.dart`,
`screens/crop_doctor/crop_doctor_common.dart`.

**Console**: `lib/brand.ts` (new), `lib/brand-context.tsx` (new), `lib/admin.ts`
(`PublicSettings`, `adminApi.publicSettings`), `components/ds/TopBar.tsx` (logo, support),
`components/admin/BrandingPreview.tsx`, `app/(console)/ConsoleShell.tsx`, `messages/*.json`,
`app/tokens.css` (regenerated) and `tailwind.config.ts` (see below).

**Strings**: five new ARB keys in all five languages (`settingsCallSupport`,
`settingsCallSupportNone`, `settingsCallSupportFailed`, `travelKmProcessed`,
`travelKmEstimated`) and two console keys (`topbar.callSupport`, `topbar.brandLogo`).

**Design**: A10, A12, A61, F10, F70, C102 updated; docs/branding.md added.

## Two things found on the way

* **`apps/console/app/tokens.css` was stale.** It is generated from `design/tokens.json` by
  `npm run prebuild`, and the NF-009 token corrections of M7 had never been regenerated into
  the committed copy. Building regenerates it, so this branch carries the regenerated file —
  and with it the rename `--color-border` → `--color-border-default` / `--color-border-strong`
  that NF-009 introduced. `tailwind.config.ts` still mapped `border` to the old, now
  non-existent variable, so every `border-border` in a *built* console has resolved to nothing
  since M7 (local `next dev` was masked by the stale file). `border` now maps to
  `--color-border-default` and a `border-strong` colour was added for the 3:1 control outline
  NF-009 asks for.
* **`**/android/.kotlin/`** (a Kotlin build-session directory the release build drops) was not
  ignored; added to `.gitignore`.

## Checks

`cd apps/mobile && ./tool/check.sh` green — core 758 (+34), agent 278 (+15), farmer 222 (+6),
root lint 34, l10n complete in all five languages.
`APK_SIZE_CHECK=1 ./tool/check.sh` green: arm64-v8a **17.67 MB**, armeabi-v7a **17.02 MB**
against the 25 MB budget (NF-005), release manifest check OK.
`cd apps/console && npm run check` — 63 files / 428 vitest (+26), lint and typecheck clean,
build clean; `npm run test:e2e` — 49 Playwright green, including the C102 preview test extended
with a derived-colour assertion.

The API suite was not run: another agent held the database during this change. Nothing in
`apps/api` was touched.

## Left for a later loop

* A per-tenant Play listing (per-tenant application label and launcher icon) — a distribution
  decision, deliberately out of scope; see docs/branding.md.
* The farmer app has no splash screen, so the tenant's mark first appears on its home header.
  If F-screens gain a splash, it should use `BrandLogo` like A01 does.
* Console light/dark are branded; the console has no Sunlight theme, so the 7:1 derivation is
  exercised only by the mobile themes (and by both test suites).
