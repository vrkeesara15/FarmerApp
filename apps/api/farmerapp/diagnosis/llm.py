"""DX-004 LLM fallback behind a provider-neutral protocol (SEC-027, NF-011, SPEC 3.4).

``LlmDiagnosisClient.diagnose(request) -> LlmOutcome``: the photos plus **only** crop,
district, season, crop stage and the top-5 corpus candidates (problem id, local and English
name, key symptoms) — never a farmer or officer name, phone or id (NF-011). The model must
pick one of the candidate ids or answer ``"unknown"``; the answer is structured JSON
validated against ``LlmAnswer``.

``ClaudeDiagnosisClient`` (Anthropic Messages API, ``claude-opus-5`` by default):

* the photo goes as a base64 ``image`` block **after** re-encoding (EXIF stripped,
  ``images.strip_for_llm``), followed by one text block with the context;
* ``output_config = {"format": {"type": "json_schema", "schema": ...}, "effort": "medium"}``
  with the schema ``{problem_id: enum(candidates + "unknown"), confidence: high|medium|low,
  reasoning, visible_symptoms[]}`` (``additionalProperties: false``, all required);
  adaptive thinking is left at the model default; ``max_tokens`` 16 000;
* ``stop_reason`` is checked before reading content: ``refusal`` -> unknown (``stop_details``
  logged), ``max_tokens`` -> one retry with twice the budget;
* invalid JSON, a schema violation or an id outside the candidates -> one retry, then
  ``unknown`` (DX-004 acceptance);
* errors, most specific first: ``RateLimitError``, ``APIStatusError`` >= 500 and
  ``APIConnectionError`` raise ``LlmTemporaryError`` (the worker nacks, Pub/Sub retries with
  backoff); any other API error -> ``unknown``.

Every call attempt becomes an ``LlmCallRecord`` (prompt without image bytes — blob URI and
sha256 instead — raw output, model, latency, tokens, stop reason) that the pipeline writes to
the append-only ``llm_call_log`` (kept one year, SPEC 3.4).
"""

from __future__ import annotations

import base64
import dataclasses
import hashlib
import json
import time
import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any, Literal, Protocol

import anthropic
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from farmerapp.logging import get_logger
from farmerapp.pii.llm_guard import (
    DIAGNOSIS_PROMPT_FIELDS,
    PromptPiiError,
    assert_no_exif,
    guard_prompt,
)

log = get_logger("farmerapp.diagnosis.llm")

UNKNOWN = "unknown"
#: The LLM marks a photo that shows no plant by starting ``reasoning`` with this (DX-010).
NOT_A_PLANT_MARK = "NOT_A_PLANT:"
PROVIDER_ANTHROPIC = "anthropic"

SYSTEM_PROMPT = (
    "You are an agronomy assistant helping extension officers in India identify crop "
    "problems from field photos. You receive one to three photos of one plant and a short "
    "context: the crop, the district, the season, the crop stage and up to five candidate "
    "problems that a reference collection of labelled images found most similar.\n\n"
    "Choose the single candidate that best explains what is visible in the photos. Answer "
    f'"{UNKNOWN}" when none of the candidates fits, when the photos are too unclear to '
    "decide, or when they do not show a plant. Never name a problem that is not in the "
    "candidate list. When the photos show no plant at all, answer "
    f'"{UNKNOWN}" and begin the reasoning with "{NOT_A_PLANT_MARK}".\n\n'
    "Confidence: high only when the visible symptoms clearly match one candidate; medium "
    "when they match but another candidate is plausible; low otherwise. Keep the reasoning "
    "to two short sentences and list the symptoms you can actually see."
)

Band = Literal["high", "medium", "low"]


# --------------------------------------------------------------------------- request / outcome
@dataclass(frozen=True)
class LlmImage:
    """One photo as sent: stripped JPEG bytes plus references for the log."""

    data: bytes  # re-encoded JPEG, EXIF removed (SEC-027)
    blob_uri: str
    sha256: str  # of the uploaded original
    media_type: str = "image/jpeg"

    @property
    def sent_sha256(self) -> str:
        return hashlib.sha256(self.data).hexdigest()


