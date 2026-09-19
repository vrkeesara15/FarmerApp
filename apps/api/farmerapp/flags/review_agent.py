"""VA-004 review agent: a three-line plain summary and a suggested action for every new flag,
written by an LLM from the flag's evidence bundle only (SPEC 6.1 "Review agent").

**Only the bundle** (``build_bundle``): the rule id and title, severity, the subject type and
id, the evidence records (``{type, id}``), the metrics, and the *number* of map points,
polygons and photos. Nothing else is read for the prompt — no records are looked up, no
names, no coordinates, no photos, and not the flag title (a rule may put a name in it,
VA-F02). SEC-027: metrics are scrubbed (keys that carry names, phones, addresses dropped;
phone-like digit runs masked to their last four digits; record ids left intact).

**Citations** (``validate_answer``): the model returns ``summary_lines`` (exactly three),
``suggested_action`` and ``cited_record_ids``. Every cited id must be an id of the bundle
(its records, the subject, ids inside the metrics) and every id-shaped string in the text
must be one too — "summary contains only referenced ids" (VA-004 acceptance). An answer
that breaks this, is not valid JSON or has the wrong shape is rejected and the call retried
once with the reason; a second failure stores ``invalid``.

**Claude** (``ClaudeFlagSummaryClient``, official ``anthropic`` SDK, ``AsyncAnthropic``):
model from ``FLAG_SUMMARY_LLM_MODEL`` (default ``claude-opus-5``), structured output through
``output_config={"format": {"type": "json_schema", "schema": ...}, "effort": "low"}``
(``additionalProperties: false``; array lengths are checked client-side — structured
outputs do not enforce array constraints). ``stop_reason`` is checked before the content is
read: ``refusal`` -> no summary (status ``refused``, ``stop_details`` logged); ``max_tokens``
counts as an invalid answer. Rate limits, 5xx and connection errors raise
``SummaryTemporaryError`` (the worker nacks, the job retries on its next run).

Every attempt is written to the append-only ``llm_call_log`` (``flag_id`` set, prompt and
raw output, kept one year; SEC-027). Summaries run **after** the flag is committed, in the
worker: the rules job and the worker's event path summarise the flags they just raised, the
``flag.created`` worker topic summarises one flag, and ``python -m farmerapp.jobs
flags-summarise`` sweeps flags raised on the API path (inline / in-process event rules).
The console shows the result labelled "Automated summary — verify evidence"
(``SUMMARY_LABEL_KEY``).
"""

from __future__ import annotations

import contextlib
import json
import re
import time
import uuid
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

import anthropic
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.llm import PROVIDER_ANTHROPIC, LlmCallRecord
from farmerapp.diagnosis.models import LlmCallLog
from farmerapp.flags.models import Flag, FlagSummary, SummaryStatus
from farmerapp.logging import get_logger
from farmerapp.rules.loader import RuleSet, get_rule_set
from farmerapp.settings import Settings, get_settings
from farmerapp.worker.messages import PubSubMessage

log = get_logger("farmerapp.flags.review_agent")

#: i18n key of the console label "Automated summary — verify evidence".
SUMMARY_LABEL_KEY = "flag.summary.automated_label"
#: A summary is attempted at most this many times (temporary errors included).
MAX_ATTEMPTS = 3
FINAL_STATUSES = frozenset(
    {SummaryStatus.DONE, SummaryStatus.REFUSED, SummaryStatus.INVALID, SummaryStatus.DISABLED}
)
LLM_LOG_RETENTION_DAYS = 365

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]

SYSTEM_PROMPT = (
    "You help a reviewer at an Indian agri-input company understand one automated "
    "validation flag. A flag is a question about data quality, never a verdict about a "
    "person. You receive the flag's evidence bundle as JSON and nothing else.\n\n"
    "Write exactly three short plain-language lines (at most 30 words each) that say what "
    "the rule noticed and what in the evidence supports it, then one suggested next step "
    "for the reviewer (for example: which record to open, whom to call, what to compare). "
    "Use only facts in the bundle; do not guess causes, intentions or facts that are not "
    "there, and say so when the evidence is thin. Refer to records by their id exactly as "
    "written in the bundle and list every id you refer to in cited_record_ids. Cite only "
    "ids that appear in the bundle. Never invent ids, names or numbers."
)

_UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
_PHONE_RE = re.compile(r"\+?\d[\d \-]{7,}\d")
_PII_KEYS = frozenset(
    {
        "name",
        "names",
        "phone",
        "phones",
        "phone_number",
        "mobile",
        "address",
        "landmark",
        "email",
        "otp",
        "code",
        "device",
        "device_id",
    }
)


# --------------------------------------------------------------------------- the bundle
def _mask_digits(text: str) -> str:
    def mask(match: re.Match[str]) -> str:
        digits = re.sub(r"\D", "", match.group(0))
        if len(digits) < 10:  # dates (2026-09-18) and short numbers are not phones
            return match.group(0)
        return "******" + digits[-4:]

    return _PHONE_RE.sub(mask, text)


def mask_text(text: str) -> str:
    """Mask phone-like digit runs, leaving record ids (UUIDs) untouched (SEC-027)."""
    out: list[str] = []
    last = 0
    for match in _UUID_RE.finditer(text):
        out.append(_mask_digits(text[last : match.start()]))
        out.append(match.group(0))
        last = match.end()
    out.append(_mask_digits(text[last:]))
    return "".join(out)


def _pii_key(key: str) -> bool:
    lowered = key.lower()
    if lowered.endswith("_last4"):  # already masked to four digits
        return False
    return (
        lowered in _PII_KEYS
        or lowered.endswith("_name")
        or lowered.endswith("_names")
        or "phone" in lowered
    )


def scrub(value: Any) -> Any:
    """Drop PII keys and mask phone numbers anywhere in a JSON value."""
    if isinstance(value, dict):
        return {str(k): scrub(v) for k, v in value.items() if not _pii_key(str(k))}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, str):
        return mask_text(value)
    return value


def _ids_in(value: Any) -> set[str]:
    if isinstance(value, dict):
        return set().union(*(_ids_in(v) for v in value.values())) if value else set()
    if isinstance(value, list):
        return set().union(*(_ids_in(v) for v in value)) if value else set()
    if isinstance(value, str):
        return {m.group(0).lower() for m in _UUID_RE.finditer(value)}
    return set()


@dataclass(frozen=True)
class EvidenceBundle:
    flag_id: uuid.UUID
    tenant_id: uuid.UUID
    payload: dict[str, Any]
    allowed_ids: frozenset[str]

    def text(self) -> str:
        return (
            "Evidence bundle of one validation flag (JSON):\n"
            + json.dumps(self.payload, sort_keys=True, indent=1, ensure_ascii=False)
            + "\n\nRecord ids you may cite: "
            + ", ".join(sorted(self.allowed_ids))
        )


def build_bundle(flag: Flag, *, rule_title: str | None) -> EvidenceBundle:
    """The only data the review agent sees (VA-004): no lookups, no other records."""
    raw = flag.evidence if isinstance(flag.evidence, dict) else {}
    records = [
        {"type": str(r.get("type", "")), "id": str(r.get("id", ""))}
        for r in raw.get("records") or []
        if isinstance(r, dict)
    ]
    geo = raw.get("map") or {}
    metrics = scrub(dict(raw.get("metrics") or {}))
    payload: dict[str, Any] = {
        "rule": {"id": flag.rule_id, "version": flag.rule_version, "title": rule_title},
        "severity": flag.severity,
        "subject": {"type": flag.subject_type, "id": str(flag.subject_id)},
        "raised_at": flag.created_at.isoformat() if flag.created_at else None,
        "records": records,
        "metrics": metrics,
        "map": {
            "points": len(geo.get("points") or []),
            "polygons": len(geo.get("polygons") or []),
        },
        "photos": len(raw.get("photos") or []),
    }
    allowed = {r["id"].lower() for r in records if r["id"]}
    allowed.add(str(flag.subject_id).lower())
    allowed |= _ids_in(metrics)
    return EvidenceBundle(
        flag_id=flag.id, tenant_id=flag.tenant_id, payload=payload, allowed_ids=frozenset(allowed)
    )


