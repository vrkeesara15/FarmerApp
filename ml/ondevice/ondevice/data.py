"""tf.data pipelines: augmentation (lighting, blur, crop, rotation) and synthetic quality labels.

Quality labels are synthesised, not annotated: every image is turned into an `ok`, `blurry` or
`dark` sample by a known transform, so the label is exact. The same transform runs in training
(random) and evaluation (deterministic, seeded per image), see `degrade`.
"""

from __future__ import annotations

import math

import numpy as np
import tensorflow as tf

from .config import CACHE_SIZE, CROP_LABELS, DATA_DIR, INPUT_SIZE, QUALITY_LABELS, Degradation
from .manifest import Row

OK, BLURRY, DARK = (QUALITY_LABELS.index(q) for q in ("ok", "blurry", "dark"))
# Sources whose frames are synthetic flat fields: blur is undefined on them, so their quality
# label is masked (-1) unless the frame is dark.
NO_QUALITY_SOURCES = ("synthetic_negatives",)
KERNEL_RADIUS = 15  # covers 3 sigma of the widest blur


def luminance(image: tf.Tensor) -> tf.Tensor:
    """Mean luminance 0..1 of an HWC float image in 0..255 (same weights as the app heuristic)."""
    y = 0.299 * image[..., 0] + 0.587 * image[..., 1] + 0.114 * image[..., 2]
    return tf.reduce_mean(y) / 255.0


def _gaussian_kernel(sigma: tf.Tensor) -> tf.Tensor:
    x = tf.range(-KERNEL_RADIUS, KERNEL_RADIUS + 1, dtype=tf.float32)
    k = tf.exp(-(x * x) / (2.0 * tf.maximum(sigma, 1e-3) ** 2))
    return k / tf.reduce_sum(k)


def _box_kernel(length: tf.Tensor) -> tf.Tensor:
    x = tf.abs(tf.range(-KERNEL_RADIUS, KERNEL_RADIUS + 1, dtype=tf.float32))
    k = tf.cast(x <= (length - 1.0) / 2.0, tf.float32)
    return k / tf.reduce_sum(k)


def separable_blur(image: tf.Tensor, kh: tf.Tensor, kv: tf.Tensor) -> tf.Tensor:
    """Blur an HWC image with a horizontal and a vertical 1-D kernel (reflect padding)."""
    r = KERNEL_RADIUS
    x = tf.pad(image[None], [[0, 0], [r, r], [r, r], [0, 0]], mode="REFLECT")
    kh4 = tf.tile(tf.reshape(kh, [1, -1, 1, 1]), [1, 1, 3, 1])
    kv4 = tf.tile(tf.reshape(kv, [-1, 1, 1, 1]), [1, 1, 3, 1])
    x = tf.nn.depthwise_conv2d(x, kh4, [1, 1, 1, 1], "VALID")
    x = tf.nn.depthwise_conv2d(x, kv4, [1, 1, 1, 1], "VALID")
    return x[0]


def _identity_kernel() -> tf.Tensor:
    return tf.one_hot(KERNEL_RADIUS, 2 * KERNEL_RADIUS + 1)


