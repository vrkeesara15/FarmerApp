"""CPU latency of the encoder (decode + preprocess + forward + normalise), per batch size and thread count.

    uv run python bench.py --model-dir .model --threads 2 --threads 0 --out bench_mac.json

``--threads 2`` mimics the Cloud Run pilot instance (2 vCPU); ``0`` = torch's default (all cores).
Inputs are 1280 x 960 JPEGs (the size the apps upload after on-device resize, NF-004).
"""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import sys
import time
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).resolve().parent / "tests"))

from images import jpeg, leaf  # noqa: E402

from embed.encoder import Encoder  # noqa: E402


def percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, round(q * (len(ordered) - 1)))]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, default=Path(".model"))
    parser.add_argument("--threads", type=int, action="append", default=None)
    parser.add_argument("--batches", type=int, nargs="+", default=[1, 4, 8])
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    encoder = Encoder.load(args.model_dir)
    default_threads = torch.get_num_threads()
    blobs = [jpeg(leaf(i, size=(1280, 960)), quality=85) for i in range(8)]
    results = []
    for threads in args.threads or [2, 0]:
        torch.set_num_threads(threads or default_threads)
        for batch in args.batches:
            encoder.encode(blobs[:batch])  # warm
            times = []
            for _ in range(args.runs):
                started = time.perf_counter()
                encoder.encode(blobs[:batch])
                times.append((time.perf_counter() - started) * 1000)
            row = {
                "threads": torch.get_num_threads(),
                "batch": batch,
                "p50_ms": round(statistics.median(times), 1),
                "p95_ms": round(percentile(times, 0.95), 1),
                "per_image_p95_ms": round(percentile(times, 0.95) / batch, 1),
            }
            results.append(row)
            print(json.dumps(row))
    report = {
        "machine": f"{platform.machine()} {platform.processor() or platform.platform()}",
        "torch": torch.__version__,
        "model": encoder.info.name,
        "revision": encoder.info.revision,
        "runs": args.runs,
        "results": results,
    }
    if args.out:
        args.out.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
