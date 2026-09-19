"""Fetch the pinned weights and save the vision tower only (Docker build step and local dev).

    uv run python -m embed.fetch --out .model

Downloads ``config.json``, ``preprocessor_config.json`` and ``model.safetensors`` of
``spec.HF_REPO`` at ``spec.REVISION`` (never ``main``), checks the weights' sha256 against
``spec.WEIGHTS_SHA256``, keeps the vision tower (the text tower is ~half of the file and unused),
and writes ``embed_manifest.json`` with the identity and the sha256 of the saved weights. At runtime
the service loads that directory offline — a cold start never talks to Hugging Face.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

from embed import spec


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(out: Path) -> dict[str, object]:
    from huggingface_hub import hf_hub_download
    from transformers import SiglipVisionModel

    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="embed-fetch-") as tmp:
        src = Path(tmp) / "src"
        src.mkdir()
        for name in spec.FILES:
            cached = hf_hub_download(spec.HF_REPO, name, revision=spec.REVISION, cache_dir=Path(tmp) / "hf")
            shutil.copyfile(cached, src / name)
        actual = sha256_file(src / spec.WEIGHTS_FILE)
        if actual != spec.WEIGHTS_SHA256:
            raise SystemExit(
                f"weights sha256 {actual} != pinned {spec.WEIGHTS_SHA256} ({spec.HF_REPO}@{spec.REVISION})"
            )
        model = SiglipVisionModel.from_pretrained(src)
        model.save_pretrained(out, safe_serialization=True)
        shutil.copyfile(src / "preprocessor_config.json", out / "preprocessor_config.json")

    manifest: dict[str, object] = {
        "name": spec.NAME,
        "version": spec.VERSION,
        "dim": spec.DIM,
        "revision": spec.REVISION,
        "hf_repo": spec.HF_REPO,
        "licence": spec.LICENCE,
        "source_weights_sha256": spec.WEIGHTS_SHA256,
        "vision_weights_sha256": sha256_file(out / spec.WEIGHTS_FILE),
    }
    (out / spec.MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=Path(".model"))
    args = parser.parse_args(argv)
    manifest = fetch(args.out)
    json.dump(manifest, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
