"""Real pinned weights (``-m integration``): semantics, processor parity, served identity.

Uses ``EMBED_MODEL_DIR`` (default ``ml/embed/.model``); fetches the pinned revision there if it is
missing (~800 MB download, ~370 MB kept).
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import numpy as np
import pytest
from images import gradient, jpeg, leaf, near_duplicate, unrelated

from embed import spec
from embed.encoder import Encoder, decode_rgb

pytestmark = pytest.mark.integration

MODEL_DIR = Path(os.environ.get("EMBED_MODEL_DIR", Path(__file__).resolve().parents[1] / ".model"))


@pytest.fixture(scope="module")
def real() -> Encoder:
    if not (MODEL_DIR / spec.MANIFEST).exists():
        from embed.fetch import fetch

        fetch(MODEL_DIR)
    return Encoder.load(MODEL_DIR)


def cos(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b))


def test_manifest_pins_the_revision(real: Encoder) -> None:
    manifest = json.loads((MODEL_DIR / spec.MANIFEST).read_text())
    assert manifest["revision"] == spec.REVISION == real.info.revision
    assert manifest["source_weights_sha256"] == spec.WEIGHTS_SHA256
    assert manifest["licence"] == spec.LICENCE


def test_dim_norm_and_determinism(real: Encoder) -> None:
    blob = jpeg(leaf())
    a, b = real.encode([blob])[0], real.encode([blob])[0]
    assert a.shape == (768,) and abs(np.linalg.norm(a) - 1) < 1e-6
    assert np.array_equal(a, b)


def test_near_duplicates_closer_than_unrelated(real: Encoder) -> None:
    base = leaf(1)
    v = real.encode(
        [
            jpeg(base),
            jpeg(near_duplicate(base), quality=60),
            jpeg(leaf(5)),
            jpeg(unrelated()),
            jpeg(gradient()),
        ]
    )
    same_scene, other_leaf, city, grad = cos(v[0], v[1]), cos(v[0], v[2]), cos(v[0], v[3]), cos(v[0], v[4])
    print(
        f"\ncosine: near-duplicate {same_scene:.3f}, other leaf {other_leaf:.3f}, "
        f"city {city:.3f}, gradient {grad:.3f}"
    )
    assert same_scene > 0.85
    assert same_scene > city + 0.2 and same_scene > grad + 0.2
    assert other_leaf > city  # another diseased leaf is nearer than a street scene


def test_jpeg_recompression_is_stable(real: Encoder) -> None:
    img = leaf(2)
    a, b = real.encode([jpeg(img, quality=95), jpeg(img, quality=50)])
    assert cos(a, b) > 0.95


def test_preprocessing_matches_transformers_processor(real: Encoder) -> None:
    from transformers import SiglipImageProcessorPil

    processor = SiglipImageProcessorPil.from_pretrained(MODEL_DIR)
    image = decode_rgb(jpeg(leaf(4)))
    theirs = processor(images=image, return_tensors="np")["pixel_values"][0]
    ours = real.preprocess(image)
    assert ours.shape == theirs.shape == (3, 224, 224)
    assert np.abs(ours - theirs).max() < 1e-2  # identical up to uint8 rounding in PIL resize
