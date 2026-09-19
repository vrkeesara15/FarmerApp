"""The API's encoder contract (docs/prs/M6-diagnosis-api.md, "Encoder service contract").

Shapes are the PR doc's JSON verbatim; ``apps/api/farmerapp/diagnosis/encoder.py``'s
``RemoteEncoder`` posts exactly ``{"model", "version", "images": [{"b64"}]}`` to ``/v1/embed`` and
refuses a response whose model / version / dim differ or whose vector count / length is wrong.
"""

from __future__ import annotations

import base64

import numpy as np
from images import gradient, jpeg, leaf, unrelated

from embed import spec

# The PR doc's request / response, verbatim (vectors elided there).
DOC_REQUEST = {"model": "siglip-base-patch16-224", "version": "2024-01", "images": [{"b64": "<base64>"}]}
DOC_RESPONSE_KEYS = {"model", "version", "dim", "vectors"}
# The API's defaults (apps/api/farmerapp/settings.py: DIAGNOSIS_ENCODER_NAME / _VERSION).
API_PINNED_NAME, API_PINNED_VERSION, API_DIM = "siglip-base-patch16-224", "2024-01", 768


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def request(*blobs: bytes, model: str = spec.NAME, version: str = spec.VERSION) -> dict:
    return {"model": model, "version": version, "images": [{"b64": b64(b)} for b in blobs]}


def test_pinned_identity_matches_the_api_settings() -> None:
    assert (spec.NAME, spec.VERSION, spec.DIM) == (API_PINNED_NAME, API_PINNED_VERSION, API_DIM)
    assert (DOC_REQUEST["model"], DOC_REQUEST["version"]) == (spec.NAME, spec.VERSION)
    assert len(spec.REVISION) == 40 and int(spec.REVISION, 16) >= 0


def test_embed_response_shape_dim_and_unit_norm(client) -> None:
    body = request(jpeg(leaf()), jpeg(unrelated()), jpeg(gradient()))
    assert set(body) == set(DOC_REQUEST) and set(body["images"][0]) == set(DOC_REQUEST["images"][0])
    resp = client.post("/v1/embed", json=body)
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert set(payload) == DOC_RESPONSE_KEYS
    assert payload["model"] == API_PINNED_NAME
    assert str(payload["version"]) == API_PINNED_VERSION
    assert int(payload["dim"]) == API_DIM
    vectors = payload["vectors"]
    assert isinstance(vectors, list) and len(vectors) == 3
    for vector in vectors:
        assert isinstance(vector, list) and len(vector) == API_DIM
        assert all(isinstance(v, float) for v in vector)
        assert abs(float(np.linalg.norm(vector)) - 1.0) < 1e-5


def test_order_preserved_and_batch_equals_singles(client) -> None:
    blobs = [jpeg(leaf(1)), jpeg(unrelated()), jpeg(leaf(2))]
    batch = np.asarray(client.post("/v1/embed", json=request(*blobs)).json()["vectors"])
    singles = np.asarray([client.post("/v1/embed", json=request(b)).json()["vectors"][0] for b in blobs])
    assert np.allclose(batch, singles, atol=1e-5)
    assert not np.allclose(batch[0], batch[1], atol=1e-3)


def test_deterministic_for_the_same_image(client) -> None:
    blob = jpeg(leaf(3))
    a = client.post("/v1/embed", json=request(blob)).json()["vectors"][0]
    b = client.post("/v1/embed", json=request(blob)).json()["vectors"][0]
    assert a == b


def test_other_model_or_version_is_refused_409(client) -> None:
    blob = jpeg(leaf())
    for model, version in (("dinov2-base", spec.VERSION), (spec.NAME, "2025-01")):
        resp = client.post("/v1/embed", json=request(blob, model=model, version=version))
        assert resp.status_code == 409
        assert resp.headers["content-type"].startswith("application/problem+json")
        problem = resp.json()
        assert problem["code"] == "model_mismatch"
        assert problem["served"] == {"model": spec.NAME, "version": spec.VERSION, "dim": spec.DIM}


def test_healthz(client) -> None:
    resp = client.get("/healthz")
    assert resp.status_code == 200 and resp.json() == {"status": "ok"}


def test_info_fields(client, settings) -> None:
    info = client.get("/info").json()
    assert {"name", "version", "dim", "revision"} <= set(info)
    assert info["name"] == spec.NAME and info["version"] == spec.VERSION and info["dim"] == 768
    assert info["revision"] == spec.REVISION
    assert info["max_batch"] == settings.max_batch == 8  # the contract's batch size
    assert info["device"] == "cpu"