# --------------------------------------------------------------------------- the answer
class SummaryAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    summary_lines: list[str] = Field(min_length=3, max_length=3)
    suggested_action: str = Field(min_length=1, max_length=600)
    cited_record_ids: list[str] = Field(min_length=1, max_length=50)

    @field_validator("summary_lines")
    @classmethod
    def _lines(cls, lines: list[str]) -> list[str]:
        cleaned = [line.strip() for line in lines]
        if any(not line or len(line) > 400 for line in cleaned):
            raise ValueError("each summary line must be 1-400 characters")
        return cleaned


def answer_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "properties": {
            "summary_lines": {"type": "array", "items": {"type": "string"}},
            "suggested_action": {"type": "string"},
            "cited_record_ids": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["summary_lines", "suggested_action", "cited_record_ids"],
        "additionalProperties": False,
    }


def validate_answer(raw: str, bundle: EvidenceBundle) -> SummaryAnswer:
    """JSON + shape + citations; ``ValueError`` names what is wrong (fed to the retry)."""
    try:
        answer = SummaryAnswer.model_validate(json.loads(raw))
    except (json.JSONDecodeError, ValidationError) as exc:
        raise ValueError(f"the answer does not match the schema: {exc}") from exc
    cited = {c.strip().lower() for c in answer.cited_record_ids}
    outside = sorted(cited - bundle.allowed_ids)
    if outside:
        raise ValueError(f"cited ids that are not in the evidence bundle: {outside}")
    in_text = _ids_in(answer.summary_lines) | _ids_in(answer.suggested_action)
    unknown = sorted(in_text - bundle.allowed_ids)
    if unknown:
        raise ValueError(f"the text mentions ids that are not in the evidence bundle: {unknown}")
    return answer


@dataclass
class SummaryOutcome:
    status: SummaryStatus
    model: str | None
    answer: SummaryAnswer | None = None
    error: str | None = None
    calls: list[LlmCallRecord] = field(default_factory=list)


class SummaryTemporaryError(RuntimeError):
    """Rate limited / provider 5xx / unreachable: try the summary again later."""

    def __init__(self, message: str, calls: list[LlmCallRecord]) -> None:
        super().__init__(message)
        self.calls = calls


class FlagSummaryClient(Protocol):
    provider: str
    model: str

    async def summarise(self, bundle: EvidenceBundle) -> SummaryOutcome: ...


def loggable_prompt(
    bundle: EvidenceBundle, *, max_tokens: int, effort: str, note: str | None
) -> dict[str, Any]:
    return {
        "purpose": "flag_summary",
        "flag_id": str(bundle.flag_id),
        "system": SYSTEM_PROMPT,
        "text": bundle.text(),
        "retry_note": note,
        "schema": answer_schema(),
        "max_tokens": max_tokens,
        "effort": effort,
    }


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


