"""ImageNet MobileNet backbone with three heads (plant, quality, crop) and the single-tensor export.

Input: float32 RGB 0..255, 224x224. A Rescaling layer inside the backbone maps to -1..1, so the int8
TFLite input is plain uint8 RGB with scale 1 / zero point 0.

Backbones (config.TrainConfig.backbone):
  mobilenet_v2   default. Plain ReLU6 inverted residuals: int8 post-training quantisation costs
                 about a point of accuracy.
  mobilenet_v3s  smaller and faster, but hard-swish + squeeze-excite do not survive int8 PTQ
                 (measured on this task, float -> int8: plant 99.9 -> 88.8 %, quality
                 99.4 -> 81.1 %, crop 97.8 -> 80.2 %); it would need
                 quantisation-aware training, which tfmot does not offer for Keras 3. Kept for
                 comparison and for a float16 / QAT path later.
"""

from __future__ import annotations

import keras
import numpy as np
import tensorflow as tf

from .config import CROP_LABELS, INPUT_SIZE, OUTPUT_LAYOUT, QUALITY_LABELS

# Early 28x28 feature map pooled into the quality head: blur and exposure are low-level cues that
# the final 7x7 features mostly discard.
EARLY_LAYER = {"mobilenet_v2": "block_5_add", "mobilenet_v3s": "expanded_conv_2_add"}


def build_model(
    dropout: float = 0.25,
    weights: str | None = "imagenet",
    backbone: str = "mobilenet_v2",
    alpha: float = 1.0,
) -> tuple[keras.Model, keras.Model]:
    """Return (model, core). The model maps an image to {"plant", "quality", "crop"}; `core` is the
    flat ImageNet graph whose layers train.py unfreezes by name."""
    shape = (INPUT_SIZE, INPUT_SIZE, 3)
    pixels = keras.Input(shape, name="pixels")
    if backbone == "mobilenet_v3s":
        base = keras.applications.MobileNetV3Small(input_shape=shape, alpha=alpha, include_top=False,
                                                   weights=weights, include_preprocessing=True)
        scaled = pixels  # MobileNetV3 carries its own Rescaling layer
    elif backbone == "mobilenet_v2":
        base = keras.applications.MobileNetV2(input_shape=shape, alpha=alpha, include_top=False, weights=weights)
        scaled = keras.layers.Rescaling(1.0 / 127.5, offset=-1.0, name="rescale")(pixels)
    else:
        raise ValueError(f"unknown backbone {backbone!r}")
    core = keras.Model(base.input, [base.output, base.get_layer(EARLY_LAYER[backbone]).output], name="core")
    feat_model = keras.Model(pixels, core(scaled), name="backbone")

    image = keras.Input((INPUT_SIZE, INPUT_SIZE, 3), name="image")
    final, early_map = feat_model(image)
    g = keras.layers.GlobalAveragePooling2D(name="gap")(final)
    g = keras.layers.Dropout(dropout, name="drop")(g)
    e = keras.layers.GlobalAveragePooling2D(name="gap_early")(early_map)
    e_std = keras.layers.GlobalMaxPooling2D(name="gmp_early")(early_map)

    plant = keras.layers.Dense(1, activation="sigmoid", name="plant")(g)

    q = keras.layers.Concatenate(name="quality_features")([g, e, e_std])
    q = keras.layers.Dense(64, activation="relu", name="quality_hidden")(q)
    quality = keras.layers.Dense(len(QUALITY_LABELS), activation="softmax", name="quality")(q)

    c = keras.layers.Dense(128, activation="relu", name="crop_hidden")(g)
    c = keras.layers.Dropout(dropout, name="crop_drop")(c)
    crop = keras.layers.Dense(len(CROP_LABELS), activation="softmax", name="crop")(c)

    model = keras.Model(image, {"plant": plant, "quality": quality, "crop": crop}, name="crop_quality")
    return model, core


def export_model(model: keras.Model) -> keras.Model:
    """Wrap the trained model so it emits one [1, 11] float tensor in OUTPUT_LAYOUT order."""
    image = keras.Input((INPUT_SIZE, INPUT_SIZE, 3), batch_size=1, name="image")
    out = model(image, training=False)
    scores = keras.layers.Concatenate(name="scores")([out["plant"], out["quality"], out["crop"]])
    wrapped = keras.Model(image, scores, name="crop_quality_export")
    assert wrapped.output_shape == (1, len(OUTPUT_LAYOUT)), wrapped.output_shape
    return wrapped


