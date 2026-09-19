"""The diagnosis pipeline (SPEC 3 flowchart): encode -> kNN -> decision -> (LLM) ->
treatment -> result.

``process(session, services, diagnosis, now=)`` runs once per queued diagnosis (the worker's
``diagnosis.requested`` handler, or inline in the request locally) and leaves it

* ``answered`` — high confidence corpus answer (DX-003), treatments with ``can_buy``;
* ``provisional`` — medium / low: the LLM chose a candidate or said "unknown" (DX-004);
  treatments shown but ``can_buy: false`` and ``cta: talk_to_field_officer`` (SPEC 3.4);
  it waits in the agronomist queue (DX-006);
* ``out_of_scope`` — DX-010: the device saw no plant, the crop has no approved corpus, the
  photo is unreadable, nothing in the corpus is similar enough, or the LLM says the photo
  shows no plant. A friendly message key, no problem and no products; routed to the
  agronomist queue — never a hallucinated diagnosis.

Everything needed to reproduce the decision is stored (DX-005): model versions (encoder,
on-device, LLM), corpus version, thresholds (with their config version), the neighbours
(image, problem, similarity), votes, candidates, final label and source.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.catalog.crops import Crop
from farmerapp.diagnosis import knn
from farmerapp.diagnosis.corpus import current_version, read_tenant_blob
from farmerapp.diagnosis.decision import Decision, decide
from farmerapp.diagnosis.encoder import EncoderError
from farmerapp.diagnosis.errors import DiagnosisImageMissingError
from farmerapp.diagnosis.images import UnreadableImageError, strip_for_llm
from farmerapp.diagnosis.llm import (
    LlmCallRecord,
    LlmCandidate,
    LlmImage,
    LlmOutcome,
    LlmRequest,
    LlmTemporaryError,
)
from farmerapp.diagnosis.models import (
    Confidence,
    CorpusProblem,
    CorpusStatus,
    Diagnosis,
    DiagnosisSource,
    DiagnosisStatus,
    LlmCallLog,
)
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.diagnosis.thresholds import thresholds_for
from farmerapp.diagnosis.treatment import farmer_store, treatments_for
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind

log = get_logger("farmerapp.diagnosis.pipeline")

#: On-device crop guesses below this confidence are ignored (the corpus decides).
CROP_GUESS_MIN = 0.6
LLM_LOG_RETENTION = timedelta(days=366)


class OutOfScope:
    NOT_A_PLANT = "not_a_plant"
    UNSUPPORTED_CROP = "unsupported_crop"
    UNREADABLE_IMAGE = "unreadable_image"
    NO_MATCH = "no_match"


class PipelineTemporaryError(RuntimeError):
    """Encoder unavailable: leave the diagnosis queued and retry the delivery."""


_BANDS = {"high": 3, "medium": 2, "low": 1}


def cap_confidence(band: str | None, cap: Confidence = Confidence.MEDIUM) -> Confidence:
    """An LLM answer is at most ``medium`` (it is provisional until confirmed)."""
    if band is None:
        return Confidence.LOW
    return Confidence(band) if _BANDS[band] <= _BANDS[cap.value] else cap


# --------------------------------------------------------------------------- result
def problem_json(problem: CorpusProblem, pest_code: str | None) -> dict[str, Any]:
    return {
        "id": str(problem.id),
        "pest_or_disease_id": str(problem.pest_or_disease_id),
        "code": pest_code,
        "type": problem.problem_type,
        "crop_id": str(problem.crop_id),
        "names": dict(problem.names or {}),
        "symptoms": dict(problem.symptoms or {}),
    }


def empty_treatments(store: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"organic": [], "chemical": [], "cultural": {}, "store": store}


def build_result(
    *,
    status: DiagnosisStatus,
    confidence: Confidence | None,
    problem: dict[str, Any] | None,
    treatments: dict[str, Any] | None,
    out_of_scope_reason: str | None = None,
    visible_symptoms: list[str] | None = None,
) -> dict[str, Any]:
    """The farmer-facing answer (FM-005). ``can_buy`` only once the corpus or an agronomist
    stands behind the label (SPEC 3.4); provisional results say "talk to your field
    officer"; out-of-scope ones "ask an expert"."""
    confirmed = status in (
        DiagnosisStatus.ANSWERED,
        DiagnosisStatus.CONFIRMED,
        DiagnosisStatus.CORRECTED,
    )
    can_buy = confirmed and problem is not None
    if status == DiagnosisStatus.OUT_OF_SCOPE:
        message_key = f"diagnosis.out_of_scope.{out_of_scope_reason or 'unknown'}"
        cta = "ask_expert"
    elif problem is None:
        message_key = "diagnosis.result.unknown"
        cta = "talk_to_field_officer"
    else:
        message_key = f"diagnosis.result.{status.value}"
        cta = "buy" if can_buy else "talk_to_field_officer"
    return {
        "problem": problem,
        "confidence": confidence.value if confidence else None,
        "provisional": status == DiagnosisStatus.PROVISIONAL,
        "can_buy": can_buy,
        "cta": cta,
        "message_key": message_key,
        "out_of_scope_reason": out_of_scope_reason,
        "visible_symptoms": list(visible_symptoms or []),
        "treatments": treatments or empty_treatments(),
    }


