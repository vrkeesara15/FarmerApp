# M6 — diagnosis engine API (M6-KICKOFF, DX-002 .. DX-010, WC-006 / WC-007 API, OPS-009, FM-015 API)

Branch `feat/M6-diagnosis-api`. SPEC 3 (flowchart, 3.1–3.4), 2.2 FA-019, 2.4 FM-004 .. FM-006 /
FM-015, 2.5 WC-006 / WC-007, 7 NF-011, 11.3 SEC-027, 12.2 OPS-009, 14.4 M6 kickoff.

This file is the contract for the **farmer app** (crop doctor F20–F23, FM-015 settings), the
**agent app** (scouting, FA-019) and the **console** (C-screens for WC-006 review queue and
WC-007 corpus manager), plus the `embed` service contract and the LLM prompt / schema.

## What landed

| Area | Where |
|---|---|
| Alembic `0027` | `corpus_problem`, `corpus_image` (`embedding vector(768)`, HNSW `vector_cosine_ops`, m 16 / ef_construction 64), `corpus_version` (append-only), `diagnosis`, `diagnosis_review` (append-only), `diagnosis_threshold` (versioned), `llm_call_log` (append-only, 1 year), `data_request`; `upload_session.purpose` += `corpus`. All under RLS, audited (except `llm_call_log`, which is itself the log; `embedding` is excluded from audit diffs). |
| Encoder (DX-002) | `farmerapp/diagnosis/encoder.py`: `ImageEncoder` protocol, `EncoderInfo(name, version, dim)`, `FakeEncoder` (pixel DCT, deterministic), `RemoteEncoder` (the `embed` service). Pinned by settings; stored on every corpus image and diagnosis. |
| kNN (DX-002) | `diagnosis/knn.py`: approved images of approved problems, same crop, same encoder, top 20, `SET LOCAL hnsw.ef_search = 40` (`DIAGNOSIS_HNSW_EF_SEARCH`), `hnsw.iterative_scan = strict_order`. |
| Decision (DX-003) | `diagnosis/decision.py` (pure): high = top-1 ≥ T1 **and** ≥ 60 % of top-10 agree; thresholds per crop in `diagnosis_threshold` (versioned, audited; `PUT /v1/diagnoses/thresholds`). |
| LLM fallback (DX-004) | `diagnosis/llm.py`: `LlmDiagnosisClient` protocol, `ClaudeDiagnosisClient` (Anthropic SDK, `claude-opus-5`), fake / disabled stand-ins. |
| Pipeline | `diagnosis/pipeline.py` (`decide_case` writes nothing; `process` stores the result), `diagnosis/worker.py` (`diagnosis.requested`), `diagnosis/service.py` (create, scope, review). |
| Treatments (DX-007/8/9) | `diagnosis/treatment.py` over `catalog.recommendable.recommendable_skus` only. |
| Corpus manager (WC-007) | `diagnosis/corpus.py`, `diagnosis/corpus_router.py`. |
| Review queue (WC-006, DX-006) | `diagnosis/router.py`, `service.review`. |
| OPS-009 job | `farmerapp/ops/diagnosis_watch.py`, `python -m farmerapp.jobs diagnosis-queue-age --tenant …`. |
| FM-015 / NF-013 | `farmerapp/privacy/` (`data_request`). |
| Seed | `jobs/seed_corpus.py`: public bootstrap corpus, 63 problems per tenant (10–12 per pilot crop) × 6 synthetic images, corpus version 1. |
| Evaluation | `ml/eval/evaluate.py`, `ml/eval/testset/` (README + CI manifest). |

## Endpoints

All errors are RFC 9457 problem+json with a stable `code`.

### Crop doctor (farmer app F20–F23, agent app FA-019)

**Upload photos first** with the existing chunked upload flow (`POST /v1/uploads` with
`purpose: "diagnosis"`, PUT chunks, `POST /v1/uploads/{id}/complete` → `blob_uri`). Photos are
resized on the device (NF-004).

`POST /v1/diagnoses` — farmer (for themself), field officer (for one of **their** farmers).
`Idempotency-Key` honoured. **202** with the `DiagnosisOut` below.

