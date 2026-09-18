# FA-014 (mobile half): visit check-in, capture, farmer confirmation and check-out screens with local proof checklist

## Requirement IDs

- FA-014 Visit check-in geofence — A30 with the client-side pre-check, override note, duty gate; rejection handling (`outside_geofence` + "Retry from the farm")
- FA-015 Visit capture — A31: in-app camera only, EXIF + device time on the `visit_photo` op, notes, crop stage, live ProofChecklist
- FA-016 Farmer confirmation — A32: OTP by SMS, push prompt, QR; waiting and confirmed states
- FA-017 Check-out and duration — A33 summary (server wins), A34 list
- Supporting: VV-003 (device geofence mirror), VV-004 / VV-005 (device score mirror), FA-028 (integrity on the check-in), NF-009 / NF-010 (48 dp targets, icon + text everywhere, Sunlight)

PR title: `feat(FA-014): visit check-in, capture, farmer confirmation and check-out screens with local proof checklist (FA-015, FA-016, FA-017)`

Branch `feat/FA-014-visit-mobile` on main `3aee5cf` (API half already merged, docs/prs/FA-014-api.md). Only `apps/mobile`, `design/` and `docs/` are touched.

## What changed

**Core (`apps/mobile/packages/core`)**
- `lib/src/geo/geo.dart`: `pointInPolygon` (ray casting, edges count as inside), `distanceToSegmentMetres`, `distanceToPolygonMetres` (0 inside).
- `lib/src/visits/visit_models.dart`: wire constants (`GeofenceResults`, `VisitStatuses`, `ConfirmationChannel`, `ConfirmationStatuses`, `CropStages`), `VisitSettings` (tenant `geofence_radius_m` / `min_visit_duration_s` cached in `kv` `visits.settings`, defaults 150 m / 300 s), `evaluateGeofence` → `GeofenceCheck` (same decision order and fields as `farmerapp/visits/geofence.py`).
- `lib/src/visits/visit_proof.dart`: `evaluateVisitProof` / `VisitProof` / `PhotoEvidence` — the device twin of `farmerapp/visits/scoring.py` (30/30/20/10/10, override 15 once approved, photo ±10 min / 150 m, integrity mock / root / drift > 300 s); open visits use `now` as the window end.
- `lib/src/visits/visit_flow.dart`: `VisitFlow` — `precheck`, `checkIn` (duty gate, no op outside without a note), `capturePhoto` / `acceptPhoto`, `saveCapture`, `checkOut`, `retryFromFarm`, `requestConfirmation`, `flushQueuedConfirmations`, `confirmOtp`.
- `lib/src/visits/visit_repository.dart` (details, lists, verified count, confirmation upserts, server visit apply), `visit_confirm_api.dart` (`VisitConfirmApi`, `HttpVisitConfirmApi`, `FakeVisitConfirmApi`), `visit_providers.dart`.
- Drift schema **v5**: `visits`, `visit_photos`, `visit_confirmations` (+ indexes), `villages.meeting_point_lat|lon|radius_m`; v4→v5 migration test.
- Sync: `visit`, `visit_photo`, `visit_confirmation` are writable entities with typed codecs in `LocalEntities` (device-only fields — pre-check, rejection, local photo path, QR token — survive server rows); `SyncError` keeps problem extras (`distance_m`, `target`, `radius_m`, detail-text fallback); the engine records a rejection on the visit row (`markRejected`); `fileReaderProvider` feeds the uploader.
- Widgets: `VisitCard.score` nullable ("In progress" pill) + footnote; `MapPanel.geofence` / `meetingPoint` / `meetingRadiusM`; A64 labels for the visit entities. `qr_flutter` added.
- 102 new ARB keys in en / te / kn / hi / mr.

**Agent app (`apps/mobile/apps/agent`)**: `lib/screens/visits/` — A30 `start_visit_screen.dart`, A31 `visit_screen.dart`, A32 `confirm_screen.dart`, A33 `summary_screen.dart`, A34 `visits_list_screen.dart`, shared `visit_copy.dart`; routes `/visits`, `/visits/new`, `/visits/:id`, `/visits/:id/confirm`, `/visits/:id/summary`; A10 quick action + Visits nav + verified-today tile; A22 Start visit + Visits tab; `HttpVisitConfirmApi` wired in `main.dart`.

