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

The logic is ``farmerapp.mlops.evaluation`` (shared with the DX-011 nightly job
``python -m farmerapp.jobs diagnosis-evaluate``, which reads the held-out manifest from the
corpus bucket and records an ``evaluation_run``). The JSON report goes to ``--out`` (default ``ml/eval/reports/latest.json``, not committed).

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
import sys
from collections.abc import Sequence
from pathlib import Path

# DX-011: the evaluation logic lives in the API package so the nightly job
# (``python -m farmerapp.jobs diagnosis-evaluate``) runs exactly the same code in-process.
from farmerapp.mlops.evaluation import (
    COLUMNS,
    OUT_OF_SCOPE,
    CaseResult,
    Report,
    Row,
    Tally,
    evaluate,
    load_manifest,
    parse_manifest,
    read_image,
    write_report,
)

__all__ = [
    "COLUMNS",
    "OUT_OF_SCOPE",
    "CaseResult",
    "Report",
    "Row",
    "Tally",
    "evaluate",
    "load_manifest",
    "main",
    "parse_manifest",
    "read_image",
    "write_report",
]


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
