"""Evaluate the diagnosis pipeline against a labelled manifest (M6-KICKOFF; DX-011 script).

Runs the production decision path in-process — encoder -> pgvector kNN -> DX-003 decision
rule -> DX-004 LLM fallback (``farmerapp.diagnosis.pipeline.decide_case``) — for every row
of a manifest, against a tenant's **approved** corpus, inside a transaction that is rolled
back (nothing is written), and reports:

* top-1 accuracy overall, per crop and per problem (the final label: corpus or LLM),
* corpus-answer share (high confidence, no LLM), LLM share, escalation rate (provisional or
  out of scope: the agronomist queue), out-of-scope share,
* for the non-plant / unsupported rows (``true_problem = out_of_scope``) whether any label
  was hallucinated (DX-010).

Usage (from ``apps/api``; ``make seed`` first for the demo corpus)::

    uv run python ../../ml/eval/evaluate.py \\
        --manifest ../../ml/eval/testset/ci/manifest.csv --tenant fcc

The JSON report goes to ``--out`` (default ``ml/eval/reports/latest.json``, not committed).

``--llm`` overrides ``DIAGNOSIS_LLM`` (``fake`` by default here, so a run costs nothing;
``claude`` evaluates the real fallback — it sends the test photos to the provider).

Manifest (CSV, header required): ``image, crop, true_problem, district, season``. ``image``
is a path relative to the manifest, a ``gs://`` blob URI, or a synthetic reference
``synthetic://leaf/<problem_code>/<variant>`` / ``synthetic://non_plant/<kind>/<variant>``
(CI only). ``crop`` is a crop code or ``unknown``; ``true_problem`` a ``pest_or_disease``
code or ``out_of_scope``. See ``ml/eval/testset/README.md``.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import sys
import uuid
from collections import defaultdict
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.diagnosis.corpus import current_version
from farmerapp.diagnosis.images import synthetic_leaf, synthetic_non_plant
from farmerapp.diagnosis.models import CorpusProblem, DiagnosisStatus
from farmerapp.diagnosis.pipeline import Case, decide_case
from farmerapp.diagnosis.services import DiagnosisServices

OUT_OF_SCOPE = "out_of_scope"
COLUMNS = ("image", "crop", "true_problem", "district", "season")


@dataclass(frozen=True)
class Row:
    image: str
    crop: str
    true_problem: str
    district: str | None = None
    season: str | None = None


@dataclass
class CaseResult:
    image: str
    crop: str
    true_problem: str
    predicted: str | None
    status: str
    source: str | None
    confidence: str | None
    correct: bool
    top1: float | None
    llm_used: bool
    reason: str | None


@dataclass
class Tally:
    cases: int = 0
    correct: int = 0
    corpus_answers: int = 0
    llm_used: int = 0
    escalated: int = 0
    out_of_scope: int = 0

    def add(self, result: CaseResult) -> None:
        self.cases += 1
        self.correct += result.correct
        self.corpus_answers += result.status == DiagnosisStatus.ANSWERED.value
        self.llm_used += result.llm_used
        self.escalated += result.status != DiagnosisStatus.ANSWERED.value
        self.out_of_scope += result.status == DiagnosisStatus.OUT_OF_SCOPE.value

    def summary(self) -> dict[str, Any]:
        n = self.cases or 1
        return {
            **asdict(self),
            "top1_accuracy": round(self.correct / n, 4),
            "corpus_answer_share": round(self.corpus_answers / n, 4),
            "llm_share": round(self.llm_used / n, 4),
            "escalation_rate": round(self.escalated / n, 4),
            "out_of_scope_share": round(self.out_of_scope / n, 4),
        }


@dataclass
class Report:
    manifest: str
    tenant_id: str
    encoder: str
    llm: str
    corpus_version: int
    generated_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())
    totals: dict[str, Any] = field(default_factory=dict)
    per_crop: dict[str, Any] = field(default_factory=dict)
    per_problem: dict[str, Any] = field(default_factory=dict)
    hallucinated_out_of_scope: int = 0
    cases: list[dict[str, Any]] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return asdict(self)


def load_manifest(path: Path) -> list[Row]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = set(COLUMNS[:3]) - set(reader.fieldnames or ())
        if missing:
            raise ValueError(f"manifest {path} lacks columns {sorted(missing)}")
        return [
            Row(
                image=r["image"].strip(),
                crop=(r.get("crop") or "unknown").strip(),
                true_problem=r["true_problem"].strip(),
                district=(r.get("district") or "").strip() or None,
                season=(r.get("season") or "").strip() or None,
            )
            for r in reader
            if r.get("image", "").strip()
        ]


async def read_image(ref: str, base: Path, services: DiagnosisServices) -> bytes:
    if ref.startswith("synthetic://"):
        kind, name, variant = ref.removeprefix("synthetic://").split("/")
        if kind == "leaf":
            return synthetic_leaf(name, int(variant))
        return synthetic_non_plant(name, int(variant))
    if ref.startswith("gs://"):
        return await services.blobs.get(ref)
    return (base / ref).read_bytes()


async def evaluate(
    session: AsyncSession,
    services: DiagnosisServices,
    tenant_id: uuid.UUID,
    rows: Sequence[Row],
    *,
    base: Path,
    manifest: str = "",
) -> Report:
    """Run every row through ``decide_case`` (the session is expected to be rolled back)."""
    crops = {
        c.code: c
        for c in (await session.execute(select(Crop).where(Crop.tenant_id == tenant_id))).scalars()
    }
    codes = {
        problem_id: code
        for problem_id, code in (
            await session.execute(
                select(CorpusProblem.id, PestOrDisease.code).join(
                    PestOrDisease, PestOrDisease.id == CorpusProblem.pest_or_disease_id
                )
            )
        ).tuples()
    }
    report = Report(
        manifest=manifest,
        tenant_id=str(tenant_id),
        encoder=services.encoder.info.label,
        llm=services.llm.model,
        corpus_version=await current_version(session, tenant_id),
    )
    totals, per_crop, per_problem = Tally(), defaultdict(Tally), defaultdict(Tally)
    for row in rows:
        data = await read_image(row.image, base, services)
        crop = crops.get(row.crop) if row.crop != "unknown" else None
        case = Case(
            tenant_id=tenant_id,
            images=[(row.image, "", data)],
            crop=crop,
            district=row.district,
            season=row.season,
        )
        verdict = await decide_case(session, services, case, final_attempt=True)
        predicted = codes.get(verdict.problem.id) if verdict.problem is not None else None
        if row.true_problem == OUT_OF_SCOPE:
            correct = predicted is None
            report.hallucinated_out_of_scope += predicted is not None
        else:
            correct = predicted == row.true_problem
        result = CaseResult(
            image=row.image,
            crop=row.crop,
            true_problem=row.true_problem,
            predicted=predicted,
            status=verdict.status.value,
            source=verdict.source.value if verdict.source else None,
            confidence=verdict.confidence.value if verdict.confidence else None,
            correct=correct,
            top1=(verdict.scores or {}).get("top1"),
            llm_used=verdict.llm_used,
            reason=verdict.reason,
        )
        totals.add(result)
        per_crop[row.crop].add(result)
        per_problem[row.true_problem].add(result)
        report.cases.append(asdict(result))
    report.totals = totals.summary()
    report.per_crop = {k: v.summary() for k, v in sorted(per_crop.items())}
    report.per_problem = {k: v.summary() for k, v in sorted(per_problem.items())}
    return report


def write_report(report: Report, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report.to_json(), indent=2, ensure_ascii=False) + "\n")


async def _run(args: argparse.Namespace) -> Report:
    from farmerapp.db import audit
    from farmerapp.db.session import get_session_factory, set_tenant
    from farmerapp.diagnosis.services import build_diagnosis_services
    from farmerapp.jobs.cli import _tenants
    from farmerapp.settings import get_settings

    settings = get_settings().model_copy(update={"diagnosis_llm": args.llm})
    services = build_diagnosis_services(settings)
    (tenant_id,) = _tenants([args.tenant])
    manifest = Path(args.manifest).resolve()
    rows = load_manifest(manifest)
    factory = get_session_factory()
    with audit.actor_scope(audit.system_actor(tenant_id)):
        async with factory() as session:
            await session.begin()
            try:
                await set_tenant(session, tenant_id)
                return await evaluate(
                    session,
                    services,
                    tenant_id,
                    rows,
                    base=manifest.parent,
                    manifest=str(args.manifest),
                )
            finally:
                await session.rollback()  # an evaluation never writes


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--tenant", required=True, help="Tenant id or demo slug (fcc, gfl).")
    parser.add_argument("--out", default=str(Path(__file__).parent / "reports" / "latest.json"))
    parser.add_argument("--llm", choices=("fake", "off", "claude"), default="fake")
    args = parser.parse_args(argv)
    report = asyncio.run(_run(args))
    write_report(report, Path(args.out))
    t = report.totals
    print(  # noqa: T201 - CLI output
        f"{t['cases']} cases: top-1 {t['top1_accuracy']:.1%}, corpus answers "
        f"{t['corpus_answer_share']:.1%}, escalation {t['escalation_rate']:.1%}, "
        f"hallucinated out-of-scope {report.hallucinated_out_of_scope} -> {args.out}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
