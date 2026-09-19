# M6 — on-device plant, quality and crop classifier (DX-001)

Branch `feat/M6-ondevice-model` (from `main` at `d6aedeb`). Only `ml/ondevice/` and `docs/`
changed. Nothing under `apps/`, `infra/` or `.github/` was touched.

PR title: `feat(DX-001): on-device plant, quality and crop classifier pipeline with int8 TFLite
export under 8 MB`

## Requirement IDs

| ID | Status after this PR |
|---|---|
| DX-001 | in-progress. Pipeline, model and artefact are done. Human gates: < 400 ms on a 2 GB phone, field-image accuracy, legal check of the ImageNet weights. Mobile wiring and the API field are separate tasks. |
| DX-005 | todo. `metadata.json` is the on-device model version record; the proposed `on_device` request block is in `ml/ondevice/INTEGRATION.md` §5. |
| DX-012 | todo. The pipeline is ready to take the field manifest and the monthly fine-tune. |

## What changed

- **Environment**: `ml/ondevice/pyproject.toml` + `uv.lock` + `.python-version` (3.12).
  TensorFlow 2.21 (native macOS arm64 wheel, no `tensorflow-macos`), Keras 3.15, `ai-edge-litert`
  2.2 (LiteRT interpreter; `tf.lite.Interpreter` is deprecated), pyarrow, pillow, pytest. Ruff
  config included. Why TF rather than PyTorch + ai-edge-torch: one toolchain end to end, and a
  mature int8 PTQ path for multi-output graphs (README §Toolchain).
- **Data**:
  - `data/sources.json` pins 8 public datasets (Hugging Face revision + sha256, all CC-BY-4.0,
    attribution recorded) plus generated negatives.
  - `data/download.py` is idempotent, checks sha256, and writes to the git-ignored `data/raw/`.
  - `data/prepare.py` does a seeded capped sample, caches 256×256 JPEGs and writes
    `data/manifest.csv`. The split is a stable hash of (source, key).
  - Result: 13,832 images. Train 9,759 / val 2,007 / test 2,066.
  - One dataset per crop: paddy (Odisha), cotton (Bangladesh), chilli (Karnataka), tomato + maize
    (+ onion → other) from TOM2024 (Burkina Faso), groundnut (West Bengal), blackgram + banana →
    other. Caltech-101 without plant classes, plus 600 generated frames, is "not a plant".
- **`ondevice/`**: `config.py` holds the frozen label order, output layout, thresholds and train
  config. `manifest.py` holds the rows, validation and split. `data.py` is the tf.data pipeline:
  lighting / crop / flip / rotation augmentation, and deterministic blur / motion-blur / dark
  transforms that give exact quality labels. `model.py` has the MobileNetV2 backbone with
  `plant` / `quality` / `crop` heads, the `[1, 11]` export wrapper, masked class-weighted losses,
  and `fold_dead_se_channels` for the V3 path.
- **`train.py`** trains in two stages (frozen backbone, then the top 5 blocks with frozen BN), with
  checkpoints on val loss. **`eval.py`** reports per-head accuracy, balanced accuracy and confusion
  matrices on the test split, plus the retake gate and coverage at `crop_min`. It works on Keras
  or TFLite.
- **`export.py`** does full-int8 PTQ over 300 train images: uint8 input (scale 1, zero point 0),
  float32 `[1, 11]` output. It enforces < 8 MB, runs the TFLite test-split eval, fails if int8 loses
  more than 3 points on any head against the float model, and writes `metadata.json`. The metadata
  holds name, version, sha256, input / output contract, label order, thresholds, data sources +
  licences + per-split counts, date, git SHA, training config and evaluation.
- **`bench.py`**: LiteRT / XNNPACK latency on 1 and 4 threads, plus Pillow preprocessing time.
- **`tests/`** (22): label order and output layout frozen; sources pinned and licensed with every
  crop covered; split stable and proportional; manifest validation and round trip; degradations
  (blur lowers Laplacian variance, dark hits the luminance target, deterministic per seed);
  dataset shapes and masks; class weights; export shapes; dead-SE folding preserves the function;
  end-to-end int8 conversion loads under XNNPACK; the shipped artefact is < 8 MB with the right
  I/O and its sha256 matches the metadata.
