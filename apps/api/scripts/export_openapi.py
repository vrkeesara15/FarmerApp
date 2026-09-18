"""Export the OpenAPI 3.1 document to ``apps/api/openapi.yaml`` or check it is current.

uv run python scripts/export_openapi.py            # write
uv run python scripts/export_openapi.py --check    # exit 1 if the committed file differs
"""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path

import yaml

from farmerapp.api.app import create_app

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "openapi.yaml"


def render() -> str:
    schema = create_app().openapi()
    return yaml.safe_dump(schema, sort_keys=False, allow_unicode=True, width=100)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)

    current = render()
    if args.check:
        existing = args.out.read_text() if args.out.exists() else ""
        if existing == current:
            print(f"openapi: {args.out} is up to date")  # noqa: T201
            return 0
        diff = difflib.unified_diff(
            existing.splitlines(), current.splitlines(), "committed", "generated", lineterm=""
        )
        print("\n".join(diff))  # noqa: T201
        print(f"openapi: {args.out} is stale; run `make openapi`", file=sys.stderr)  # noqa: T201
        return 1

    args.out.write_text(current)
    print(f"openapi: wrote {args.out}")  # noqa: T201
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
