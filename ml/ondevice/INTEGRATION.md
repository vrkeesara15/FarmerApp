# DX-001 integration contract — mobile (FM-004 crop doctor, A41 scouting) and API (DX-005)

Model `crop_quality`, version **`ondevice-v1.0`**, file `crop_quality_v1.tflite`. The authoritative
values are in `artifacts/metadata.json`. The app should read labels, layout and thresholds from
that file rather than hard-coding them.

## 1. Asset path (for the mobile team)

Copy both files, unchanged, in the same PR:

```
ml/ondevice/artifacts/crop_quality_v1.tflite  ->  apps/mobile/packages/core/assets/models/crop_quality_v1.tflite
ml/ondevice/artifacts/metadata.json           ->  apps/mobile/packages/core/assets/models/crop_quality_v1.metadata.json
```

Register `assets/models/` under `flutter: assets:` in `packages/core/pubspec.yaml`, and load the
files with `rootBundle` (via `tflite_flutter`'s `Interpreter.fromAsset` or the buffer API). Never
download or hot-load a model: a new model always ships in an app release (ml/ondevice/README.md).
After copying, check the SHA-256 of the asset against `metadata.json.sha256` in a unit test.

This file is the only change in this repo that concerns `apps/mobile`. The Dart integration is a
separate task.

## 2. Input preprocessing

Start from the processed photo (`PhotoProcessor` output: EXIF-oriented, long edge 1280, RGB):

1. Take the centred square whose side is **0.875 × the short edge**. Training cached a square at
   256 px and evaluation centre-crops 224 of it, so 224/256 = 0.875.
2. Resize that square to **224 × 224**. Use area / average (`img.Interpolation.average`) or
   bilinear.
3. Write the pixels as **uint8 RGB, NHWC, `[1, 224, 224, 3]`**, row-major, R then G then B. Do
   **not** normalise: the tensor is `uint8` with scale 1 and zero point 0, and the model rescales
   internally. Do not use BGR, and do not pass float.

This runs off the UI thread (`compute`), like `LaplacianQualityModel`.

## 3. Output decoding

One output tensor, **float32 `[1, 11]`**, laid out as:

| index | name | meaning |
|---|---|---|
| 0 | `plant` | p(leaf / plant present), sigmoid |
| 1–3 | `quality_ok`, `quality_blurry`, `quality_dark` | softmax, sums to 1 |
| 4–10 | `crop_paddy`, `crop_cotton`, `crop_chilli`, `crop_maize`, `crop_tomato`, `crop_groundnut`, `crop_other` | softmax, sums to 1 |

The crop codes match the catalogue crop codes. The label order is frozen for the `v1` major
(`tests/test_labels.py`).

## 4. Retake rule and thresholds (`metadata.json.thresholds`)

| threshold | value | rule |
|---|---|---|
| `dark_min` | 0.5 | `quality_dark >= dark_min` → retake, tip `photo.tip.dark` |
| `blurry_min` | 0.5 | else `quality_blurry >= blurry_min` → retake, tip `photo.tip.blurry` |
| `plant_min` | 0.5 | else `plant < plant_min` → retake, tip **`photo.tip.not_plant`** (new key: "Point the camera at the leaf"; needs ARB strings in all 5 languages) |
| `crop_min` | 0.6 | if the photo is accepted: top crop probability `>= crop_min` → `crop_detected_on_device = <label>`; below it → `null` |

- Check quality before plant presence, because a dark or blurred frame can't be judged for leaf
  presence. Dark wins over blurry, as in the heuristic.
- The on-device crop is a **hint**. The crop the user picked, or the crop of the plot, stays the
  source of truth. `other` is a valid detection ("not a pilot crop"). Pre-select the detected crop
  in the picker. Never overwrite the user's choice.
- These thresholds are set on public data. They are re-tuned on pilot field photos (see §7) and ship
  in `metadata.json`, so a threshold change is a new asset, not a code change.

Suggested Dart shape: `TfliteQualityModel implements OnDeviceQualityModel` returns the existing
`PhotoQualityResult` with `isBlurry`, `isTooDark` and `tipKey` set by the rule above.
`blurScore` = `quality_blurry` and `brightness` = mean luminance of the 224 input. Add these
optional fields: `isPlant`, `plantScore`, `cropCode`, `cropScore`, `modelVersion`,
`usedFallback`. `isAcceptable` becomes `!isBlurry && !isTooDark && isPlant`.

## 5. What goes to `POST /v1/diagnoses` (DX-005 provenance)

The diagnosis endpoint doesn't exist yet: it is M6 API work, and `openapi.yaml` only has the
`diagnosis` upload purpose. Below is the proposed request fragment, for the API owner to adopt in
the DX-005 schema. `diagnosis.model_versions` stores the model version.

```json
{
  "crop_code": "chilli",
  "crop_detected_on_device": "chilli",
  "on_device": {
    "model": "crop_quality",
    "model_version": "ondevice-v1.0",
    "model_sha256": "<metadata.json sha256>",
    "fallback": null,
    "plant_score": 0.998,
    "quality": {"ok": 0.97, "blurry": 0.02, "dark": 0.01},
    "crop_scores": {"paddy": 0.01, "cotton": 0.0, "chilli": 0.93, "maize": 0.01, "tomato": 0.03, "groundnut": 0.0, "other": 0.02},
    "heuristic": {"blur_score": 212.4, "brightness": 0.46},
    "latency_ms": 38
  }
}
```

- `crop_detected_on_device`: a crop code, or `null` when below `crop_min` or on fallback.
- `on_device.model_version` goes into `diagnosis.model_versions.ondevice`. The server-side
  embedding model and the corpus add their own entries (DX-002 / DX-005).
- Only photos that pass the gate are uploaded, so the scores above describe accepted photos. The
  number of retakes per tip can be sent as analytics (AN-007) and is not part of the diagnosis.
- No location or identity goes into this block.

## 6. Fallback to the Laplacian heuristic

Use `PhotoQualityCheck.defaultModel` (`LaplacianQualityModel`: blur threshold 40, dark threshold
0.15 at 320 px) when any of these happens:

- the asset is missing, or its SHA-256 doesn't match `metadata.json`;
- interpreter creation or `allocateTensors` throws (old or unsupported CPU, out of memory on a 2 GB
  device);
- the input or output shapes and dtypes differ from §2 / §3, for example after a bad asset swap;
- an inference throws or takes longer than **1,500 ms**. Then mark the model broken for the
  session and stop retrying.

On fallback: no plant check and no crop hint (`crop_detected_on_device = null`),
`on_device.fallback = "laplacian"`, `on_device.model_version = "heuristic-laplacian-v1"`, and the
`heuristic` block filled in. Report the reason once per session as a non-fatal (OPS / Crashlytics).
Never block the user: if both paths fail, accept the photo and let the server decide.

## 7. Human gates

- **Latency.** The < 400 ms acceptance on a 2 GB RAM reference Android phone has to be measured on
  the device (BENCHMARK.md). The Mac number in `artifacts/bench_mac.json` only shows that the graph
  runs under XNNPACK.
- **Field accuracy.** `metadata.json.evaluation` is measured on public bootstrap data only
  (`source=public`). Before `crop_detected_on_device` pre-selects anything in production, an
  agronomist-labelled set of pilot field photos (≥ 50 per crop, all 6 crops + other + not-a-plant)
  has to pass the DX-001 accuracy check, and the thresholds have to be re-tuned on it (DX-012
  pipeline). Until then the mobile team should ship the quality / plant gate, and keep the crop hint
  behind a Remote Config flag (`ondevice_crop_hint`, default off).
