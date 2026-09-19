"""Train the DX-001 multi-head model (plant / quality / crop) on data/manifest.csv.

Usage: uv run python train.py [--out runs/latest] [--head-epochs N] [--finetune-epochs N] [--limit N]

Stage 1 trains the heads on a frozen ImageNet MobileNetV2 (config.TrainConfig.backbone); stage 2
unfreezes the top of the backbone (BatchNorm stays frozen) with a cosine-decayed learning rate.
The best epoch by validation loss is kept. Outputs: <out>/model.keras, config.json, history.json, class_weights.json.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import replace
from pathlib import Path

import keras
import numpy as np
import tensorflow as tf

from ondevice.config import CROP_LABELS, QUALITY_LABELS, RUNS_DIR, TrainConfig
from ondevice.data import crop_class_weights, eval_dataset, plant_pos_weight, train_dataset
from ondevice.manifest import read_manifest
from ondevice.model import build_model, masked_sparse_ce, weighted_bce


def compile_model(model: keras.Model, cfg: TrainConfig, lr, crop_w: np.ndarray, pos_w: float) -> None:
    model.compile(
        optimizer=keras.optimizers.AdamW(learning_rate=lr, weight_decay=1e-4),
        loss={
            "plant": weighted_bce(pos_w),
            "quality": masked_sparse_ce(None, len(QUALITY_LABELS), cfg.label_smoothing),
            "crop": masked_sparse_ce(crop_w, len(CROP_LABELS), cfg.label_smoothing),
        },
        loss_weights=cfg.loss_weights,
    )


def unfreeze_top(backbone: keras.Model, from_layer: str) -> int:
    backbone.trainable = True
    names = [layer.name for layer in backbone.layers]
    start = names.index(from_layer)
    n = 0
    for i, layer in enumerate(backbone.layers):
        trainable = i >= start and not isinstance(layer, keras.layers.BatchNormalization)
        layer.trainable = trainable
        n += int(trainable and bool(layer.weights))
    return n


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=RUNS_DIR / "latest")
    parser.add_argument("--head-epochs", type=int, default=None)
    parser.add_argument("--finetune-epochs", type=int, default=None)
    parser.add_argument("--limit", type=int, default=None, help="rows per split (smoke tests)")
    parser.add_argument("--no-pretrained", action="store_true", help="random init (offline smoke tests)")
    args = parser.parse_args()

    cfg = TrainConfig()
    if args.head_epochs is not None:
        cfg = replace(cfg, head_epochs=args.head_epochs)
    if args.finetune_epochs is not None:
        cfg = replace(cfg, finetune_epochs=args.finetune_epochs)
    keras.utils.set_random_seed(cfg.seed)

    rows = read_manifest()
    train_rows = [r for r in rows if r.split == "train"]
    val_rows = [r for r in rows if r.split == "val"]
    if args.limit:
        rng = np.random.default_rng(cfg.seed)
        train_rows = list(rng.permutation(np.array(train_rows, dtype=object))[: args.limit])
        val_rows = val_rows[: max(args.limit // 4, cfg.batch_size)]
    crop_w = crop_class_weights(train_rows)
    pos_w = plant_pos_weight(train_rows)
    print(f"train {len(train_rows)}  val {len(val_rows)}")
    print("crop class weights", dict(zip(CROP_LABELS, np.round(crop_w, 3).tolist(), strict=True)), "plant pos w", pos_w)

    train_ds = train_dataset(train_rows, cfg.degradation, cfg.batch_size, cfg.seed)
    val_ds = eval_dataset(val_rows, cfg.degradation, cfg.batch_size, kind=None)
    steps = max(1, len(train_rows) // cfg.batch_size)

    model, backbone = build_model(cfg.dropout, weights=None if args.no_pretrained else "imagenet",
                                  backbone=cfg.backbone, alpha=cfg.alpha)
    args.out.mkdir(parents=True, exist_ok=True)
    ckpt = args.out / "model.keras"
    history: dict[str, list[float]] = {}
    t0 = time.time()

    def run(epochs: int, initial: int, lr) -> None:
        if epochs <= 0:
            return
        compile_model(model, cfg, lr, crop_w, pos_w)
        cb = [
            keras.callbacks.ModelCheckpoint(ckpt, monitor="val_loss", save_best_only=True),
            keras.callbacks.EarlyStopping(monitor="val_loss", patience=4, restore_best_weights=True),
        ]
        h = model.fit(train_ds, validation_data=val_ds, epochs=initial + epochs, initial_epoch=initial,
                      callbacks=cb, verbose=2)
        for k, v in h.history.items():
            history.setdefault(k, []).extend(float(x) for x in v)

    backbone.trainable = False
    run(cfg.head_epochs, 0, cfg.head_lr)
    n = unfreeze_top(backbone, cfg.finetune_from_layer)
    print(f"stage 2: {n} backbone layers trainable")
    schedule = keras.optimizers.schedules.CosineDecay(cfg.finetune_lr, decay_steps=steps * max(cfg.finetune_epochs, 1),
                                                      alpha=0.05)
    run(cfg.finetune_epochs, cfg.head_epochs, schedule)
    model.save(ckpt)  # restore_best_weights already rolled back to the best epoch of stage 2

    pretrained = None if args.no_pretrained else f"imagenet (keras.applications {cfg.backbone} alpha {cfg.alpha})"
    (args.out / "config.json").write_text(json.dumps(
        {**cfg.to_dict(), "train_rows": len(train_rows), "val_rows": len(val_rows), "pretrained": pretrained,
         "tensorflow": tf.__version__, "keras": keras.__version__, "train_seconds": round(time.time() - t0)},
        indent=2))
    (args.out / "history.json").write_text(json.dumps(history, indent=2))
    (args.out / "class_weights.json").write_text(json.dumps(
        {"crop": dict(zip(CROP_LABELS, crop_w.tolist(), strict=True)), "plant_pos_weight": pos_w}, indent=2))
    print(f"saved {ckpt} in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