async def result_for_problem(
    session: AsyncSession,
    diagnosis: Diagnosis,
    problem: CorpusProblem,
    *,
    status: DiagnosisStatus,
    confidence: Confidence,
    today: date,
    visible_symptoms: list[str] | None = None,
) -> dict[str, Any]:
    from farmerapp.diagnosis.corpus import pest_codes

    farmer = await session.get_one(Farmer, diagnosis.farmer_id)
    store = await farmer_store(session, farmer)
    treatments = await treatments_for(
        session,
        tenant_id=diagnosis.tenant_id,
        crop_id=problem.crop_id,
        pest_or_disease_id=problem.pest_or_disease_id,
        store=store,
        today=today,
        cultural=problem.cultural_practices,
    )
    codes = await pest_codes(session, [problem.pest_or_disease_id])
    return build_result(
        status=status,
        confidence=confidence,
        problem=problem_json(problem, codes.get(problem.pest_or_disease_id)),
        treatments=treatments,
        visible_symptoms=visible_symptoms,
    )


# --------------------------------------------------------------------------- notifications
async def recipients(session: AsyncSession, diagnosis: Diagnosis) -> list[uuid.UUID]:
    """The farmer's own login (if any) and the officer: the requester when an officer asked,
    else the officer who registered the farmer."""
    farmer = await session.get(Farmer, diagnosis.farmer_id)
    out: list[uuid.UUID] = []
    if farmer is not None and farmer.user_id is not None:
        out.append(farmer.user_id)
    officer = diagnosis.requested_by if diagnosis.subject == "officer" else None
    if officer is None and farmer is not None:
        officer = farmer.registered_by
    if officer is not None and officer not in out:
        exists = await session.scalar(select(User.id).where(User.id == officer))
        if exists is not None:
            out.append(officer)
    return out


async def notify(
    session: AsyncSession, diagnosis: Diagnosis, kind: NotificationKind, *, now: datetime
) -> list[uuid.UUID]:
    users = await recipients(session, diagnosis)
    for user_id in users:
        session.add(
            Notification(
                tenant_id=diagnosis.tenant_id,
                user_id=user_id,
                kind=kind.value,
                title_key=f"notification.{kind.value}.title",
                body_key=f"notification.{kind.value}.body",
                data={
                    "diagnosis_id": str(diagnosis.id),
                    "status": diagnosis.status,
                    "farmer_id": str(diagnosis.farmer_id),
                },
            )
        )
    diagnosis.notified_at = now
    return users


# --------------------------------------------------------------------------- llm log
async def write_llm_logs(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    diagnosis_id: uuid.UUID | None,
    calls: list[LlmCallRecord],
    *,
    now: datetime,
) -> None:
    for call in calls:
        session.add(
            LlmCallLog(
                tenant_id=tenant_id,
                diagnosis_id=diagnosis_id,
                provider=call.provider,
                model=call.model,
                attempt=call.attempt,
                prompt=call.prompt,
                raw_output=call.raw_output,
                parsed=call.parsed,
                outcome=call.outcome,
                stop_reason=call.stop_reason,
                stop_details=call.stop_details,
                error=call.error,
                input_tokens=call.input_tokens,
                output_tokens=call.output_tokens,
                latency_ms=call.latency_ms,
                retain_until=(now + LLM_LOG_RETENTION).date(),
            )
        )
        log.info(
            "llm_call",
            tenant_id=str(tenant_id),
            diagnosis_id=str(diagnosis_id) if diagnosis_id else None,
            provider=call.provider,
            model=call.model,
            attempt=call.attempt,
            outcome=call.outcome,
            stop_reason=call.stop_reason,
            latency_ms=call.latency_ms,
            input_tokens=call.input_tokens,
            output_tokens=call.output_tokens,
        )
    await session.flush()