**Design**: `design/screens/A30.md`–`A34.md` (new), `A10.md`, `A22.md`, `components/ProofChecklist.md`, `VisitCard.md`, `MapPanel.md`.

Design decisions and assumptions:
- The pre-check is advisory: the server re-evaluates in PostGIS and wins. Outside, the op goes out only with an `override_note`.
- Duty gate reads the local `duty_sessions` row (works right after a restart, before the controller restores).
- Requesting a confirmation has no sync op in the API contract. OTP and QR need the network now. An offline "Ask in Kisan app" is kept as a local `queued` confirmation row and sent the next time A32 opens online. It is not an outbox op, so nothing unsupported reaches `/v1/sync`.
- The QR token stays on the device only (never in an outbox payload).
- Notes are sent with the next A32 open / check-out (one `visit` update, only when changed); the crop stage is sent at once.
- Tenant settings are read from the `kv` cache; until a settings pull exists they are the SPEC defaults (150 m, 5 min).
- A checked-out visit not yet scored by the server shows the "In progress" pill on A34 plus "Will sync when online"; A33 shows the local expectation.

## Screenshots / goldens

`apps/mobile/apps/agent/test/goldens/goldens/`: `a30_start_visit_{inside,outside}`, `a31_visit_in_progress`, `a32_confirm_{choose,qr_waiting,confirmed}`, `a33_summary`, `a34_visits_list` × `{light,sunlight}`; `a22_farmer_profile_*` regenerated (Start visit enabled).

## Migration notes

- [x] Drift v5 (additive: three tables, three nullable village columns; v1..v4 → v5 tested).
- [ ] No API / Alembic change.

## Test evidence

`cd apps/mobile && ./tool/check.sh` → `mobile check: OK` (core 455, agent 92, farmer 9 tests; analyze clean; l10n complete; string lint OK).

New tests:
- `packages/core/test/geo/geofence_test.dart`: point in polygon (convex, concave, closed ring, winding), distance to polygon (edge, corner), buffer inside at 100 m / outside at 500 m, tenant radius, meeting point radius and fallback, nearest target, no target.
- `packages/core/test/visits/visit_proof_test.dart`: 100 / 70 (boundary) / 65 override / 40 (boundary) / 30, 69 / 39 thresholds, mock / root / drift zeroing (300 s ok), gallery / time / GPS / missing-EXIF photos, open-visit ticking.
- `packages/core/test/visits/visit_flow_test.dart`: off duty blocked; inside payload; outside without / with note; cached radius; photo op (`taken_in_app`, EXIF, upload dependency); capture + check-out ops and server-owned score on pull; conflict applies score fields; `outside_geofence` rejection + retry; `SyncError` extras; OTP happy / wrong, OTP / QR offline, push queued → sent → confirmed via pull, QR token kept local, not synced.
- `packages/core/test/db/migration_test.dart`: v4 → v5.
- `apps/agent/test/visits/visit_screens_test.dart`: A30 off duty / inside / outside / picker, A31 no gallery affordance + voice placeholder + ticking score + crop stage, photo through the UI, rejected banner + retry, A32 OTP / offline / QR / push, A33 server wins + under-minimum warning, A34 tabs / filter / sync state, A10 / A22 wiring.
- `apps/agent/test/visits/visit_offline_e2e_test.dart`: offline on duty → A22 → A30 → photo → check-out → A33, then online: `policy_acceptance, duty_session, visit/create, visit_photo/create, visit/update` applied in order, photo uploaded first.
- `apps/agent/test/goldens/visits_golden_test.dart`.
- `apps/agent/test/farmers/farmer_profile_test.dart` updated: Start visit is now enabled, Visits tab lists visits.

## Checklist

- [x] Tests first; acceptance criteria covered (blocked outside without note; gallery disabled; confirmed only after one channel; under minimum flagged, not rejected)
- [x] Strings in ARB (5 languages); no hard-coded copy (lint OK)
- [x] Location only on duty: the pre-check reads the duty sampler and check-in requires an open session
- [x] No secrets; OTP codes never stored; QR token device-local
- [x] docs/progress.md updated (FA-014 .. FA-017 done, both halves)