def decode_scores(scores: np.ndarray) -> dict:
    """Numpy mirror of the app's output decoding (INTEGRATION.md)."""
    s = np.asarray(scores, np.float32).reshape(-1)
    nq = len(QUALITY_LABELS)
    return {
        "plant": float(s[0]),
        "quality": dict(zip(QUALITY_LABELS, map(float, s[1 : 1 + nq]), strict=True)),
        "crop": dict(zip(CROP_LABELS, map(float, s[1 + nq :]), strict=True)),
    }


# ---- losses (masked, class-weighted) -------------------------------------------------------------


def masked_sparse_ce(class_weights: np.ndarray | None, n: int, smoothing: float):
    """Sparse CE that ignores label -1 and weights by class; returns a per-sample loss."""
    cw = tf.constant(class_weights if class_weights is not None else np.ones(n, np.float32), tf.float32)

    def loss(y_true, y_pred):
        y = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        valid = y >= 0
        y_safe = tf.where(valid, y, 0)
        target = tf.one_hot(y_safe, n) * (1.0 - smoothing) + smoothing / n
        ce = -tf.reduce_sum(target * tf.math.log(tf.clip_by_value(y_pred, 1e-7, 1.0)), axis=-1)
        w = tf.gather(cw, y_safe) * tf.cast(valid, tf.float32)
        return ce * w

    return loss


def weighted_bce(pos_weight: float):
    def loss(y_true, y_pred):
        y = tf.cast(tf.reshape(y_true, [-1]), tf.float32)
        p = tf.clip_by_value(tf.reshape(y_pred, [-1]), 1e-7, 1 - 1e-7)
        ce = -(y * tf.math.log(p) + (1 - y) * tf.math.log(1 - p))
        return ce * (y * pos_weight + (1 - y))

    return loss


# ---- export surgery -------------------------------------------------------------------------------


def fold_dead_se_channels(model: keras.Model, images: np.ndarray) -> dict[str, int]:
    """Neutralise squeeze-excite channels whose ReLU never fires, without changing the function.

    The ImageNet MobileNetV3-Small weights ship SE blocks with dead squeeze channels (in
    `expanded_conv_6` all 32 are dead). int8 conversion then gives the squeeze output a [0, 0]
    range, and XNNPACK refuses the resulting requantisation scale (>= 256), so the model would not
    load with the default CPU delegate. A channel is dead if its pre-activation is <= 0 on every
    calibration image: its kernel and bias are set to 0 (the ReLU output is 0 either way). If a
    whole block is dead, channel 0 becomes a constant 1 and its contribution is subtracted from the
    excite bias, so the excite output is unchanged and the tensor range is non-degenerate.
    Returns {layer name: dead channels}.
    """
    backbone = model.get_layer("backbone").get_layer("core")
    names = [layer.name for layer in backbone.layers if layer.name.endswith("squeeze_excite_conv")]
    if not names:  # MobileNetV2 has no squeeze-excite blocks
        return {}
    probe = keras.Model(backbone.input, [backbone.get_layer(n).output for n in names])
    maxima = None
    for start in range(0, len(images), 32):
        outs = probe.predict_on_batch(images[start : start + 32])
        batch = [o.reshape(-1, o.shape[-1]).max(0) for o in outs]
        maxima = batch if maxima is None else [np.maximum(a, b) for a, b in zip(maxima, batch, strict=True)]
    report = {}
    for name, peak in zip(names, maxima, strict=True):
        dead = peak <= 0.0
        if not dead.any():
            continue
        squeeze = backbone.get_layer(name)
        excite = backbone.get_layer(name + "_1")
        k, b = squeeze.get_weights()
        k2, b2 = excite.get_weights()
        k[..., dead] = 0.0
        b[dead] = 0.0
        if dead.all():
            b[0] = 1.0  # constant channel: ReLU(1) = 1
            b2 = b2 - k2[0, 0, 0, :]  # excite weight kept (sane scales); its effect cancelled here
        squeeze.set_weights([k, b])
        excite.set_weights([k2, b2])
        report[name] = int(dead.sum())
    return report
