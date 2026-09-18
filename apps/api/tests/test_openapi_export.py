from __future__ import annotations

from pathlib import Path

from scripts import export_openapi


def test_export_and_check(tmp_path: Path) -> None:
    out = tmp_path / "openapi.yaml"
    assert export_openapi.main(["--out", str(out)]) == 0
    assert out.read_text().startswith("openapi: 3.1.0")
    assert export_openapi.main(["--check", "--out", str(out)]) == 0
    out.write_text("openapi: 3.0.0\n")
    assert export_openapi.main(["--check", "--out", str(out)]) == 1