class ClaudeFlagSummaryClient:
    """``FlagSummaryClient`` over ``anthropic.AsyncAnthropic`` (or a test double with the same
    ``messages.create``)."""

    provider = PROVIDER_ANTHROPIC

    def __init__(
        self,
        client: Any,
        *,
        model: str = "claude-opus-5",
        max_tokens: int = 4_000,
        effort: str = "low",
    ) -> None:
        self._client = client
        self.model = model
        self._max_tokens = max_tokens
        self._effort = effort

    def _record(
        self,
        calls: list[LlmCallRecord],
        attempt: int,
        prompt: dict[str, Any],
        started: float,
        *,
        outcome: str,
        response: Any = None,
        raw_output: str | None = None,
        parsed: dict[str, Any] | None = None,
        error: str | None = None,
    ) -> None:
        usage = getattr(response, "usage", None)
        stop_reason = getattr(response, "stop_reason", None)
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
                stop_details=_dump(getattr(response, "stop_details", None))
                if stop_reason == "refusal"
                else None,
                error=error,
                input_tokens=getattr(usage, "input_tokens", None),
                output_tokens=getattr(usage, "output_tokens", None),
            )
        )

    async def summarise(self, bundle: EvidenceBundle) -> SummaryOutcome:
        calls: list[LlmCallRecord] = []
        note: str | None = None
        for attempt in (1, 2):
            text = bundle.text()
            if note:
                text += (
                    f"\n\nYour previous answer was rejected: {note}. Answer again, citing only "
                    "ids from the list above."
                )
            prompt = loggable_prompt(
                bundle, max_tokens=self._max_tokens, effort=self._effort, note=note
            )
            started = time.monotonic()
            try:
                response = await self._client.messages.create(
                    model=self.model,
                    max_tokens=self._max_tokens,
                    system=SYSTEM_PROMPT,
                    messages=[{"role": "user", "content": [{"type": "text", "text": text}]}],
                    output_config={
                        "format": {"type": "json_schema", "schema": answer_schema()},
                        "effort": self._effort,
                    },
                )
            except anthropic.RateLimitError as exc:
                self._record(
                    calls, attempt, prompt, started, outcome="rate_limited", error=str(exc)[:500]
                )
                raise SummaryTemporaryError("LLM rate limited", calls) from exc
            except anthropic.APIStatusError as exc:
                error = f"{exc.status_code}: {str(exc)[:500]}"
                if exc.status_code >= 500:
                    self._record(
                        calls, attempt, prompt, started, outcome="server_error", error=error
                    )
                    raise SummaryTemporaryError("LLM provider error", calls) from exc
                self._record(calls, attempt, prompt, started, outcome="api_error", error=error)
                return SummaryOutcome(SummaryStatus.ERROR, self.model, error=error, calls=calls)
            except anthropic.APIConnectionError as exc:
                self._record(
                    calls,
                    attempt,
                    prompt,
                    started,
                    outcome="connection_error",
                    error=str(exc)[:500],
                )
                raise SummaryTemporaryError("LLM unreachable", calls) from exc
            except anthropic.AnthropicError as exc:
                self._record(
                    calls, attempt, prompt, started, outcome="api_error", error=str(exc)[:500]
                )
                return SummaryOutcome(
                    SummaryStatus.ERROR, self.model, error=str(exc)[:500], calls=calls
                )

            stop_reason = getattr(response, "stop_reason", None)
            if stop_reason == "refusal":  # checked before the content is read
                self._record(calls, attempt, prompt, started, outcome="refusal", response=response)
                log.warning(
                    "flag_summary_refused",
                    flag_id=str(bundle.flag_id),
                    model=self.model,
                    stop_details=calls[-1].stop_details,
                )
                return SummaryOutcome(SummaryStatus.REFUSED, self.model, calls=calls)
            raw = _first_text(response.content)
            try:
                if stop_reason == "max_tokens":
                    raise ValueError("the answer was cut off (max_tokens)")
                answer = validate_answer(raw or "", bundle)
            except ValueError as exc:
                note = str(exc)[:500]
                self._record(
                    calls,
                    attempt,
                    prompt,
                    started,
                    outcome="max_tokens" if stop_reason == "max_tokens" else "invalid",
                    response=response,
                    raw_output=raw,
                    error=note,
                )
                log.warning(
                    "flag_summary_rejected",
                    flag_id=str(bundle.flag_id),
                    attempt=attempt,
                    reason=note,
                )
                continue
            self._record(
                calls,
                attempt,
                prompt,
                started,
                outcome="ok",
                response=response,
                raw_output=raw,
                parsed=answer.model_dump(mode="json"),
            )
            return SummaryOutcome(SummaryStatus.DONE, self.model, answer=answer, calls=calls)
        return SummaryOutcome(SummaryStatus.INVALID, self.model, error=note, calls=calls)


