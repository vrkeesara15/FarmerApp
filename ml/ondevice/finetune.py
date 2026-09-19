"""DX-012 monthly fine-tune of the on-device model on approved corpus field images.

Usage (from ml/ondevice, after ``gcloud storage rsync gs://<corpus> data/mirror/<corpus>``):

    uv run python finetune.py \\
        --training-export data/mirror/<corpus>/training/<tenant>/<YYYYMMDD>/manifest.csv \\
        --training-export-uri gs://<corpus>/training/<tenant>/<YYYYMMDD>/manifest.csv \\
        --images-dir data/mirror --base runs/latest/model.keras --out runs/finetune-<YYYYMMDD>
    uv run python export.py --keras runs/finetune-<YYYYMMDD>/model.keras --out runs/finetune-<YYYYMMDD>/export \\
        --model-version <next> --source public+field \\
        --training-manifest-uri gs://<corpus>/training/<tenant>/<YYYYMMDD>/manifest.csv

1. The export's field images are cached (``ondevice/field.py``: sha256-checked, centre-cropped)
   and appended to the public bootstrap manifest; the split of every field row is the stable hash
   split, so field images of one case never straddle train and test.
2. The previous model (``--base``) is fine-tuned on the merged train split with the top of the
   backbone unfrozen at a low learning rate (``--epochs``, early stopping on validation loss).
3. ``export.py`` then quantises it and writes ``metadata.json`` with the evaluation numbers (the
   merged test split, field rows included) and the next ``model_version``; the pipeline uploads
   both to ``gs://<corpus>/models/on-device/<version>/`` and runs the API job
   ``register-model-candidate``. **Nothing reaches a phone until an agronomist or the owner
   approves the candidate in the console** (``POST /v1/models/releases/{id}/decision``).

Outputs: ``<out>/model.keras``, ``<out>/config.json`` (with the training export URI and the
field row counts), ``<out>/history.json``, ``<out>/field_problems.txt`` (images skipped),
``<out>/next_version.txt``.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import replace
from pathlib import Path

import keras
import numpy as np

from ondevice.config import CROP_LABELS, MANIFEST, MODEL_VERSION, RUNS_DIR, TrainConfig
from ondevice.data import crop_class_weights, eval_dataset, plant_pos_weight, train_dataset
from ondevice.field import materialise, merge, mirror_fetch, next_version, read_export
from ondevice.manifest import read_manifest, write_manifest
from train import compile_model, unfreeze_top


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training-export", type=Path, required=True, help="local copy of the export CSV")
    parser.add_argument("--training-export-uri", default="", help="its gs:// URI (kept in config.json)")
    parser.add_argument("--images-dir", type=Path, required=True, help="gcloud storage rsync mirror root")
    parser.add_argument("--base", type=Path, default=RUNS_DIR / "latest" / "model.keras")
    parser.add_argument("--base-version", default=MODEL_VERSION)
    parser.add_argument("--out", type=Path, default=RUNS_DIR / "finetune")
    parser.add_argument("--epochs", type=int, default=6)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--min-field-rows", type=int, default=50, help="refuse to train on fewer")
    args = parser.parse_args()

    cfg = replace(TrainConfig(), finetune_epochs=args.epochs, finetune_lr=args.lr)
    keras.utils.set_random_seed(cfg.seed)
    field_rows, problems = materialise(
        read_export(args.training_export.read_text()), mirror_fetch(args.images_dir)
    )
    if len(field_rows) < args.min_field_rows:
        raise SystemExit(f"only {len(field_rows)} field images; need {args.min_field_rows} (see --min-field-rows)")
    rows = merge(read_manifest(), field_rows)
    args.out.mkdir(parents=True, exist_ok=True)
    write_manifest(rows, args.out / "manifest.csv")
    write_manifest(rows, MANIFEST)  # export.py / eval.py read the default manifest
    (args.out / "field_problems.txt").write_text("\n".join(problems) + ("\n" if problems else ""))

    train_rows = [r for r in rows if r.split == "train"]
    val_rows = [r for r in rows if r.split == "val"]
    crop_w, pos_w = crop_class_weights(train_rows), plant_pos_weight(train_rows)
    train_ds = train_dataset(train_rows, cfg.degradation, cfg.batch_size, cfg.seed)
    val_ds = eval_dataset(val_rows, cfg.degradation, cfg.batch_size, kind=None)

    model = keras.models.load_model(args.base, compile=False)
    backbone = next(layer for layer in model.layers if isinstance(layer, keras.Model))
    unfrozen = unfreeze_top(backbone, cfg.finetune_from_layer)
    steps = max(1, len(train_rows) // cfg.batch_size)
    schedule = keras.optimizers.schedules.CosineDecay(cfg.finetune_lr, decay_steps=steps * cfg.finetune_epochs,
                                                      alpha=0.05)
    compile_model(model, cfg, schedule, crop_w, pos_w)
    ckpt = args.out / "model.keras"
    t0 = time.time()
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=cfg.finetune_epochs,
        callbacks=[
            keras.callbacks.ModelCheckpoint(ckpt, monitor="val_loss", save_best_only=True),
            keras.callbacks.EarlyStopping(monitor="val_loss", patience=3, restore_best_weights=True),
        ],
        verbose=2,
    )
    model.save(ckpt)
    field_by_split = {s: sum(1 for r in field_rows if r.split == s) for s in ("train", "val", "test")}
    candidate = next_version(args.base_version)
    (args.out / "config.json").write_text(json.dumps(
        {**cfg.to_dict(), "base": str(args.base), "base_version": args.base_version, "candidate_version": candidate,
         "training_manifest_uri": args.training_export_uri, "field_rows": field_by_split,
         "field_skipped": len(problems), "backbone_layers_trainable": unfrozen,
         "crop_class_weights": dict(zip(CROP_LABELS, np.round(crop_w, 3).tolist(), strict=True)),
         "train_seconds": round(time.time() - t0)}, indent=2))
    (args.out / "history.json").write_text(json.dumps({k: [float(x) for x in v] for k, v in history.history.items()}))
    (args.out / "next_version.txt").write_text(candidate + "\n")
    print(f"fine-tuned {ckpt} on {field_by_split} field rows -> candidate {candidate}")


if __name__ == "__main__":
    main()
