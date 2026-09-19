"""Evaluate the model on the held-out test split: per-head accuracy and confusion matrices.

Usage:
  uv run python eval.py                                  # Keras checkpoint runs/latest/model.keras
  uv run python eval.py --tflite artifacts/crop_quality_v1.tflite --out artifacts

Passes over the test split:
  clean   centre crop, `ok` transform -> plant head (all rows) and crop head (plant rows)
  blurry  same rows, deterministic blur -> quality head
  dark    same rows, deterministic under-exposure -> quality head
The quality head is scored on the union of the three passes. The retake gate (not a plant /
blurry / dark, thresholds from config.Thresholds) is scored as a binary decision too.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np

from ondevice.config import CROP_LABELS, QUALITY_LABELS, RUNS_DIR, Thresholds, TrainConfig
from ondevice.data import BLURRY, DARK, OK, eval_dataset
from ondevice.manifest import read_manifest


class KerasPredictor:
    def __init__(self, path: Path):
        import keras

        self.model = keras.saving.load_model(path, compile=False)
        self.name = str(path)

    def __call__(self, images: np.ndarray) -> np.ndarray:
        out = self.model.predict_on_batch(images)
        return np.concatenate([out["plant"], out["quality"], out["crop"]], axis=1)


class TFLitePredictor:
    def __init__(self, path: Path, threads: int = 4):
        from ai_edge_litert.interpreter import Interpreter

        self.interpreter = Interpreter(model_path=str(path), num_threads=threads)
        self.interpreter.allocate_tensors()
        self.inp = self.interpreter.get_input_details()[0]
        self.out = self.interpreter.get_output_details()[0]
        self.name = str(path)

    def __call__(self, images: np.ndarray) -> np.ndarray:
        rows = []
        for image in images:
            x = np.clip(np.round(image), 0, 255).astype(self.inp["dtype"])[None]
            self.interpreter.set_tensor(self.inp["index"], x)
            self.interpreter.invoke()
            rows.append(self.interpreter.get_tensor(self.out["index"])[0].astype(np.float32))
        return np.stack(rows)


def predict(predictor, ds) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    scores, labels = [], {"plant": [], "quality": [], "crop": []}
    for images, y in ds:
        scores.append(predictor(images.numpy()))
        for k in labels:
            labels[k].append(np.reshape(y[k].numpy(), [-1]))
    return np.concatenate(scores), {k: np.concatenate(v) for k, v in labels.items()}


def confusion(y_true: np.ndarray, y_pred: np.ndarray, n: int) -> np.ndarray:
    m = np.zeros((n, n), np.int64)
    np.add.at(m, (y_true, y_pred), 1)
    return m


def head_report(y_true: np.ndarray, y_pred: np.ndarray, labels: tuple[str, ...]) -> dict:
    m = confusion(y_true, y_pred, len(labels))
    support = m.sum(1)
    recall = np.divide(np.diag(m), support, out=np.zeros(len(labels)), where=support > 0)
    colsum = m.sum(0)
    precision = np.divide(np.diag(m), colsum, out=np.zeros(len(labels)), where=colsum > 0)
    return {
        "accuracy": float(np.trace(m) / max(m.sum(), 1)),
        "balanced_accuracy": float(recall[support > 0].mean()),
        "n": int(m.sum()),
        "labels": list(labels),
        "per_class": {
            lab: {"recall": round(float(recall[i]), 4), "precision": round(float(precision[i]), 4),
                  "support": int(support[i])}
            for i, lab in enumerate(labels)
        },
        "confusion": m.tolist(),
    }


def evaluate(predictor, rows, cfg: TrainConfig, th: Thresholds) -> dict:
    nq = len(QUALITY_LABELS)
    passes = {}
    t0 = time.time()
    for name, kind in (("clean", OK), ("blurry", BLURRY), ("dark", DARK)):
        passes[name] = predict(predictor, eval_dataset(rows, cfg.degradation, 64, kind))
    s, y = passes["clean"]
    plant_pred = (s[:, 0] >= th.plant_min).astype(int)
    report = {"model": predictor.name, "test_rows": len(rows), "seconds": round(time.time() - t0, 1)}
    report["plant"] = head_report(y["plant"].astype(int), plant_pred, ("not_plant", "plant"))

    is_plant = y["plant"] > 0.5
    crop_probs = s[is_plant, 1 + nq :]
    crop_true = y["crop"][is_plant]
    crop_pred = crop_probs.argmax(1)
    report["crop"] = head_report(crop_true, crop_pred, CROP_LABELS)
    confident = crop_probs.max(1) >= th.crop_min
    report["crop"]["at_threshold"] = {
        "crop_min": th.crop_min,
        "coverage": float(confident.mean()),
        "accuracy_when_confident": (
            float((crop_pred[confident] == crop_true[confident]).mean()) if confident.any() else None
        ),
    }

    q_true, q_pred, retake_true, retake_pred = [], [], [], []
    for name in ("clean", "blurry", "dark"):
        s, y = passes[name]
        valid = y["quality"] >= 0
        q_true.append(y["quality"][valid])
        q_pred.append(s[valid, 1 : 1 + nq].argmax(1))
        q = s[:, 1 : 1 + nq]
        retake = (s[:, 0] < th.plant_min) | (q[:, 1] >= th.blurry_min) | (q[:, 2] >= th.dark_min)
        should = (y["plant"] < 0.5) | (y["quality"] == BLURRY) | (y["quality"] == DARK)
        retake_true.append(should.astype(int))
        retake_pred.append(retake.astype(int))
    report["quality"] = head_report(np.concatenate(q_true), np.concatenate(q_pred), QUALITY_LABELS)
    rt, rp = np.concatenate(retake_true), np.concatenate(retake_pred)
    report["retake_gate"] = head_report(rt, rp, ("use", "retake"))
    ok_plant = (rt == 0)
    report["retake_gate"]["false_retake_rate_on_good_plant_photos"] = float(rp[ok_plant].mean())
    return report


def markdown(report: dict) -> str:
    lines = [f"# DX-001 evaluation — `{Path(report['model']).name}`", "",
             f"Held-out test split: {report['test_rows']} images (public bootstrap data, source=public).", "",
             "| Head | Accuracy | Balanced accuracy | n |", "|---|---|---|---|"]
    for head in ("plant", "quality", "crop", "retake_gate"):
        r = report[head]
        lines.append(f"| {head} | {r['accuracy']:.4f} | {r['balanced_accuracy']:.4f} | {r['n']} |")
    at = report["crop"]["at_threshold"]
    acc = at["accuracy_when_confident"]
    lines += ["", f"Crop at p >= {at['crop_min']}: coverage {at['coverage']:.3f}, accuracy when confident "
              f"{'n/a' if acc is None else f'{acc:.4f}'}. False retake rate on good plant photos: "
              f"{report['retake_gate']['false_retake_rate_on_good_plant_photos']:.4f}.", ""]
    for head in ("plant", "quality", "crop"):
        r = report[head]
        lines += [f"## {head} confusion (rows = truth, columns = prediction)", "",
                  "| truth \\ pred | " + " | ".join(r["labels"]) + " | recall |",
                  "|---|" + "---|" * (len(r["labels"]) + 1)]
        for lab, row in zip(r["labels"], r["confusion"], strict=True):
            lines.append(f"| {lab} | " + " | ".join(map(str, row)) + f" | {r['per_class'][lab]['recall']:.3f} |")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keras", type=Path, default=RUNS_DIR / "latest" / "model.keras")
    parser.add_argument("--tflite", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--split", default="test", choices=("val", "test"))
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    predictor = TFLitePredictor(args.tflite) if args.tflite else KerasPredictor(args.keras)
    out = args.out or (args.tflite.parent if args.tflite else args.keras.parent)
    rows = [r for r in read_manifest() if r.split == args.split]
    if args.limit:  # evenly spaced, so every source is represented
        rows = rows[:: max(1, len(rows) // args.limit)][: args.limit]
    report = evaluate(predictor, rows, TrainConfig(), Thresholds())
    stem = "eval_tflite" if args.tflite else "eval_keras"
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{stem}.json").write_text(json.dumps(report, indent=2))
    (out / f"{stem}.md").write_text(markdown(report))
    for head in ("plant", "quality", "crop", "retake_gate"):
        print(f"{head:12s} acc {report[head]['accuracy']:.4f}  balanced {report[head]['balanced_accuracy']:.4f}"
              f"  n={report[head]['n']}")
    print(f"wrote {out / stem}.json / .md")


if __name__ == "__main__":
    main()