class FakeFlagSummaryClient:
    """``FLAG_SUMMARY_LLM=fake`` (local dev, demos): a deterministic summary of the bundle."""

    provider = "fake"
    model = "fake-llm"

    def __init__(self) -> None:
        self.bundles: list[EvidenceBundle] = []

    async def summarise(self, bundle: EvidenceBundle) -> SummaryOutcome:
        self.bundles.append(bundle)
        records = bundle.payload["records"] or [bundle.payload["subject"]]
        first = records[0]
        metrics = bundle.payload["metrics"]
        reasons = metrics.get("reasons") or [metrics.get("reason") or "see metrics"]
        answer = SummaryAnswer(
            summary_lines=[
                f"Rule {bundle.payload['rule']['id']} raised a {bundle.payload['severity']} "
                f"flag about a {bundle.payload['subject']['type']}.",
                "Reason: " + ", ".join(str(r).replace("_", " ") for r in reasons) + ".",
                f"The evidence cites {len(bundle.payload['records'])} record(s).",
            ],
            suggested_action=f"Open {first['type']} {first['id']} and check the metrics.",
            cited_record_ids=[first["id"]],
        )
        raw = answer.model_dump_json()
        call = LlmCallRecord(
            provider=self.provider,
            model=self.model,
            attempt=1,
            prompt=loggable_prompt(bundle, max_tokens=0, effort="none", note=None),
            outcome="ok",
            latency_ms=0,
            raw_output=raw,
            parsed=answer.model_dump(mode="json"),
            stop_reason="end_turn",
        )
        return SummaryOutcome(SummaryStatus.DONE, self.model, answer=answer, calls=[call])


class LazyClaudeFlagSummaryClient:
    """Builds ``anthropic.AsyncAnthropic()`` on first use (``ANTHROPIC_API_KEY`` from Secret
    Manager), so a worker or job without a key still starts."""

    provider = PROVIDER_ANTHROPIC

    def __init__(self, *, model: str, max_tokens: int) -> None:
        self.model = model
        self._max_tokens = max_tokens
        self._delegate: ClaudeFlagSummaryClient | None = None

    async def summarise(self, bundle: EvidenceBundle) -> SummaryOutcome:  # pragma: no cover
        if self._delegate is None:
            self._delegate = ClaudeFlagSummaryClient(
                anthropic.AsyncAnthropic(), model=self.model, max_tokens=self._max_tokens
            )
        return await self._delegate.summarise(bundle)


_CLIENT: FlagSummaryClient | None = None


def build_client(settings: Settings | None = None) -> FlagSummaryClient | None:
    """The process's summary client from ``FLAG_SUMMARY_LLM`` (``None`` when off)."""
    global _CLIENT
    settings = settings or get_settings()
    if settings.flag_summary_llm == "off":
        return None
    if settings.flag_summary_llm == "fake":
        return FakeFlagSummaryClient()
    if _CLIENT is None or _CLIENT.model != settings.flag_summary_llm_model:
        _CLIENT = LazyClaudeFlagSummaryClient(
            model=settings.flag_summary_llm_model, max_tokens=settings.flag_summary_llm_max_tokens
        )
    return _CLIENT