# --------------------------------------------------------------------------- steps
async def _resolve_crop(session: AsyncSession, diagnosis: Diagnosis) -> Crop | None:
    if diagnosis.crop_id is not None:
        return await session.get(Crop, diagnosis.crop_id)
    guess = diagnosis.crop_detected_on_device or {}
    code, confidence = guess.get("code"), float(guess.get("confidence") or 0)
    if code and confidence >= CROP_GUESS_MIN:
        crop = await session.scalar(
            select(Crop).where(
                Crop.tenant_id == diagnosis.tenant_id, Crop.code == code, Crop.deleted_at.is_(None)
            )
        )
        if crop is not None:
            diagnosis.crop_id = crop.id
        return crop
    return None


async def _crop_supported(session: AsyncSession, tenant_id: uuid.UUID, crop_id: uuid.UUID) -> bool:
    count = await session.scalar(
        select(func.count())
        .select_from(CorpusProblem)
        .where(
            CorpusProblem.tenant_id == tenant_id,
            CorpusProblem.crop_id == crop_id,
            CorpusProblem.status == CorpusStatus.APPROVED.value,
            CorpusProblem.deleted_at.is_(None),
        )
    )
    return bool(count)


def _device_says_no_plant(diagnosis: Diagnosis) -> bool:
    flags = [(i.get("quality") or {}).get("plant_present") for i in diagnosis.images or []]
    return bool(flags) and all(flag is False for flag in flags)


def _finish(
    diagnosis: Diagnosis,
    *,
    status: DiagnosisStatus,
    result: dict[str, Any],
    now: datetime,
    source: DiagnosisSource | None,
    confidence: Confidence | None,
    final_problem_id: uuid.UUID | None = None,
    reason: str | None = None,
) -> None:
    diagnosis.status = status.value
    diagnosis.result = result
    diagnosis.source = source.value if source else None
    diagnosis.confidence = confidence.value if confidence else None
    diagnosis.final_problem_id = final_problem_id
    diagnosis.out_of_scope_reason = reason
    diagnosis.answered_at = now


async def _out_of_scope(
    session: AsyncSession, diagnosis: Diagnosis, reason: str, *, now: datetime
) -> None:
    _finish(
        diagnosis,
        status=DiagnosisStatus.OUT_OF_SCOPE,
        result=build_result(
            status=DiagnosisStatus.OUT_OF_SCOPE,
            confidence=None,
            problem=None,
            treatments=None,
            out_of_scope_reason=reason,
        ),
        now=now,
        source=None,
        confidence=None,
        reason=reason,
    )


@dataclass(frozen=True)
class Case:
    """The inputs of one decision: photos plus crop context (no people, NF-011)."""

    tenant_id: uuid.UUID
    images: list[tuple[str, str, bytes]]  # (blob uri, sha256, bytes)
    crop: Crop | None
    district: str | None = None
    season: str | None = None
    crop_stage: str | None = None
    language: str = "en"
    device_no_plant: bool = False


@dataclass
class Verdict:
    """What the pipeline concluded for a case (before any row is written)."""

    status: DiagnosisStatus
    source: DiagnosisSource | None = None
    confidence: Confidence | None = None
    problem: CorpusProblem | None = None
    reason: str | None = None
    scores: dict[str, Any] | None = None
    llm: LlmOutcome | None = None
    crop_id: uuid.UUID | None = None

    @property
    def llm_used(self) -> bool:
        return self.llm is not None


async def _llm_request(
    session: AsyncSession, case: Case, decision: Decision
) -> tuple[LlmRequest, dict[uuid.UUID, CorpusProblem]]:
    ids = [c.problem_id for c in decision.candidates]
    problems = {
        p.id: p
        for p in (
            await session.execute(select(CorpusProblem).where(CorpusProblem.id.in_(ids)))
        ).scalars()
    }
    language = case.language or "en"
    candidates = []
    for c in decision.candidates:
        problem = problems.get(c.problem_id)
        if problem is None:  # pragma: no cover - a candidate always has its problem row
            continue
        names = problem.names or {}
        symptoms = (problem.symptoms or {}).get("en") or []
        local = names.get(language) if language != "en" else None
        candidates.append(
            LlmCandidate(
                problem_id=str(problem.id),
                english_name=str(names.get("en") or ""),
                local_name=str(local) if local else None,
                symptoms=tuple(str(s) for s in symptoms[:5]),
            )
        )
    request = LlmRequest(
        images=tuple(
            LlmImage(data=strip_for_llm(data), blob_uri=uri, sha256=sha)
            for uri, sha, data in case.images
        ),
        crop=case.crop.name if case.crop is not None else "unknown",
        district=case.district,
        season=case.season,
        crop_stage=case.crop_stage,
        candidates=tuple(candidates),
    )
    return request, problems


