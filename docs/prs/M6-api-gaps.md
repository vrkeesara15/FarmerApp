# M6 API gaps — agronomist corpus uploads, crop-guess flag, ask-expert without re-upload, crop codes, on-device provenance

Branch `feat/M6-api-gaps` (from `main` at `ef377f7`). Closes the API follow-ups of
docs/prs/M6-crop-doctor.md and item 1 of docs/prs/M6-console-agronomist.md. Contract base:
docs/prs/M6-diagnosis-api.md. Requirement IDs: WC-007, DX-001, FM-006, DX-005 (FA-019 via the sync op).

## API

| Change | Where | Contract |
|---|---|---|
| Agronomist corpus uploads (WC-007) | `uploads/router.py` `UPLOAD_ROLES` += `agronomist`; `uploads/service.py` `PURPOSE_LIMITED_ROLES` | The agronomist may start / resume / complete uploads with `purpose: "corpus"` only; any other purpose is `403 forbidden`. The authz matrix (from `openapi.yaml` `x-roles`) now expects the agronomist allowed on the four upload operations. |
| `features.on_device_crop_guess` (DX-001) | `tenants/settings.py` `FeatureSettings`, `settings_router.py` | Tenant setting, default `false`. In `GET /v1/settings` and `GET /v1/settings/public` as `features: {on_device_crop_guess}`; `PATCH /v1/settings {features: {on_device_crop_guess: true|null}}` (owner / director / tenant admin, step-up) merges key by key, `null` resets; audited as `tenant_settings.update` with before / after (plus the listener's `tenant.update`). The apps already read this shape. |
| Ask an expert (FM-006) | `diagnosis/router.py` `askExpertDiagnosis`, `service.ask_expert` | `POST /v1/diagnoses/{id}/ask-expert {note?: string ≤ 2000}` (body optional). Farmer (the case is theirs) or field officer (**who asked for it**; an officer who only sees it: `403 forbidden`); not visible: `404`. Sets `flagged`, `expert_requested_at`, `expert_requested_by`, `expert_note` on the **same** row — no second diagnosis, no re-upload — so the case appears in `GET /v1/diagnoses/review-queue` (`flagged=true`), and every active agronomist (owners if none) gets a `diagnosis_expert_requested` notification. Idempotent: an already flagged case is returned unchanged, nobody notified again. After an agronomist review: `409 diagnosis_already_reviewed`. Answer `200 DiagnosisDetailOut`. Audited by the FA-006 listener (`diagnosis.update`); the change reaches the apps through the sync feed. |
| `crop_code` (FM-004 / FA-019) | `schemas.DiagnosisCreate`, `service.crop_id_for_code` | `POST /v1/diagnoses` and the sync `diagnosis` create op take `crop_code` (e.g. `paddy`, case-insensitive) instead of `crop_id`; resolved among the caller's tenant's crops; unknown → `422 diagnosis_invalid` (`loc: ["crop_code"]`). One of `crop_id` / `crop_code` is required; a UUID `crop_id` together with `crop_code` is `422 validation_error`; `crop_id: "unknown"` + `crop_code` uses the code. |
| `on_device` block (DX-001 / DX-005) | `schemas.OnDeviceIn`, Alembic `0028` `diagnosis.on_device` | ml/ondevice/INTEGRATION.md §5 shape: `{model, model_version, model_sha256?, fallback?, plant_score?, quality?{ok,blurry,dark}, crop_scores?{code: p}, heuristic?{blur_score,brightness}, latency_ms?}`, extra keys refused (no location / identity). Stored as sent; `model_versions.on_device` = `model_version` (else the old `on_device_model`). Returned as `on_device` in the reviewer detail / queue item (farmers and officers get `null`, like `scores`). |

`DiagnosisOut` gained `expert_requested_at`; `DiagnosisDetailOut` gained `on_device`,
`expert_requested_by`, `expert_note`. New notification kind `diagnosis_expert_requested`
(i18n keys `notification.diagnosis_expert_requested.{title,body}` for FA-007 delivery).

Alembic `0028` (expand-only): `diagnosis.on_device jsonb`, `expert_requested_at timestamptz`,
`expert_requested_by uuid → user (SET NULL)`, `expert_note text`, all nullable.

## Clients (minimal switches)

- **Mobile (`packages/core`)**: `DiagnosisApi.askExpert` (`POST …/ask-expert`);
  `DiagnosisRepository.askExpert` on an answered case calls it and stores the returned row
  (same id, device-only fields kept) instead of queueing a new `ask_expert` case with the same
  blobs; `409` → "already with the expert"; offline → new outcome `failed` with the string
  `cropDoctorAskExpertFailed` (5 languages, machine-assisted, NF-008 review). `Diagnosis.askExpert`
  also reads the server's `flagged`. `submit` sends `crop_code` when the crop has no server id
  (pilot tiles) instead of `crop_id: "unknown"`. Farmer F24–F28 and agent A43 messages switch on
  the outcome. The apps still send `on_device_model` + `crop_guess`; sending the full `on_device`
  block is a mobile follow-up (done: docs/prs/M6-final.md).
- **Console (C60)**: `ProvenanceBlock` adds "On-device scores" (plant, photo quality, top crop,
  fallback), "On-device time" and the ask-expert note when present; strings in 5 languages.

## Tests

- API: `tests/diagnosis/test_api_gaps.py` (ask-expert flow, queue, notifications, audit, sync
  feed, idempotency, 409 after review, scope 403 / 404, provisional LLM case; `crop_code` REST +
  sync incl. unknown code; `on_device` storage, reviewer-only visibility, fallback shape,
  validation), `tests/uploads/test_upload_api.py::test_agronomist_uploads_corpus_images_only`,
  `tests/admin/test_settings_api.py::test_on_device_crop_guess_flag_default_off_public_and_audited`,
  authz matrix rows for the new operation and the agronomist upload fixture.
- Mobile: repository ask-expert (sent without re-upload, offline `failed` then retry, reviewed →
  already with expert), `crop_code` in the create op, HTTP contract for `ask-expert`.
- Console: provenance rows with / without the on-device block.

## Human gates

None new. `on_device_crop_guess` stays off until the DX-001 field-accuracy gate passes
(ml/ondevice/INTEGRATION.md §7). New mobile / console strings need the NF-008 native-speaker review.
