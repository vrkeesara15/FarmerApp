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
- `reports/`: output of local runs (not committed).

Still to do:

- Threshold tuning for DX-003 (T1 cosine, 60 % top-10 agreement, similarity floor) per crop for
  the real encoder, from a run on the real held-out set, written through
  `PUT /v1/diagnoses/thresholds` (versioned, audited) — human gate.
- Nightly evaluation job (`nightly-evaluation`, Cloud Run Job), report in the console and an
  alert when top-1 accuracy drops more than 5 points (DX-011, P1).