```json
{
  "id": "uuid (optional, client-generated for offline capture)",
  "farmer_id": "uuid (required for a field officer; a farmer may omit it)",
  "crop_plot_id": "uuid | null",
  "crop_id": "uuid | \"unknown\"",
  "images": [
    {"blob_uri": "gs://…", "sha256": "hex (optional, checked)",
     "quality": {"passed": true, "blur_score": 212.5, "brightness": 0.55, "plant_present": true}}
  ],
  "crop_guess": {"code": "paddy", "confidence": 0.93},
  "on_device_model": "crop-tflite-2026.10",
  "crop_stage": "vegetative",
  "captured_at": "2026-09-19T05:10:00Z",
  "ask_expert": false,
  "crop_code": "paddy (alternative to crop_id, added in M6-api-gaps)",
  "on_device": {"model": "crop_quality", "model_version": "ondevice-v1.0", "plant_score": 0.998,
                "quality": {"ok": 0.97, "blurry": 0.02, "dark": 0.01},
                "crop_scores": {"paddy": 0.93, "other": 0.02}, "latency_ms": 38}
}
```

Added in `feat/M6-api-gaps` (docs/prs/M6-api-gaps.md): `crop_code` instead of `crop_id`, the
`on_device` block, and `POST /v1/diagnoses/{id}/ask-expert {note?}`.

1–3 images (422 `validation_error` otherwise). Problems: `404 not_found` (farmer not yours),
`422 diagnosis_image_missing` (not a completed upload of your tenant), `422
image_sha_mismatch`, `422 diagnosis_invalid` (unknown crop, crop plot not the farmer's, officer
without `farmer_id`). With `crop_id: "unknown"` the crop plot's crop is used, else the
on-device guess (confidence ≥ 0.6), else the corpus of every crop is searched.

Locally (`DIAGNOSIS_DELIVERY=inline`) the answer is in the 202 body; in stg / prd
(`pubsub`) the body is `queued` and the result arrives by **polling** `GET
/v1/diagnoses/{id}` (every 2 s, back off to 10 s) **and** through the sync change feed.

`GET /v1/diagnoses/{id}` / `GET /v1/diagnoses?farmer_id=&status=&cursor=&limit=` — farmer
(own), field officer (own farmers, or what they asked), cluster head / store manager (their
farmers), agronomist, owner, director, tenant admin, auditor. Accountants: 403.

`DiagnosisOut` (also the sync `data`):

```json
{
  "id": "…", "subject": "farmer | officer", "farmer_id": "…", "crop_plot_id": null,
  "requested_by": "…", "crop_id": "…", "crop_detected_on_device": {"code": "paddy", "confidence": 0.93},
  "district": "Warangal", "season": "kharif", "crop_stage": "vegetative",
  "status": "queued | answered | provisional | confirmed | corrected | out_of_scope",
  "source": "corpus | llm | agronomist | null",
  "confidence": "high | medium | low | null",
  "provisional": false,
  "can_buy": true,
  "cta": "buy | talk_to_field_officer | ask_expert",
  "message_key": "diagnosis.result.answered",
  "result": {
    "problem": {"id": "corpus problem id", "pest_or_disease_id": "…", "code": "paddy_blast",
                "type": "disease", "crop_id": "…",
                "names": {"en": "Rice blast", "te": "…", "kn": "…", "hi": "…", "mr": "…"},
                "symptoms": {"en": ["Spindle-shaped spots with grey centres on leaves", "…"]}},
    "confidence": "high", "provisional": false, "can_buy": true, "cta": "buy",
    "message_key": "diagnosis.result.answered", "out_of_scope_reason": null,
    "visible_symptoms": [],
    "treatments": {
      "organic": [ProductOption…], "chemical": [ProductOption…],
      "cultural": {"en": ["…"], "te": ["…"]},
      "store": {"id": "…", "code": "WGL", "name": "FCC Warangal", "source": "village | nearest"}
    }
  },
  "final_problem_id": "…", "out_of_scope_reason": null, "flagged": false,
  "model_versions": {"encoder": "siglip-base-patch16-224@2024-01", "on_device": "…", "llm": null},
  "corpus_version": 7,
  "images": [{"blob_uri": "…", "sha256": "…", "quality": {…}, "signed_url": "https://… (15 min)"}],
  "captured_at": "…", "answered_at": "…", "reviewed_at": null,
  "created_at": "…", "updated_at": "…", "version": 3,
  "scores": null, "reviews": [], "reviewed_by": null, "llm_used": false
}
```

