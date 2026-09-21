# Device support matrix and reference-device test plan (NF-001)

> NF-001: *Android 8+ (API 26), 2 GB RAM, 16 GB storage; tested on 3 reference devices (one
> Samsung A-series, one Redmi, one low-end Realme/Itel).*

Two halves: what the apps claim to support and what CI enforces of that claim, then the
manual pass that a person has to do on real hardware before a release, because RAM, storage,
thermal throttling and a 2G cell are not things a test runner can pretend.

## Support matrix

| | Supported | Enforced by |
|---|---|---|
| Android | **8.0 Oreo, API 26** and above | `minSdk = 26` in both `android/app/build.gradle.kts`, asserted by `apps/mobile/test/device_support_test.dart` |
| Target API | Flutter's current target (Play's requirement) | `targetSdk = flutter.targetSdkVersion` |
| RAM | **2 GB** | Manual pass below (device B and C) |
| Free storage | **16 GB device**, app + data under 300 MB in normal use | Manual pass below; APK budget in CI |
| ABIs shipped | `armeabi-v7a`, `arm64-v8a` | `tool/apk_size_check.sh`; x86_64 is emulator-only and not shipped |
| APK size | **< 25 MB per ABI** (FM-014) — Play delivers one ABI per device, so the fat APK is not the number that matters | `APK_SIZE_CHECK=1 ./tool/check.sh`, run in `ci-mobile.yml` |
| Screen | 360 × 800 dp baseline; usable 320 dp wide | Golden tests at phone size; store mode (ST-*) adds a tablet layout |
| Cold start | **< 3 s** on the slowest reference device (NF-005) | `AppStartTrace` on device (below) |
| Play services | Optional. Without them push, Crashlytics, Performance and Remote Config all fall back to no-ops and every farmer-facing flow still works. | `FirebasePushService.create`, `FarmerObservability.create`, `MitraObservability.create` |
| Offline | 72 h for the officer app (NF-002) | Manual pass below |

### What CI can and cannot prove

CI proves the floor (`minSdk`), the ABI split and the size budget. It runs on a fast Linux
runner with no Android device, so it cannot prove cold start, memory pressure, GPS behaviour,
camera quality or what happens when the phone gets hot. Everything in the manual pass exists
because it failed for somebody on a real phone once.

## The three reference devices

Chosen to bracket the fleet rather than to be representative of it: the cheapest phone a
farmer plausibly owns, the mid-range phone most officers are issued, and one in between.

| | Device | Android | RAM | Why this one |
|---|---|---|---|---|
| **A** | Samsung Galaxy A-series (A14 / A15 class) | 13–14 | 4 GB | The officer fleet. If a bug only shows here it affects the people who use the app all day. |
| **B** | Redmi (Redmi 10 / 12 class) | 11–13 | 4 GB | The most common handset in the pilot districts. MIUI's aggressive battery management is the one that kills background sync and the duty foreground service. |
| **C** | Realme C-series or Itel (entry level) | **8.1–10** | **2 GB** | The NF-001 floor, and the device every performance number is judged on. Slow eMMC storage, weak GPU, and the OS will kill a backgrounded app within minutes. |

Device C is the acceptance device. A number measured on A or B says nothing about NF-001 or
NF-005.

## Cold start, measured on the device

`AppStartTrace` (`packages/core/lib/src/obs/performance_monitor.dart`) starts a clock on the
first line of `main()` and reports two numbers:

- **time to first frame** — what the farmer experiences as "the app opened". Measured from
  `main()` to the end of the frame the engine actually rasterised, via
  `SchedulerBinding.addTimingsCallback`, not from a post-frame callback (which fires before
  the raster work and flatters the number on a slow GPU).
- **time to interactive** — the point where the database, settings and session are up and the
  farmer can act.

Both are reported to Firebase Performance as the `app_start` trace *and* printed, so a release
build on device C needs no cloud at all:

```bash
flutter build apk --release --target-platform android-arm   # v7a for device C
adb install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
adb shell am force-stop in.farmerapp.kisan
adb logcat -c && adb shell monkey -p in.farmerapp.kisan 1 >/dev/null
adb logcat -d | grep app_start
# app_start: first frame 1840 ms, interactive 1520 ms (NF-005 budget 3000 ms)
```

Take the **median of five cold starts** after a reboot, with the app force-stopped between
runs. The first start after an install is always slower (dex optimisation) and is not the
number.

