"""Image -> 768-dim unit vector with the pinned SigLIP vision tower (DX-002).

Pre-processing follows the model's own ``preprocessor_config.json`` (SigLIP: resize to 224 x 224,
bicubic, no crop; rescale 1/255; normalise mean 0.5 / std 0.5) and is checked against
``transformers``' ``SiglipImageProcessorPil`` in the integration test. Photos are decoded to pixels
with the EXIF orientation applied, so no metadata (GPS, device, time) ever reaches the model, and
nothing is stored. The embedding is the vision tower's pooled output (the multi-head attention
pooling head, i.e. SigLIP's ``image_embeds``), L2-normalised.
"""

from __future__ import annotations

import io
import json
import threading
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import torch
from PIL import Image, ImageOps, UnidentifiedImageError

from embed import spec

#: Refuse decompression bombs early: 40 MP is well above any phone photo (a 12 MP phone is ~4000 x 3000).
MAX_PIXELS = 40_000_000
Image.MAX_IMAGE_PIXELS = MAX_PIXELS  # Pillow warns above this and refuses above 2x


class UnreadableImageError(ValueError):
    """The bytes are not a decodable image (or exceed the pixel limit)."""


@dataclass(frozen=True)
class EncoderInfo:
    name: str
    version: str
    dim: int
    revision: str
    weights_sha256: str
    device: str


@dataclass(frozen=True)
class Preprocess:
    height: int = 224
    width: int = 224
    resample: int = int(Image.Resampling.BICUBIC)
    rescale: float = 1 / 255
    mean: tuple[float, float, float] = (0.5, 0.5, 0.5)
    std: tuple[float, float, float] = (0.5, 0.5, 0.5)

    @classmethod
    def from_config(cls, path: Path) -> Preprocess:
        cfg: dict[str, Any] = json.loads(path.read_text())
        size = cfg.get("size", {})
        return cls(
            height=int(size.get("height", 224)),
            width=int(size.get("width", 224)),
            resample=int(cfg.get("resample", Image.Resampling.BICUBIC)),
            rescale=float(cfg.get("rescale_factor", 1 / 255)),
            mean=tuple(cfg.get("image_mean", (0.5, 0.5, 0.5))),  # type: ignore[arg-type]
            std=tuple(cfg.get("image_std", (0.5, 0.5, 0.5))),  # type: ignore[arg-type]
        )

    def __call__(self, image: Image.Image) -> np.ndarray:
        resized = image.resize((self.width, self.height), resample=Image.Resampling(self.resample))
        pixels = np.asarray(resized, dtype=np.float32) * np.float32(self.rescale)
        pixels = (pixels - np.asarray(self.mean, np.float32)) / np.asarray(self.std, np.float32)
        return pixels.transpose(2, 0, 1)  # CHW


def decode_rgb(data: bytes) -> Image.Image:
    """Pixels only: EXIF orientation baked in, every metadata block dropped, RGB."""
    try:
        with Image.open(io.BytesIO(data)) as raw:
            if raw.width * raw.height > MAX_PIXELS:  # checked from the header, before decoding
                raise UnreadableImageError(f"image over {MAX_PIXELS} pixels")
            raw.load()
            oriented = ImageOps.exif_transpose(raw) or raw
            rgb = oriented.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise UnreadableImageError("not a decodable image") from exc
    # A fresh image from the pixel buffer: no .info / EXIF / ICC carried along.
    return Image.frombytes("RGB", rgb.size, rgb.tobytes())


def l2_normalise(vectors: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    return vectors / np.clip(norms, 1e-12, None)


class Encoder:
    """Holds the model (loaded once) and embeds batches; ``encode`` is thread-safe (serialised)."""

    def __init__(
        self,
        model: torch.nn.Module,
        preprocess: Preprocess,
        info: EncoderInfo,
        *,
        device: torch.device | None = None,
    ) -> None:
        self.device = device or torch.device("cpu")
        self.model = model.to(self.device).eval()
        self.preprocess = preprocess
        self.info = info
        self._lock = threading.Lock()

    @classmethod
    def load(cls, model_dir: Path, *, device: str = "cpu", threads: int | None = None) -> Encoder:
        from transformers import SiglipVisionModel

        if threads:
            torch.set_num_threads(threads)
        manifest = json.loads((model_dir / spec.MANIFEST).read_text())
        if (manifest["name"], manifest["version"], int(manifest["dim"])) != (
            spec.NAME,
            spec.VERSION,
            spec.DIM,
        ):
            raise RuntimeError(
                f"model dir holds {manifest['name']}@{manifest['version']}, "
                f"service pins {spec.NAME}@{spec.VERSION}"
            )
        model = SiglipVisionModel.from_pretrained(model_dir, local_files_only=True, dtype=torch.float32)
        info = EncoderInfo(
            name=spec.NAME,
            version=spec.VERSION,
            dim=spec.DIM,
            revision=manifest["revision"],
            weights_sha256=manifest["vision_weights_sha256"],
            device=device,
        )
        encoder = cls(
            model,
            Preprocess.from_config(model_dir / "preprocessor_config.json"),
            info,
            device=torch.device(device),
        )
        encoder.warm_up()
        return encoder

    def warm_up(self) -> None:
        """One dummy batch so the first real request does not pay kernel / allocator set-up."""
        self.encode_images([Image.new("RGB", (self.preprocess.width, self.preprocess.height), (90, 140, 60))])

    def encode_images(self, images: Sequence[Image.Image]) -> np.ndarray:
        batch = torch.from_numpy(np.stack([self.preprocess(image) for image in images]))
        with self._lock, torch.inference_mode():
            out = self.model(pixel_values=batch.to(self.device))
            pooled = out.pooler_output.float().cpu().numpy()
        if pooled.shape[1] != self.info.dim:
            raise RuntimeError(f"model produced {pooled.shape[1]}-dim vectors, pinned {self.info.dim}")
        return l2_normalise(pooled.astype(np.float64))

    def encode(self, blobs: Sequence[bytes]) -> np.ndarray:
        return self.encode_images([decode_rgb(blob) for blob in blobs])