`ProductOption` (ranked, `rank` 1 = best):
`{rank, kind: organic|chemical, sku_id, product_id, product_name, brand, own_brand, pack_label,
active_ingredient, label_claim_id, efficacy_tier, dose_per_acre, dose_value, dose_unit,
dose_per_tank_15l, phi_days, ppe_text, safety_text, price_paise, mrp_paise, stock_qty, in_stock}`.
Pass `sku_id` + `label_claim_id` into the order line (FA-020 checks the claim again).

App rules (SPEC 3.4, FM-005):

* Show the confidence **as words** (`high` / `medium` / `low`), the `message_key` headline,
  the symptoms checklist in the user's language (fall back to `en`).
* **Buy button only when `can_buy` is true** (`answered`, `confirmed`, `corrected`). When
  `provisional`: show "provisional — expert will confirm", the treatments (dose, PHI, PPE,
  safety) and a **"Talk to your field officer"** CTA (`cta`), never a buy button. The farmer is
  notified when the agronomist confirms or corrects (`diagnosis_reviewed` notification).
* `out_of_scope`: no problem, no products; show `message_key` (`diagnosis.out_of_scope.
  not_a_plant | unsupported_crop | unreadable_image | no_match | expert_not_diagnosable`) and
  "ask an expert" — the case is already in the agronomist queue.
* Every chemical option shows dose per acre, dose per 15 L tank, PHI days, PPE and safety text
  (DX-009). `phi_days` is null for nutrients.

i18n keys the apps need: `diagnosis.result.{answered,provisional,unknown,confirmed,corrected}`,
`diagnosis.out_of_scope.{not_a_plant,unsupported_crop,unreadable_image,no_match,expert_not_diagnosable}`,
`diagnosis.cta.{buy,talk_to_field_officer,ask_expert}`, `diagnosis.confidence.{high,medium,low}`,
`notification.{diagnosis_ready,diagnosis_reviewed,diagnosis_queue_aged,diagnosis_llm_rate,data_request_received}.{title,body}`.

### Sync (offline capture, FA-025)

* `diagnosis` is a **sync entity** (conflict rule `server_wins`). Device writes: **create only**
  — `{"entity": "diagnosis", "action": "create", "entity_id": <client uuid>, "payload": <the
  POST body without id>}`; `client_ts` becomes `captured_at` unless the payload has one. Queue
  the op **after** the photo uploads completed (the server rejects missing blobs with
  `diagnosis_image_missing`). A replayed entity id answers `conflict` with the server row.
  `update` / `delete` are `rejected`.
* Change feed: the farmer receives their own diagnoses, a field officer their farmers' ones (and
  whatever they asked). `data` = `DiagnosisOut`; every status change (answered, provisional,
  reviewed) is a new change.

### Agronomist queue (console, WC-006)

`GET /v1/diagnoses/review-queue` (agronomist, owner) — unreviewed `provisional` /
`out_of_scope` diagnoses plus `ask_expert` ones, **oldest first**. Filters `crop_id`,
`confidence` (repeatable), `min_age_hours`, `flagged`; cursor pagination. Items are
`DiagnosisOut` + `scores` (neighbours, votes, candidates, thresholds, the LLM's answer and
reasoning), `reviews`, `age_hours`, `overdue` (> 18 h), signed photo URLs; `counts: {total,
overdue, by_confidence}`.

`POST /v1/diagnoses/{id}/review` (agronomist) `{action: confirm | correct | not_diagnosable,
problem_id?, note, add_to_corpus: bool}`:

* `confirm` keeps the label; `correct` sets `problem_id` (a corpus problem of the same crop);
  the result is rebuilt with treatments, `status` `confirmed` / `corrected`, `source
  agronomist`, `confidence high`, `can_buy true`;
