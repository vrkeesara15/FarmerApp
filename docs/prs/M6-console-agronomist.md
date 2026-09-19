# M6 — console: agronomist review queue, corpus manager, basic diagnosis quality (WC-006, WC-007)

Branch `feat/M6-console-agronomist` (from `main` f23e287). Console half of WC-006 / WC-007 on top of
the API contract in `docs/prs/M6-diagnosis-api.md`. Only `apps/console`, `design/` and `docs/`
changed.

## Screens

| Screen | Route | What |
|---|---|---|
| C60 review queue (`design/screens/C60.md`) | `/agronomist` | Provisional / out-of-scope / flagged diagnoses oldest first; age and live SLA badge (DX-006: warning from 18 h or API `overdue`, breach at 24 h); filters crop / confidence / age / flagged; detail with photo gallery (signed URLs, zoom), farm context limited to crop / district / season / stage, model candidates (similarity, votes, vote share, corpus and LLM picks, thresholds + config version), the LLM answer and reasoning labelled **"Automated suggestion — verify"**, provenance (source, encoder, on-device model, LLM model, corpus version), review history; confirm / correct (problem picker of the crop, searchable in every language) / not diagnosable, note, "add these photos to the corpus"; after submit "The farmer and their field officer have been notified." with the farmer's new result. |
| C61 corpus manager (`design/screens/C61.md`) | `/agronomist/corpus` | "Only approved entries are used in production" banner with the corpus version; problems table per crop with status chips and served-image counts; "Show what production uses" filter; create / edit (names, symptoms and cultural practices in five languages, type from the pest); images grid with chunked upload then attach, embedding status (encoder@version), per-image metadata; draft -> reviewed -> approved -> retired buttons by role and state; approval dialog as the regulatory human gate (explicit "I have verified this entry", optional "also approve the n reviewed images" = one `/v1/corpus/approvals` = one version bump); retire; version history. |
| C62 diagnosis quality (`design/screens/C62.md`) | `/agronomist/quality` | Basic cards computed in the browser from the review queue and the last 30 days of `GET /v1/diagnoses` (no summary endpoint): answered by corpus, escalation rate, reviewed within 24 h, queue now; by-source and queue-age bars; top unknowns. Marked as interim: AN-007 (M7) replaces it (and adds test-set accuracy). |

Role-based nav (`lib/nav.ts` `AGRONOMIST_ROLES`): agronomist and owner see "Agronomist"; owners get
a read-only note and no review form / workflow / upload / create controls; every other role is
hidden (and gets the ForbiddenState if they type the URL). The API enforces the same.

## Code

* `lib/diagnosis.ts` (types, `reviewSla`, `candidateRows`, `validateReview`, `reviewBody`, calls),
  `lib/corpus.ts` (types, `CORPUS_TRANSITIONS` mirror, `corpusActions`, `isEditable`,
  `bumpsVersion`, `servedImageCount`, `matchesProblem`, calls), `lib/uploads.ts` (chunked
  upload: whole-file sha256, 256 KB chunks with `X-Chunk-Sha256`, resume from
  `received_chunks`, complete), `lib/diagnosis-quality.ts` (`summariseQuality`),
  `lib/hooks/diagnosis.ts` (TanStack Query).
* `components/agronomist/*` (ReviewQueue, Evidence, PhotoGallery, ReviewForm, CorpusManager,
  ProblemDialog, QualityView, common).
* Mock API `lib/mock/diagnosis.ts` (payloads shaped like the OpenAPI schemas: `ReviewQueuePage`,
  `DiagnosisDetailOut` with `scores` / `reviews`, `CorpusProblemOut`, `CorpusImageOut`,
  `CorpusVersionsOut`; problem codes `review_invalid`, `diagnosis_not_reviewable`,
  `invalid_transition`, `corpus_entry_locked`, `corpus_problem_exists`, `corpus_image_exists`,
  `chunk_sha_*`, `upload_*`) and `/v1/uploads*` (raw chunk bytes; the route handler now reads
  the body once as bytes). Crop / pest ids are the catalogue mock's.
* Problem codes -> messages in `lib/problem-messages.ts`; ~200 strings in `messages/en.json`
  with te / kn / hi / mr translations (`agronomist.*`, `queue.*`, `review.*`, `corpus.*`,
  `quality.*`, `problems.*`).

## Tests

* vitest: `lib/diagnosis.test.ts` (SLA countdown 18 / 24 h, candidates and vote share,
  review validation: correct requires a problem different from the label), `lib/corpus.test.ts`
  (workflow action availability by role and state), `lib/diagnosis-quality.test.ts`,
  `lib/mock/diagnosis.test.ts` (queue order / roles, correction rebuilds the result and adds
  reviewed images, workflow + version bump, approvals, chunked upload + attach),
  `components/agronomist/Agronomist.test.tsx` (candidate rendering, LLM label, provenance,
  review form), `lib/nav.test.tsx` (agronomist / owner visible, others hidden).
* Playwright `e2e/agronomist.spec.ts`: queue -> open provisional -> correct -> notified;
  corpus create -> upload (mocked) -> draft -> reviewed -> approved with the version bump ->
  production filter shows only approved -> retire; owner read-only across C60-C62.
  `e2e/smoke.spec.ts`: `/agronomist*` are now data screens (signed out -> sign-in prompt)
  instead of the placeholder EmptyState.
* `npm run check` green (lint + string lint, typecheck, 310 vitest, build); `npm run
  test:e2e` 27 passed.

## API gaps / follow-ups (for the API worktree)

1. **Agronomists cannot upload corpus images yet**: `farmerapp/uploads/router.py`
   `UPLOAD_ROLES` (and `x-roles` of `initUpload` / `putUploadChunk` / `completeUpload`) lacks
   `agronomist`, although `POST /v1/corpus/problems/{id}/images` requires an upload with
   purpose `corpus` and is agronomist-only. The console codes against the contract; the mock
   allows the agronomist. Add `Role.AGRONOMIST` to `UPLOAD_ROLES` (plus authz matrix rows).
2. No diagnosis quality summary endpoint and no date filter on `GET /v1/diagnoses`: C62 pages
   up to 1,000 recent rows client-side. AN-007 (M7) should add a server summary.
3. The review response does not list who was notified; the console states the contract
   ("farmer and their field officer"). A `notified: [role]` field would let it be exact (a
   farmer without an app login gets no notification today).
4. The review queue item has no candidate names; the console joins `GET /v1/corpus/problems`
   (readable by agronomist / owner).

## Human gates

None new. Translations of the new console strings are machine-assisted (NF-008 native-speaker
review), like the rest of the console catalogue.
