# FA-012 (mobile half): farmer registration wizard with map boundary, crops, consent and offline save (FA-013)

## Requirement IDs

- FA-012 (P0) Farmer registration — mobile half **done** (API half: docs/prs/FA-012-api.md). Acceptance on device: registration saved offline through the outbox and synced; duplicate phone blocked locally at once and, after sync, the server's `farmer_phone_exists` rejection is surfaced on A64 and as a "Duplicate — merge?" banner on A22; two consent records (data, marketing) queued with the farmer.
- FA-013 (P0) Multiple farms per farmer, multiple crop plots per farm — mobile half **done**: the wizard captures any number of farms with any number of plots; A23 adds / edits farms on an existing farmer. End-to-end test: 2 farms + 3 plots through the UI, offline, then synced.
- VA-F01 phone OTP to the farmer (`/v1/farmers/phone/verify/send|confirm`) with an offline "verify later"; VA-F03 polygon sanity on device (self-intersection blocks, declared vs measured acres ±30 % warns).
- NF-004 farm photo through the shared pipeline (camera only); NF-009 / NF-010 read-aloud button on both consent cards, plain-language notice in the farmer's language, icons paired with text, 48 dp targets.
- FA-025 follow-ups: typed `villages` table (schema v3) fed by the change feed; expired `phone_verification_token` dropped by the engine before sending.

PR title: `feat(FA-012): farmer registration wizard with map boundary, crops, consent and offline save (FA-013)`

Branch `feat/FA-012-registration-wizard`. Only `apps/mobile`, `design/`, `docs/` touched (the API loop works in `apps/api` concurrently).

## What changed

### Core — `apps/mobile/packages/core`