async def decide_case(
    session: AsyncSession,
    services: DiagnosisServices,
    case: Case,
    *,
    final_attempt: bool = False,
) -> Verdict:
    """encode -> kNN -> DX-003 decision -> (DX-004 LLM): the verdict for ``case``. Writes
    nothing (``ml/eval/evaluate.py`` runs it too). Raises ``PipelineTemporaryError`` (encoder
    down) / ``LlmTemporaryError`` (LLM rate limit / 5xx / network) unless ``final_attempt``."""
    tenant_id, crop = case.tenant_id, case.crop
    if case.device_no_plant:
        return Verdict(DiagnosisStatus.OUT_OF_SCOPE, reason=OutOfScope.NOT_A_PLANT)
    if crop is not None and not await _crop_supported(session, tenant_id, crop.id):
        return Verdict(DiagnosisStatus.OUT_OF_SCOPE, reason=OutOfScope.UNSUPPORTED_CROP)
    try:
        vectors = await services.encoder.encode([data for _, _, data in case.images])
    except UnreadableImageError:
        return Verdict(DiagnosisStatus.OUT_OF_SCOPE, reason=OutOfScope.UNREADABLE_IMAGE)
    except EncoderError as exc:
        raise PipelineTemporaryError("encoder unavailable") from exc

    await knn.tune_session(session, ef_search=services.settings.diagnosis_hnsw_ef_search)
    neighbours = await knn.nearest_for_images(
        session,
        vectors,
        tenant_id=tenant_id,
        crop_id=crop.id if crop is not None else None,
        encoder=services.encoder.info,
        k=services.settings.diagnosis_knn_k,
    )
    thresholds = await thresholds_for(session, tenant_id, crop.id if crop else None)
    decision = decide(neighbours, thresholds)
    scores: dict[str, Any] = {
        "neighbours": [n.to_json() for n in neighbours],
        "thresholds": thresholds.to_json(),
        "decision": decision.to_json(),
        "top1": round(decision.top1, 6),
        "votes": decision.votes,
        "candidates": decision.to_json()["candidates"],
    }
    if not decision.in_scope:
        return Verdict(DiagnosisStatus.OUT_OF_SCOPE, reason=OutOfScope.NO_MATCH, scores=scores)
    if decision.high and decision.problem_id is not None:
        problem = await session.get_one(CorpusProblem, decision.problem_id)
        return Verdict(
            DiagnosisStatus.ANSWERED,
            source=DiagnosisSource.CORPUS,
            confidence=Confidence.HIGH,
            problem=problem,
            scores=scores,
            crop_id=problem.crop_id,
        )

    # Medium / low: the LLM chooses among the candidates or says "unknown" (DX-004).
    request, problems = await _llm_request(session, case, decision)
    try:
        outcome = await services.llm.diagnose(request)
    except LlmTemporaryError as exc:
        if not final_attempt:
            raise
        outcome = LlmOutcome.unknown("error", services.llm.model, exc.calls)
    scores["llm"] = {
        "model": services.llm.model,
        "status": outcome.status,
        "problem_id": str(outcome.problem_id) if outcome.problem_id else None,
        "confidence": outcome.confidence,
        "reasoning": outcome.reasoning,
        "not_a_plant": outcome.not_a_plant,
    }
    if outcome.not_a_plant:
        return Verdict(
            DiagnosisStatus.OUT_OF_SCOPE, reason=OutOfScope.NOT_A_PLANT, scores=scores, llm=outcome
        )
    chosen = problems.get(outcome.problem_id) if outcome.problem_id else None
    if chosen is None:
        return Verdict(
            DiagnosisStatus.PROVISIONAL,
            source=DiagnosisSource.LLM,
            confidence=Confidence.LOW,
            scores=scores,
            llm=outcome,
        )
    return Verdict(
        DiagnosisStatus.PROVISIONAL,
        source=DiagnosisSource.LLM,
        confidence=cap_confidence(outcome.confidence),
        problem=chosen,
        scores=scores,
        llm=outcome,
        crop_id=chosen.crop_id,
    )


