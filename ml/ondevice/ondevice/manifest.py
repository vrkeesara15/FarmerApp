"""Manifest rows (data/manifest.csv) and the deterministic train / val / test split.

The split is a pure function of (source id, source key) so that re-running data/prepare.py,
adding a source, or changing caps never moves an image between splits. When field images arrive
(SPEC 3.3), the key becomes the farm / district-season id so that photos of the same plant never
straddle splits.
"""

from __future__ import annotations

import csv
import hashlib
from dataclasses import dataclass
from pathlib import Path

from .config import CROP_LABELS, MANIFEST

FIELDS = ("path", "source", "key", "is_plant", "crop", "orig_label", "licence", "split")
SPLITS = ("train", "val", "test")


@dataclass(frozen=True)
class Row:
    path: str  # relative to data/
    source: str
    key: str
    is_plant: int
    crop: str  # "" for non-plant rows
    orig_label: str
    licence: str
    split: str

    @property
    def crop_index(self) -> int:
        """Index into CROP_LABELS, -1 when the row has no crop (the crop loss ignores it)."""
        return CROP_LABELS.index(self.crop) if self.crop else -1


def split_for(source: str, key: str, val_fraction: float = 0.15, test_fraction: float = 0.15) -> str:
    """Stable hash split: the same (source, key) always lands in the same split."""
    digest = hashlib.sha256(f"{source}:{key}".encode()).digest()
    u = int.from_bytes(digest[:8], "big") / 2**64
    if u < test_fraction:
        return "test"
    if u < test_fraction + val_fraction:
        return "val"
    return "train"


def write_manifest(rows: list[Row], path: Path = MANIFEST) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow({f: getattr(row, f) for f in FIELDS})


def read_manifest(path: Path = MANIFEST) -> list[Row]:
    with path.open(newline="") as fh:
        rows = []
        for rec in csv.DictReader(fh):
            rec["is_plant"] = int(rec["is_plant"])
            row = Row(**rec)
            validate(row)
            rows.append(row)
    return rows


def validate(row: Row) -> None:
    if row.split not in SPLITS:
        raise ValueError(f"{row.path}: bad split {row.split!r}")
    if row.is_plant not in (0, 1):
        raise ValueError(f"{row.path}: is_plant must be 0/1")
    if row.is_plant and row.crop not in CROP_LABELS:
        raise ValueError(f"{row.path}: plant row needs a crop in {CROP_LABELS}, got {row.crop!r}")
    if not row.is_plant and row.crop:
        raise ValueError(f"{row.path}: non-plant row must not carry a crop")