* `not_diagnosable` closes an out-of-scope / unknown case without a label;
* `add_to_corpus` copies the photos into the corpus as `reviewed` images of that problem
  (embedded now, served only after approval, WC-007);
* the farmer (their login) and the officer get a `diagnosis_reviewed` notification; the
  action is appended to `diagnosis_review`.
* Problems: `404`, `409 diagnosis_not_reviewable` (still queued), `422 review_invalid`.

`GET /v1/diagnoses/thresholds` (agronomist, owner, director) → `{defaults, items[]}`;
`PUT /v1/diagnoses/thresholds {crop_id|null, t1, agreement, min_similarity, note}`
(agronomist) appends the next `config_version` for that crop (null = tenant default).

### Corpus manager (console, WC-007)

Agronomist writes; owner and director read (SPEC 2.6).

| Route | |
|---|---|
| `GET /v1/corpus/problems?crop_id=&status=&source=` | problems + `image_counts` by status + `corpus_version` |
| `POST /v1/corpus/problems` | `{pest_or_disease_id, crop_id, names{en required, te,kn,hi,mr}, symptoms{lang:[...]}, cultural_practices{lang:[...]}, source, notes}` → draft (409 `corpus_problem_exists`, 422 `corpus_problem_invalid`) |
| `GET/PATCH /v1/corpus/problems/{id}` | edit only draft / reviewed (409 `corpus_entry_locked`) |
| `POST /v1/corpus/problems/{id}/transition` | `{to, note}`: draft → reviewed → approved → retired (reviewed → draft allowed); 409 `invalid_transition` |
| `GET /v1/corpus/problems/{id}/images?status=` | images |
| `POST /v1/corpus/problems/{id}/images` | `{blob_uri (upload purpose "corpus"), sha256?, stage, part leaf|stem|fruit|whole, severity low|medium|high, region, season, source}` → draft image, embedding computed by the server (503 `encoder_unavailable`) |
| `POST /v1/corpus/images/{id}/transition` | same workflow for one image |
| `POST /v1/corpus/approvals` | `{problem_ids[], image_ids[], note}` — approve reviewed entries together: **one** corpus version bump |
| `GET /v1/corpus/versions` | `{current, items[{version, approved_by, note, changes{problems, images, retired}}]}` |

Approving (or retiring something served) bumps the version; approved rows record
`approved_by`, `approved_at`, `approved_in_version`. **Only approved problems with approved
images are ever used by the kNN** (tested).

### Data requests (farmer app settings FM-015, console NF-013)

* `POST /v1/me/deletion-request {reason?}` (any signed-in user) → **201** `{ticket_id, type:
  "deletion", status: "received", due_by, created_at}` (30 days); tenant admins get a
  `data_request_received` notification. While a request is open, a repeat answers **200** with
  the same ticket.
* `GET /v1/me/deletion-request` → the latest ticket (404 if none).
* `GET /v1/admin/data-requests?type=&status=` (owner, tenant admin) → tickets with `overdue`.
* `PATCH /v1/admin/data-requests/{id} {status: in_progress|completed|rejected, note?}`.
  The erasure itself is a reviewed manual operation (financial records are kept 8 years,
  NF-012). The same table carries `access` and `correction` requests (NF-013 groundwork).

## Encoder service contract (`ml/embed`, Cloud Run `embed`, ingress internal)

`POST {DIAGNOSIS_EMBED_URL}/v1/embed`, `Authorization: Bearer <OIDC identity token, audience
= the service URL>` (the worker / api service account is the invoker):

```json
{"model": "siglip-base-patch16-224", "version": "2024-01",
 "images": [{"b64": "<base64 of the JPEG bytes>"}]}
```

→ `200`

```json
{"model": "siglip-base-patch16-224", "version": "2024-01", "dim": 768,
 "vectors": [[0.0123, -0.044, …]]}
```

* One vector per image, in order, L2-normalised, `dim` 768.
* The service must refuse (`409`) a request whose `model` / `version` it does not serve; the API
  refuses any response whose model, version or dimension differs from the pinned settings
  (`DIAGNOSIS_ENCODER_NAME`, `DIAGNOSIS_ENCODER_VERSION`) — vectors of two encoders are never
  mixed. Changing the encoder = new version + full corpus re-embedding (DX-012).