def degrade(image: tf.Tensor, kind: tf.Tensor, seed: tf.Tensor, cfg: Degradation) -> tf.Tensor:
    """Apply the quality transform for `kind` (OK / BLURRY / DARK) with stateless randomness."""
    seeds = tf.random.experimental.stateless_split(seed, 6)
    u = [tf.random.stateless_uniform([], seeds[i]) for i in range(6)]

    def ok():
        sigma = u[0] * cfg.ok_sigma_max
        k = tf.cond(sigma > 0.3, lambda: _gaussian_kernel(sigma), _identity_kernel)
        out = separable_blur(image, k, k)
        # ok frames must be clearly lit: lift anything below ok_lum_min.
        lum = luminance(out)
        gain = tf.maximum(1.0, cfg.ok_lum_min / tf.maximum(lum, 1e-3))
        return tf.clip_by_value(out * gain, 0.0, 255.0)

    def blurry():
        sigma = cfg.blur_sigma_min + u[0] * (cfg.blur_sigma_max - cfg.blur_sigma_min)
        g = _gaussian_kernel(sigma)
        length = 2.0 * tf.round(4.0 + u[1] * 8.0) + 1.0  # motion blur 9..25 px
        m = _box_kernel(length)
        ident = _identity_kernel()
        motion = u[2] < 0.35
        horizontal = u[3] < 0.5
        kh = tf.where(motion, tf.where(horizontal, m, ident), g)
        kv = tf.where(motion, tf.where(horizontal, ident, m), g)
        return separable_blur(image, kh, kv)

    def dark():
        target = cfg.dark_lum_min + u[0] * (cfg.dark_lum_max - cfg.dark_lum_min)
        lum = luminance(image)
        gain = tf.minimum(1.0, target / tf.maximum(lum, 1e-3))
        noise = tf.random.stateless_normal(tf.shape(image), seeds[5]) * (1.0 + 4.0 * u[1])
        return tf.clip_by_value(image * gain + noise, 0.0, 255.0)

    return tf.switch_case(tf.cast(kind, tf.int32), [ok, blurry, dark])


def _lighting(image: tf.Tensor) -> tf.Tensor:
    """Photometric jitter for sun / shade / white balance (keeps values in 0..255)."""
    x = image / 255.0
    x = tf.image.random_brightness(x, 0.15)
    x = tf.image.random_contrast(x, 0.75, 1.3)
    x = tf.image.random_saturation(x, 0.7, 1.3)
    x = tf.image.random_hue(x, 0.03)
    return tf.clip_by_value(x, 0.0, 1.0) * 255.0


def _geometry(image: tf.Tensor) -> tf.Tensor:
    """Random scale crop to 224, flips, 90-degree turns and a small free rotation."""
    size = tf.random.uniform([], INPUT_SIZE, CACHE_SIZE + 1, dtype=tf.int32)
    image = tf.image.random_crop(image, [size, size, 3])
    image = tf.image.resize(image, [INPUT_SIZE, INPUT_SIZE])
    image = tf.image.random_flip_left_right(image)
    image = tf.image.random_flip_up_down(image)
    image = tf.image.rot90(image, tf.random.uniform([], 0, 4, dtype=tf.int32))
    angle = tf.random.uniform([], -0.35, 0.35)  # +-20 degrees
    return _rotate(image, angle)


def _rotate(image: tf.Tensor, angle: tf.Tensor) -> tf.Tensor:
    """Rotate about the centre with reflect fill (ImageProjectiveTransformV3, no extra deps)."""
    c, s = tf.cos(angle), tf.sin(angle)
    h = w = float(INPUT_SIZE)
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    # output -> input mapping
    transform = [c, -s, cx - c * cx + s * cy, s, c, cy - s * cx - c * cy, 0.0, 0.0]
    out = tf.raw_ops.ImageProjectiveTransformV3(
        images=image[None],
        transforms=tf.cast(tf.stack(transform)[None], tf.float32),
        output_shape=[INPUT_SIZE, INPUT_SIZE],
        fill_value=0.0,
        interpolation="BILINEAR",
        fill_mode="REFLECT",
    )
    return out[0]


def _centre(image: tf.Tensor) -> tf.Tensor:
    off = (CACHE_SIZE - INPUT_SIZE) // 2
    return image[off : off + INPUT_SIZE, off : off + INPUT_SIZE, :]


def _load(path: tf.Tensor) -> tf.Tensor:
    raw = tf.io.read_file(path)
    image = tf.io.decode_jpeg(raw, channels=3)
    image = tf.ensure_shape(image, [CACHE_SIZE, CACHE_SIZE, 3])
    return tf.cast(image, tf.float32)


