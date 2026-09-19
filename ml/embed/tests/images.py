"""Deterministic synthetic test photos (no licensed field images are in the repo)."""

from __future__ import annotations

import io
import math
import random

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


def leaf(seed: int = 1, size: tuple[int, int] = (640, 480)) -> Image.Image:
    """A green leaf with brown lesions on a soil background."""
    rng = random.Random(seed)
    w, h = size
    img = Image.new("RGB", size, (96, 72, 48))
    px = img.load()
    for _ in range(4000):  # soil grain
        x, y = rng.randrange(w), rng.randrange(h)
        shade = rng.randint(-25, 25)
        px[x, y] = (96 + shade, 72 + shade, 48 + shade)
    draw = ImageDraw.Draw(img)
    draw.ellipse((w * 0.12, h * 0.3, w * 0.88, h * 0.7), fill=(60, 140, 50), outline=(40, 100, 35), width=4)
    draw.line((w * 0.12, h * 0.5, w * 0.88, h * 0.5), fill=(120, 180, 90), width=5)  # midrib
    for i in range(1, 8):  # veins
        x = w * (0.12 + 0.76 * i / 8)
        draw.line((x, h * 0.5, x + w * 0.06, h * 0.34), fill=(100, 165, 80), width=2)
        draw.line((x, h * 0.5, x + w * 0.06, h * 0.66), fill=(100, 165, 80), width=2)
    for _ in range(9):  # lesions: grey centre, brown margin
        cx, cy = rng.uniform(w * 0.2, w * 0.8), rng.uniform(h * 0.38, h * 0.62)
        rx, ry = rng.uniform(10, 22), rng.uniform(5, 9)
        draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(120, 80, 40))
        draw.ellipse((cx - rx / 2, cy - ry / 2, cx + rx / 2, cy + ry / 2), fill=(170, 165, 150))
    return img.filter(ImageFilter.GaussianBlur(0.8))


def near_duplicate(img: Image.Image) -> Image.Image:
    """Same scene re-shot: slight rotation, crop, exposure change."""
    w, h = img.size
    out = img.rotate(6, resample=Image.Resampling.BICUBIC, fillcolor=(96, 72, 48))
    out = out.crop((int(w * 0.04), int(h * 0.05), int(w * 0.97), int(h * 0.96))).resize((w, h))
    return ImageEnhance.Brightness(out).enhance(1.12)


def unrelated(size: tuple[int, int] = (640, 480)) -> Image.Image:
    """A city-like scene: sky, grey buildings with windows, a road."""
    w, h = size
    img = Image.new("RGB", size, (135, 190, 235))
    draw = ImageDraw.Draw(img)
    rng = random.Random(7)
    x = 0
    while x < w:
        bw, bh = rng.randint(60, 120), rng.randint(int(h * 0.3), int(h * 0.75))
        grey = rng.randint(90, 170)
        draw.rectangle((x, h * 0.85 - bh, x + bw, h * 0.85), fill=(grey, grey, grey + 10))
        for wy in range(int(h * 0.85 - bh) + 10, int(h * 0.85) - 10, 22):
            for wx in range(x + 8, x + bw - 12, 18):
                draw.rectangle((wx, wy, wx + 9, wy + 12), fill=(240, 230, 150))
        x += bw + rng.randint(4, 16)
    draw.rectangle((0, h * 0.85, w, h), fill=(50, 50, 55))
    for lx in range(0, w, 60):
        draw.rectangle((lx, h * 0.92, lx + 30, h * 0.93), fill=(250, 250, 250))
    return img


def gradient(size: tuple[int, int] = (300, 200)) -> Image.Image:
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            px[x, y] = (int(255 * x / size[0]), int(128 + 100 * math.sin(y / 9)), 90)
    return img


def jpeg(img: Image.Image, quality: int = 88, exif: bytes | None = None) -> bytes:
    out = io.BytesIO()
    if exif is None:
        img.save(out, format="JPEG", quality=quality)
    else:
        img.save(out, format="JPEG", quality=quality, exif=exif)
    return out.getvalue()


def exif_with_gps_and_rotation(orientation: int = 6) -> bytes:
    exif = Image.Exif()
    exif[0x0112] = orientation  # Orientation: 6 = rotate 90 CW on display
    exif[0x010F] = "TestPhoneMaker"
    gps = exif.get_ifd(0x8825)
    gps[1] = "N"
    gps[2] = (17.0, 58.0, 0.0)  # Warangal-ish
    gps[3] = "E"
    gps[4] = (79.0, 35.0, 0.0)
    return exif.tobytes()
