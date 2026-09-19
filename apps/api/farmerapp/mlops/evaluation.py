"""DX-011 evaluation of the diagnosis pipeline against a labelled manifest.

The evaluation logic that ``ml/eval/evaluate.py`` (the CLI) and the nightly
``diagnosis-evaluate`` job share. It runs the production decision path in-process —
encoder -> pgvector kNN -> DX-003 decision rule -> DX-004 LLM fallback
(``farmerapp.diagnosis.pipeline.decide_case``) — for every row of a manifest, against the
tenant's **approved** corpus, inside a transaction (or savepoint) that is rolled back, and
reports top-1 accuracy overall / per crop / per problem, corpus-answer share, LLM share,
escalation rate, out-of-scope share and hallucinated labels on out-of-scope rows (DX-010).

Manifest (CSV, header required): ``image, crop, true_problem, district, season``. ``image``
is a path relative to the manifest (a local path, or a key next to the manifest in the
bucket), a ``gs://`` blob URI, or a synthetic reference ``synthetic://leaf/<code>/<n>`` /
``synthetic://non_plant/<kind>/<n>`` (CI only).

Nightly job (``run_nightly_evaluation``): reads the held-out manifest from the corpus bucket
(``CORPUS_BUCKET`` + ``DIAGNOSIS_EVAL_MANIFEST``), evaluates in a rolled-back savepoint, then
writes an ``evaluation_run`` row with the metrics and the delta against the previous
successful run. A top-1 drop of more than ``diagnosis_evaluation.alert_drop_points`` (5)
logs ``diagnosis_eval_accuracy_drop`` (WARNING, the log-based alert) and notifies the
agronomists and owners (``diagnosis_eval_drop``). The LLM fallback is ``off`` by default in
the job (no test photos sent to a provider each night; escalated rows count as unanswered);
``--llm configured`` evaluates with the deployed client.
"""

from __future__ import annotations

import asyncio
import csv
import io
import json
import uuid
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.corpus import current_version
from farmerapp.diagnosis.images import synthetic_leaf, synthetic_non_plant
from farmerapp.diagnosis.models import CorpusProblem, DiagnosisStatus
from farmerapp.diagnosis.pipeline import Case, decide_case
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.logging import get_logger
from farmerapp.mlops.models import EvaluationRun, EvaluationStatus
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.tenants.settings import get_tenant_settings
from farmerapp.uploads.blobstore import URI_SCHEME, BlobStore

log = get_logger("farmerapp.mlops.evaluation")

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


def parse_manifest(text: str, *, name: str = "manifest") -> list[Row]:
    reader = csv.DictReader(io.StringIO(text))
    missing = set(COLUMNS[:3]) - set(reader.fieldnames or ())
    if missing:
        raise ValueError(f"manifest {name} lacks columns {sorted(missing)}")
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


def load_manifest(path: Path) -> list[Row]:
    return parse_manifest(path.read_text(encoding="utf-8"), name=str(path))


def _read_local(base: Path | str, ref: str) -> bytes:
    return (Path(base) / ref).read_bytes()


def _join_uri(base_uri: str, ref: str) -> str:
    return base_uri.rstrip("/") + "/" + ref.lstrip("/")


async def read_image(
    ref: str, base: Path | str, services: DiagnosisServices, blobs: BlobStore | None = None
) -> bytes:
    """Bytes of a manifest image: synthetic, ``gs://`` URI, or relative to ``base`` (a local
    directory or a ``gs://`` prefix)."""
    if ref.startswith("synthetic://"):
        kind, name, variant = ref.removeprefix("synthetic://").split("/")
        if kind == "leaf":
            return synthetic_leaf(name, int(variant))
        return synthetic_non_plant(name, int(variant))
    store = blobs or services.blobs
    if ref.startswith(URI_SCHEME):
        return await store.get(ref)
    if isinstance(base, str) and base.startswith(URI_SCHEME):  # noqa: ASYNC240 - a str URI
        return await store.get(_join_uri(base, ref))
    return await asyncio.to_thread(_read_local, base, ref)


async def evaluate(
    session: AsyncSession,
    services: DiagnosisServices,
    tenant_id: uuid.UUID,
    rows: Sequence[Row],
    *,
    base: Path | str,
    manifest: str = "",
    blobs: BlobStore | None = None,
) -> Report:
    """Run every row through ``decide_case`` (the caller rolls the session back)."""
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
    totals = Tally()
    per_crop: defaultdict[str, Tally] = defaultdict(Tally)
    per_problem: defaultdict[str, Tally] = defaultdict(Tally)
    for row in rows:
        data = await read_image(row.image, base, services, blobs)
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


# --------------------------------------------------------------------------- nightly job
def manifest_uri(bucket: str, manifest: str) -> str:
    """``DIAGNOSIS_EVAL_MANIFEST`` as a full URI (a key is relative to the corpus bucket)."""
    if manifest.startswith(URI_SCHEME):
        return manifest
    return f"{URI_SCHEME}{bucket}/{manifest.lstrip('/')}"


def _dirname(uri: str) -> str:
    return uri.rsplit("/", 1)[0]


async def _previous_run(session: AsyncSession, tenant_id: uuid.UUID) -> EvaluationRun | None:
    row: EvaluationRun | None = await session.scalar(
        select(EvaluationRun)
        .where(
            EvaluationRun.tenant_id == tenant_id,
            EvaluationRun.status == EvaluationStatus.OK.value,
            EvaluationRun.deleted_at.is_(None),
        )
        .order_by(EvaluationRun.started_at.desc(), EvaluationRun.id.desc())
        .limit(1)
    )
    return row


