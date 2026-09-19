"""Label order and output layout are the mobile contract (INTEGRATION.md): pin them."""

import json
import re

from ondevice.config import (
    ARTIFACTS_DIR,
    CROP_LABELS,
    INPUT_SIZE,
    MODEL_VERSION,
    OUTPUT_LAYOUT,
    QUALITY_LABELS,
    TFLITE_NAME,
    Thresholds,
)


def test_crop_label_order_is_frozen():
    assert CROP_LABELS == ("paddy", "cotton", "chilli", "maize", "tomato", "groundnut", "other")


def test_quality_label_order_is_frozen():
    assert QUALITY_LABELS == ("ok", "blurry", "dark")


def test_output_layout_is_frozen():
    assert OUTPUT_LAYOUT == (
        "plant",
        "quality_ok", "quality_blurry", "quality_dark",
        "crop_paddy", "crop_cotton", "crop_chilli", "crop_maize", "crop_tomato", "crop_groundnut", "crop_other",
    )
    assert len(OUTPUT_LAYOUT) == 11


def test_version_and_file_name():
    assert re.fullmatch(r"ondevice-v\d+\.\d+", MODEL_VERSION)
    assert TFLITE_NAME == "crop_quality_v1.tflite"
    assert INPUT_SIZE == 224


def test_thresholds_are_probabilities():
    th = Thresholds()
    for value in (th.plant_min, th.blurry_min, th.dark_min, th.crop_min):
        assert 0.0 < value < 1.0


def test_shipped_metadata_matches_code():
    meta_path = ARTIFACTS_DIR / "metadata.json"
    if not meta_path.exists():
        import pytest

        pytest.skip("no exported artefact yet (make export)")
    meta = json.loads(meta_path.read_text())
    assert meta["labels"]["crop"] == list(CROP_LABELS)
    assert meta["labels"]["quality"] == list(QUALITY_LABELS)
    assert meta["output"]["layout"] == list(OUTPUT_LAYOUT)
    assert meta["model_version"] == MODEL_VERSION
    assert meta["file"] == TFLITE_NAME
    assert meta["source"] == "public"
    th = Thresholds()
    assert meta["thresholds"] == {"plant_min": th.plant_min, "blurry_min": th.blurry_min,
                                  "dark_min": th.dark_min, "crop_min": th.crop_min}
    for src in meta["training"]["data_sources"]:
        assert src["licence"], src["id"]
