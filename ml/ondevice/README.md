# ml/ondevice — on-device plant, quality and crop model (DX-001)

Owner: ML. Milestone: M6 (DX-001), monthly fine-tune M7+ (DX-012).

One small int8 TFLite network runs on the phone before a crop-doctor photo is uploaded (SPEC 3,
flowchart step B). It answers three questions:

| Head | Output | Used for |
|---|---|---|
| `plant` | sigmoid p(leaf / plant present) | "not a plant" retake |
| `quality` | softmax over `ok`, `blurry`, `dark` | "blurry" / "dark" retake tips |
| `crop` | softmax over `paddy`, `cotton`, `chilli`, `maize`, `tomato`, `groundnut`, `other` | `crop_detected_on_device` |

Shipped artefact: [`artifacts/crop_quality_v1.tflite`](artifacts/) (under 8 MB) and
[`artifacts/metadata.json`](artifacts/metadata.json) (model name and version, input and output
contract, label order, thresholds, data sources and licences, date, git SHA, test-split accuracy).
The mobile contract is in [INTEGRATION.md](INTEGRATION.md). How to measure latency on the reference
phone is in [BENCHMARK.md](BENCHMARK.md).

## Commands

Run these from this directory. You need `uv`; Python 3.12 is pinned in `.python-version`.

```sh
make setup    # uv sync --frozen: TensorFlow 2.21 (native macOS arm64 wheel), LiteRT 2.2, pyarrow, pillow
make data     # data/download.py (pinned HF revisions, sha256-checked, ~1.4 GB) + data/prepare.py
make train    # train.py -> runs/latest/model.keras (26 min on an Apple M5 CPU, no GPU)
make eval     # eval.py -> runs/latest/eval_keras.{json,md}
make export   # export.py -> artifacts/crop_quality_v1.tflite + metadata.json + eval_tflite.{json,md}
make bench    # bench.py -> artifacts/bench_mac.json
make test     # pytest: data pipeline, label order, export size, interpreter shapes
```

## Toolchain choice

- **TensorFlow 2.21 + Keras 3 for training, `tf.lite.TFLiteConverter` for export, `ai-edge-litert`
  2.2 (LiteRT) for the interpreter.** TF 2.21 ships native `macosx_12_0_arm64` wheels for
  cp312, so `tensorflow-macos` isn't needed. Training runs on the CPU; no Metal plugin is needed.
  `tf.lite.Interpreter` is deprecated, so evaluation, benchmark and tests use
  `ai_edge_litert.interpreter.Interpreter`, the same runtime the app gets. The runtime applies
  XNNPACK by default.
- PyTorch + `ai-edge-torch` was considered. It adds a second framework, and its int8 PTQ path goes
  through PT2E export, which is less mature for multi-output mobile models. The TF path is one
  toolchain end to end.
- Keras-3 models are exported through `keras.export.ExportArchive` to a SavedModel, then
  converted. Converting a concrete function directly leaves resource variables in the graph, and
  calibration then fails.

## Model

- 224×224 RGB input, **MobileNetV2 (α 1.0, ImageNet init)** backbone, three heads. The quality head
  also sees globally pooled features from the 28×28 `block_5_add` map, because blur and exposure are
  low-level cues.
- **Why not MobileNetV3-Small** (the first candidate, 1.4 MB): hard-swish + squeeze-excite do not
  survive int8 post-training quantisation. On this task it trained to 99.9 / 99.4 / 97.8 % (plant /
  quality / crop) in float and fell to 88.8 / 81.1 / 80.2 % in int8. Different calibration sets,
  sizes and quantisers did not help, and dropping the quality head's early tap didn't either.
  Quantisation-aware training would fix it, but `tensorflow-model-optimization` does not support
  Keras 3. Its ImageNet weights also contain dead squeeze-excite blocks that make XNNPACK refuse
  the int8 graph. `ondevice/model.py::fold_dead_se_channels` repairs that without changing the
  function, and is kept for a later V3 / QAT path. MobileNetV2 quantises within about a point per head
  (the export gate fails above 3 points).
- **Quality stays a learned head, with the Laplacian heuristic as a fallback.** Labels come from
  known transforms (Gaussian and motion blur, under-exposure with sensor noise, see
  `ondevice/data.py::degrade`), so they are exact and free. One model pass covers blur, darkness
  and leaf presence together, and the heuristic can't tell "a sharp photo of a wall" from "a sharp
  photo of a leaf". The existing `LaplacianQualityModel` stays as the fallback when the model can't
  load (INTEGRATION.md). The app should keep logging its `blur_score` next to the model's
  scores so field photos can recalibrate both.