# --------------------------------------------------------------------------- persistence
def _log_calls(
    session: AsyncSession, flag: Flag, calls: Iterable[LlmCallRecord], now: datetime
) -> None:
    for call in calls:
        session.add(
            LlmCallLog(
                tenant_id=flag.tenant_id,
                created_at=now,
                flag_id=flag.id,
                diagnosis_id=None,
                provider=call.provider,
                model=call.model[:64],
                attempt=call.attempt,
                prompt=call.prompt,
                raw_output=call.raw_output,
                parsed=call.parsed,
                outcome=call.outcome[:16],
                stop_reason=call.stop_reason,
                stop_details=call.stop_details,
                error=call.error,
                input_tokens=call.input_tokens,
                output_tokens=call.output_tokens,
                latency_ms=call.latency_ms,
                retain_until=(now + timedelta(days=LLM_LOG_RETENTION_DAYS)).date(),
            )
        )


async def summarise_flag(
    session: AsyncSession,
    flag_id: uuid.UUID,
    client: FlagSummaryClient,
    *,
    rule_set: RuleSet | None = None,
    now: datetime | None = None,
) -> FlagSummary | None:
    """Summarise one flag (idempotent: a final summary is never redone). Raises
    ``SummaryTemporaryError`` after recording the attempt when the provider is unavailable."""
    now = now or datetime.now(UTC)
    flag = await session.get(Flag, flag_id)
    if flag is None or flag.deleted_at is not None:
        return None
    row = (
        await session.execute(select(FlagSummary).where(FlagSummary.flag_id == flag.id))
    ).scalar_one_or_none()
    if row is not None and (
        SummaryStatus(row.status) in FINAL_STATUSES or row.attempts >= MAX_ATTEMPTS
    ):
        return row
    if row is None:
        row = FlagSummary(
            tenant_id=flag.tenant_id,
            flag_id=flag.id,
            status=SummaryStatus.PENDING.value,
            attempts=0,
            cited_record_ids=[],
        )
        session.add(row)
    rules = rule_set or get_rule_set()
    title = rules.rules[flag.rule_id].title if flag.rule_id in rules.rules else None
    bundle = build_bundle(flag, rule_title=title)
    row.attempts += 1
    row.model = client.model
    try:
        outcome = await client.summarise(bundle)
    except SummaryTemporaryError as exc:
        _log_calls(session, flag, exc.calls, now)
        row.status = SummaryStatus.PENDING.value
        row.error = str(exc)
        await session.flush()
        log.warning("flag_summary_deferred", flag_id=str(flag.id), attempts=row.attempts)
        raise
    _log_calls(session, flag, outcome.calls, now)
    row.status = outcome.status.value
    row.error = outcome.error
    if outcome.answer is not None:
        row.summary_lines = list(outcome.answer.summary_lines)
        row.suggested_action = outcome.answer.suggested_action
        row.cited_record_ids = sorted({c.strip().lower() for c in outcome.answer.cited_record_ids})
        row.completed_at = now
    elif outcome.status in FINAL_STATUSES:
        row.completed_at = now
    await session.flush()
    log.info(
        "flag_summary",
        flag_id=str(flag.id),
        rule_id=flag.rule_id,
        status=row.status,
        attempts=row.attempts,
        calls=len(outcome.calls),
    )
    return row


@dataclass
class SummaryReport:
    tenant_id: uuid.UUID
    done: int = 0
    other: int = 0
    deferred: int = 0


async def summarise_flags(
    tenant_id: uuid.UUID,
    flag_ids: Iterable[uuid.UUID],
    *,
    client: FlagSummaryClient | None = None,
    session_provider: SessionProvider = job_session,
    rule_set: RuleSet | None = None,
    now: datetime | None = None,
) -> SummaryReport:
    """Summarise committed flags, one transaction each (an LLM call never holds the rules
    transaction open). A temporary provider error defers the flag to the next sweep."""
    report = SummaryReport(tenant_id=tenant_id)
    client = client if client is not None else build_client()
    if client is None:
        return report
    with audit.actor_scope(audit.system_actor(tenant_id)):
        for flag_id in flag_ids:
            async with session_provider(tenant_id) as session:
                try:
                    row = await summarise_flag(session, flag_id, client, rule_set=rule_set, now=now)
                except SummaryTemporaryError:  # the attempt is logged and committed
                    report.deferred += 1
                    continue
            if row is not None and row.status == SummaryStatus.DONE.value:
                report.done += 1
            else:
                report.other += 1
    return report


