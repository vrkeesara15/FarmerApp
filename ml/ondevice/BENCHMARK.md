# DX-001 latency benchmark

Acceptance (SPEC DX-001): the on-device model **runs under 400 ms on a 2 GB RAM device**. The
number that counts is measured on a real phone. That measurement is a **human gate**: this repo can
only show that the graph runs under the same runtime and delegate on a developer machine.

## 1. Developer machine (automated): `make bench`

`bench.py` loads `artifacts/crop_quality_v1.tflite` with the LiteRT interpreter
(`ai-edge-litert` 2.2, XNNPACK CPU delegate applied by default). It does 20 warm-up runs, then
times 200 `invoke()` calls on 1 and 4 threads, and times decode + crop + resize of a 1280×960 JPEG
with Pillow for reference. The result goes to `artifacts/bench_mac.json`.

Latest run, 2026-09-19, `crop_quality_v1.tflite` (3.00 MB, int8 MobileNetV2 α 1.0, about 300 M
MACs). This is a reference point, not the acceptance number:

| machine | threads | mean | p50 | p90 |
|---|---|---|---|---|
| Apple M5, macOS 26 arm64, LiteRT 2.2 | 1 (XNNPACK) | 2.94 ms | 2.94 ms | 2.97 ms |
| Apple M5, macOS 26 arm64, LiteRT 2.2 | 4 (XNNPACK) | 2.04 ms | 2.03 ms | 2.12 ms |
| Pillow decode 1280×960 JPEG + crop + resize 224 | 1 | | 12.6 ms | |

For orientation only: an int8 MobileNetV2 1.0 at 224 px usually runs in the order of 100 ms on
one Cortex-A53 core with XNNPACK. That would leave headroom under 400 ms for JPEG decode and
resize, but only the device run below counts. If the device misses the budget, the fallbacks are,
in order: 2 threads, then α 0.75 (`TrainConfig.alpha`, about 40 % fewer MACs), then 192 px input.

## 2. Reference device (human gate)

**Device.** Use an Android phone with **2 GB RAM** from the pilot's low-end tier, for example
Samsung Galaxy A03 Core, Redmi A1 / A2, or Nokia C12 (Unisoc / MediaTek / Snapdragon 4xx class,
Cortex-A53 / A55). Record the model, SoC, Android version and free RAM at test time. Charge above
50 %, turn off battery saver, let the phone cool for 5 minutes, close other apps.

### 2a. `benchmark_model` over adb (model only)

```sh
# Prebuilt LiteRT / TFLite benchmark binary for arm64 (download "android_aarch64 benchmark_model"
# from the LiteRT / TensorFlow Lite performance-measurement page, or build it with Bazel:
#   bazel build -c opt --config=android_arm64 //tensorflow/lite/tools/benchmark:benchmark_model)
adb push benchmark_model /data/local/tmp/
adb shell chmod +x /data/local/tmp/benchmark_model
adb push ml/ondevice/artifacts/crop_quality_v1.tflite /data/local/tmp/

# Single thread, XNNPACK (the app's default CPU path)
adb shell /data/local/tmp/benchmark_model \
  --graph=/data/local/tmp/crop_quality_v1.tflite \
  --num_threads=1 --use_xnnpack=true \
  --warmup_runs=10 --num_runs=100 --enable_op_profiling=false

# 2 and 4 threads (what the app will use on 4+ core devices)
adb shell /data/local/tmp/benchmark_model --graph=/data/local/tmp/crop_quality_v1.tflite \
  --num_threads=2 --use_xnnpack=true --num_runs=100
adb shell /data/local/tmp/benchmark_model --graph=/data/local/tmp/crop_quality_v1.tflite \
  --num_threads=4 --use_xnnpack=true --num_runs=100

# Memory: peak RSS is printed as "Peak memory footprint (MB)"; also note init time.
```

Record `Inference timings in us: ... avg=` (warm-up excluded), `Init`, and the peak memory
footprint. Pass condition: **avg single-thread < 400 ms** (a pass on 2 threads is also recorded;
the app uses 2).

### 2b. In-app timing (end to end, what the farmer waits for)

When the mobile integration lands, it should expose a debug-only "Model timing" screen (behind
the developer menu, never in release builds). It runs the real path 50 times on the bundled sample
photo: JPEG decode → crop / resize → `invoke` → decode scores. It shows p50 / p90 per stage plus a
cold-start first run (interpreter creation + first inference). Pass condition: **p90 of the full
path < 400 ms** and cold start < 1.5 s (the fallback timeout in INTEGRATION.md §6).

### 2c. Record the result

Add a row to the table below and set DX-001 in `docs/progress.md` from "gated" to "done"
(latency) with the device and numbers.

| date | device (SoC, RAM, Android) | tool | threads | avg / p90 (ms) | peak mem (MB) | by |
|---|---|---|---|---|---|---|
| — | — | — | — | pending (human gate) | — | — |