@dataclass(frozen=True)
class LlmCandidate:
    problem_id: str
    english_name: str
    local_name: str | None
    symptoms: tuple[str, ...]


@dataclass(frozen=True)
class LlmRequest:
    images: tuple[LlmImage, ...]
    crop: str
    district: str | None
    season: str | None
    crop_stage: str | None
    candidates: tuple[LlmCandidate, ...]

    @property
    def allowed_ids(self) -> list[str]:
        return [c.problem_id for c in self.candidates] + [UNKNOWN]


class LlmAnswer(BaseModel):
    """The structured output the model must return (validated after ``json.loads``)."""

    model_config = ConfigDict(extra="forbid")

    problem_id: str = Field(min_length=1, max_length=64)
    confidence: Band
    reasoning: str = Field(max_length=2000)
    visible_symptoms: list[str] = Field(max_length=20)


@dataclass
class LlmCallRecord:
    provider: str
    model: str
    attempt: int
    prompt: dict[str, Any]
    outcome: str  # ok | invalid | refusal | max_tokens | rate_limited | server_error |
    #               connection_error | api_error
    latency_ms: int
    raw_output: str | None = None
    parsed: dict[str, Any] | None = None
    stop_reason: str | None = None
    stop_details: dict[str, Any] | None = None
    error: str | None = None
    input_tokens: int | None = None
    output_tokens: int | None = None


@dataclass
class LlmOutcome:
    problem_id: uuid.UUID | None  # None = unknown
    confidence: Band | None
    reasoning: str | None
    visible_symptoms: list[str]
    not_a_plant: bool
    status: str  # answered | unknown | refusal | invalid | error | disabled
    model: str | None
    calls: list[LlmCallRecord] = field(default_factory=list)

    @classmethod
    def unknown(
        cls, status: str, model: str | None, calls: list[LlmCallRecord] | None = None
    ) -> LlmOutcome:
        return cls(
            problem_id=None,
            confidence=None,
            reasoning=None,
            visible_symptoms=[],
            not_a_plant=False,
            status=status,
            model=model,
            calls=calls or [],
        )


class LlmTemporaryError(RuntimeError):
    """Rate limited / provider 5xx / connection problem: retry the whole diagnosis later."""

    def __init__(self, message: str, calls: list[LlmCallRecord]) -> None:
        super().__init__(message)
        self.calls = calls


class LlmDiagnosisClient(Protocol):
    provider: str
    model: str

    async def diagnose(self, request: LlmRequest) -> LlmOutcome: ...


# --------------------------------------------------------------------------- prompt
def answer_schema(allowed_ids: Sequence[str]) -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "problem_id": {"type": "string", "enum": list(allowed_ids)},
            "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
            "reasoning": {"type": "string"},
            "visible_symptoms": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["problem_id", "confidence", "reasoning", "visible_symptoms"],
        "additionalProperties": False,
    }


def context_text(request: LlmRequest) -> str:
    """The text block: crop context and candidates only (NF-011: nothing about people)."""
    lines = [
        f"Crop: {request.crop}",
        f"District: {request.district or 'not given'}",
        f"Season: {request.season or 'not given'}",
        f"Crop stage: {request.crop_stage or 'not given'}",
        "",
        "Candidate problems (choose one id, or unknown):",
    ]
    for c in request.candidates:
        local = f" / {c.local_name}" if c.local_name else ""
        symptoms = "; ".join(c.symptoms) if c.symptoms else "no checklist"
        lines.append(f"- id {c.problem_id}: {c.english_name}{local}. Key symptoms: {symptoms}")
    return "\n".join(lines)


GUARD_SITE = "diagnosis.fallback"