async def pending_flag_ids(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    now: datetime,
    max_age_days: int = 7,
    limit: int = 200,
) -> list[uuid.UUID]:
    """Recent flags without a final summary (the sweep's work list)."""
    finals = [s.value for s in FINAL_STATUSES]
    done = select(FlagSummary.flag_id).where(
        FlagSummary.tenant_id == tenant_id,
        (FlagSummary.status.in_(finals)) | (FlagSummary.attempts >= MAX_ATTEMPTS),
    )
    rows = await session.scalars(
        select(Flag.id)
        .where(
            Flag.tenant_id == tenant_id,
            Flag.deleted_at.is_(None),
            Flag.created_at >= now - timedelta(days=max_age_days),
            Flag.id.not_in(done),
        )
        .order_by(Flag.created_at, Flag.id)
        .limit(limit)
    )
    return list(rows)


async def summarise_pending(
    tenant_ids: Iterable[uuid.UUID],
    *,
    client: FlagSummaryClient | None = None,
    session_provider: SessionProvider = job_session,
    now: datetime | None = None,
    max_age_days: int = 7,
    limit: int = 200,
) -> list[SummaryReport]:
    """``python -m farmerapp.jobs flags-summarise``: every recent flag without a summary."""
    now = now or datetime.now(UTC)
    client = client if client is not None else build_client()
    reports: list[SummaryReport] = []
    for tenant_id in tenant_ids:
        if client is None:
            reports.append(SummaryReport(tenant_id=tenant_id))
            continue
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with session_provider(tenant_id) as session:
                ids = await pending_flag_ids(
                    session, tenant_id, now=now, max_age_days=max_age_days, limit=limit
                )
        reports.append(
            await summarise_flags(
                tenant_id, ids, client=client, session_provider=session_provider, now=now
            )
        )
    return reports


async def handle_flag_created_message(
    message: PubSubMessage,
    *,
    client: FlagSummaryClient | None = None,
    session_provider: SessionProvider = job_session,
) -> SummaryReport | None:
    """Worker topic ``flag.created`` (payload ``tenant_id`` + ``flag_id``). A malformed
    payload is logged and acknowledged; a temporary provider error re-raises (nack)."""
    client = client if client is not None else build_client()
    if client is None:
        return None
    try:
        body = message.json_body()
        tenant_id = uuid.UUID(str(body["tenant_id"]))
        flag_id = uuid.UUID(str(body["flag_id"]))
    except (KeyError, ValueError):
        log.error("flag_created_malformed", message_id=message.message_id)
        return None
    report = SummaryReport(tenant_id=tenant_id)
    deferred: SummaryTemporaryError | None = None
    with audit.actor_scope(audit.system_actor(tenant_id)):
        async with session_provider(tenant_id) as session:
            try:
                row = await summarise_flag(session, flag_id, client)
            except SummaryTemporaryError as exc:  # commit the logged attempt, then nack
                deferred, row = exc, None
    if deferred is not None:
        raise deferred
    if row is not None and row.status == SummaryStatus.DONE.value:
        report.done += 1
    return report


__all__ = [
    "MAX_ATTEMPTS",
    "SUMMARY_LABEL_KEY",
    "SYSTEM_PROMPT",
    "ClaudeFlagSummaryClient",
    "EvidenceBundle",
    "FakeFlagSummaryClient",
    "FlagSummaryClient",
    "SummaryAnswer",
    "SummaryOutcome",
    "SummaryReport",
    "SummaryTemporaryError",
    "answer_schema",
    "build_bundle",
    "build_client",
    "handle_flag_created_message",
    "mask_text",
    "pending_flag_ids",
    "scrub",
    "summarise_flag",
    "summarise_flags",
    "summarise_pending",
    "validate_answer",
]
