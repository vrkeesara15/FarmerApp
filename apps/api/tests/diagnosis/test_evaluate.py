"""ml/eval/evaluate.py over the CI manifest against the SMALL seeded corpus."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.diagnosis.services import DiagnosisServices
from tests.authz.conftest import World

REPO = Path(__file__).resolve().parents[4]
SCRIPT = REPO / "ml" / "eval" / "evaluate.py"
MANIFEST = REPO / "ml" / "eval" / "testset" / "ci" / "manifest.csv"


def _module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("ml_eval_evaluate", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


async def test_ci_manifest_report(
    db_session: AsyncSession, world: World, services: DiagnosisServices, tmp_path: Path
) -> None:
    evaluate = _module()
    rows = evaluate.load_manifest(MANIFEST)
    assert len(rows) == 18
    report = await evaluate.evaluate(
        db_session, services, world.a.tenant.id, rows, base=MANIFEST.parent, manifest="ci"
    )
    totals = report.totals
    assert totals["cases"] == 18
    assert totals["top1_accuracy"] == 1.0
    assert report.hallucinated_out_of_scope == 0  # DX-010
    assert report.per_problem["out_of_scope"]["out_of_scope_share"] == 1.0
    assert report.per_crop["paddy"]["cases"] == 15 and report.per_crop["unknown"]["cases"] == 3
    assert totals["corpus_answer_share"] == pytest.approx(12 / 18, abs=1e-3)
    assert totals["escalation_rate"] == pytest.approx(6 / 18, abs=1e-3)
    assert report.encoder == "fake-dct@1" and report.corpus_version == 1
    out = tmp_path / "report.json"
    evaluate.write_report(report, out)
    saved = json.loads(out.read_text())
    assert saved["totals"]["cases"] == 18 and len(saved["cases"]) == 18


def test_manifest_validation(tmp_path: Path) -> None:
    evaluate = _module()
    bad = tmp_path / "manifest.csv"
    bad.write_text("image,crop\nx.jpg,paddy\n")
    with pytest.raises(ValueError, match="true_problem"):
        evaluate.load_manifest(bad)
