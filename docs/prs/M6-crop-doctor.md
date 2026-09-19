# M6 crop doctor and scouting — DX-001 on-device gate, guided camera, provisional results without buy actions, one-tap order and expert actions

Branch `feat/M6-crop-doctor` (from `main` at `f23e287`). Mobile only (`apps/mobile`, `design/`, `docs/`).
SPEC 2.4 FM-004 .. FM-006 / FM-015, 2.2 FA-019, 3 (flowchart, DX-001, DX-010, 3.4), 13.1–13.3
(A40–A43, F20–F28). Contracts: docs/prs/M6-diagnosis-api.md, ml/ondevice/INTEGRATION.md.

## Requirement IDs

- **DX-001** (integration done; field-validation gate below) — `crop_quality_v1.tflite` +
  `crop_quality_v1.metadata.json` shipped unchanged in `packages/core/assets/models/` (sha256 checked
  in a test and again at load), `TfliteQualityModel`, crop hint behind the `on_device_crop_guess` flag.
- **FM-004** (done) — F20–F23: guided live camera with the overlay, up to 3 photos, blurry / dark /
  not-a-plant refused with the matching tip (text + audio), crop auto-detect (flagged) with manual
  override on big tiles.
- **FM-005** (done) — F24–F28: analysing / queued offline, high-confidence result, provisional
  variant with no buy action, "updated" state with history, out of scope.
- **FM-006** (done) — one-tap Order (cart → store queue with the SKU and its `label_claim_id`),
  Call my officer, Ask an expert.
- **FA-019** (done) — A22 Scout / Home Scout → crop plot → A40–A43, result attached to farmer and
  plot, "Create order for farmer", A22 Diagnoses tab.
- **FM-015** (done) — F70 on the real `POST/GET /v1/me/deletion-request` shape.
- F62 officer card reads `officer {id, name, phone}` (already coded in M6 farmer app; now tested
  with and without the object).

## Design

### DX-001 in `packages/core`

- **Plugin: `tflite_flutter` 0.12.1** (the TensorFlow team's plugin; LiteRT 1.4 AAR with
  `libtensorflowlite_jni.so` for arm64-v8a and armeabi-v7a). The LiteRT GPU delegate it pulls in is
  excluded in both apps' `build.gradle.kts` (CPU / XNNPACK only). Its Kotlin target is aligned with
  its Java 11 target in the root `build.gradle.kts` (the plugin leaves Kotlin at 17, which Gradle
  rejects). `flutter_litert` 3.8 was considered: it bundles desktop runtimes (host tests would run the
  real model) but downloads `libLiteRt.so` from Google Maven at build time and adds the LiteRT Next
  runtime and a CMake build to the APK — rejected for size and reproducible CI builds.
- **Measured APK sizes** (farmer, release, obfuscated, R8, per ABI): see Results. The model is
  3.0 MB stored; the runtime ~1.7 MB compressed. The farmer APK stays under 25 MB, so the model ships
  in **both** apps (the "agent only" fallback was not needed).
- `photo/tflite_quality_model.dart`: `QualityModelMetadata` (layout, labels, thresholds from the
  metadata file), `preprocessForQualityModel` (centre square 0.875 × short edge → 224 × 224 uint8
  RGB NHWC, area resize, not normalised; runs in `compute`), `decodeQualityOutput` (dark ≥ 0.5 →
  `photo.tip.dark`, else blurry ≥ 0.5 → `photo.tip.blurry`, else plant < 0.5 →
  `photo.tip.not_plant`; crop guess only on an accepted photo with top score ≥ `crop_min` 0.6),
  `TfliteQualityModel` (loads once, checks sha256 and tensor shapes/dtypes, one inference at a
  time, 1 500 ms timeout; any failure marks the model broken for the session, reports the reason
  once and answers with the Laplacian heuristic — the user is never blocked), `QualityModelLog`
  (timing per check: preprocess ms, inference ms, fallback; `dart:developer` log
  `photo.quality`). `photo/tflite_flutter_interpreter.dart`: the `QualityInterpreter` over
  `tflite_flutter` — interpreter built from the asset bytes, inference on the plugin's
  `IsolateInterpreter` (off the UI thread).
- `PhotoQualityResult` gained `isPlant`, `plantScore`, `cropCode`, `cropScore`, `cropScores`,
  `qualityScores`, `modelVersion` (`ondevice-v1.0` / `heuristic-laplacian-v1`), `usedFallback`,
  `latencyMs`; `isAcceptable = !blurry && !dark && isPlant`; `toDiagnosisQuality()` emits exactly
  the API's `PhotoQualityIn` fields. `PhotoTipKeys.notPlant` + `photoTipNotPlant` /
  `photoQualityNotPlant` in five languages; `CameraGuideOverlay` lights "fill the frame" for it.