- Training has two stages: heads on a frozen backbone (4 epochs), then the last 5 inverted-residual
  blocks are unfrozen with BatchNorm frozen (8 epochs, cosine LR, AdamW). The loss is masked,
  class-weighted cross-entropy with label smoothing 0.05: non-plant rows have no crop label, and
  synthetic flat frames have no blur label. Augmentation: random scale crop, flips, 90° turns,
  ±20° rotation, brightness / contrast / saturation / hue jitter, then the quality transform
  (22 % blurry, 18 % dark). Seeds are fixed (`TrainConfig.seed`). Runs are seeded but not
  bit-exact on CPU.
- Export uses full-integer PTQ over 300 train images (3/5 ok, 1/5 blurry, 1/5 dark). Input is
  uint8 with scale 1 and zero point 0 (raw pixels). Output is float32 `[1, 11]`.

## Results (`ondevice-v1.0`, held-out test split of the public data, 2,066 images)

| Head | float (Keras) | **int8 TFLite (shipped)** | int8 drop |
|---|---|---|---|
| plant (plant vs not) | 99.56 % | **99.42 %** | 0.15 pt |
| quality (ok / blurry / dark, 6,042 frames) | 99.07 % | **98.01 %** | 1.06 pt |
| crop (7 classes, plant rows) | 97.56 % | **97.24 %** (balanced 97.69 %) | 0.31 pt |
| retake gate (use vs retake) | 99.21 % | **98.13 %** (1.1 % false retakes on good photos) | |

Size: 3.00 MB (DX-001 limit 8 MB). Mac latency: 2.9 ms single thread under XNNPACK
(BENCHMARK.md). Confusion matrices: `artifacts/eval_tflite.md`.

## Data (SPEC 3.3: public data only for bootstrapping, `source=public`)

`data/sources.json` pins each dataset to a Hugging Face revision and sha256. Everything is
CC-BY-4.0 except the generated negatives. Attributions are in `sources.json` and `metadata.json`.

| Crop / class | Source | Origin |
|---|---|---|
| paddy | Rice Leaf Disease Image Samples (Sethy 2020), doi:10.17632/fwcj7stb8r.2 | Odisha, India |
| cotton | SAR-CLD-2024 (Bishshash 2024), doi:10.17632/b3jy2p6k8w.2 (raw config) | Bangladesh |
| chilli | COLD chilli (Aishwarya & Reddy 2024), doi:10.17632/tf9dtfz9m6.2 (raw, 532 images) | Karnataka, India |
| tomato, maize, onion→other | TOM2024 (Appiah 2024), doi:10.17632/3d4yg89rtr.1 | Burkina Faso |
| groundnut | Groundnut leaf dataset (Sasmal 2024), doi:10.17632/x6x5jkk873.2 | West Bengal, India |
| other | Blackgram BPLD (Talasila 2022), Banana leaf (Hailu 2021) | Andhra Pradesh, Ethiopia |
| not a plant | Caltech-101 minus plant categories and the Google background set (CaltechDATA, doi:10.22002/D1.20086) + 600 generated frames (flat, gradient, soil, sky, covered lens, wall) | — |

The backbone starts from the `keras.applications` ImageNet weights. The Keras code is Apache-2.0,
but the weights were trained on ImageNet, whose terms are research-oriented. Before release, legal
should confirm this is acceptable for a commercial app (human gate), or the backbone should be
re-initialised from a permissively licensed checkpoint.

Each source is capped (1,500 per crop, 2,500 Caltech) by a seeded shuffle, cached at 256×256 and
split 70/15/15 by a stable hash of (source, image key). Datasets, cache, manifest and runs are
never committed (`.gitignore`).

**What the accuracy numbers mean.** Every pilot crop comes from exactly one public dataset, each
with its own camera, background and framing. On the held-out split, the crop head partly
recognises the dataset rather than the crop. SPEC 3 expects lab-to-field drops of 20–50 points.
Read these numbers as proof that the pipeline works, not as field accuracy. The accuracy gate
needs pilot field images (human gate, see docs/progress.md DX-001).

## Next steps

- Dataset manifest over the field corpus bucket (`farmerapp-<env>-corpus`), split by
  district / season so photos of the same farm never straddle splits (replace the `key` in
  `ondevice/manifest.py`). Public images stay tagged `source=public`.
- Monthly fine-tune as a Vertex AI pipeline with an approval gate (DX-012). Acceptance: no top-1
  drop > 5 points on `ml/eval/testset`.
- Each new artefact is copied into `apps/mobile/packages/core/assets/models/` by a PR and is never
  hot-loaded. Bump `MODEL_VERSION` (`ondevice-v<major>.<minor>`) when labels or the output layout
  change (major) or the weights change (minor).
