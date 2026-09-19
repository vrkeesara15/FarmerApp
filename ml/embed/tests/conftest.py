from __future__ import annotations

import sys
from collections.abc import Iterator
from pathlib import Path

import pytest
import torch
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from embed import spec  # noqa: E402
from embed.app import Settings, create_app  # noqa: E402
from embed.encoder import Encoder, EncoderInfo, Preprocess  # noqa: E402


def tiny_encoder() -> Encoder:
    """Same architecture family and output width as the pinned model, random weights, 1 layer.

    Contract / validation tests run in seconds without the 370 MB download; the semantic checks
    (near duplicates, processor parity) are in ``test_integration.py`` against the real weights.
    """
    from transformers import SiglipVisionConfig, SiglipVisionModel

    torch.manual_seed(0)
    config = SiglipVisionConfig(
        hidden_size=spec.DIM,
        intermediate_size=512,
        num_hidden_layers=1,
        num_attention_heads=12,
        image_size=224,
        patch_size=32,
    )
    info = EncoderInfo(spec.NAME, spec.VERSION, spec.DIM, spec.REVISION, "0" * 64, "cpu")
    return Encoder(SiglipVisionModel(config), Preprocess(), info)


@pytest.fixture(scope="session")
def encoder() -> Encoder:
    return tiny_encoder()


@pytest.fixture(scope="session")
def settings() -> Settings:
    return Settings(model_dir=Path("/nonexistent"), max_batch=8, max_image_bytes=2 * 1024 * 1024)


@pytest.fixture(scope="session")
def client(encoder: Encoder, settings: Settings) -> Iterator[TestClient]:
    app = create_app(settings, encoder_factory=lambda _: encoder)
    with TestClient(app) as c:
        yield c
