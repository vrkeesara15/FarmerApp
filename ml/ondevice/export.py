"""Export the trained model to an int8 TFLite file + metadata.json (the DX-005 model version record).

Usage: uv run python export.py [--keras runs/latest/model.keras] [--out artifacts] [--skip-eval]

* Full-integer post-training quantisation with a representative dataset drawn from the train split
  (clean, blurry and dark frames, deterministic). Weights and activations are int8; the input is
  uint8 RGB (scale 1, zero point 0: feed raw pixels) and the output is one float32 [1, 11] tensor.
* Fails if the file is not under 8 MB (DX-001).
* Evaluates the .tflite on the test split (unless --skip-eval) and records the summary in metadata;
  when runs/<run>/eval_keras.json exists (make eval), fails if int8 costs more than 3 points on a head.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

import numpy as np
import tensorflow as tf

from ondevice.config import (
    ARTIFACTS_DIR,
    CROP_LABELS,
    INPUT_SIZE,
    MAX_TFLITE_BYTES,
    MODEL_NAME,
    MODEL_VERSION,
    OUTPUT_LAYOUT,
    QUALITY_LABELS,
    ROOT,
    RUNS_DIR,
    SOURCES,
    TFLITE_NAME,
    Thresholds,
    TrainConfig,
)
from ondevice.data import eval_dataset
from ondevice.manifest import read_manifest
from ondevice.model import export_model, fold_dead_se_channels

REPRESENTATIVE_SAMPLES = 300


def _representative_rows(cfg: TrainConfig, batch: int = 1):
    rows = [r for r in read_manifest() if r.split == "train"]
    step = max(1, len(rows) // REPRESENTATIVE_SAMPLES)
    return eval_dataset(rows[::step][:REPRESENTATIVE_SAMPLES], cfg.degradation, batch, kind=None)


def calibration_images(cfg: TrainConfig) -> np.ndarray:
    """~300 train images (3/5 ok, 1/5 blurry, 1/5 dark), float32 0..255, deterministic."""
    return np.concatenate([x.numpy() for x, _ in _representative_rows(cfg, batch=50)])


def quantize_model(model, calibration: np.ndarray) -> tuple[bytes, dict[str, int]]:
    """Fold dead SE channels, wrap to the [1, 11] output and convert to full-int8 TFLite."""
    import keras

    folded = fold_dead_se_channels(model, calibration)
    wrapped = export_model(model)

    def representative():
        # Pin the input range to exactly 0..255 so the uint8 input maps 1:1 to pixel values.
        board = np.zeros((1, INPUT_SIZE, INPUT_SIZE, 3), np.float32)
        board[:, ::2, ::2, :] = 255.0
        yield [board]
        for image in calibration:
            yield [image[None].astype(np.float32)]

    with tempfile.TemporaryDirectory() as tmp:
        saved = Path(tmp) / "saved_model"
        archive = keras.export.ExportArchive()
        archive.track(wrapped)
        archive.add_endpoint(
            "serve",
            lambda image: {"scores": wrapped(image, training=False)},
            input_signature=[tf.TensorSpec([1, INPUT_SIZE, INPUT_SIZE, 3], tf.float32, name="image")],
        )
        archive.write_out(str(saved), verbose=False)
        converter = tf.lite.TFLiteConverter.from_saved_model(str(saved), signature_keys=["serve"])
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = representative
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.uint8
        converter.inference_output_type = tf.float32
        return converter.convert(), folded


def convert(keras_path: Path, cfg: TrainConfig) -> tuple[bytes, dict[str, int]]:
    import keras

    model = keras.saving.load_model(keras_path, compile=False)
    tflite, folded = quantize_model(model, calibration_images(cfg))
    print(f"folded dead squeeze-excite channels: {folded}")
    return tflite, folded


def git_sha() -> str:
    try:
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = subprocess.call(["git", "diff", "--quiet", "HEAD", "--", "."], cwd=ROOT) != 0
        return sha + ("-dirty" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def data_sources() -> list[dict]:
    counts = Counter((r.source, r.split) for r in read_manifest())
    out = []
    for s in json.loads(SOURCES.read_text())["sources"]:
        out.append({
            "id": s["id"],
            "source": "public" if s["format"] != "synthetic" else "synthetic",
            "repo": s.get("repo"),
            "revision": s.get("revision"),
            "licence": s["licence"],
            "attribution": s["attribution"],
            "images": {split: counts.get((s["id"], split), 0) for split in ("train", "val", "test")},
        })
    return out


def io_details(tflite: bytes) -> dict:
    from ai_edge_litert.interpreter import Interpreter

    it = Interpreter(model_content=tflite)
    it.allocate_tensors()
    i, o = it.get_input_details()[0], it.get_output_details()[0]
    return {
        "input": {"name": i["name"], "shape": i["shape"].tolist(), "dtype": np.dtype(i["dtype"]).name,
                  "quantization": {"scale": float(i["quantization"][0]), "zero_point": int(i["quantization"][1])}},
        "output": {"name": o["name"], "shape": o["shape"].tolist(), "dtype": np.dtype(o["dtype"]).name},
    }


def metadata(tflite: bytes, keras_path: Path, cfg: TrainConfig, evaluation: dict | None,
             folded: dict[str, int], *, model_version: str = MODEL_VERSION, source: str = "public",
             training_manifest_uri: str | None = None) -> dict:
    th = Thresholds()
    run_cfg = keras_path.parent / "config.json"
    io = io_details(tflite)
    return {
        "model_name": MODEL_NAME,
        "model_version": model_version,
        "file": TFLITE_NAME,
        "size_bytes": len(tflite),
        "sha256": hashlib.sha256(tflite).hexdigest(),
        "created_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "git_sha": git_sha(),
        "source": source,
        "architecture": f"{cfg.backbone} (alpha {cfg.alpha}, ImageNet init) + plant / quality / crop heads",
        "quantization": "int8 full-integer post-training (weights + activations), uint8 input, float32 output",
        "export_surgery": {"dead_squeeze_excite_channels_folded": folded,
                           "why": "keeps XNNPACK able to load the int8 graph; function unchanged"},
        "input": {
            **io["input"],
            "layout": "NHWC",
            "color": "RGB",
            "normalisation": "none: raw 0..255 pixel values as uint8 (the model rescales internally)",
            "resize": f"centre square of side 0.875 x short edge, resized to {INPUT_SIZE}x{INPUT_SIZE} "
                      "(area / bilinear); matches the evaluation centre crop",
        },
        "output": {**io["output"], "layout": list(OUTPUT_LAYOUT),
                   "semantics": {"plant": "sigmoid p(plant or leaf present)",
                                 "quality_*": "softmax over quality labels", "crop_*": "softmax over crop labels"}},
        "labels": {"quality": list(QUALITY_LABELS), "crop": list(CROP_LABELS)},
        "thresholds": {"plant_min": th.plant_min, "blurry_min": th.blurry_min, "dark_min": th.dark_min,
                       "crop_min": th.crop_min},
        "training": {
            "config": json.loads(run_cfg.read_text()) if run_cfg.exists() else cfg.to_dict(),
            "data_sources": data_sources(),
            "note": "Bootstrap on public datasets only (SPEC 3.3). Field images from the pilot are the real "
                    "source; DX-012 fine-tunes monthly on them.",
        },
        "evaluation": evaluation,
        # DX-012: the API's export this candidate was fine-tuned on (None for the bootstrap).
        "training_manifest_uri": training_manifest_uri,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keras", type=Path, default=RUNS_DIR / "latest" / "model.keras")
    parser.add_argument("--out", type=Path, default=ARTIFACTS_DIR)
    parser.add_argument("--skip-eval", action="store_true")
    parser.add_argument("--model-version", default=MODEL_VERSION,
                        help="DX-012 candidates: finetune.py writes the next version to next_version.txt")
    parser.add_argument("--source", default="public", help="public (bootstrap) or public+field (DX-012)")
    parser.add_argument("--training-manifest-uri", default=None, help="DX-012 training export gs:// URI")
    parser.add_argument("--max-int8-drop", type=float, default=0.03,
                        help="fail if int8 accuracy on any head is this much below the float model (eval_keras.json)")
    args = parser.parse_args()
    cfg = TrainConfig()

    tflite, folded = convert(args.keras, cfg)
    if len(tflite) >= MAX_TFLITE_BYTES:
        sys.exit(f"{TFLITE_NAME} is {len(tflite)} bytes, over the DX-001 limit of {MAX_TFLITE_BYTES}")
    args.out.mkdir(parents=True, exist_ok=True)
    path = args.out / TFLITE_NAME
    path.write_bytes(tflite)
    print(f"wrote {path} ({len(tflite) / 1e6:.2f} MB)")

    evaluation = None
    if not args.skip_eval:
        from eval import TFLitePredictor, evaluate, markdown

        rows = [r for r in read_manifest() if r.split == "test"]
        report = evaluate(TFLitePredictor(path), rows, cfg, Thresholds())
        (args.out / "eval_tflite.json").write_text(json.dumps(report, indent=2))
        (args.out / "eval_tflite.md").write_text(markdown(report))
        evaluation = {
            "split": "test",
            "images": len(rows),
            "accuracy": {h: round(report[h]["accuracy"], 4) for h in ("plant", "quality", "crop", "retake_gate")},
            "balanced_accuracy": {h: round(report[h]["balanced_accuracy"], 4)
                                  for h in ("plant", "quality", "crop", "retake_gate")},
            "false_retake_rate_on_good_plant_photos":
                round(report["retake_gate"]["false_retake_rate_on_good_plant_photos"], 4),
            "report": "eval_tflite.md",
        }
        print(json.dumps(evaluation["accuracy"]))
        float_report = args.keras.parent / "eval_keras.json"
        if float_report.exists():
            ref = json.loads(float_report.read_text())
            drop = {h: round(ref[h]["accuracy"] - report[h]["accuracy"], 4) for h in ("plant", "quality", "crop")}
            evaluation["float_accuracy"] = {h: round(ref[h]["accuracy"], 4) for h in ("plant", "quality", "crop")}
            evaluation["int8_drop"] = drop
            print(f"int8 drop vs float: {drop}")

    meta = metadata(tflite, args.keras, cfg, evaluation, folded, model_version=args.model_version,
                    source=args.source, training_manifest_uri=args.training_manifest_uri)
    (args.out / "metadata.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"wrote {args.out / 'metadata.json'} (version {args.model_version}, sha256 {meta['sha256'][:12]})")
    if evaluation and max(evaluation.get("int8_drop", {"-": 0.0}).values()) > args.max_int8_drop:
        sys.exit(f"int8 quantisation costs more than {args.max_int8_drop:.0%} on a head: {evaluation['int8_drop']}")


if __name__ == "__main__":
    main()