def guard_request(request: LlmRequest) -> None:
    """SEC-027: the shared guard, run before the prompt leaves the process.

    Three assertions: the request carries exactly the reviewed fields
    (``DIAGNOSIS_PROMPT_FIELDS`` — adding one to ``LlmRequest`` fails here until it is
    reviewed), the rendered context text carries nothing person-shaped, and every image was
    re-encoded by ``images.strip_for_llm`` so no EXIF / GPS block survives.
    """
    fields = {f.name for f in dataclasses.fields(request)}
    if fields != set(DIAGNOSIS_PROMPT_FIELDS):
        raise PromptPiiError(
            GUARD_SITE,
            [
                f"unreviewed prompt field {n!r}"
                for n in sorted(fields ^ set(DIAGNOSIS_PROMPT_FIELDS))
            ],
        )
    guard_prompt({"text": context_text(request)}, where=GUARD_SITE)
    for image in request.images:
        assert_no_exif(image.data, where=f"{GUARD_SITE}:{image.sha256[:12]}")


def build_messages(request: LlmRequest) -> list[dict[str, Any]]:
    guard_request(request)
    content: list[dict[str, Any]] = [
        {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": image.media_type,
                "data": base64.b64encode(image.data).decode(),
            },
        }
        for image in request.images
    ]
    content.append({"type": "text", "text": context_text(request)})
    return [{"role": "user", "content": content}]


def loggable_prompt(request: LlmRequest, *, max_tokens: int, effort: str) -> dict[str, Any]:
    """The prompt as logged: no image bytes (SEC-027), their references instead."""
    guard_request(request)
    return {
        "system": SYSTEM_PROMPT,
        "images": [
            {
                "blob_uri": image.blob_uri,
                "sha256": image.sha256,
                "sent_sha256": image.sent_sha256,
                "media_type": image.media_type,
                "bytes": len(image.data),
            }
            for image in request.images
        ],
        "text": context_text(request),
        "schema": answer_schema(request.allowed_ids),
        "max_tokens": max_tokens,
        "effort": effort,
    }


def parse_answer(raw: str, allowed_ids: Sequence[str]) -> LlmAnswer:
    """``json.loads`` + Pydantic + candidate check; ``ValueError`` for anything invalid."""
    try:
        answer = LlmAnswer.model_validate(json.loads(raw))
    except (json.JSONDecodeError, ValidationError) as exc:
        raise ValueError(f"invalid answer: {exc}") from exc
    if answer.problem_id not in allowed_ids:
        raise ValueError(f"problem_id {answer.problem_id!r} is not a candidate")
    return answer


def outcome_from_answer(answer: LlmAnswer, model: str, calls: list[LlmCallRecord]) -> LlmOutcome:
    if answer.problem_id == UNKNOWN:
        return LlmOutcome(
            problem_id=None,
            confidence=answer.confidence,
            reasoning=answer.reasoning,
            visible_symptoms=list(answer.visible_symptoms),
            not_a_plant=answer.reasoning.strip().upper().startswith(NOT_A_PLANT_MARK),
            status="unknown",
            model=model,
            calls=calls,
        )
    return LlmOutcome(
        problem_id=uuid.UUID(answer.problem_id),
        confidence=answer.confidence,
        reasoning=answer.reasoning,
        visible_symptoms=list(answer.visible_symptoms),
        not_a_plant=False,
        status="answered",
        model=model,
        calls=calls,
    )


# --------------------------------------------------------------------------- Claude
def _first_text(content: Sequence[Any]) -> str | None:
    for block in content:
        if getattr(block, "type", None) == "text":
            return str(block.text)
    return None


