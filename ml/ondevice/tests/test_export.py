"""Model graph, export surgery, int8 conversion and the shipped artefact."""

import hashlib
import json

import numpy as np
import pytest
from ai_edge_litert.interpreter import Interpreter

from ondevice.config import ARTIFACTS_DIR, CROP_LABELS, INPUT_SIZE, MAX_TFLITE_BYTES, OUTPUT_LAYOUT, TFLITE_NAME
from ondevice.model import build_model, decode_scores, export_model, fold_dead_se_channels

ARTIFACT = ARTIFACTS_DIR / TFLITE_NAME


@pytest.fixture(scope="module")
def model():
    m, _ = build_model(weights=None)
    return m


def scores(m, x):
    out = m.predict_on_batch(x)
    return np.concatenate([out["plant"], out["quality"], out["crop"]], axis=1)


def test_fold_is_a_no_op_without_squeeze_excite(model):
    x = np.zeros((1, INPUT_SIZE, INPUT_SIZE, 3), np.float32)
    assert fold_dead_se_channels(model, x) == {}


def test_heads_and_export_shape(model):
    x = np.random.default_rng(0).uniform(0, 255, (2, INPUT_SIZE, INPUT_SIZE, 3)).astype(np.float32)
    s = scores(model, x)
    assert s.shape == (2, len(OUTPUT_LAYOUT))
    assert np.allclose(s[:, 1:4].sum(1), 1, atol=1e-4) and np.allclose(s[:, 4:].sum(1), 1, atol=1e-4)
    wrapped = export_model(model)
    assert wrapped.output_shape == (1, len(OUTPUT_LAYOUT))
    np.testing.assert_allclose(wrapped.predict_on_batch(x[:1]), s[:1], atol=1e-5)


def test_decode_scores():
    raw = np.array([0.9, 0.7, 0.2, 0.1] + [0.0] * 6 + [1.0], np.float32)
    d = decode_scores(raw)
    assert d["plant"] == pytest.approx(0.9)
    assert list(d["quality"]) == ["ok", "blurry", "dark"]
    assert list(d["crop"]) == list(CROP_LABELS) and d["crop"]["other"] == 1.0


def test_fold_dead_se_channels_preserves_function():
    m, bb = build_model(weights=None, backbone="mobilenet_v3s")
    # Kill every channel of one SE block and half of another, as the ImageNet weights do.
    for name, frac in (("expanded_conv_6_squeeze_excite_conv", 1.0), ("expanded_conv_3_squeeze_excite_conv", 0.5)):
        layer = bb.get_layer(name)
        k, b = layer.get_weights()
        n = int(len(b) * frac)
        k[..., :n] = 0.0
        b[:n] = -5.0
        layer.set_weights([k, b])
    x = np.random.default_rng(1).uniform(0, 255, (8, INPUT_SIZE, INPUT_SIZE, 3)).astype(np.float32)
    before = scores(m, x)
    report = fold_dead_se_channels(m, x)
    n_se6 = len(bb.get_layer("expanded_conv_6_squeeze_excite_conv").get_weights()[1])
    assert report["expanded_conv_6_squeeze_excite_conv"] == n_se6
    assert report["expanded_conv_3_squeeze_excite_conv"] >= 1
    np.testing.assert_allclose(scores(m, x), before, atol=1e-4)
    # The folded all-dead block now has one constant live channel -> non-degenerate int8 range.
    assert bb.get_layer("expanded_conv_6_squeeze_excite_conv").get_weights()[1].max() == 1.0


def test_int8_conversion_end_to_end(model):
    """Random-weight model through the real export path: int8, < 8 MB, loads under XNNPACK."""
    from export import quantize_model

    calib = np.random.default_rng(2).uniform(0, 255, (4, INPUT_SIZE, INPUT_SIZE, 3)).astype(np.float32)
    tflite, _ = quantize_model(model, calib)
    assert len(tflite) < MAX_TFLITE_BYTES
    check_interpreter(Interpreter(model_content=tflite, num_threads=1))


def check_interpreter(it: Interpreter) -> np.ndarray:
    it.allocate_tensors()  # the default resolver applies XNNPACK; this fails if XNNPACK rejects the graph
    inp, out = it.get_input_details(), it.get_output_details()
    assert len(inp) == 1 and len(out) == 1
    assert inp[0]["shape"].tolist() == [1, INPUT_SIZE, INPUT_SIZE, 3]
    assert inp[0]["dtype"] == np.uint8
    scale, zero = inp[0]["quantization"]
    assert scale == pytest.approx(1.0, rel=1e-3) and zero == 0  # feed raw RGB bytes
    assert out[0]["shape"].tolist() == [1, len(OUTPUT_LAYOUT)]
    assert out[0]["dtype"] == np.float32
    x = np.random.default_rng(3).integers(0, 256, (1, INPUT_SIZE, INPUT_SIZE, 3), dtype=np.uint8)
    it.set_tensor(inp[0]["index"], x)
    it.invoke()
    s = it.get_tensor(out[0]["index"])[0]
    assert 0.0 <= s[0] <= 1.0
    assert s[1:4].sum() == pytest.approx(1.0, abs=0.02) and s[4:].sum() == pytest.approx(1.0, abs=0.02)
    return s


@pytest.mark.skipif(not ARTIFACT.exists(), reason="no exported artefact yet (make export)")
def test_shipped_artifact_size_shapes_and_hash():
    assert ARTIFACT.stat().st_size < MAX_TFLITE_BYTES  # DX-001
    check_interpreter(Interpreter(model_path=str(ARTIFACT), num_threads=1))
    meta = json.loads((ARTIFACTS_DIR / "metadata.json").read_text())
    data = ARTIFACT.read_bytes()
    assert meta["sha256"] == hashlib.sha256(data).hexdigest()
    assert meta["size_bytes"] == len(data)
    assert meta["input"]["shape"] == [1, INPUT_SIZE, INPUT_SIZE, 3] and meta["input"]["dtype"] == "uint8"
    assert meta["output"]["shape"] == [1, len(OUTPUT_LAYOUT)]
