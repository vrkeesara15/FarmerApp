# ml/eval — test sets and evaluation

Owner: agronomy + ML. Milestone: M6 (DX-003, DX-010, DX-011).

- `evaluate.py` (M6-KICKOFF, done): runs the production decision path in-process
  (`farmerapp.diagnosis.pipeline.decide_case`: embed → pgvector kNN → DX-003 decision rule →
  DX-004 LLM fallback) over a manifest against a tenant's approved corpus, in a rolled-back
  transaction, and writes a JSON report: top-1 accuracy per crop and per problem, corpus-answer
  share, LLM share, escalation rate (provisional + out of scope), hallucinated labels on the
  out-of-scope slice (DX-010). Usage and flags: see the module docstring.
- `testset/`: layout and rules of the held-out, agronomist-labelled field sets
  (`testset/README.md`); `testset/ci/manifest.csv` is a tiny synthetic set run in CI
  (`apps/api/tests/diagnosis/test_evaluate.py`). Real field images are not committed.
- `reports/`: output of local runs (not committed). The evaluation logic itself lives in
  `apps/api/farmerapp/mlops/evaluation.py` (this script is its CLI), so the nightly job runs
  exactly the same code in-process.
- **Nightly job (DX-011, M7, done):** `python -m farmerapp.jobs diagnosis-evaluate --tenant …`
  (Cloud Scheduler 01:00 IST) reads the held-out manifest from the corpus bucket
  (`CORPUS_BUCKET` + `DIAGNOSIS_EVAL_MANIFEST`, default `eval/heldout/manifest.csv`; image paths
  are relative to the manifest), evaluates in a rolled-back savepoint and writes an
  `evaluation_run` row with the metrics per crop and per problem. A top-1 drop of more than 5
  points against the previous successful run logs `diagnosis_eval_accuracy_drop` and notifies the
  agronomists and owners. The console reads `GET /v1/diagnoses/quality` and
  `GET /v1/diagnoses/evaluations` (AN-007).
  **Human gate:** upload the agronomist-labelled held-out set to that manifest path (real field
  images are never committed); until then the job records a failed run.

Still to do:

- Threshold tuning for DX-003 (T1 cosine, 60 % top-10 agreement, similarity floor) per crop for
  the real encoder, from a run on the real held-out set, written through
  `PUT /v1/diagnoses/thresholds` (versioned, audited) — human gate.
- The held-out field set itself (agronomist-labelled, in the corpus bucket) and the console
  screen for the evaluation history (AN-007 dashboard).