`main()` is later than process start (zygote fork, engine, Dart isolate), so this
under-reports what a stopwatch would show by roughly 200–400 ms on device C. The stopwatch
number is the acceptance one; this is the trend that CI-less regressions show up in.

## Manual test plan

Run before every release that goes past the internal track. One pass per device; **device C is
mandatory**, A and B are mandatory for a release that touches sync, location or the camera.

Record the result in the release ticket as a table of ✅ / ❌ with the device and build number.

### 1. Install and first run

| # | Step | Pass |
|---|---|---|
| 1.1 | Install the per-ABI release APK. Note the installed size in Settings → Apps. | Under 120 MB installed |
| 1.2 | First launch: language picker appears, all five languages legible, "Listen" speaks each one | NF-008, NF-009 |
| 1.3 | Cold start measured as above, median of five | **< 3 s on device C** (NF-005) |
| 1.4 | Phone + OTP login end to end | < 60 s (FM-001) |

### 2. Farmer app, the flows that matter

| # | Step | Pass |
|---|---|---|
| 2.1 | Walk every screen from the home screen without typing anything | Only F02 and F03 ask for input, both on the number pad (NF-010) |
| 2.2 | Tap every "Listen" button in each of the five languages | Speaks, or says "audio unavailable" — never silent (NF-009) |
| 2.3 | Crop doctor: three photos in bright outdoor light | Blurry/dark/not-a-plant refused with the tip read aloud (FM-004) |
| 2.4 | Crop doctor in Sunlight theme, outdoors at midday | Every control readable at arm's length (NF-009) |
| 2.5 | Place an order, pay by UPI QR | Receipt renders; amounts in ₹1,25,000.50 form, dates DD-MM-YYYY (NF-008) |
| 2.6 | Turn off data mid-flow, finish the flow, turn data back on | Queued work syncs; no data lost (NF-002) |

### 3. Officer app, the flows that break on cheap phones

| # | Step | Pass |
|---|---|---|
| 3.1 | Start duty, walk 1 km with the screen off | Foreground notification survives; points recorded at the sampling interval (FA-010) |
| 3.2 | Device B specifically: leave the app backgrounded for 30 min with MIUI battery saver on | Duty service still running, or the app tells the officer it was killed (FA-011) |
| 3.3 | Airplane mode for a working day: 10 visits, 5 orders, 20 photos | All queued; nothing lost; outbox count visible (NF-002 72 h) |
| 3.4 | Reconnect on 2G (throttle with `adb shell settings put global preferred_network_mode`) | Sync completes; photos resume in 256 KB chunks (NF-003) |
| 3.5 | Fill storage to under 500 MB free, then take photos | The app refuses gracefully rather than crashing |
| 3.6 | Store mode on a tablet, one full day-close | ST-005 totals match |

### 4. Memory and stability on device C

| # | Step | Pass |
|---|---|---|
| 4.1 | `adb shell dumpsys meminfo in.farmerapp.kisan` after 10 minutes of use | Under 250 MB PSS |
| 4.2 | Open the crop doctor 10 times in a row | No progressive slowdown, no OOM kill |
| 4.3 | Rotate and background/foreground on every screen | No crash, no lost input |
| 4.4 | Leave the app open for an hour on battery | Battery drain under 5%/h with duty off |

### 5. Accessibility spot check (NF-009)

The automated gates (48 dp targets, labelled icons, 16 sp body, WCAG AA contrast over the
tokens) run in `apps/mobile/apps/farmer/test/a11y_test.dart` and
`packages/core/test/theme/contrast_test.dart` on every route. What a person still has to check:

| # | Step | Pass |
|---|---|---|
| 5.1 | TalkBack on, walk the farmer app home → crop doctor → result | Every control announces what it is and what it does |
| 5.2 | Font size at the largest Android setting | Nothing clipped, no overlapping text |
| 5.3 | Outdoors at midday in the Sunlight theme | Every screen readable without shading the phone |

## Human gates

- **The three devices themselves.** They have to be bought and kept charged; an emulator with
  2 GB of RAM allocated is not device C, because it has a desktop CPU behind it.
- **The release sign-off.** A release goes past the internal track only with a completed pass
  for device C in the ticket (docs/runbooks/bad-mobile-release-rollback.md).
- **Firebase.** Crashlytics crash-free-sessions per version (OPS-002) needs the Firebase
  projects and `google-services.json` per flavour. Until they exist, every app-side signal in
  this document is the printed one and the manual pass is the only gate.