- **Geo** `lib/src/geo/geo.dart` (pure Dart): `GeoPoint`, `distanceMetres` (haversine), `polygonAreaSquareMetres` / `polygonAreaAcres` (spherical shoelace, Chamberlain and Duquette), `polygonCentroid`, `isSelfIntersecting` (segment test incl. the closing edge), `polygonToGeoJson` / `polygonFromGeoJson` (one closed `[lon, lat]` ring — the `FarmCreate.boundary` shape), `areaDiffersBeyondTolerance` (VA-F03 30 %).
- **Drift schema v3** `db/app_database.dart`: `villages` table (id, name, district, mandal, state, store_id, lat/lon, version, updated_at); migration v2 → v3 = `createTable(villages)`; `LocalEntities.writeRef/readRef/deleteRef` route the `village` entity of the change feed to the typed table (merge over the existing row), other reference entities stay in `synced_refs`. `SyncEntities.village` / `.crop`.
- **Engine** `sync/sync_engine.dart`: `_prepare` strips `phone_verification_expires_at` from a farmer create and, when the 30-minute token has expired by push time, drops `phone_verification_token` and sends `phone_verified: false` (stored op and local row updated) — an offline registration that reaches the server hours later is applied as unverified instead of rejected. `sync/sync_providers.dart`: `clockProvider`, `idGeneratorProvider`, `outboxProvider`.
- **Farmers module** `lib/src/farmers/`:
  - `farm_options.dart`: `SoilTypes`, `IrrigationTypes`, `LandOwnershipTypes`, `Seasons` (wire values = API enums; `Seasons.forDate`: Jun–Sep kharif, Mar–May zaid, else rabi) with localised labels; `CropRef` (from the `crop` feed, `pilotFallback` with `pilot:<code>` ids until the feed delivers the tenant's crops); `indianMobilePattern`, `toE164India`.
  - `registration_draft.dart`: `RegistrationDraft` (mode new farmer / farm, step, basics, `PhoneVerification`, token + expiry, village id or typed name, language, ownership, `FarmDraft[]` with `BoundaryMode`, points, declared acres, soil / irrigation / ownership, `DraftPhoto[]`, `CropPlotDraft[]`, `existing` + `removedPlotIds` for edits, consents) — JSON round trip, stored under `kv` key `registration.draft`.
  - `registration_notifier.dart`: `RegistrationNotifier` / `RegistrationState` — `start()` restores or creates the draft (loads an existing farm for A23 edit), every mutator persists, `issuesFor(step)` (`StepIssue`), `next()` / `back()` / `goTo()`, `setPhone` → `checkDuplicate()` against local clean farmers, `sendOtp()` (offline → `OtpFailure.network`) / `confirmOtp()` / `verifyLater()`, walk capture (`startWalk` asks `LocationSource.ensureAvailable`, appends fixes ≥ 3 m apart, `closePolygon` cancels the subscription), tap capture (`addCorner`, `undoPoint`, `clearBoundary`), `setDeclaredAcres` / `useComputedAcres`, photo (`takePhoto` → camera → `PhotoProcessor` + quality gate → `usePhoto` → `PhotoStore` + `Outbox.enqueueUpload('farm_photo')`), farms (`addFarm`, `selectFarm`, `removeFarm`), plots (`addPlot`, `updatePlot`, `removePlot`), consents, payload builders (`farmerPayload`, `farmPayload`, `plotPayload`), `save()` — one `db.transaction` queuing farmer → per farm (create or update) + plots (create / update / delete) → consent records, then clears the draft.
  - `farmer_repository.dart`: `FarmerRepository` (villages, crops, `findByPhone`, A20 `farmers(filter)` with name / phone-suffix / village search and village / crop filters, `watchFarmers`, A22 `farmer(id)` with farms + plots + consents + rejection + `duplicateOfId`, `watchFarmer`, `farm`, `plots`); `FarmerListFilter`, `FarmerSummary`, `FarmDetail`, `FarmerDetail`; `farmerPhoneExistsCode`.
  - `phone_verify_api.dart`: `FarmerPhoneVerifyApi` (`FakeFarmerPhoneVerifyApi`: code 123456, 5 wrong → locked, `offline`; `HttpFarmerPhoneVerifyApi`: bearer + refresh, maps 202 / 401 `otp_invalid|otp_expired` / 404 / 423 / 429 to outcomes).
  - `location_source.dart` (`GeoFix`, `LocationAvailability`, `FakeLocationSource`, `GeolocatorLocationSource`), `camera_source.dart` (`CameraSource` with a single `capture()`; `ImagePickerCameraSource` binds it to `ImageSource.camera` — no gallery method exists), `photo_store.dart` (`MemoryPhotoStore`, `DocumentsPhotoStore`).
  - `farmers_providers.dart`: `farmerRepositoryProvider`, `farmerPhoneVerifyApiProvider`, `locationSourceProvider`, `cameraSourceProvider`, `photoStoreProvider`, `mapTileProviderProvider`, `registrationProvider`, `farmerListProvider(filter)`, `farmerDetailProvider(id)`, `villagesProvider`, `cropsProvider`.
- **Widgets**: `MapPanel` (`widgets/map_panel.dart`, `flutter_map` 8 + OSM tiles, `BlankTileProvider` for tests / goldens; polygon or open line, numbered corner markers as separate semantics nodes, position + accuracy ring, tap callback, camera follows the walk but never moves under a tapping finger); `ConsentCard` (title, body, notice, Required / Optional badge, Read aloud, switch); `LanguagePicker.compact` (script-name chips for forms); `FarmerCard` gains `pendingSync` and `attention`; `CropChip` text is flexible.
- **ARB**: +164 keys × 5 languages (`farmers*`, `reg*`, `soil*`, `irrigation*`, `ownership*`, `season*`, `profile*`, `consentGiven/NotGiven`, `farmAddTitle/EditTitle`, `map*`); `build/untranslated.json` = `{}`.
- Dependencies: `flutter_map`, `latlong2`, `geolocator`, `image_picker`.

### Agent app — `apps/mobile/apps/agent`

- `screens/farmers/farmer_list_screen.dart` A20; `add_farmer_wizard_screen.dart` A21 shell (`AppStepper`, resume snackbar, discard, bottom bar in `bottomNavigationBar` so snackbars never cover it); `steps/basics_step.dart` A21a, `steps/boundary_step.dart` A21b, `steps/crops_step.dart` A21c, `steps/consent_step.dart` A21d, `steps/review_step.dart` A21e; `farmer_profile_screen.dart` A22; `farm_edit_screen.dart` A23; `wizard_copy.dart` (issue / step / OTP copy, `ChoiceChips`, `NoticeBox`, `FactRow`, `DraftTextField`, `SectionTitle`).
- `router.dart`: `/farmers`, `/farmers/new`, `/farmers/:farmerId`, `/farmers/:farmerId/farms/new`, `/farmers/:farmerId/farms/:farmId`.
- `main.dart`: overrides `farmerPhoneVerifyApiProvider` (`HttpFarmerPhoneVerifyApi`), `locationSourceProvider` (`GeolocatorLocationSource`), `cameraSourceProvider` (`ImagePickerCameraSource`), `photoStoreProvider` (`DocumentsPhotoStore`).
- `AndroidManifest.xml`: INTERNET, ACCESS_FINE/COARSE_LOCATION, CAMERA. `dart_test.yaml`: 2-minute per-test timeout.

### Design and docs

- `design/screens/A20.md`, `A21.md` (a–e), `A22.md`, `A23.md`; `design/components/MapPanel.md`; `FarmerCard.md` updated. `docs/progress.md`: FA-012 and FA-013 done (both halves).

## Decisions and assumptions

- **Village / crop reference data** comes from the sync change feed (`village` → typed table, `crop` → `synced_refs`). The API feed does not emit them yet (M2 kickoff): until it does, the village picker falls back to a typed village name (`village_name` in the payload; the server will reject a missing `village_id`, which A64 surfaces for edit-and-retry) and the crop tiles show the SPEC 0.3 pilot crops with `pilot:<code>` placeholder ids. API follow-up noted in progress.md.
- **Expired verification token**: the API rejects an expired `phone_verification_token` (422). The engine strips it at push time and the farmer syncs unverified; A22 shows "Phone not verified" and a "Verify phone" placeholder for the record-level OTP flow (`/v1/farmers/{id}/phone/verify/*`, next mobile loop).
- **Consent `channel`**: sent as `officer` (the API's CHECK value); the consent text version is assigned by the server (`tenant.settings.consent_version`).
- **Location** is read only after the officer taps "Start walking" on A21b and stops at "Pause", "Close boundary", leaving the step, or save (FA-010). No background tracking.
- **Camera only** for farm photos: `CameraSource` has one method and the real implementation passes `ImageSource.camera`; there is no gallery code path (FA-015 rule applied early).
- **Tap mode camera**: the map does not re-centre while the officer taps corners (it would move the next tap); it follows GPS fixes in walk mode.
- **Snackbars vs bottom bar**: wizard and profile actions live in `Scaffold.bottomNavigationBar` so a snackbar ("Fix the highlighted fields", "Continuing where you left off") never covers Next / Save.
- **A23 edit** reconciles plots (update kept, create new, delete removed) with the farm's `base_version`; conflict handling stays with the engine (server wins).
- Merge of a duplicate farmer is console work (WC-104); the banner links to the existing record.

## Screenshots / goldens (UI changes)

New: `apps/agent/test/goldens/goldens/a20_farmer_list`, `a21a_basics`, `a21b_boundary`, `a21c_crops`, `a21d_consent`, `a21e_review`, `a22_farmer_profile`, `a23_edit_farm` × `{light,sunlight}` (16); `packages/core/test/goldens/goldens/map_panel_*`, `consent_card_*`. Regenerated: `farmer_card_*` (third card: pending + attention rows), `crop_chip_*` (flexible text, same look). All other goldens unchanged.

## Migration notes

- [x] Drift v2 → v3: additive `villages` table; `test/db/migration_test.dart` covers v1 → v3, a genuine v2 file → v3 keeping queued outbox rows, fresh at v3, reopen.
- [ ] Alembic — n/a (mobile loop)
- [ ] RLS — n/a (device DB)
- [x] Dependencies: `flutter_map` (BSD-3), `latlong2`, `geolocator` (Android plugin), `image_picker` (Android plugin). OSM tile usage policy: proper user agent set; tenant tile server / cache is an OPS follow-up before scale.

## Test evidence

`cd apps/mobile && ./tool/check.sh` — green: pub get, codegen, no untranslated messages, `dart format` clean, `flutter analyze` zero issues (core, agent, farmer), string lint clean, `flutter test`: core **351 passed** (283 before; +68), agent **39** (11 before; +28), farmer 9.

New tests:
- `packages/core/test/geo/geo_test.dart` (21) — hectare square = 2.47 acres, winding, closed ring, degenerate, centroid, bow-tie / closing-edge / concave self-intersection, GeoJSON encode / decode / text / rejects, VA-F03 tolerance edge (30 % passes, 31 % fails), haversine.
- `packages/core/test/farmers/registration_notifier_test.dart` (23) — fresh draft stored; interrupted wizard resumes at the same step with data; discard; farm-mode draft isolation; basics issues; typed village fallback; invalid number never sent; local duplicate blocked and cleared; tombstoned farmer not a duplicate; OTP send / wrong / right with token + expiry; lockout; number change resets; offline network failure + verify later; walk-around fixes (3 m filter, accuracy, close stops GPS, no appends after close); location denied; tap corners / undo / clear; VA-F03 warning vs block; photo pipeline → queued upload → payload placeholder; cancelled camera; crops validation + season; consent; **save with 2 farms + 3 plots → 8 ops in order with payloads → online sync applies all, rows clean**; incomplete save refused; verify-later save; A23 add farm; A23 edit farm reconciles plots.
- `packages/core/test/farmers/farmer_repository_test.dart` (9) — list, search (name / digits / village), filters, pending, live stream, detail, rejected duplicate link, crop fallback vs feed, villages sorted.
- `packages/core/test/widgets/map_panel_test.dart` (4), `consent_card_test.dart` (1), `test/db/migration_test.dart` (+1: v2 → v3), `test/sync/sync_engine_push_test.dart` (+2: valid token sent without expiry; expired token dropped), `test/sync/sync_engine_pull_test.dart` (village → typed table incl. partial update + delete).
- agent `test/farmers/registration_flow_test.dart` (4) — **end-to-end offline: A20 → A21a–e with 2 farms / 3 plots through the UI (map taps, date pickers, consent switches) → outbox ops in order with payloads and consent records → A22 → FakeSyncApi online → 8 applied, rows clean, pending note gone**; resume after "app killed" + discard; online OTP wrong then right; local duplicate blocked with link to the existing farmer.
- agent `test/farmers/farmer_list_test.dart` (4), `farmer_profile_test.dart` (4: facts / disabled actions / tabs, **rejected-after-sync duplicate banner → link**, A23 add farm ops, A23 edit farm ops), `test/goldens/farmers_golden_test.dart` (16).

## Checklist

- [x] Tests written first; acceptance criteria covered (FA-012 offline save + sync, duplicate blocked locally and after sync, consent records; FA-013 2 farms + 3 plots)
- [ ] Role + tenant authorisation tests — n/a on mobile
- [x] Strings externalised (164 keys × 5 languages); timestamps UTC; no money
- [x] No secrets in code, fixtures or logs (OTP codes only in the fake; tokens via `TokenStore`)
- [x] Location only on explicit walk capture; camera only, no gallery
- [x] docs/progress.md updated; OpenAPI untouched (no API change)
