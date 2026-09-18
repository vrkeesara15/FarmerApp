# Play Console: background location declaration (VV-009)

Applies to the **field agent app "Mitra"** (`in.farmerapp.mitra`) only. The farmer app "Kisan" (`in.farmerapp.kisan`) declares **no** location permission at all (its manifest has none; CI must keep it that way).

Submitting the form, uploading the video and publishing are **human-only** steps (CLAUDE.md "Never do"). This file is the checklist and the prepared answers; tick it in the release PR.

## 1. Why the app needs background location

Mitra records a field officer's location **only while the officer has switched duty on** (FA-010), through an Android foreground service with a persistent notification ("On duty — location on"). Location continues while the screen is off or the app is in the background because officers ride between villages with the phone in a pocket; the track computes the travel allowance (FA-023) and gives credit for farm visits (VV-004). Recording stops the moment duty is switched off, at the tenant's end-of-day time (20:00 by default) or after 60 minutes idle at home (VV-007). Nothing is recorded off duty (tests: `packages/core/test/duty/duty_controller_test.dart` "NEGATIVE: nothing is buffered while off duty").

Officers are **employees of the tenant** who accept a written location policy in HR onboarding (VV-010) and again in-app (A05, FA-011) before the toggle can be used.

## 2. Declaration form answers (Play Console → App content → Sensitive permissions)

| Question | Answer |
|---|---|
| Does your app access location in the background? | Yes |
| Feature that requires it | "Duty tracking: records the officer's route while on duty to compute travel allowance and verify farm visits. Runs only after the officer taps 'Go on duty' and stops when duty ends." |
| Is it a core feature? | Yes — travel allowance and visit verification are the product (SPEC §4). |
| Why foreground-only is insufficient | Officers travel between farms with the phone locked in a pocket for 30–90 minutes; foreground-only access would leave gaps in the track and unpaid kilometres. |
| Prominent disclosure | Screen A05 before any location access: what is collected, only while on duty, why (travel allowance and visit credit), who can see it; explicit "I agree" stored with the policy version and shown again when the policy changes. |
| Permission flow | A06 in-app rationale → `ACCESS_FINE_LOCATION` prompt → separate rationale → "Allow all the time" system page (background asked only after foreground is granted). |
| Persistent notification | Yes, foreground service type `location`, notification visible for the whole shift with elapsed time. |
| Data sharing | Location is sent to the tenant's FarmerApp backend (asia-south1) only; not shared with third parties or SDKs; not used for advertising. |
| Retention | Raw points 180 days, then daily aggregates (`purge-location-points` job). |
| User control | Duty toggle on the home screen; auto-end at 20:00; policy text in five languages; log out ends the session. |

## 3. Demo video script (≤ 30 s, phone screen recording with the system UI visible)

1. 0–4 s: Launch Mitra, log in (OTP), **A05 disclosure** on screen — pause on the four points, tap "Read the full policy" to show the sheet, tap "I agree".
2. 4–10 s: **A06** — tap Allow on Location → system "While using the app"; tap Allow on "Location all the time" → system settings page → choose "Allow all the time"; notifications prompt.
3. 10–16 s: **A10 Home** — toggle "Go on duty"; show the **persistent notification** ("On duty — location on") in the shade; show the "location on only while on duty" note.
4. 16–22 s: Background the app, lock the screen for a few seconds, unlock — the notification is still there; open A12 "My day" showing the track and km.
5. 22–28 s: Back on A10, toggle "Go off duty" — the notification disappears at once; pull the shade to show it is gone.
6. 28–30 s: Show A63 → A64 sync details (points uploaded), end.

Record on a Pixel (Android 14) with the reference tenant; no real farmer data on screen.

## 4. Privacy policy outline (hosted URL required in the listing)

1. Who we are (tenant operator + FarmerApp as processor) and contact.
2. Data collected in Mitra: account (phone, name, role), **location while on duty** (lat/lon, accuracy, speed, bearing, time, battery, device integrity flags), visit photos and notes, farmer records the officer enters.
3. When location is collected: only after "Go on duty", never off duty; foreground notification always visible.
4. Purpose: travel allowance, visit verification, dispute resolution in the officer's favour, route planning.
5. Who sees it: cluster heads, directors, owner, auditors of the tenant; never store managers or farmers; never sold.
6. Retention: raw points 180 days → daily totals; visits and TA claims per tenant policy; deletion on request through the tenant.
7. Security: TLS, per-tenant isolation (RLS), data residency asia-south1, device-bound sessions.
8. Employee rights and the HR location policy version (VV-010), how to raise a concern.
9. Children: not directed at children. Changes: versioned; in-app re-acceptance when the location policy changes.

## 5. "Is this a monitoring tool?" (Play "Stalkerware / monitoring" question)

Answer **No, unless review asks**. Mitra is an enterprise workforce app used by the tenant's own employees with a written policy they sign, with prominent in-app disclosure and a persistent notification; it is not designed to monitor a person covertly and tracks only during self-declared duty hours. If the reviewer nonetheless classifies it as an employee monitoring tool, apply the "monitoring tool" listing requirements: add `IsMonitoringTool` metadata, the required disclosure in the store listing, and keep the persistent notification and disclosure (already present). The SPEC's acceptance criterion says "app flagged as monitoring tool only if required by review" — follow the reviewer.

## 6. Manifest checklist (apps/mobile/apps/agent/android/app/src/main/AndroidManifest.xml)

- [x] `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (FA-012 / FA-010)
- [x] `ACCESS_BACKGROUND_LOCATION` with the comment pointing here
- [x] `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` (Android 14 typed service)
- [x] `POST_NOTIFICATIONS` (Android 13+)
- [x] `SCHEDULE_EXACT_ALARM` (VV-007 prompt; inexact fallback in code), `WAKE_LOCK`
- [x] `<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="location" android:exported="false" />`
- [x] Farmer app manifest has **no** location permission (grep in the release PR)

## 7. Release PR checklist (human)

- [ ] Declaration form answered as in §2 and submitted
- [ ] Demo video (§3) recorded on the reference device and uploaded
- [ ] Privacy policy (§4) published at a stable URL and linked in the listing
- [ ] Monitoring-tool question answered per §5; metadata added only if review requires it
- [ ] Battery budget on the reference device: < 6 % over an 8-hour shift (VV-001 acceptance) measured and noted
- [ ] Foreground service verified on Android 8, 10, 12, 14 test devices (notification visible, survives screen off, stops at "Go off duty")
