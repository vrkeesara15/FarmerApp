"""DX-012 field images for the monthly fine-tune (TensorFlow-free, unit tested).

The API's weekly ``export-training-set`` job writes the approved corpus field images of a tenant
as ``gs://<corpus>/training/<tenant>/<YYYYMMDD>/manifest.csv`` (columns
``path, source, key, is_plant, crop, orig_label, licence, split`` + ``sha256, problem_code, part,
severity, stage, region, season``; ``path`` is a ``gs://`` URI). This module turns it into rows
of the on-device manifest (``data/manifest.csv`` dialect, paths relative to ``data/``):

1. ``read_export`` parses and validates the export (labels must be on-device crop labels,
   splits are recomputed with ``split_for`` so they can never disagree with the exporter);
2. ``materialise`` fetches each image (a local mirror directory made by ``gcloud storage rsync``,
   or any ``fetch(uri) -> bytes``), checks its sha256, centre-crops and caches it at
   ``CACHE_SIZE`` under ``data/cache/field/<sha256>.jpg``;
3. ``merge`` appends the field rows to the public bootstrap manifest (field rows keep their own
   ``source`` so evaluation can report the field split separately);
4. ``next_version`` bumps ``ondevice-v<major>.<minor>`` for the candidate (a new label would be a
   major bump and a mobile contract change; the fine-tune never adds labels).
"""

from __future__ import annotations

import csv
import hashlib
import io
import re
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from .config import CACHE_SIZE, CROP_LABELS, DATA_DIR
from .manifest import Row, split_for, validate

EXPORT_FIELDS = ("path", "source", "key", "is_plant", "crop", "orig_label", "licence", "split", "sha256")
FIELD_CACHE = "cache/field"
_VERSION = re.compile(r"^ondevice-v(\d+)\.(\d+)$")

Fetch = Callable[[str], bytes]


@dataclass(frozen=True)
class ExportRow:
    uri: str
    source: str
    key: str
    crop: str
    orig_label: str
    licence: str
    split: str
    sha256: str


def read_export(text: str) -> list[ExportRow]:
    reader = csv.DictReader(io.StringIO(text))
    missing = set(EXPORT_FIELDS) - set(reader.fieldnames or ())
    if missing:
        raise ValueError(f"training export lacks columns {sorted(missing)}")
    rows: list[ExportRow] = []
    for rec in reader:
        if rec["is_plant"] != "1":
            raise ValueError(f"{rec['path']}: field corpus rows are plant images")
        if rec["crop"] not in CROP_LABELS:
            raise ValueError(f"{rec['path']}: crop {rec['crop']!r} is not an on-device label")
        if not re.fullmatch(r"[0-9a-f]{64}", rec["sha256"]):
            raise ValueError(f"{rec['path']}: bad sha256")
        rows.append(
            ExportRow(
                uri=rec["path"],
                source=rec["source"],
                key=rec["key"],
                crop=rec["crop"],
                orig_label=rec["orig_label"],
                licence=rec["licence"],
                split=split_for(rec["source"], rec["key"]),
                sha256=rec["sha256"],
            )
        )
    return rows


def mirror_fetch(root: Path) -> Fetch:
    """``gs://bucket/key`` -> ``root/bucket/key`` (the layout ``gcloud storage rsync`` makes)."""

    def fetch(uri: str) -> bytes:
        if not uri.startswith("gs://"):
            raise ValueError(f"not a gs:// URI: {uri}")
        return (root / uri.removeprefix("gs://")).read_bytes()

    return fetch


def _square(image: Image.Image, size: int) -> Image.Image:
    w, h = image.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    return image.crop((left, top, left + side, top + side)).resize((size, size), Image.Resampling.LANCZOS)


def materialise(
    rows: Iterable[ExportRow], fetch: Fetch, data_dir: Path = DATA_DIR
) -> tuple[list[Row], list[str]]:
    """Cache every image and return (manifest rows, problems). A missing or tampered image is
    skipped and reported, never trained on."""
    out: list[Row] = []
    problems: list[str] = []
    cache = data_dir / FIELD_CACHE
    cache.mkdir(parents=True, exist_ok=True)
    for row in rows:
        rel = f"{FIELD_CACHE}/{row.sha256}.jpg"
        target = data_dir / rel
        if not target.exists():
            try:
                data = fetch(row.uri)
            except (OSError, ValueError) as exc:
                problems.append(f"{row.uri}: {type(exc).__name__}")
                continue
            if hashlib.sha256(data).hexdigest() != row.sha256:
                problems.append(f"{row.uri}: sha256 mismatch")
                continue
            with Image.open(io.BytesIO(data)) as img:
                _square(img.convert("RGB"), CACHE_SIZE).save(target, "JPEG", quality=92)
        manifest_row = Row(
            path=rel,
            source=row.source,
            key=row.key,
            is_plant=1,
            crop=row.crop,
            orig_label=row.orig_label,
            licence=row.licence,
            split=row.split,
        )
        validate(manifest_row)
        out.append(manifest_row)
    return out, problems


def merge(public: list[Row], field: list[Row]) -> list[Row]:
    """Public bootstrap rows plus the field rows (field rows replace a public row with the
    same path; there should be none)."""
    field_paths = {r.path for r in field}
    return [r for r in public if r.path not in field_paths] + field


def next_version(current: str) -> str:
    match = _VERSION.match(current)
    if match is None:
        raise ValueError(f"not an on-device model version: {current!r}")
    return f"ondevice-v{match.group(1)}.{int(match.group(2)) + 1}"


__all__ = [
    "EXPORT_FIELDS",
    "ExportRow",
    "materialise",
    "merge",
    "mirror_fetch",
    "next_version",
    "read_export",
]
