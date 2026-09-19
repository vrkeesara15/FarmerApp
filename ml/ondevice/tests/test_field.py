"""DX-012 field images: the API's training export becomes on-device manifest rows (sha256
checked, cached, stable splits) and the candidate version is bumped."""

from __future__ import annotations

import csv
import hashlib
import io
from pathlib import Path

import pytest
from PIL import Image

from ondevice.field import EXPORT_FIELDS, materialise, merge, mirror_fetch, next_version, read_export
from ondevice.manifest import Row, split_for

API_FIELDS = (*EXPORT_FIELDS, "problem_code", "part", "severity", "stage", "region", "season")


def _jpeg(colour: tuple[int, int, int], size: tuple[int, int] = (320, 240)) -> bytes:
    out = io.BytesIO()
    Image.new("RGB", size, colour).save(out, "JPEG")
    return out.getvalue()


def _export(rows: list[dict[str, str]]) -> str:
    out = io.StringIO()
    writer = csv.DictWriter(out, fieldnames=API_FIELDS, lineterminator="\n")
    writer.writeheader()
    for r in rows:
        writer.writerow({k: r.get(k, "") for k in API_FIELDS})
    return out.getvalue()


def _row(uri: str, data: bytes, key: str, crop: str = "paddy", split: str = "train") -> dict[str, str]:
    return {
        "path": uri,
        "source": "corpus-internal",
        "key": key,
        "is_plant": "1",
        "crop": crop,
        "orig_label": "paddy_blast",
        "licence": "internal",
        "split": split,  # recomputed on read
        "sha256": hashlib.sha256(data).hexdigest(),
        "problem_code": "paddy_blast",
    }


def test_export_to_manifest_rows(tmp_path: Path) -> None:
    mirror = tmp_path / "mirror"
    good, other = _jpeg((30, 140, 40)), _jpeg((120, 90, 30))
    (mirror / "corpus-b" / "t").mkdir(parents=True)
    (mirror / "corpus-b" / "t" / "a.jpg").write_bytes(good)
    (mirror / "corpus-b" / "t" / "b.jpg").write_bytes(b"tampered")
    rows = read_export(
        _export(
            [
                _row("gs://corpus-b/t/a.jpg", good, "case-1"),
                _row("gs://corpus-b/t/b.jpg", other, "case-2"),
                _row("gs://corpus-b/t/missing.jpg", other, "case-3"),
            ]
        )
    )
    assert [r.split for r in rows] == [split_for("corpus-internal", f"case-{i}") for i in (1, 2, 3)]
    data_dir = tmp_path / "data"
    manifest, problems = materialise(rows, mirror_fetch(mirror), data_dir)
    assert len(manifest) == 1 and len(problems) == 2
    assert any("sha256 mismatch" in p for p in problems) and any("FileNotFoundError" in p for p in problems)
    (row,) = manifest
    assert row.path == f"cache/field/{hashlib.sha256(good).hexdigest()}.jpg" and row.crop == "paddy"
    with Image.open(data_dir / row.path) as img:
        assert img.size == (256, 256)
    # cached: a second pass needs no fetch
    again, problems = materialise(rows[:1], lambda _uri: (_ for _ in ()).throw(OSError("offline")), data_dir)
    assert again == manifest and problems == []


def test_export_validation() -> None:
    data = _jpeg((1, 2, 3))
    with pytest.raises(ValueError, match="on-device label"):
        read_export(_export([_row("gs://b/x.jpg", data, "k", crop="onion")]))
    with pytest.raises(ValueError, match="lacks columns"):
        read_export("path,crop\n")
    bad = _row("gs://b/x.jpg", data, "k")
    bad["sha256"] = "zz"
    with pytest.raises(ValueError, match="sha256"):
        read_export(_export([bad]))


def test_merge_and_version() -> None:
    public = [Row("cache/p/1.jpg", "sethy", "1", 1, "paddy", "blast", "CC-BY-4.0", "train")]
    field = [Row("cache/field/x.jpg", "corpus-internal", "c", 1, "paddy", "blast", "internal", "test")]
    assert merge(public, field) == public + field
    assert next_version("ondevice-v1.0") == "ondevice-v1.1"
    assert next_version("ondevice-v2.9") == "ondevice-v2.10"
    with pytest.raises(ValueError):
        next_version("v1")
