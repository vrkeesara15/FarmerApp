# ml/eval — test sets and evaluation

Owner: agronomy + ML. Milestone: M6 (DX-003, DX-010, DX-011).

Planned content (SPEC 3):

- `testset/`: held-out, agronomist-labelled field images per crop × problem, plus a non-plant / unsupported-crop
  set (DX-010). Stored as manifests (image URI in the corpus bucket, label, district, season, labeller); no images
  committed to git.
- `evaluate.py`: runs the full pipeline (embed → kNN → decision rule → LLM fallback) over the test set and reports
  top-1 / top-5 accuracy, "unknown" rate, LLM fallback rate and corpus-vs-LLM agreement, per crop and problem.
- Threshold tuning for DX-003 (T1 cosine, 60% top-10 agreement) with per-crop overrides written to the config table.
- Nightly evaluation job (`nightly-evaluation`, Cloud Run Job) publishes the report to the console and alerts when
  top-1 accuracy drops more than 5 points (DX-011).