def _dump(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    dump = getattr(value, "model_dump", None)
    return dict(dump(mode="json")) if callable(dump) else {"value": str(value)}


class ClaudeDiagnosisClient:
    """``LlmDiagnosisClient`` over ``anthropic.AsyncAnthropic`` (constructed once, injected)."""

    provider = PROVIDER_ANTHROPIC

    def __init__(
        self,
        client: Any,
        *,
        model: str = "claude-opus-5",
        max_tokens: int = 16_000,
        effort: str = "medium",
    ) -> None:
        self._client = client  # anthropic.AsyncAnthropic (or a test double)
        self.model = model
        self._max_tokens = max_tokens
        self._effort = effort

    def _record(
        self,
        calls: list[LlmCallRecord],
        step: tuple[int, dict[str, Any], float],
        *,
        outcome: str,
        raw_output: str | None = None,
        parsed: dict[str, Any] | None = None,
        stop_reason: str | None = None,
        stop_details: dict[str, Any] | None = None,
        error: str | None = None,
        usage: Any = None,
    ) -> None:
        attempt, prompt, started = step
        calls.append(
            LlmCallRecord(
                provider=self.provider,
                model=self.model,
                attempt=attempt,
                prompt=prompt,
                outcome=outcome,
                latency_ms=int((time.monotonic() - started) * 1000),
                raw_output=raw_output,
                parsed=parsed,
                stop_reason=stop_reason,
                stop_details=stop_details,
                error=error,
                input_tokens=getattr(usage, "input_tokens", None),
                output_tokens=getattr(usage, "output_tokens", None),
            )
        )

    async def diagnose(self, request: LlmRequest) -> LlmOutcome:
        allowed = request.allowed_ids
        messages = build_messages(request)
        schema = answer_schema(allowed)
        calls: list[LlmCallRecord] = []
        max_tokens = self._max_tokens
        invalid_retries, budget_retries = 1, 1
        attempt = 0
        while True:
            attempt += 1
            prompt = loggable_prompt(request, max_tokens=max_tokens, effort=self._effort)
            started = time.monotonic()
            step = (attempt, prompt, started)
            try:
                response = await self._client.messages.create(
                    model=self.model,
                    max_tokens=max_tokens,
                    system=SYSTEM_PROMPT,
                    messages=messages,
                    output_config={
                        "format": {"type": "json_schema", "schema": schema},
                        "effort": self._effort,
                    },
                )
            except anthropic.RateLimitError as exc:
                self._record(calls, step, outcome="rate_limited", error=str(exc)[:500])
                raise LlmTemporaryError("LLM rate limited", calls) from exc
            except anthropic.APIStatusError as exc:
                error = f"{exc.status_code}: {str(exc)[:500]}"
                if exc.status_code >= 500:
                    self._record(calls, step, outcome="server_error", error=error)
                    raise LlmTemporaryError("LLM provider error", calls) from exc
                self._record(calls, step, outcome="api_error", error=error)
                return LlmOutcome.unknown("error", self.model, calls)
            except anthropic.APIConnectionError as exc:
                self._record(calls, step, outcome="connection_error", error=str(exc)[:500])
                raise LlmTemporaryError("LLM unreachable", calls) from exc
            except anthropic.AnthropicError as exc:
                self._record(calls, step, outcome="api_error", error=str(exc)[:500])
                return LlmOutcome.unknown("error", self.model, calls)

            usage = getattr(response, "usage", None)
            stop_reason = getattr(response, "stop_reason", None)
            raw = _first_text(response.content)
            if stop_reason == "refusal":
                details = _dump(getattr(response, "stop_details", None))
                self._record(
                    calls,
                    step,
                    outcome="refusal",
                    raw_output=raw,
                    stop_reason=stop_reason,
                    stop_details=details,
                    usage=usage,
                )
                log.warning("llm_refusal", model=self.model, stop_details=details)
                return LlmOutcome.unknown("refusal", self.model, calls)
            if stop_reason == "max_tokens":
                self._record(
                    calls,
                    step,
                    outcome="max_tokens",
                    raw_output=raw,
                    stop_reason=stop_reason,
                    usage=usage,
                )
                if budget_retries > 0:
                    budget_retries -= 1
                    max_tokens *= 2
                    continue
                return LlmOutcome.unknown("invalid", self.model, calls)
            try:
                answer = parse_answer(raw or "", allowed)
            except ValueError as exc:
                self._record(
                    calls,
                    step,
                    outcome="invalid",
                    raw_output=raw,
                    stop_reason=stop_reason,
                    error=str(exc)[:500],
                    usage=usage,
                )
                if invalid_retries > 0:
                    invalid_retries -= 1
                    continue
                return LlmOutcome.unknown("invalid", self.model, calls)
            self._record(
                calls,
                step,
                outcome="ok",
                raw_output=raw,
                parsed=answer.model_dump(mode="json"),
                stop_reason=stop_reason,
                usage=usage,
            )
            return outcome_from_answer(answer, self.model, calls)


# --------------------------------------------------------------------------- stand-ins
class FakeLlmDiagnosisClient:
    """Deterministic stand-in (``DIAGNOSIS_LLM=fake``: tests, CI evaluation, local dev):
    picks the first candidate with ``medium`` confidence; no candidates -> unknown."""

    provider = "fake"
    model = "fake-llm"

    def __init__(self) -> None:
        self.requests: list[LlmRequest] = []

    async def diagnose(self, request: LlmRequest) -> LlmOutcome:
        self.requests.append(request)
        allowed = request.allowed_ids
        choice = allowed[0]
        raw = json.dumps(
            {
                "problem_id": choice,
                "confidence": "medium" if choice != UNKNOWN else "low",
                "reasoning": "Closest reference match (fake LLM).",
                "visible_symptoms": [],
            }
        )
        answer = parse_answer(raw, allowed)
        call = LlmCallRecord(
            provider=self.provider,
            model=self.model,
            attempt=1,
            prompt=loggable_prompt(request, max_tokens=0, effort="none"),
            outcome="ok",
            latency_ms=0,
            raw_output=raw,
            parsed=answer.model_dump(mode="json"),
            stop_reason="end_turn",
        )
        return outcome_from_answer(answer, self.model, [call])


class DisabledLlmClient:
    """``DIAGNOSIS_LLM=off``: no provider configured; every fallback is ``unknown``."""

    provider = "off"
    model = "off"

    async def diagnose(self, request: LlmRequest) -> LlmOutcome:
        return LlmOutcome.unknown("disabled", None)


class LazyClaudeClient:
    """Builds ``anthropic.AsyncAnthropic()`` on the first fallback (credentials from the
    environment: ``ANTHROPIC_API_KEY`` via Secret Manager), so an API or worker without a key
    still starts; then delegates to one ``ClaudeDiagnosisClient`` for the process."""

    provider = PROVIDER_ANTHROPIC

    def __init__(self, *, model: str, max_tokens: int, effort: str) -> None:
        self.model = model
        self._max_tokens = max_tokens
        self._effort = effort
        self._delegate: ClaudeDiagnosisClient | None = None

    async def diagnose(self, request: LlmRequest) -> LlmOutcome:  # pragma: no cover - network
        if self._delegate is None:
            self._delegate = ClaudeDiagnosisClient(
                anthropic.AsyncAnthropic(),
                model=self.model,
                max_tokens=self._max_tokens,
                effort=self._effort,
            )
        return await self._delegate.diagnose(request)


__all__ = [
    "NOT_A_PLANT_MARK",
    "SYSTEM_PROMPT",
    "UNKNOWN",
    "ClaudeDiagnosisClient",
    "DisabledLlmClient",
    "FakeLlmDiagnosisClient",
    "LazyClaudeClient",
    "LlmAnswer",
    "LlmCallRecord",
    "LlmCandidate",
    "LlmDiagnosisClient",
    "LlmImage",
    "LlmOutcome",
    "LlmRequest",
    "LlmTemporaryError",
    "answer_schema",
    "build_messages",
    "context_text",
    "loggable_prompt",
    "parse_answer",
]
