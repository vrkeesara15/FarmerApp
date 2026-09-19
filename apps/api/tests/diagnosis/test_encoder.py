"""DX-002 encoders: the deterministic fake and the pinned remote ``embed`` client."""

from __future__ import annotations

import io
import json

import httpx
import numpy as np
import pytest
from PIL import Image

from farmerapp.diagnosis.encoder import (
    EMBEDDING_DIM,
    EncoderError,
    EncoderInfo,
    FakeEncoder,
    RemoteEncoder,
    build_encoder,
    cosine,
    fake_embedding,
)
from farmerapp.diagnosis.images import (
    NON_PLANT_KINDS,
    UnreadableImageError,
    strip_for_llm,
    synthetic_leaf,
    synthetic_non_plant,
    to_jpeg,
)
from farmerapp.settings import Settings


async def test_fake_encoder_is_deterministic_unit_length_and_768_dims() -> None:
    encoder = FakeEncoder()
    image = synthetic_leaf("paddy_blast", 1)
    first, second = await encoder.encode([image, image])
    assert len(first) == EMBEDDING_DIM == encoder.info.dim
    assert first == second
    assert np.linalg.norm(first) == pytest.approx(1.0)
    assert encoder.info.label == "fake-dct@1"


def test_near_duplicates_are_closer_than_other_problems_and_non_plants() -> None:
    a1, a2 = (
        fake_embedding(synthetic_leaf("paddy_blast", 1)),
        fake_embedding(synthetic_leaf("paddy_blast", 2)),
    )
    other = fake_embedding(synthetic_leaf("paddy_bph", 1))
    same = cosine(a1, a2)
    assert same > 0.95
    assert same > cosine(a1, other)
    for kind in NON_PLANT_KINDS:
        assert cosine(a1, fake_embedding(synthetic_non_plant(kind, 0))) < 0.85


def test_unreadable_bytes_raise() -> None:
    with pytest.raises(UnreadableImageError):
        fake_embedding(b"definitely not a jpeg")
    flat = to_jpeg(Image.new("RGB", (8, 8), (0, 0, 0)))
    assert np.linalg.norm(fake_embedding(flat)) == pytest.approx(1.0)


def test_strip_for_llm_drops_exif_gps_and_caps_the_edge() -> None:
    """SEC-027: the JPEG sent to the LLM has no EXIF (GPS, device) whatsoever."""
    exif = Image.Exif()
    exif[0x010F] = "PhoneMaker"  # Make
    exif[0x8825] = {1: "N", 2: (17.0, 58.0, 8.0), 3: "E", 4: (79.0, 35.0, 38.0)}  # GPS IFD
    big = Image.new("RGB", (2400, 1200), (30, 140, 40))
    original = to_jpeg(big, exif=exif.tobytes())
    assert Image.open(io.BytesIO(original)).getexif()
    stripped = strip_for_llm(original)
    image = Image.open(io.BytesIO(stripped))
    assert not image.getexif()
    assert "exif" not in image.info
    assert max(image.size) == 1568


def _remote(handler: httpx.MockTransport) -> RemoteEncoder:
    return RemoteEncoder(
        base_url="http://embed.test/",
        info=EncoderInfo("siglip-base", "2024-01"),
        client=httpx.AsyncClient(transport=handler),
        token_provider=_token,
    )


async def _token() -> str:
    return "id-token"


async def test_remote_encoder_contract() -> None:
    seen: dict[str, object] = {}

    def handle(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["auth"] = request.headers.get("authorization")
        body = json.loads(request.content)
        seen["body"] = body
        return httpx.Response(
            200,
            json={
                "model": "siglip-base",
                "version": "2024-01",
                "dim": EMBEDDING_DIM,
                "vectors": [[0.1] * EMBEDDING_DIM for _ in body["images"]],
            },
        )

    vectors = await _remote(httpx.MockTransport(handle)).encode([b"a", b"b"])
    assert len(vectors) == 2 and len(vectors[0]) == EMBEDDING_DIM
    assert seen["url"] == "http://embed.test/v1/embed"
    assert seen["auth"] == "Bearer id-token"
    body = seen["body"]
    assert isinstance(body, dict)
    assert body["model"] == "siglip-base" and body["version"] == "2024-01"
    assert body["images"][0] == {"b64": "YQ=="}


@pytest.mark.parametrize(
    "payload",
    [
        {"model": "dinov2", "version": "2024-01", "dim": EMBEDDING_DIM, "vectors": [[0.0] * 768]},
        {"model": "siglip-base", "version": "2023", "dim": EMBEDDING_DIM, "vectors": [[0.0] * 768]},
        {"model": "siglip-base", "version": "2024-01", "dim": EMBEDDING_DIM, "vectors": []},
        {"model": "siglip-base", "version": "2024-01", "dim": EMBEDDING_DIM, "vectors": [[0.0]]},
    ],
)
async def test_remote_encoder_refuses_another_space(payload: dict[str, object]) -> None:
    transport = httpx.MockTransport(lambda _r: httpx.Response(200, json=payload))
    with pytest.raises(EncoderError):
        await _remote(transport).encode([b"a"])


async def test_remote_encoder_http_failure() -> None:
    transport = httpx.MockTransport(lambda _r: httpx.Response(503))
    with pytest.raises(EncoderError):
        await _remote(transport).encode([b"a"])


def test_build_encoder_from_settings() -> None:
    assert isinstance(build_encoder(Settings(diagnosis_encoder="fake")), FakeEncoder)
    remote = build_encoder(
        Settings(
            diagnosis_encoder="remote",
            diagnosis_encoder_name="siglip-x",
            diagnosis_encoder_version="7",
            app_env="test",
        )
    )
    assert isinstance(remote, RemoteEncoder)
    assert remote.info == EncoderInfo("siglip-x", "7")