- **`Makefile`**: `setup data train eval export bench test all`.
- **Docs**: `ml/ondevice/README.md` (model, data, results, choices), `INTEGRATION.md` (the mobile /
  API contract: asset path, preprocessing, decoding, retake rule, `crop_detected_on_device` +
  `on_device` block for `POST /v1/diagnoses`, Laplacian fallback), `BENCHMARK.md` (device
  procedure, human gate), `docs/progress.md` DX-001.
- **Committed artefacts** (`ml/ondevice/artifacts/`): `crop_quality_v1.tflite` (3,001,256 bytes),
  `metadata.json`, `eval_tflite.{md,json}`, `bench_mac.json`. Datasets, cache, manifest and runs are
  git-ignored.

## Results (full path run on this branch: data → train → eval → export → bench → test)

| Head | float | int8 TFLite (shipped) |
|---|---|---|
| plant | 99.56 % | 99.42 % |
| quality (ok / blurry / dark) | 99.07 % | 98.01 % |
| crop (7 classes) | 97.56 % | 97.24 % (balanced 97.69 %) |
| retake gate | 99.21 % | 98.13 % (1.1 % false retakes on good photos) |

- Size 3.00 MB. Latency on an Apple M5, LiteRT 2.2 with XNNPACK: 2.94 ms mean on 1 thread,
  2.04 ms on 4 threads.
- Training: 26 min on the M5 CPU.

## Design decisions

- **MobileNetV2 instead of MobileNetV3-Small.** V3-Small was built and trained first (1.4 MB;
  float 99.9 / 99.4 / 97.8 %). int8 PTQ dropped it to 88.8 / 81.1 / 80.2 %. Calibration size and
  mix, the old quantiser, and removing the early tap did not help. `tfmot` QAT does not support
  Keras 3. The Keras ImageNet V3 weights also have dead squeeze-excite blocks (all 32 channels in
  `expanded_conv_6`), which make XNNPACK reject the int8 graph (requantisation scale ≥ 256).
  `fold_dead_se_channels` fixes that exactly and is tested. MobileNetV2 loses ≤ 1.1 points.
- **Quality is learned, and the Laplacian heuristic stays as the fallback.** Synthetic transforms
  give exact labels. One pass decides blur, darkness and leaf presence, and the heuristic can't tell
  a sharp wall from a sharp leaf. The retake rule checks quality before plant presence, and dark
  wins over blurry, as in NF-004.
- **Single `[1, 11]` float output.** Multi-output TFLite tensor order is not stable across
  converters. One tensor with a documented, test-pinned layout is robust for `tflite_flutter`.
- **Crop hint is a hint.** `crop_min` 0.6 gives 96.4 % coverage at 98.8 % accuracy on the public
  test split. Below the threshold it sends `null`. The user's crop choice stays the source of
  truth, and the hint ships behind a flag until the field gate passes.

## Human gates

1. **Latency**: < 400 ms on a 2 GB RAM reference phone. Procedure: `ml/ondevice/BENCHMARK.md`
   (`benchmark_model` via adb, plus the in-app timing screen).
2. **Field accuracy**: every crop comes from one public dataset, so the crop head partly learns
   the dataset. SPEC 3 expects 20–50 points lower on field photos. This needs agronomist-labelled
   pilot photos (≥ 50 per crop + other + not-a-plant), an eval, and a threshold re-tune.
3. **Legal**: ImageNet-pretrained weights in a commercial app.

## Test evidence

- `cd ml/ondevice && uv run --frozen pytest`: 22 passed.
- `uvx ruff check .`: clean.
- Full path logs are summarised above. The exact reports are in
  `ml/ondevice/artifacts/eval_tflite.md` and `bench_mac.json`.
- `make check` (repo root) covers api / console / mobile / infra, none of which changed here. The
  ml suite is run on its own (above). `metadata.json.git_sha` records the base commit plus
  `-dirty`, because the artefact was exported before this commit.

## Migration notes

- [ ] Alembic migration: n/a
- [ ] RLS / tenant_id: n/a
- [ ] OpenAPI: unchanged. The `POST /v1/diagnoses` fields are a proposal for DX-005.