async def process(
    session: AsyncSession,
    services: DiagnosisServices,
    diagnosis: Diagnosis,
    *,
    now: datetime | None = None,
    final_attempt: bool = False,
) -> Diagnosis:
    """Run the pipeline for a ``queued`` diagnosis (no-op otherwise) and store the result.
    Raises ``LlmTemporaryError`` / ``PipelineTemporaryError`` to retry later unless
    ``final_attempt`` (then a failing LLM call is "unknown")."""
    now = now or datetime.now(UTC)
    if diagnosis.status != DiagnosisStatus.QUEUED.value:
        return diagnosis
    started = time.monotonic()
    tenant_id = diagnosis.tenant_id
    diagnosis.corpus_version = await current_version(session, tenant_id)
    diagnosis.model_versions = {
        **(diagnosis.model_versions or {}),
        "encoder": services.encoder.info.label,
        "llm": None,
    }
    crop = await _resolve_crop(session, diagnosis)
    images: list[tuple[str, str, bytes]] = []
    unreadable = False
    try:
        for photo in diagnosis.images or []:
            data, digest = await read_tenant_blob(services.blobs, tenant_id, photo["blob_uri"])
            images.append((photo["blob_uri"], digest, data))
    except DiagnosisImageMissingError:
        unreadable = True
    case = Case(
        tenant_id=tenant_id,
        images=images,
        crop=crop,
        district=diagnosis.district,
        season=diagnosis.season,
        crop_stage=diagnosis.crop_stage,
        language=diagnosis.language or "en",
        device_no_plant=_device_says_no_plant(diagnosis),
    )
    if unreadable and not case.device_no_plant:
        verdict = Verdict(DiagnosisStatus.OUT_OF_SCOPE, reason=OutOfScope.UNREADABLE_IMAGE)
    else:
        verdict = await decide_case(session, services, case, final_attempt=final_attempt)
    diagnosis.scores = verdict.scores
    if verdict.llm is not None:
        diagnosis.llm_used = True
        diagnosis.model_versions = {**diagnosis.model_versions, "llm": services.llm.model}
        await write_llm_logs(session, tenant_id, diagnosis.id, verdict.llm.calls, now=now)
    if diagnosis.crop_id is None and verdict.crop_id is not None:
        diagnosis.crop_id = verdict.crop_id
    symptoms = verdict.llm.visible_symptoms if verdict.llm is not None else None
    if verdict.status == DiagnosisStatus.OUT_OF_SCOPE:
        await _out_of_scope(session, diagnosis, verdict.reason or OutOfScope.NO_MATCH, now=now)
    elif verdict.problem is not None:
        confidence = verdict.confidence or Confidence.LOW
        result = await result_for_problem(
            session,
            diagnosis,
            verdict.problem,
            status=verdict.status,
            confidence=confidence,
            today=now.date(),
            visible_symptoms=symptoms,
        )
        _finish(
            diagnosis,
            status=verdict.status,
            result=result,
            now=now,
            source=verdict.source,
            confidence=confidence,
            final_problem_id=verdict.problem.id,
        )
    else:
        _finish(
            diagnosis,
            status=DiagnosisStatus.PROVISIONAL,
            result=build_result(
                status=DiagnosisStatus.PROVISIONAL,
                confidence=Confidence.LOW,
                problem=None,
                treatments=None,
                visible_symptoms=symptoms,
            ),
            now=now,
            source=verdict.source,
            confidence=Confidence.LOW,
        )
    return await _done(session, diagnosis, now=now, started=started)


async def _done(
    session: AsyncSession, diagnosis: Diagnosis, *, now: datetime, started: float
) -> Diagnosis:
    await notify(session, diagnosis, NotificationKind.DIAGNOSIS_READY, now=now)
    await session.flush()
    await session.refresh(diagnosis)
    log.info(
        "diagnosis_answered",
        tenant_id=str(diagnosis.tenant_id),
        diagnosis_id=str(diagnosis.id),
        status=diagnosis.status,
        source=diagnosis.source,
        confidence=diagnosis.confidence,
        llm_used=diagnosis.llm_used,
        out_of_scope_reason=diagnosis.out_of_scope_reason,
        top1=(diagnosis.scores or {}).get("top1"),
        processing_ms=int((time.monotonic() - started) * 1000),
        turnaround_ms=int((now - diagnosis.created_at).total_seconds() * 1000)
        if diagnosis.created_at is not None
        else None,
    )
    return diagnosis


__all__ = [
    "CROP_GUESS_MIN",
    "Case",
    "OutOfScope",
    "PipelineTemporaryError",
    "Verdict",
    "build_result",
    "cap_confidence",
    "decide_case",
    "empty_treatments",
    "notify",
    "problem_json",
    "process",
    "recipients",
    "result_for_problem",
    "write_llm_logs",
]
