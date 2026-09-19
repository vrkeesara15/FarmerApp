"""Benchmark the .tflite with the LiteRT interpreter (XNNPACK CPU delegate) on this machine.

Usage: uv run python bench.py [--model artifacts/crop_quality_v1.tflite] [--runs 200] [--out artifacts/bench_mac.json]

Reports invoke() latency only (the model), single thread and 4 threads, plus preprocessing of a
1280x960 JPEG (decode + centre crop + resize to 224) measured with Pillow for reference. This is a
developer-machine number; the DX-001 acceptance (< 400 ms on a 2 GB RAM Android device) is a human
gate, see BENCHMARK.md.
"""

from __future__ import annotations

import argparse
import io
import json
import platform
import statistics
import subprocess
import time
from pathlib import Path

import numpy as np
from ai_edge_litert.interpreter import Interpreter
from PIL import Image

from ondevice.config import ARTIFACTS_DIR, INPUT_SIZE, TFLITE_NAME


def time_invoke(model: Path, threads: int, runs: int, warmup: int = 20) -> dict:
    it = Interpreter(model_path=str(model), num_threads=threads)  # XNNPACK is applied by default
    it.allocate_tensors()
    inp = it.get_input_details()[0]
    rng = np.random.default_rng(0)
    x = rng.integers(0, 256, inp["shape"], dtype=np.uint8)
    for _ in range(warmup):
        it.set_tensor(inp["index"], x)
        it.invoke()
    samples = []
    for _ in range(runs):
        it.set_tensor(inp["index"], x)
        t0 = time.perf_counter()
        it.invoke()
        samples.append((time.perf_counter() - t0) * 1000)
    samples.sort()
    return {
        "threads": threads,
        "runs": runs,
        "mean_ms": round(statistics.fmean(samples), 3),
        "p50_ms": round(samples[len(samples) // 2], 3),
        "p90_ms": round(samples[int(len(samples) * 0.9)], 3),
        "max_ms": round(samples[-1], 3),
    }


def time_preprocess(runs: int = 50) -> dict:
    rng = np.random.default_rng(1)
    frame = Image.fromarray(rng.integers(0, 256, (960, 1280, 3), dtype=np.uint8))
    buf = io.BytesIO()
    frame.save(buf, "JPEG", quality=80)
    data = buf.getvalue()
    samples = []
    for _ in range(runs):
        t0 = time.perf_counter()
        img = Image.open(io.BytesIO(data)).convert("RGB")
        w, h = img.size
        side = min(w, h)
        img = img.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))
        img = img.resize((INPUT_SIZE, INPUT_SIZE), Image.Resampling.BILINEAR, reducing_gap=2.0)
        np.asarray(img, np.uint8)[None]
        samples.append((time.perf_counter() - t0) * 1000)
    return {"what": "decode 1280x960 JPEG q80 + centre crop + resize 224 (Pillow)",
            "p50_ms": round(sorted(samples)[len(samples) // 2], 3)}


def cpu_name() -> str:
    if platform.system() == "Darwin":
        try:
            return subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
        except (OSError, subprocess.CalledProcessError):
            pass
    return platform.processor() or "cpu"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=ARTIFACTS_DIR / TFLITE_NAME)
    parser.add_argument("--runs", type=int, default=200)
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    result = {
        "model": args.model.name,
        "size_bytes": args.model.stat().st_size,
        "machine": f"{platform.system()} {platform.machine()} ({cpu_name()})",
        "python": platform.python_version(),
        "delegate": "XNNPACK (LiteRT default CPU delegate)",
        "invoke": [time_invoke(args.model, t, args.runs) for t in (1, 4)],
        "preprocess": time_preprocess(),
    }
    print(json.dumps(result, indent=2))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