- **Crop hint flag**: `PublicTenantSettings.onDeviceCropGuess` from `features.on_device_crop_guess`
  (default **off**). Off: no guess is shown, pre-selected or sent. On: the best guess of the
  accepted photos pre-selects the crop (never over the user's pick) and is sent as `crop_guess`.
  The progress row / INTEGRATION.md called it `ondevice_crop_hint`; this branch uses
  `on_device_crop_guess` as briefed.

### Crop-doctor data layer (`packages/core/lib/src/diagnosis/`)

- `diagnosis` is a writable sync entity (`sync_docs`, server wins, create payload without `id`).
  `DiagnosisRepository.submit` saves the processed photos (`PhotoStore`), queues one resumable upload
  per photo (`purpose: diagnosis`, 256 KB chunks) and one create op whose `images[].blob_uri` are
  `upload:<id>` placeholders — the engine sends it only after the uploads complete (contract:
  "queue the op after the photo uploads"). Payload: `farmer_id` (officer), `crop_plot_id`, `crop_id`
  (server id, else `unknown` for a pilot placeholder / "I don't know"), `images [{blob_uri, sha256,
  quality}]`, `crop_guess` (flag on), `on_device_model`, `crop_stage`, `captured_at`, `ask_expert`.
- The answer lands from the applied echo (inline delivery), `DiagnosisPoller` (`GET
  /v1/diagnoses/{id}`, 2 s backing off to 10 s, pushes the outbox first) and the change feed.
  `DiagnosisCodec.onWrite` keeps the device-only `_local` block (photo paths, crop code) and, when an
  answer is replaced (agronomist confirm / correct), appends it to `_local.history` and raises
  `update_unseen` (F27); `markSeen` clears it. Results are read from the phone (NF-002).
- `Diagnosis.showBuy` = `can_buy` **and** not provisional **and** status answered / confirmed /
  corrected (defence in depth for SPEC 3.4). `DiagnosisRepository.askExpert`: already with the
  expert (provisional / out of scope / asked) → nothing sent; still queued → `ask_expert` added to
  the queued op; answered → the same blobs go to the agronomist as a new `ask_expert` case (API
  follow-up below).
- `CropDoctorCapture` (Riverpod notifier shared by both apps): shot → `DiagnosisPhotoPipeline`
  (`PhotoProcessor` + gate) → pending → Use / Retake; up to 3; crop choice; submit.
- `GuidedCamera` (`PluginGuidedCamera` over `camera` 0.12: back lens, no audio, JPEG, flash off;
  `FakeGuidedCamera` for tests), `FakeDiagnosisServer` / `FakeDiagnosisApi` (tests and previews).
- Orders: `CartLine.labelClaimId`, `CartNotifier.addRecommended`, `OrderRepository` and
  `KisanRepository.placeOrder` send `label_claim_id` on the line; `catalogItemForOption` uses the
  cached SKU or builds one from the recommendation.

### Shared widgets

`GuidedCameraView` (preview + `CameraGuideOverlay` + counter + shutter + permission / error
states), `DiagnosisResultView` (headline for `message_key`, `DiagnosisResultCard` with tappable
symptom checklist, Organic / Chemical tabs, `TreatmentCard` with the new `TankDose` pictogram, PHI,
PPE incl. clothing, label safety text, ranked `ProductCard`s with `OwnBrandBadge`, cultural
practices, F27 banner, earlier answers) and `DiagnosisActionBar` (buy allowed: Order + call; else
Talk to your field officer + Ask an expert; out of scope: Ask an expert). `ProductCard` gained
`actionLabel / actionIcon / showAction / actionKey`; `DiagnosisResultCard` gained
`provisionalState` and `onSymptomTap`. Component docs updated.

### Farmer app (F20–F28)

`screens/crop_doctor/`: F20 intro (3 picture tips read aloud, Open camera, "My crop checks"),
F21 camera, F22 photo check (tip read aloud on refusal, 3-photo cap, crop row when detected),
F23 crop tiles (own plots first, pilot crops, "I don't know"), F24–F28 result screen (poller, queued
offline state, result, banner, Order / Call my officer / Ask an expert). Home shows the F27 card.
`main.dart` wires `PluginGuidedCamera`, `TfliteQualityModel` (loaded at start),
`DocumentsPhotoStore` (photos survive until uploaded) and `HttpDiagnosisApi`. The placeholder
screen is gone.

### Agent app (A40–A43, FA-019)

`screens/scouting/scouting_screens.dart`: crop plot choice, A40 camera, A41 review (with "Also ask
our expert"), A42 / A43 result (farmer · crop header, model / corpus provenance footer, Create order
for farmer, Call farmer, Ask an expert), `FarmerDiagnosesList` on the A22 Diagnoses tab. A22 Scout
and Home Scout are live (farmer picker `?for=scout`).

### FM-015

`FakeKisanApi` now mirrors the landed API (uuid `ticket_id`, `type`, `created_at`, 201 then 200 with
the same open ticket); F70 shows the first 8 characters of the ticket uuid as the reference and the
`rejected` status. An HTTP contract test checks `POST/GET /v1/me/deletion-request` paths, body and
parsing.

## Tests

Core: `test/photo/tflite_quality_model_test.dart` (asset sha256 / size / layout / thresholds,
preprocessing crop and brightness, decoding and the retake rule incl. dark > blurry > plant, API
quality object, fake-interpreter model: timing log, blurry / dark / not-a-plant tips, sha mismatch,
missing asset, wrong shapes, interpreter error broken for the session, timeout, heuristic fallback;
real model on the host — skipped with the reason), `test/diagnosis/diagnosis_repository_test.dart`
(submit payload, offline queue then sync applies the answer, poll back-off, provisional never
buyable, out of scope, F27 history + banner, first answer is not an update, ask-expert outcomes,
farmer / plot filters, refused create kept), `crop_doctor_capture_test.dart` (gate tips, 3-photo cap,
flag off / on, manual override wins, real heuristic pipeline rejects a blurred photo),
`http_contract_test.dart` (deletion request, `GET /v1/diagnoses/{id}`, `officer` object, flag),
`test/widgets/diagnosis_result_view_test.dart` (words, symptoms, order carries SKU + claim, dose /
tank / PHI / PPE / safety text on every chemical, provisional and out of scope without any buy
action, F27, Telugu).
Farmer: `crop_doctor_test.dart` (gate with tip + audio + lit overlay, F23 tiles attach the plot,
F25 → cart → `POST /v1/orders` with `label_claim_id`, dose / PHI / PPE, F26 no buy + officer call,
F24 offline then sync, F27 via sync + Home card, F28, flag + override, readable offline, F62
without officer), `delete_account_test.dart` (uuid ticket, in_progress), `no_typing_test.dart`
(new routes). Agent: `scouting/scouting_test.dart` (A22 Scout → A43 with farmer + plot, stored
confidence + model version, Create order for farmer with SKU + claim, provisional without buy,
A42 offline then sync, Diagnoses tab, Home Scout), `farmer_profile_test.dart` (Scout live).
Goldens (Light + Sunlight): farmer `f21_camera`, `f22_photo_check_blurry`, `f25_result_{en,te,hi}`,
`f26_provisional`, `f28_not_a_plant`; agent `a43_result_high`, `a43_result_provisional`;
`a22_farmer_profile` regenerated (Scout button enabled).

## Results

`cd apps/mobile && APK_SIZE_CHECK=1 ./tool/check.sh`: green. Tests: core 650 + 1 skipped (host real
model), agent 201, farmer 123 (were 600 / 193 / 95 at the M6 farmer-app merge); analyze zero
issues; format clean; no untranslated messages; string lint OK.

**APK sizes** (farmer, release, obfuscated, R8, per ABI): arm64-v8a **17.11 MB**, armeabi-v7a
**16.42 MB** (were 11.87 / 11.29 MB). Budget 25 MB: OK. Split: model 3.0 MB (stored),
`libtensorflowlite_jni.so` 4.3 MB → 1.7 MB compressed, camera (CameraX shared with the QR
scanner) and the new screens (~0.5 MB Dart).

## Human gates

- **DX-001 latency**: < 400 ms on a 2 GB RAM reference phone — run `ml/ondevice/BENCHMARK.md` and
  read the in-app `ondevice_quality_timing` log (preprocess + inference) on the device.
- **DX-001 field validation before `on_device_crop_guess` is turned on** (≥ 50 agronomist-labelled
  pilot photos per crop + other + not-a-plant, threshold re-tune → new metadata asset); legal check of
  the ImageNet-pretrained weights. The quality / plant gate ships now; the crop hint stays off.
- **Host test of the real model is skipped** (reported by the test): `tflite_flutter` resolves its
  desktop library next to the Flutter runner, which `flutter_tester` does not have. The real model is
  exercised on a device.
- **Camera on devices**: CameraX preview + capture on the reference phones (Android 8+, 2 GB), the
  permission prompt wording, low light.
- **Translations** of the ~72 new strings (te / kn / hi / mr) by native speakers, and the audio
  prompts (`f20_intro`, `photo_tip_*`, `f23_choose_crop`, `f24_*`, `f25_result`) recorded (NF-008 /
  NF-009).
- **End to end against the real API** (stg): photo uploads (`purpose: diagnosis`), the create op,
  pubsub delivery + polling, agronomist review reaching the phone.

## API / infra follow-ups (not in this branch)

Closed in `feat/M6-api-gaps` (docs/prs/M6-api-gaps.md): the settings flag, `ask-expert`, `crop_code` and the `on_device` block (the apps do not send the block yet). FA-007 push is still open.

- `features.on_device_crop_guess` in `GET /v1/settings/public` (tenant setting, default false).
- `POST /v1/diagnoses/{id}/ask-expert` to flag an answered case without a second diagnosis (the app
  re-submits the same blobs with `ask_expert: true` today).
- Accept a `crop_code` (or deliver the `crop` reference feed to the farmer role) so a farmer's pick
  of a pilot crop without a server id is not sent as `unknown`.
- Adopt the INTEGRATION.md `on_device` block (plant / quality / crop scores, latency, fallback) in
  `DiagnosisCreate` (the app sends `crop_guess` + `on_device_model` now; the full scores stay on
  the phone).
- FA-007 push delivery of `diagnosis_reviewed` (the app shows F27 when the change arrives by sync).