async def _alert_recipients(session: AsyncSession, tenant_id: uuid.UUID) -> list[uuid.UUID]:
    rows = await session.scalars(
        select(User.id)
        .where(
            User.tenant_id == tenant_id,
            User.role.in_([UserRole.AGRONOMIST.value, UserRole.OWNER.value]),
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
        )
        .order_by(User.role, User.id)
    )
    return list(rows)


async def nightly_evaluation(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    services: DiagnosisServices,
    manifest: str,
    corpus_blobs: BlobStore,
    now: datetime | None = None,
) -> EvaluationRun:
    """Evaluate in a savepoint that is rolled back, then record the run (and alert)."""
    started = now or datetime.now(UTC)
    previous = await _previous_run(session, tenant_id)
    run = EvaluationRun(
        tenant_id=tenant_id,
        manifest=manifest,
        started_at=started,
        status=EvaluationStatus.OK.value,
        previous_run_id=previous.id if previous is not None else None,
        cases=0,
        hallucinated_out_of_scope=0,
        summary={},
        per_crop={},
        per_problem={},
    )
    try:
        text = (await corpus_blobs.get(manifest)).decode("utf-8")
        rows = parse_manifest(text, name=manifest)
        savepoint = await session.begin_nested()
        try:
            report = await evaluate(
                session,
                services,
                tenant_id,
                rows,
                base=_dirname(manifest),
                manifest=manifest,
                blobs=corpus_blobs,
            )
        finally:
            await savepoint.rollback()  # an evaluation never writes
    except Exception as exc:  # the run is recorded as failed, the job exits non-zero later
        log.exception("diagnosis_eval_failed", tenant_id=str(tenant_id), manifest=manifest)
        run.status = EvaluationStatus.FAILED.value
        run.error = f"{type(exc).__name__}: {exc}"[:2000]
        run.finished_at = datetime.now(UTC)
        session.add(run)
        await session.flush()
        return run
    totals = report.totals
    run.encoder = report.encoder
    run.llm = report.llm
    run.corpus_version = report.corpus_version
    run.cases = int(totals.get("cases", 0))
    run.top1_accuracy = totals.get("top1_accuracy")
    run.corpus_answer_share = totals.get("corpus_answer_share")
    run.escalation_rate = totals.get("escalation_rate")
    run.hallucinated_out_of_scope = report.hallucinated_out_of_scope
    run.summary = totals
    run.per_crop = report.per_crop
    run.per_problem = report.per_problem
    run.finished_at = datetime.now(UTC)
    threshold = (await get_tenant_settings(session, tenant_id)).diagnosis_evaluation
    if (
        previous is not None
        and previous.top1_accuracy is not None
        and run.top1_accuracy is not None
    ):
        run.top1_delta_points = round((run.top1_accuracy - previous.top1_accuracy) * 100, 2)
        run.alerted = -run.top1_delta_points > threshold.alert_drop_points
    session.add(run)
    await session.flush()
    log.info(
        "diagnosis_eval_done",
        tenant_id=str(tenant_id),
        run_id=str(run.id),
        cases=run.cases,
        top1_accuracy=run.top1_accuracy,
        corpus_answer_share=run.corpus_answer_share,
        escalation_rate=run.escalation_rate,
        delta_points=run.top1_delta_points,
    )
    if run.alerted:
        log.warning(
            "diagnosis_eval_accuracy_drop",
            tenant_id=str(tenant_id),
            run_id=str(run.id),
            top1_accuracy=run.top1_accuracy,
            previous_top1_accuracy=previous.top1_accuracy if previous else None,
            delta_points=run.top1_delta_points,
            threshold_points=threshold.alert_drop_points,
        )
        kind = NotificationKind.DIAGNOSIS_EVAL_DROP.value
        for user_id in await _alert_recipients(session, tenant_id):
            session.add(
                Notification(
                    tenant_id=tenant_id,
                    user_id=user_id,
                    kind=kind,
                    title_key=f"notification.{kind}.title",
                    body_key=f"notification.{kind}.body",
                    data={
                        "evaluation_run_id": str(run.id),
                        "top1_accuracy": run.top1_accuracy,
                        "delta_points": run.top1_delta_points,
                    },
                )
            )
        await session.flush()
    return run


def corpus_blob_store(settings: Any) -> BlobStore:
    """A blob store that writes into the corpus bucket (reads work on any ``gs://`` URI)."""
    from farmerapp.uploads.blobstore import build_blob_store

    return build_blob_store(settings.model_copy(update={"photos_bucket": settings.corpus_bucket}))


async def run_nightly_evaluation(
    tenant_ids: Iterable[uuid.UUID],
    *,
    services: DiagnosisServices,
    manifest: str | None = None,
    corpus_blobs: BlobStore | None = None,
) -> list[EvaluationRun]:
    settings = services.settings
    uri = manifest_uri(settings.corpus_bucket, manifest or settings.diagnosis_eval_manifest)
    blobs = corpus_blobs or corpus_blob_store(settings)
    runs: list[EvaluationRun] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                runs.append(
                    await nightly_evaluation(
                        session,
                        tenant_id=tenant_id,
                        services=services,
                        manifest=uri,
                        corpus_blobs=blobs,
                    )
                )
    return runs


__all__ = [
    "COLUMNS",
    "OUT_OF_SCOPE",
    "CaseResult",
    "Report",
    "Row",
    "Tally",
    "corpus_blob_store",
    "evaluate",
    "load_manifest",
    "manifest_uri",
    "nightly_evaluation",
    "parse_manifest",
    "read_image",
    "run_nightly_evaluation",
    "write_report",
]
