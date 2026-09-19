"""Prove the contract end to end: the API's own ``RemoteEncoder`` against a running embed service.

Run with the **API's** environment (read-only use of apps/api), e.g. from the repo root:

    UV_PROJECT_ENVIRONMENT=/tmp/apivenv uv sync --frozen --project apps/api
    /tmp/apivenv/bin/python ml/embed/scripts/check_remote_encoder.py --url http://localhost:8095

Checks: pinned name / version / dim accepted, one unit vector per image in order, the API's
own synthetic seed images embed, two variants of one problem are closer than a non-plant photo,
and a client pinned to another version is refused (service 409 -> ``EncoderError``), so vectors of
two encoders can never be mixed.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "apps" / "api"))

from farmerapp.diagnosis import images as api_images  # noqa: E402
from farmerapp.diagnosis.encoder import (  # noqa: E402
    EMBEDDING_DIM,
    EncoderError,
    EncoderInfo,
    RemoteEncoder,
    cosine,
)
from farmerapp.settings import Settings  # noqa: E402


async def run(url: str) -> dict[str, object]:
    settings = Settings()
    info = EncoderInfo(settings.diagnosis_encoder_name, settings.diagnosis_encoder_version)
    encoder = RemoteEncoder(base_url=url, info=info, timeout_s=settings.diagnosis_embed_timeout_s)

    leaf, non_plant = api_images.synthetic_leaf, api_images.synthetic_non_plant
    photos = [
        leaf("paddy_blast", 0),
        leaf("paddy_blast", 1),
        leaf("cotton_pink_bollworm", 0),
        non_plant("document", 0),
        non_plant("brick", 0),
    ]

    started = time.perf_counter()
    vectors = await encoder.encode(photos)
    elapsed_ms = (time.perf_counter() - started) * 1000
    assert len(vectors) == len(photos)
    for vector in vectors:
        assert len(vector) == EMBEDDING_DIM == info.dim
        assert abs(float(np.linalg.norm(vector)) - 1.0) < 1e-5
    same_problem = cosine(vectors[0], vectors[1])
    other_problem = cosine(vectors[0], vectors[2])
    non_plants = [cosine(vectors[0], v) for v in vectors[3:]]
    assert same_problem > max(non_plants), (same_problem, non_plants)

    wrong = RemoteEncoder(base_url=url, info=EncoderInfo(info.name, "2099-01"))
    try:
        await wrong.encode(photos[:1])
        refused = False
    except EncoderError:
        refused = True
    assert refused, "a client pinned to another version must be refused"

    return {
        "pinned": info.label,
        "vectors": len(vectors),
        "dim": len(vectors[0]),
        "cos_same_problem_variants": round(same_problem, 4),
        "cos_other_problem": round(other_problem, 4),
        "cos_leaf_vs_non_plant_max": round(max(non_plants), 4),
        "batch_ms": round(elapsed_ms, 1),
        "other_version_refused": refused,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost:8095")
    args = parser.parse_args()
    print(json.dumps(asyncio.run(run(args.url)), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
