"""Data pipeline: manifest split, validation, degradations and dataset shapes."""

import json

import numpy as np
import pytest
import tensorflow as tf
from PIL import Image

from ondevice.config import CROP_LABELS, INPUT_SIZE, SOURCES, Degradation
from ondevice.data import BLURRY, DARK, OK, crop_class_weights, degrade, eval_dataset, luminance, train_dataset
from ondevice.manifest import Row, read_manifest, split_for, validate, write_manifest

CFG = Degradation()


def laplacian_var(img: np.ndarray) -> float:
    y = img @ np.array([0.299, 0.587, 0.114], np.float32)
    lap = y[:-2, 1:-1] + y[2:, 1:-1] + y[1:-1, :-2] + y[1:-1, 2:] - 4 * y[1:-1, 1:-1]
    return float(lap.var())


def textured(seed: int = 0) -> tf.Tensor:
    rng = np.random.default_rng(seed)
    base = rng.integers(40, 220, (INPUT_SIZE // 8, INPUT_SIZE // 8, 3)).astype(np.uint8)
    img = np.asarray(Image.fromarray(base).resize((INPUT_SIZE, INPUT_SIZE), Image.Resampling.NEAREST), np.float32)
    return tf.constant(img)


def test_split_is_stable_and_proportional():
    assert split_for("rice_india", "data/train-00000-of-00001.parquet#0") == split_for(
        "rice_india", "data/train-00000-of-00001.parquet#0")
    splits = [split_for("s", str(i)) for i in range(20000)]
    frac = {s: splits.count(s) / len(splits) for s in ("train", "val", "test")}
    assert abs(frac["test"] - 0.15) < 0.01 and abs(frac["val"] - 0.15) < 0.01


def test_validate_rejects_inconsistent_rows():
    good = Row("cache/x/1.jpg", "x", "1", 1, "paddy", "Blast", "CC-BY-4.0", "train")
    validate(good)
    with pytest.raises(ValueError):
        validate(Row("p", "x", "1", 1, "rice", "", "", "train"))  # unknown crop
    with pytest.raises(ValueError):
        validate(Row("p", "x", "1", 0, "paddy", "", "", "train"))  # non-plant with crop
    with pytest.raises(ValueError):
        validate(Row("p", "x", "1", 1, "paddy", "", "", "holdout"))  # bad split
    assert good.crop_index == CROP_LABELS.index("paddy")
    assert Row("p", "x", "1", 0, "", "", "", "test").crop_index == -1


def test_manifest_round_trip(tmp_path):
    rows = [Row("a.jpg", "s", "k1", 1, "cotton", "Curl", "CC-BY-4.0", "train"),
            Row("b.jpg", "t", "k2", 0, "", "car", "CC-BY-4.0", "test")]
    write_manifest(rows, tmp_path / "m.csv")
    assert read_manifest(tmp_path / "m.csv") == rows


def test_sources_are_pinned_and_licensed():
    sources = json.loads(SOURCES.read_text())["sources"]
    ids = [s["id"] for s in sources]
    assert len(ids) == len(set(ids))
    crops = set()
    for s in sources:
        assert s["licence"]
        if s["format"] != "synthetic":
            assert s["licence"] == "CC-BY-4.0", s["id"]
            assert len(s["revision"]) == 40
            assert all(f["size"] > 0 and f["sha256"] and len(f["sha256"]) == 64 for f in s["files"])
        crops.update([s["crop"]] if s.get("crop") else s.get("crop_map", {}).values())
    assert crops == set(CROP_LABELS), "every crop label needs at least one bootstrap source"


def test_blur_lowers_sharpness_and_ok_keeps_it():
    img = textured()
    sharp = laplacian_var(img.numpy())
    ok = degrade(img, tf.constant(OK), tf.constant([1, 2]), CFG).numpy()
    blurry = degrade(img, tf.constant(BLURRY), tf.constant([1, 2]), CFG).numpy()
    assert laplacian_var(ok) > 0.5 * sharp
    assert laplacian_var(blurry) < 0.1 * sharp


def test_dark_hits_target_luminance_and_ok_is_lit():
    img = textured(3)
    for seed in range(5):
        dark = degrade(img, tf.constant(DARK), tf.constant([seed, 9]), CFG)
        assert float(luminance(dark)) < CFG.dark_lum_max + 0.02
    dim = img * 0.05
    ok = degrade(dim, tf.constant(OK), tf.constant([0, 1]), CFG)
    assert float(luminance(ok)) >= CFG.ok_lum_min - 1e-3


def test_degrade_is_deterministic_per_seed():
    img = textured(5)
    a = degrade(img, tf.constant(BLURRY), tf.constant([4, 4]), CFG).numpy()
    b = degrade(img, tf.constant(BLURRY), tf.constant([4, 4]), CFG).numpy()
    np.testing.assert_array_equal(a, b)


@pytest.fixture()
def tiny_rows(tmp_path):
    rows = []
    rng = np.random.default_rng(0)
    for i in range(8):
        path = tmp_path / f"{i}.jpg"
        Image.fromarray(rng.integers(0, 255, (256, 256, 3), dtype=np.uint8)).save(path)
        plant = i % 2 == 0
        source = "caltech101" if not plant else "rice_india"
        if i == 7:
            source = "synthetic_negatives"
        rows.append(Row(str(path), source, str(i), int(plant), "paddy" if plant else "", "", "x", "train"))
    return rows


def test_train_dataset_shapes(tiny_rows):
    ds = train_dataset(tiny_rows, CFG, batch_size=4, seed=1)
    images, labels = next(iter(ds))
    assert images.shape == (4, INPUT_SIZE, INPUT_SIZE, 3) and images.dtype == tf.float32
    assert float(tf.reduce_min(images)) >= 0.0 and float(tf.reduce_max(images)) <= 255.0
    assert labels["plant"].shape == (4, 1)
    assert labels["quality"].shape == (4,) and labels["crop"].shape == (4,)


def test_eval_dataset_labels_and_masks(tiny_rows):
    ds = eval_dataset(tiny_rows, CFG, batch_size=8, kind=BLURRY)
    images, labels = next(iter(ds))
    crop = labels["crop"].numpy()
    assert list(crop) == [0, -1, 0, -1, 0, -1, 0, -1]  # non-plant rows carry no crop
    quality = labels["quality"].numpy()
    assert quality[7] == -1  # synthetic frames: blur label masked
    assert set(quality[:7]) <= {BLURRY, DARK}
    again = next(iter(eval_dataset(tiny_rows, CFG, batch_size=8, kind=BLURRY)))[0]
    np.testing.assert_allclose(images.numpy(), again.numpy())


def test_crop_class_weights_upweight_rare_classes():
    rows = [Row("p", "s", str(i), 1, "paddy", "", "", "train") for i in range(100)]
    rows += [Row("p", "s", f"c{i}", 1, "chilli", "", "", "train") for i in range(25)]
    w = crop_class_weights(rows)
    assert w[CROP_LABELS.index("chilli")] > w[CROP_LABELS.index("paddy")]
    assert w[CROP_LABELS.index("cotton")] == 0.0  # absent class
