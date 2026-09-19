"""Pluggable server image encoder (DX-002, DX-005).

``ImageEncoder.encode(images) -> list[vector]`` turns photos into 768-dim unit vectors for
the pgvector kNN. The encoder is **pinned**: ``EncoderInfo(name, version, dim)`` comes from
settings (``DIAGNOSIS_ENCODER_NAME`` / ``DIAGNOSIS_ENCODER_VERSION``) and is stored on every
corpus image and every diagnosis; the kNN only compares vectors of the same name + version,
so changing the encoder means re-embedding the corpus (DX-012), never mixing spaces.

Implementations:

* ``FakeEncoder`` — deterministic and derived from the pixels, so tests, the seed and the CI
  evaluation work without a model: each RGB channel is downscaled to 32 x 32, transformed
  with a 2-D DCT-II and its 16 x 16 low-frequency block kept (3 x 256 = 768 numbers); the DC
  terms are damped so colour does not swamp layout, then the vector is L2-normalised. Near
  duplicates (same scene, jittered) land close together, different scenes apart.
* ``RemoteEncoder`` — the ``embed`` Cloud Run service (``ml/embed``, SigLIP / DINOv2 family)
  over HTTP; contract in docs/prs/M6-diagnosis-api.md: ``POST {base}/v1/embed`` with
  ``{"model": name, "version": version, "images": [{"b64": ...}]}`` ->
  ``{"model", "version", "dim", "vectors": [[...]]}``. A response for another model / version
  / dimension is refused (``EncoderError``), so a mis-deployed service can never write
  vectors of another space.
"""

from __future__ import annotations

import base64
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from typing import Protocol

import httpx
import numpy as np
from PIL import Image

from farmerapp.diagnosis.images import decode_rgb
from farmerapp.settings import Settings

EMBEDDING_DIM = 768
FAKE_ENCODER_NAME = "fake-dct"
FAKE_ENCODER_VERSION = "1"

_SIDE = 32  # downscale edge
_KEEP = 16  # low-frequency block kept per channel (16 x 16 x 3 = 768)
_DC_WEIGHT = 0.25

Vector = list[float]


class EncoderError(RuntimeError):
    """The encoder could not embed the images (service down, wrong model, bad response)."""


@dataclass(frozen=True)
class EncoderInfo:
    name: str
    version: str
    dim: int = EMBEDDING_DIM

    @property
    def label(self) -> str:
        return f"{self.name}@{self.version}"


class ImageEncoder(Protocol):
    info: EncoderInfo

    async def encode(self, images: Sequence[bytes]) -> list[Vector]:
        """One unit vector of ``info.dim`` floats per image, in order."""
        ...


def _dct_matrix(n: int) -> np.ndarray:
    k = np.arange(n)[:, None]
    i = np.arange(n)[None, :]
    m = np.cos(np.pi * (2 * i + 1) * k / (2 * n)) * np.sqrt(2.0 / n)
    m[0, :] = np.sqrt(1.0 / n)
    out: np.ndarray = m
    return out


_DCT = _dct_matrix(_SIDE)


def fake_embedding(data: bytes) -> Vector:
    """The ``FakeEncoder`` vector of one image (``UnreadableImageError`` if not an image)."""
    image = decode_rgb(data).resize((_SIDE, _SIDE), Image.Resampling.BILINEAR)
    pixels = np.asarray(image, dtype=np.float64) / 255.0
    parts: list[np.ndarray] = []
    for channel in range(3):
        coeffs = _DCT @ pixels[:, :, channel] @ _DCT.T
        block = coeffs[:_KEEP, :_KEEP].copy()
        block[0, 0] *= _DC_WEIGHT
        parts.append(block.reshape(-1))
    vector = np.concatenate(parts)
    norm = float(np.linalg.norm(vector))
    if norm == 0.0:
        vector = np.zeros(EMBEDDING_DIM)
        vector[0] = 1.0
    else:
        vector = vector / norm
    return [float(v) for v in vector]


class FakeEncoder:
    """Deterministic pixel-derived encoder (tests, seed, CI evaluation, local dev)."""

    def __init__(self, info: EncoderInfo | None = None) -> None:
        self.info = info or EncoderInfo(FAKE_ENCODER_NAME, FAKE_ENCODER_VERSION)
        self.calls = 0

    async def encode(self, images: Sequence[bytes]) -> list[Vector]:
        self.calls += 1
        return [fake_embedding(data) for data in images]


TokenProvider = Callable[[], Awaitable[str | None]]


class RemoteEncoder:
    """The ``embed`` service (``ml/embed``) over HTTP, pinned to one model version."""

    def __init__(
        self,
        *,
        base_url: str,
        info: EncoderInfo,
        timeout_s: float = 20.0,
        token_provider: TokenProvider | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.info = info
        self._url = base_url.rstrip("/") + "/v1/embed"
        self._timeout = timeout_s
        self._token_provider = token_provider
        self._client = client

    async def encode(self, images: Sequence[bytes]) -> list[Vector]:
        body = {
            "model": self.info.name,
            "version": self.info.version,
            "images": [{"b64": base64.b64encode(data).decode()} for data in images],
        }
        headers: dict[str, str] = {}
        if self._token_provider is not None:
            token = await self._token_provider()
            if token:
                headers["Authorization"] = f"Bearer {token}"
        try:
            if self._client is not None:
                resp = await self._client.post(self._url, json=body, headers=headers)
            else:
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    resp = await client.post(self._url, json=body, headers=headers)
            resp.raise_for_status()
            payload = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise EncoderError("embed service call failed") from exc
        if (
            payload.get("model") != self.info.name
            or str(payload.get("version")) != self.info.version
            or int(payload.get("dim", 0)) != self.info.dim
        ):
            raise EncoderError(
                f"embed service answered {payload.get('model')}@{payload.get('version')}, "
                f"pinned {self.info.label}"
            )
        vectors = payload.get("vectors")
        if not isinstance(vectors, list) or len(vectors) != len(images):
            raise EncoderError("embed service returned the wrong number of vectors")
        out: list[Vector] = []
        for vector in vectors:
            if not isinstance(vector, list) or len(vector) != self.info.dim:
                raise EncoderError("embed service returned a vector of the wrong dimension")
            out.append([float(v) for v in vector])
        return out


def build_encoder(settings: Settings) -> ImageEncoder:
    if settings.diagnosis_encoder == "remote":
        from farmerapp.gcp import MetadataIdentityToken

        info = EncoderInfo(settings.diagnosis_encoder_name, settings.diagnosis_encoder_version)
        base = settings.diagnosis_embed_url
        return RemoteEncoder(
            base_url=base,
            info=info,
            timeout_s=settings.diagnosis_embed_timeout_s,
            token_provider=None if settings.is_local else MetadataIdentityToken(base),
        )
    return FakeEncoder()


def cosine(a: Sequence[float], b: Sequence[float]) -> float:
    va, vb = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    denominator = float(np.linalg.norm(va) * np.linalg.norm(vb))
    return float(va @ vb) / denominator if denominator else 0.0


__all__ = [
    "EMBEDDING_DIM",
    "FAKE_ENCODER_NAME",
    "FAKE_ENCODER_VERSION",
    "EncoderError",
    "EncoderInfo",
    "FakeEncoder",
    "ImageEncoder",
    "RemoteEncoder",
    "Vector",
    "build_encoder",
    "cosine",
    "fake_embedding",
]
