# ml/pipelines — DX-012 retraining pipelines (Vertex AI, as code)

Owner: ML + platform. Milestone: M7 (DX-012). **Nothing here runs from CI or from an agent**:
the pipelines are compiled and committed; submitting them to Vertex AI Pipelines and building the
training image are human steps (SPEC 14.6 / CLAUDE.md "Never do").

| File | What |
|---|---|
| `retrain_pipeline.py` | the two pipelines as KFP v2 code (the source of truth) |
| `compiled/ondevice_monthly_finetune.yaml` | compiled `ondevice-monthly-finetune` |
| `compiled/encoder_reembed.yaml` | compiled `encoder-reembed` |

```sh
make compile   # recompile the YAML from the Python (kfp 2.13, no project venv needed)
make check     # compile into a temp directory and diff against compiled/ (CI-safe)
```

## ondevice-monthly-finetune (DX-012 monthly fine-tune)

1. **export-training-set** — the Cloud Run job of the API image writes the tenant's approved
   corpus field images as `gs://<corpus>/training/<tenant>/<YYYYMMDD>/manifest.csv`
   (`farmerapp.mlops.training_export`; also runs weekly on its own schedule).
2. **finetune-and-export** — the `ml/ondevice` training image mirrors the referenced images,
   runs `finetune.py` (sha256-checked field images cached, merged with the public bootstrap
   manifest, the previous model fine-tuned) and `export.py` (int8 TFLite + `metadata.json` with
   the evaluation numbers, the next `model_version` and the training manifest URI), then uploads
   `model.tflite`, `metadata.json` and `model.keras` to
   `gs://<corpus>/models/on-device/<version>/`.
3. **register-model-candidate** — the API job records a `model_release` **candidate** (the
   sha256 is computed from the uploaded bytes, never trusted from the metadata) and notifies the
   agronomists and owners.

**Approval gate (in the API, not in Vertex):** an agronomist or the owner approves or rejects the
candidate with `POST /v1/models/releases/{id}/decision` (step-up, audited; a candidate without
evaluation numbers cannot be approved). Apps download only the newest **approved** release from
`GET /v1/models/on-device/current` and verify its sha256.

Parameters: `project`, `region`, `tenant_id`, `corpus_bucket`, `export_date` (`YYYYMMDD`),
`base_model_uri` (the previous `model.keras` in the corpus bucket), `base_version`
(`ondevice-v1.0`). The training image is `ONDEVICE_IMAGE` at compile time.

## encoder-reembed (DX-012 re-embedding)

1. **reembed-corpus** — stages every live corpus image's vector under the new encoder
   (`corpus_embedding`); diagnoses are unaffected, and the kNN can already answer from the
   staged vectors if the API pin moves first.
2. **diagnosis-evaluate** — the DX-011 held-out evaluation, so the agronomist sees the accuracy
   before the flip.

**Human gate:** retune the DX-003 thresholds (`ml/eval`), move `DIAGNOSIS_ENCODER_NAME` /
`DIAGNOSIS_ENCODER_VERSION`, then run `python -m farmerapp.jobs activate-encoder` (one
transaction; the previous vectors are kept, so activating the old version again is the rollback).

## Human gate: wiring Vertex AI

Not done by an agent, and deliberately not in Terraform yet:

1. build and push the `ml/ondevice` training image (TensorFlow 2.21 + `uv` + `gcloud`) to
   Artifact Registry, and set `ONDEVICE_IMAGE` when compiling;
2. enable `aiplatform.googleapis.com`, create the pipeline service account and grant it
   `roles/run.developer` on the `export-training-set` and `diagnosis-evaluate` jobs,
   `roles/storage.objectUser` on the corpus bucket and `roles/aiplatform.user`;
3. upload `compiled/*.yaml` and create the monthly schedule (Vertex AI Pipelines scheduler);
4. record the run name in the candidate (`--pipeline-run`, already passed by the pipeline).

Until then the same three steps can be run by hand: the two API jobs
(`gcloud run jobs execute … --args=…`) and `make train` / `make export` in `ml/ondevice`.