def _columns(rows: list[Row]) -> dict[str, np.ndarray]:
    return {
        "path": np.array([str(DATA_DIR / r.path) for r in rows]),
        "plant": np.array([float(r.is_plant) for r in rows], np.float32),
        "crop": np.array([r.crop_index for r in rows], np.int32),
        "quality_mask": np.array([r.source in NO_QUALITY_SOURCES for r in rows]),
    }


def _labels(image, kind, plant, crop, quality_mask):
    # A frame that ends up dark is 'dark' whatever transform produced it (e.g. a covered lens).
    is_dark = luminance(image) < 0.12
    quality = tf.where(is_dark, DARK, tf.cast(kind, tf.int32))
    quality = tf.where(quality_mask & ~is_dark, -1, quality)
    return {"plant": plant[None], "quality": quality, "crop": crop}


def train_dataset(rows: list[Row], cfg: Degradation, batch_size: int, seed: int) -> tf.data.Dataset:
    cols = _columns(rows)
    probs = tf.math.log([[1.0 - cfg.p_blurry - cfg.p_dark, cfg.p_blurry, cfg.p_dark]])

    def make(path, plant, crop, quality_mask):
        image = _geometry(_lighting(_load(path)))
        kind = tf.random.categorical(probs, 1, dtype=tf.int32)[0, 0]
        s = tf.random.uniform([2], 0, 2**31 - 1, dtype=tf.int32)
        image = degrade(image, kind, s, cfg)
        image = tf.ensure_shape(image, [INPUT_SIZE, INPUT_SIZE, 3])
        return image, _labels(image, kind, plant, crop, quality_mask)

    ds = tf.data.Dataset.from_tensor_slices((cols["path"], cols["plant"], cols["crop"], cols["quality_mask"]))
    ds = ds.shuffle(len(rows), seed=seed, reshuffle_each_iteration=True)
    ds = ds.map(make, num_parallel_calls=tf.data.AUTOTUNE)
    return ds.batch(batch_size, drop_remainder=True).prefetch(tf.data.AUTOTUNE)


MIXED_KINDS = (OK, OK, OK, BLURRY, DARK)


def eval_dataset(rows: list[Row], cfg: Degradation, batch_size: int, kind: int | None) -> tf.data.Dataset:
    """Deterministic centre-crop images with quality transform `kind`, seeded by row index.

    kind=None mixes transforms by row index (3/5 ok, 1/5 blurry, 1/5 dark) for validation.
    """
    cols = _columns(rows)
    idx = np.arange(len(rows), dtype=np.int32)
    if kind is None:
        kinds = np.array([MIXED_KINDS[i % len(MIXED_KINDS)] for i in idx], np.int32)
    else:
        kinds = np.full(len(rows), kind, np.int32)

    def make(i, k, path, plant, crop, quality_mask):
        image = _centre(_load(path))
        image = degrade(image, k, tf.stack([i, k + 7]), cfg)
        image = tf.ensure_shape(image, [INPUT_SIZE, INPUT_SIZE, 3])
        return image, _labels(image, k, plant, crop, quality_mask)

    ds = tf.data.Dataset.from_tensor_slices(
        (idx, kinds, cols["path"], cols["plant"], cols["crop"], cols["quality_mask"])
    )
    return ds.map(make, num_parallel_calls=tf.data.AUTOTUNE).batch(batch_size).prefetch(tf.data.AUTOTUNE)


def crop_class_weights(rows: list[Row]) -> np.ndarray:
    """Inverse-frequency weights over plant rows, normalised to mean 1 (sqrt-damped)."""
    counts = np.array([sum(r.crop_index == i for r in rows) for i in range(len(CROP_LABELS))], np.float64)
    w = np.where(counts > 0, (counts.sum() / np.maximum(counts, 1) / len(CROP_LABELS)) ** 0.5, 0.0)
    return (w / w[counts > 0].mean()).astype(np.float32)


def plant_pos_weight(rows: list[Row]) -> float:
    pos = sum(r.is_plant for r in rows)
    neg = len(rows) - pos
    return float(math.sqrt(neg / max(pos, 1)))
