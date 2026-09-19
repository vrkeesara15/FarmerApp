"""Image helpers for the diagnosis pipeline (SPEC 3, SEC-027, M6 seed).

* ``decode_rgb`` — open any photo the apps upload (JPEG / PNG / WebP) as RGB with the EXIF
  orientation applied; ``UnreadableImageError`` for bytes that are not an image (DX-010:
  such a request is out of scope, never "diagnosed").
* ``strip_for_llm`` — SEC-027: the JPEG sent to the LLM is **re-encoded** from pixels, so no
  EXIF block (GPS position, device serial, capture time) survives; the long edge is capped
  at 1568 px (the vision model's native resolution; larger only costs tokens).
* ``synthetic_leaf`` / ``synthetic_non_plant`` — deterministic placeholder images for the
  M6 public seed, the CI evaluation manifest and the DX-010 non-plant tests. **They are not
  field photos**: no licensed dataset is present, so every problem gets a synthetic "leaf"
  (a green blade with a problem-specific spot / stripe pattern). Variants of one problem are
  near-duplicates (same pattern, jittered), so an image encoder maps them close together,
  and different problems apart. Real field images are a human gate (SPEC 3.3).
"""

from __future__ import annotations

import hashlib
import io
import random

from PIL import Image, ImageDraw, ImageFilter, ImageOps, UnidentifiedImageError

#: Long-edge cap of the image sent to the LLM (SEC-027 re-encode; token budget).
LLM_MAX_EDGE = 1568
LLM_JPEG_QUALITY = 85


class UnreadableImageError(ValueError):
    """The bytes are not a decodable image."""


def decode_rgb(data: bytes) -> Image.Image:
    try:
        with Image.open(io.BytesIO(data)) as raw:
            raw.load()
            image = ImageOps.exif_transpose(raw) or raw
            return image.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise UnreadableImageError("not a decodable image") from exc


def strip_for_llm(data: bytes, *, max_edge: int = LLM_MAX_EDGE) -> bytes:
    """A fresh JPEG from the pixels only: EXIF (incl. GPS) and every other metadata block
    are dropped (SEC-027); orientation is baked in; long edge <= ``max_edge``."""
    image = decode_rgb(data)
    if max(image.size) > max_edge:
        image.thumbnail((max_edge, max_edge), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    image.save(out, format="JPEG", quality=LLM_JPEG_QUALITY, optimize=True)
    return out.getvalue()


def to_jpeg(image: Image.Image, *, quality: int = 85, exif: bytes | None = None) -> bytes:
    out = io.BytesIO()
    if exif is not None:
        image.save(out, format="JPEG", quality=quality, exif=exif)
    else:
        image.save(out, format="JPEG", quality=quality)
    return out.getvalue()


# --------------------------------------------------------------------------- synthetic
def _rng(*parts: str) -> random.Random:
    seed = int.from_bytes(hashlib.sha256("|".join(parts).encode()).digest()[:8], "big")
    return random.Random(seed)  # nosec B311 - deterministic placeholder pixels, not security


def synthetic_leaf(problem_code: str, variant: int, *, size: int = 256) -> bytes:
    """A placeholder "field photo" of ``problem_code``: soil background, a green leaf and
    the problem's signature (spot colour, layout and size; streaks for some). ``variant``
    jitters position, lighting and noise so variants are near-duplicates."""
    sig = _rng("signature", problem_code)
    var = _rng("variant", problem_code, str(variant))
    soil = (
        110 + sig.randint(-20, 20),
        80 + sig.randint(-15, 15),
        50 + sig.randint(-10, 10),
    )
    image = Image.new("RGB", (size, size), soil)
    draw = ImageDraw.Draw(image)
    green = (40 + sig.randint(0, 40), 120 + sig.randint(0, 70), 30 + sig.randint(0, 30))
    tilt = sig.randint(-25, 25) + var.randint(-4, 4)
    leaf = Image.new("L", (size, size), 0)
    ImageDraw.Draw(leaf).ellipse((size * 0.12, size * 0.30, size * 0.88, size * 0.70), fill=255)
    leaf = leaf.rotate(tilt, resample=Image.Resampling.BILINEAR)
    image.paste(Image.new("RGB", (size, size), green), (0, 0), leaf)
    # Problem signature: 3-9 spots at fixed relative positions, one colour, one size band.
    spot = (sig.randint(60, 230), sig.randint(30, 200), sig.randint(0, 120))
    radius = sig.randint(6, 22)
    for _ in range(sig.randint(3, 9)):
        cx = size * sig.uniform(0.25, 0.75) + var.uniform(-3, 3)
        cy = size * sig.uniform(0.38, 0.62) + var.uniform(-3, 3)
        r = radius * var.uniform(0.85, 1.15)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=spot)
    if sig.random() < 0.5:  # streaks (blights, deficiencies)
        stripe = (sig.randint(150, 240), sig.randint(150, 230), sig.randint(0, 90))
        angle = sig.uniform(-0.4, 0.4)
        for i in range(sig.randint(2, 5)):
            y = size * (0.40 + 0.05 * i) + var.uniform(-2, 2)
            draw.line(
                (size * 0.2, y, size * 0.8, y + size * angle * 0.3),
                fill=stripe,
                width=sig.randint(2, 6),
            )
    # Lighting and sensor noise.
    gain = var.uniform(0.92, 1.08)
    image = image.point(lambda v: max(0, min(255, int(v * gain))))
    return to_jpeg(image.filter(ImageFilter.GaussianBlur(var.uniform(0.3, 1.0))), quality=88)


NON_PLANT_KINDS: tuple[str, ...] = ("sky", "wall", "document", "brick", "tarmac", "screen")


def synthetic_non_plant(kind: str, variant: int, *, size: int = 256) -> bytes:
    """A placeholder photo of something that is not a plant (DX-010 fixtures)."""
    var = _rng("non_plant", kind, str(variant))
    image = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(image)
    if kind == "sky":
        for y in range(size):
            shade = int(160 + 80 * y / size)
            draw.line((0, y, size, y), fill=(90 + var.randint(-10, 10), 150, shade))
    elif kind == "wall":
        image.paste((150 + var.randint(-15, 15),) * 3, (0, 0, size, size))
    elif kind == "document":
        image.paste((245, 245, 240), (0, 0, size, size))
        for i in range(12):
            y = 20 + i * 19
            draw.line((20, y, size - var.randint(20, 90), y), fill=(30, 30, 30), width=3)
    elif kind == "brick":
        for row in range(0, size, 24):
            for col in range(-(row // 24 % 2) * 24, size, 48):
                draw.rectangle(
                    (col, row, col + 44, row + 20), fill=(160, 60 + var.randint(0, 20), 40)
                )
    elif kind == "tarmac":
        image.paste((55, 55, 60), (0, 0, size, size))
        draw.rectangle((size * 0.45, 0, size * 0.55, size), fill=(230, 230, 230))
    else:  # screen: a phone / TV screen with a UI
        image.paste((15, 15, 25), (0, 0, size, size))
        draw.rectangle((30, 30, size - 30, 90), fill=(40, 90, 220))
        draw.rectangle((30, 110, size - 30, size - 30), fill=(230, 230, 235))
    return to_jpeg(image.filter(ImageFilter.GaussianBlur(0.6)), quality=88)


__all__ = [
    "LLM_MAX_EDGE",
    "NON_PLANT_KINDS",
    "UnreadableImageError",
    "decode_rgb",
    "strip_for_llm",
    "synthetic_leaf",
    "synthetic_non_plant",
    "to_jpeg",
]