* `GET /healthz` → 200. Batch up to 8 images; p95 < 1 s per image on CPU.

## LLM fallback (DX-004, SEC-027, NF-011)

`anthropic.AsyncAnthropic()` built once per process (credentials from the environment:
`ANTHROPIC_API_KEY` from Secret Manager); `DIAGNOSIS_LLM=claude|fake|off`,
`DIAGNOSIS_LLM_MODEL` (default `claude-opus-5`).

Request: `messages.create(model, max_tokens=16000, system=SYSTEM_PROMPT, messages=[user:
[image blocks…, text block]], output_config={"format": {"type": "json_schema", "schema": …},
"effort": "medium"})`; adaptive thinking left at the model default.

* Image blocks: `{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
  "data": …}}` — the JPEG is **re-encoded from pixels** (EXIF incl. GPS dropped, long edge ≤
  1568 px).
* Text block (the only context sent — never names, phones or ids):

```
Crop: Paddy
District: Warangal
Season: kharif
Crop stage: vegetative

Candidate problems (choose one id, or unknown):
- id <corpus problem uuid>: Rice blast / అగ్గి తెగులు. Key symptoms: …
… (top 5 by similarity)
```

* System prompt: `farmerapp.diagnosis.llm.SYSTEM_PROMPT` (choose one candidate or
  "unknown"; never a problem outside the list; photos without a plant → "unknown" with
  reasoning starting `NOT_A_PLANT:`).
* Schema (strict, all required, `additionalProperties: false`):
  `{problem_id: enum[<5 candidate ids>, "unknown"], confidence: enum[high, medium, low],
  reasoning: string, visible_symptoms: string[]}` — parsed with `json.loads`, validated with
  Pydantic.
* `stop_reason == "refusal"` → unknown (`stop_details` logged); `"max_tokens"` → one retry with
  32 000; invalid JSON / schema / id outside the candidates → one retry, then unknown.
* Errors: `RateLimitError`, `APIStatusError` ≥ 500 and `APIConnectionError` are temporary (the
  worker nacks, Pub/Sub retries with backoff; after `DIAGNOSIS_MAX_ATTEMPTS` = 5 deliveries the
  case becomes unknown → provisional + queue); other API errors → unknown.
* An LLM answer is at most `medium` confidence and always `provisional`.
* Every attempt is a row in `llm_call_log` (prompt without image bytes: blob URI, sha256 of the
  original and of the sent JPEG; raw output; parsed answer; model; latency; input / output
  tokens; stop reason / details; `retain_until` = +1 year). Log event `llm_call`.

Not enabled: the server-side refusal `fallbacks` beta (a refusal is simply "unknown" and goes to
the agronomist). Worth a product decision once real traffic shows the refusal rate.

## Decision rule and provenance (DX-003, DX-005)

Defaults (config version 0): T1 **0.92**, agreement **0.60** of the top-10, similarity floor
**0.85** (below → out of scope, no LLM call). They were tuned for the **fake** pixel encoder on
the synthetic seed (non-plant photos top out at ~0.80, variants of one problem at ≥ 0.96) and
**must be retuned per crop for the real encoder** from an `ml/eval` report (human gate).

`diagnosis.scores` stores `neighbours` (image, problem, similarity — the top 20), `thresholds`
(with `config_version`), `decision` (confidence, proposal, top-1, agreement, votes,
candidates), `llm` (status, answer, reasoning). `decision.replay(scores)` re-derives the same
decision (tested over random cases and on a stored diagnosis); `model_versions`,
`corpus_version`, `final_problem_id` and `source` complete the record.

## Operations (OPS-009, DX-006)

`python -m farmerapp.jobs diagnosis-queue-age --tenant <id|fcc>` (hourly; Cloud Scheduler
entry is an infra follow-up):

* `diagnosis_queue_aged` (WARNING) + a `diagnosis_queue_aged` notification to agronomists
  (owners if none) once per diagnosis older than **18 h** in the queue (`age_alerted_at`);
