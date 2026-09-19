"""Build data/cache/ (256x256 JPEGs) and data/manifest.csv from data/raw/ + synthetic negatives.

Usage: uv run python data/prepare.py [--limit N]   (--limit caps every source, for smoke tests)

* Each source is sampled deterministically (seeded shuffle, then `max_images`).
* Images are resized so the short side is 256 and centre-cropped to 256x256 (train crops 224).
* The split is a stable hash of (source id, source key) -- see ondevice/manifest.py.
* All rows are public bootstrap data (SPEC 3.3, source=public) or generated negatives.
"""

from __future__ import annotations

import argparse
import io
import json
import random
import sys
import tarfile
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import pyarrow.parquet as pq
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ondevice.config import CACHE_DIR, CACHE_SIZE, DATA_DIR, MANIFEST, SOURCES, TrainConfig  # noqa: E402
from ondevice.manifest import Row, split_for, write_manifest  # noqa: E402

RAW_DIR = DATA_DIR / "raw"
SEED = TrainConfig().seed


def to_square(img: Image.Image, size: int = CACHE_SIZE) -> Image.Image:
    img = img.convert("RGB")
    w, h = img.size
    scale = size / min(w, h)
    img = img.resize((max(size, round(w * scale)), max(size, round(h * scale))), Image.Resampling.BILINEAR,
                     reducing_gap=3.0)
    w, h = img.size
    left, top = (w - size) // 2, (h - size) // 2
    return img.crop((left, top, left + size, top + size))


def save(img: Image.Image, rel: str) -> None:
    dest = DATA_DIR / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    to_square(img).save(dest, "JPEG", quality=92)


def parquet_records(source: dict, with_images: bool = True):
    """Yield (key, crop, orig_label, image_bytes | None) for every row of every pinned parquet file."""
    col = source.get("crop_from_column")
    for file in source["files"]:
        pf = pq.ParquetFile(RAW_DIR / source["id"] / file["path"])
        label_names = _label_names(pf)
        offset = 0
        for rg in range(pf.metadata.num_row_groups):
            cols = (["image"] if with_images else []) + ["label"] + ([col] if col else [])
            table = pf.read_row_group(rg, columns=cols).to_pydict()
            for i, label in enumerate(table["label"]):
                crop = source["crop_map"][table[col][i]] if col else source["crop"]
                key = f"{file['path']}#{offset + i}"
                data = table["image"][i]["bytes"] if with_images else None
                yield key, crop, label_names.get(label, str(label)), data
            offset += len(table["label"])


def _label_names(pf: pq.ParquetFile) -> dict[int, str]:
    meta = pf.schema_arrow.metadata or {}
    try:
        info = json.loads(meta[b"huggingface"])["info"]["features"]["label"]
        return dict(enumerate(info["names"]))
    except (KeyError, ValueError):
        return {}


def prepare_parquet(source: dict, limit: int | None) -> list[Row]:
    # Pass 1: keys only (cheap) to sample deterministically per crop; pass 2: decode the chosen rows.
    by_crop: dict[str, list[str]] = defaultdict(list)
    for key, crop, _, _ in parquet_records(source, with_images=False):
        by_crop[crop].append(key)
    cap = min(source["max_images"], limit or source["max_images"])
    rng = random.Random(f"{SEED}:{source['id']}")
    chosen: set[str] = set()
    for _crop, keys in sorted(by_crop.items()):
        keys = sorted(keys)
        rng.shuffle(keys)
        chosen.update(keys[:cap])
    rows = []
    for key, crop, orig, data in parquet_records(source):
        if key not in chosen:
            continue
        rel = f"cache/{source['id']}/{len(rows):05d}.jpg"
        try:
            save(Image.open(io.BytesIO(data)), rel)
        except OSError as err:  # a corrupt image in a public set: skip, never crash the build
            print(f"  skip {key}: {err}")
            continue
        rows.append(_row(source, rel, key, crop, orig))
    return rows


def prepare_caltech(source: dict, limit: int | None) -> list[Row]:
    zpath = RAW_DIR / source["id"] / source["files"][0]["path"]
    excluded = set(source["exclude_categories"])
    with zipfile.ZipFile(zpath) as zf:
        inner = next(n for n in zf.namelist() if n.endswith("101_ObjectCategories.tar.gz") and "MACOSX" not in n)
        blob = zf.read(inner)
    members: dict[str, list[tuple[str, bytes]]] = defaultdict(list)
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tf:
        for m in tf:
            if not m.isfile() or not m.name.lower().endswith(".jpg"):
                continue
            category = m.name.split("/")[-2]
            if category in excluded:
                continue
            members[category].append((m.name, tf.extractfile(m).read()))
    rng = random.Random(f"{SEED}:{source['id']}")
    picked: list[tuple[str, str, bytes]] = []
    for category in sorted(members):
        items = sorted(members[category])
        rng.shuffle(items)
        picked.extend((category, name, data) for name, data in items[: source["max_per_category"]])
    rng.shuffle(picked)
    cap = min(source["max_images"], limit or source["max_images"])
    rows = []
    for category, name, data in picked[:cap]:
        rel = f"cache/{source['id']}/{len(rows):05d}.jpg"
        save(Image.open(io.BytesIO(data)), rel)
        rows.append(_row(source, rel, name, "", category))
    return rows


