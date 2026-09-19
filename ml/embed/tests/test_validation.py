"""Input limits and validation errors (RFC 9457 problem+json, stable ``code``)."""

from __future__ import annotations

import base64
import io

import numpy as np
import pytest
from images import exif_with_gps_and_rotation, jpeg, leaf
from PIL import Image

from embed import spec
from embed.app import Settings
from embed.encoder import UnreadableImageError, decode_rgb


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def post(client, images: list, **extra):
    body = {"model": spec.NAME, "version": spec.VERSION, "images": images, **extra}
    return client.post("/v1/embed", json=body)


def assert_problem(resp, status: int, code: str) -> dict:
    assert resp.status_code == status, resp.text
    assert resp.headers["content-type"].startswith("application/problem+json")
    problem = resp.json()
    assert problem["code"] == code and problem["status"] == status
    return problem


def test_empty_batch_422(client) -> None:
    assert_problem(post(client, []), 422, "validation_error")


def test_more_than_max_batch_422(client) -> None:
    blob = b64(jpeg(leaf(), quality=30))
    problem = assert_problem(post(client, [{"b64": blob}] * 9), 422, "validation_error")
    assert problem["max_batch"] == 8


def test_exactly_max_batch_ok(client) -> None:
    blob = b64(jpeg(leaf(), quality=30))
    resp = post(client, [{"b64": blob}] * 8)
    assert resp.status_code == 200 and len(resp.json()["vectors"]) == 8


@pytest.mark.parametrize(
    "body",
    [
        {"version": spec.VERSION, "images": [{"b64": "AAAA"}]},  # no model
        {"model": spec.NAME, "images": [{"b64": "AAAA"}]},  # no version
        {"model": spec.NAME, "version": spec.VERSION, "images": [{"uri": "gs://b/o.jpg"}]},  # not b64
        {"model": spec.NAME, "version": spec.VERSION, "images": [{"b64": ""}]},
        {"model": spec.NAME, "version": spec.VERSION, "images": "AAAA"},
    ],
)
def test_malformed_body_422(client, body) -> None:
    assert_problem(client.post("/v1/embed", json=body), 422, "validation_error")


def test_invalid_base64_422_with_index(client) -> None:
    good = b64(jpeg(leaf()))
    problem = assert_problem(post(client, [{"b64": good}, {"b64": "not base64 !!"}]), 422, "invalid_base64")
    assert problem["index"] == 1


def test_not_an_image_422_with_index(client) -> None:
    good = b64(jpeg(leaf()))
    problem = assert_problem(
        post(client, [{"b64": good}, {"b64": good}, {"b64": b64(b"%PDF-1.7 not a photo")}]),
        422,
        "unreadable_image",
    )
    assert problem["index"] == 2


def test_truncated_jpeg_is_unreadable(client) -> None:
    blob = jpeg(leaf())[:300]
    assert_problem(post(client, [{"b64": b64(blob)}]), 422, "unreadable_image")


def test_image_over_byte_limit_413(client, settings: Settings) -> None:
    big = b"\xff\xd8" + b"\0" * (settings.max_image_bytes + 10)
    problem = assert_problem(post(client, [{"b64": b64(big)}]), 413, "image_too_large")
    assert problem["index"] == 0 and problem["max_bytes"] == settings.max_image_bytes


def test_request_over_total_limit_413(client, settings: Settings) -> None:
    resp = client.post(
        "/v1/embed",
        content=b"{" + b" " * (settings.max_request_bytes + 1) + b"}",
        headers={"content-type": "application/json"},
    )
    assert_problem(resp, 413, "request_too_large")


def test_decompression_bomb_refused() -> None:
    img = Image.new("L", (8000, 6000))  # 48 MP > 40 MP limit, tiny as PNG
    out = io.BytesIO()
    img.save(out, format="PNG")
    with pytest.raises(UnreadableImageError):
        decode_rgb(out.getvalue())


def test_png_and_webp_accepted(client) -> None:
    blobs = []
    for fmt in ("PNG", "WEBP"):
        out = io.BytesIO()
        leaf().save(out, format=fmt)
        blobs.append({"b64": b64(out.getvalue())})
    resp = post(client, blobs)
    assert resp.status_code == 200 and len(resp.json()["vectors"]) == 2


def test_exif_is_stripped_and_orientation_applied() -> None:
    base = leaf(size=(320, 200))
    tagged = jpeg(base, quality=95, exif=exif_with_gps_and_rotation(6))
    with Image.open(io.BytesIO(tagged)) as raw:
        assert raw.getexif().get_ifd(0x8825)  # the input really carries GPS
    decoded = decode_rgb(tagged)
    assert decoded.size == (200, 320)  # orientation 6 rotated to upright
    assert not decoded.info and not decoded.getexif()  # no metadata survives decoding


def test_rotated_exif_embeds_like_upright_pixels(encoder) -> None:
    base = leaf(size=(320, 200))
    upright = base.transpose(Image.Transpose.ROTATE_270)  # what orientation 6 displays
    tagged = jpeg(base, quality=95, exif=exif_with_gps_and_rotation(6))
    a = encoder.encode([tagged])[0]
    b = encoder.encode([jpeg(upright, quality=95)])[0]
    assert float(np.dot(a, b)) > 0.99