* `diagnosis_queue_snapshot` every run (`queue`, `overdue`, `oldest_hours`) — the business metric;
* re-delivery of `queued` diagnoses older than 15 min (lost message / publish failure);
* `diagnosis_llm_fallback_rate` every run (`answered`, `llm_fallbacks`, `rate` of the IST day);
  above **40 %** (≥ 5 answers) `diagnosis_llm_fallback_alert` (WARNING) and one
  `diagnosis_llm_rate` notification per day to agronomists and owners.

Other log events: `diagnosis_requested`, `diagnosis_answered` (`status`, `source`,
`confidence`, `llm_used`, `processing_ms`, `turnaround_ms` — the "< 5 s on 3G" SLI),
`diagnosis_reviewed`, `llm_call`, `llm_refusal`, `diagnosis_retry`, `data_request_received`.

## kNN benchmark (DX-002)

`FARMERAPP_SLOW=1 uv run pytest -m slow tests/diagnosis/test_knn_benchmark.py --no-cov -s`:
200 000 random 768-dim vectors over 6 crops, HNSW rebuilt as in 0027, 200 production queries
(app role under RLS, one crop, top 20). Result on the dev laptop: see docs/perf/M6-knn.md.

## Settings (environment; `.env.example` at the repo root is outside this branch's scope — add them there with the next root change)

`DIAGNOSIS_ENCODER` (`fake` | `remote`; prd requires `remote`), `DIAGNOSIS_ENCODER_NAME`,
`DIAGNOSIS_ENCODER_VERSION`, `DIAGNOSIS_EMBED_URL`, `DIAGNOSIS_EMBED_TIMEOUT_S`,
`DIAGNOSIS_LLM` (`claude` | `fake` | `off`; prd refuses `fake`), `DIAGNOSIS_LLM_MODEL`,
`DIAGNOSIS_LLM_MAX_TOKENS`, `DIAGNOSIS_LLM_EFFORT`, `DIAGNOSIS_DELIVERY` (`inline` | `pubsub`),
`DIAGNOSIS_KNN_K`, `DIAGNOSIS_HNSW_EF_SEARCH`, `DIAGNOSIS_MAX_ATTEMPTS`; `ANTHROPIC_API_KEY`
(Secret Manager).

## Human gates

* **Real field images** (SPEC 3.3 step 3): the seed corpus is `source = public` with
  **synthetic placeholder images**; officers photograph scouting cases, the agronomist labels
  weekly; 150+ approved field images per problem before a problem counts as high-confidence
  capable. Licensed public datasets may only bootstrap.
* **Encoder choice and deployment** of `ml/embed` (SigLIP / DINOv2), then **threshold
  retuning** per crop from an `ml/eval` run on the real held-out set.
* **Held-out test set** (`ml/eval/testset/pilot-*`), agronomist-labelled.
* **Translations**: Kannada / Marathi problem names and every non-English symptom checklist and
  cultural practice are machine-assisted or missing (English fallback) — native-speaker and
  agronomist review (NF-008).
* **`ANTHROPIC_API_KEY`** in Secret Manager for stg / prd; data-processing review of sending
  crop photos to the LLM provider (NF-011: images and crop context only).
* **Label claims** (CIB&RC data) still carry the seed `source_ref` (WC-005 gate) — treatments
  come only from approved claims.
* Infra (not in this branch): Cloud Scheduler for `diagnosis-queue-age`, the `diagnosis.requested`
  push subscription retry policy, `DIAGNOSIS_DELIVERY=pubsub` in stg / prd, log-based alerts
  on `diagnosis_queue_aged` / `diagnosis_llm_fallback_alert`.

## Tests

`tests/diagnosis/` (decision, encoder, LLM client, pipeline end to end, review / queue,
delivery + worker + sync, corpus manager, treatments, seed + schema, evaluation script, the
slow kNN benchmark), `tests/ops/test_diagnosis_watch.py`, `tests/privacy/`, authz matrix
fixtures for all 21 new operations, RLS meta-test (automatic for the 8 new tables). `SKIP_AUDIT=1 make check-api`: 3258 passed + 1 serial, 2 skipped (the slow benchmark and an integration case), coverage 97.06 %, wall clock 14 min.