def synthetic_image(rng: np.random.Generator, kind: str) -> Image.Image:
    s = CACHE_SIZE
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32) / s
    if kind == "flat":
        base = np.ones((s, s, 3), np.float32) * rng.uniform(20, 235, 3)
        img = base + rng.normal(0, rng.uniform(1, 8), (s, s, 3))
    elif kind == "gradient":
        a, b = rng.uniform(0, 255, 3), rng.uniform(0, 255, 3)
        t = (xx * np.cos(rng.uniform(0, 6.28)) + yy * np.sin(rng.uniform(0, 6.28)))[..., None]
        t = (t - t.min()) / (np.ptp(t) + 1e-6)
        img = a * (1 - t) + b * t + rng.normal(0, 3, (s, s, 3))
    elif kind == "soil":
        noise = sum(
            np.array(Image.fromarray(rng.integers(0, 255, (s // k, s // k), dtype=np.uint8)).resize((s, s),
                     Image.Resampling.BICUBIC), np.float32) / (i + 1)
            for i, k in enumerate((32, 16, 8, 4, 2, 1))
        )
        noise = (noise - noise.min()) / (np.ptp(noise) + 1e-6)
        brown = np.array([rng.uniform(90, 150), rng.uniform(60, 100), rng.uniform(30, 60)], np.float32)
        img = brown * (0.5 + noise[..., None])
    elif kind == "sky":
        top, bottom = np.array([70, 130, 220], np.float32), np.array([190, 215, 240], np.float32)
        img = top * (1 - yy[..., None]) + bottom * yy[..., None]
        for _ in range(rng.integers(0, 6)):
            cx, cy, r = rng.uniform(0, 1), rng.uniform(0, 1), rng.uniform(0.05, 0.25)
            blob = np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / (r * r)))[..., None]
            img = img * (1 - blob) + 245 * blob
    elif kind == "covered":
        img = np.ones((s, s, 3), np.float32) * rng.uniform(0, 25) + rng.normal(0, 4, (s, s, 3))
    else:  # "wall": plaster with a few straight edges (doors, window bars)
        img = np.ones((s, s, 3), np.float32) * rng.uniform(120, 230, 3) + rng.normal(0, 6, (s, s, 3))
        for _ in range(rng.integers(1, 5)):
            x0 = rng.integers(0, s)
            img[:, x0 : x0 + rng.integers(3, 30)] *= rng.uniform(0.3, 0.8)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    return out.filter(ImageFilter.GaussianBlur(rng.uniform(0, 1.5)))


def prepare_synthetic(source: dict, limit: int | None) -> list[Row]:
    rng = np.random.default_rng(SEED)
    kinds = ("flat", "gradient", "soil", "sky", "covered", "wall")
    n = min(source["max_images"], limit or source["max_images"])
    rows = []
    for i in range(n):
        kind = kinds[i % len(kinds)]
        rel = f"cache/{source['id']}/{i:05d}.jpg"
        save(synthetic_image(rng, kind), rel)
        rows.append(_row(source, rel, f"{kind}-{i}", "", kind))
    return rows


def _row(source: dict, rel: str, key: str, crop: str, orig: str) -> Row:
    cfg = TrainConfig()
    return Row(
        path=rel,
        source=source["id"],
        key=key,
        is_plant=int(bool(source["is_plant"])),
        crop=crop or "",
        orig_label=orig,
        licence=source["licence"],
        split=split_for(source["id"], key, cfg.val_fraction, cfg.test_fraction),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=None, help="cap per source (smoke tests)")
    parser.add_argument("--only", default="", help="comma-separated source ids")
    args = parser.parse_args()
    wanted = {s for s in args.only.split(",") if s}
    sources = json.loads(SOURCES.read_text())["sources"]
    handlers = {"parquet": prepare_parquet, "caltech_zip": prepare_caltech, "synthetic": prepare_synthetic}
    rows: list[Row] = []
    for source in sources:
        if wanted and source["id"] not in wanted:
            continue
        print(f"{source['id']}: preparing")
        got = handlers[source["format"]](source, args.limit)
        print(f"  {len(got)} images")
        rows.extend(got)
    write_manifest(rows, MANIFEST)
    counts = Counter((r.split, r.crop or "not_plant") for r in rows)
    for split in ("train", "val", "test"):
        print(split, {k[1]: v for k, v in sorted(counts.items()) if k[0] == split})
    print(f"manifest: {MANIFEST} ({len(rows)} rows), cache: {CACHE_DIR}")


if __name__ == "__main__":
    main()
