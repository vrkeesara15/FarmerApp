"""AN-016: the question -> SQL step, behind a provider-neutral protocol.

``NlqClient.write_sql(request) -> NlqOutcome``. The prompt carries **only**:

* the question the owner typed;
* :func:`farmerapp.nlq.views.schema_text` — view names, grains and column meanings;
* the caller's role and scope in words ("cluster head, one cluster"), never an id;
* today's date in IST, so "last week" means something.

It never carries a row, a name, a phone, a coordinate or a tenant id, and it is run through
the shared SEC-027 guard (:func:`farmerapp.pii.llm_guard.guard_prompt`, with the request's
fields pinned by ``NLQ_PROMPT_FIELDS``) before the call is made. The rows the query returns
go to the caller and never back to a model — which is why the plain-language answer is the
model's own ``explanation`` of what it computed, completed by the real row count rather than
by a second call that would have to see the data.

``ClaudeNlqClient`` mirrors the DX-004 client (``farmerapp.diagnosis.llm``): the Anthropic
Messages API, ``claude-opus-5`` by default, structured output through
``output_config={"format": {"type": "json_schema", "schema": …}}`` with
``additionalProperties: false`` and every field required. The model answers either with SQL
or with a refusal:

``{"sql": "SELECT …", "explanation": "…", "refusal": null}``
``{"sql": null, "explanation": null, "refusal": "I only have officer, store, farmer,
referral and mandi-price views."}``

A refusal, a provider error, a malformed answer and SQL the validator rejects all end the
same way for the caller: "I could not answer that" plus the reason.
"""

from __future__ import annotations

import dataclasses
import json
import time
from dataclasses import dataclass, field
from datetime import date
from functools import partial
from typing import Any, Literal, Protocol

import anthropic
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from farmerapp.logging import get_logger
from farmerapp.nlq.views import VIEW_NAMES, schema_text
from farmerapp.pii.llm_guard import NLQ_PROMPT_FIELDS, PromptPiiError, guard_prompt

log = get_logger("farmerapp.nlq.llm")

PROVIDER_ANTHROPIC = "anthropic"

SYSTEM_PROMPT = (
    "You turn a business question from a company owner into ONE read-only PostgreSQL "
    "SELECT statement over a small set of authorised views, and explain in one or two "
    "plain sentences what that statement computes.\n\n"
    "Hard rules:\n"
    "1. Exactly one SELECT statement. Never INSERT, UPDATE, DELETE, COPY, CREATE, ALTER, "
    "DROP, GRANT, SET or any other statement, and never two statements.\n"
    "2. Read only the views listed below. Never a table, never another view, never "
    "pg_catalog or information_schema, never a schema prefix.\n"
    "3. Never select tenant_id: every view is already filtered to the caller's company and "
    "to what their role may see. Do not add a tenant, cluster or store filter yourself.\n"
    "4. Use only ordinary SQL: aggregates, CASE, COALESCE, date_trunc, EXTRACT, arithmetic, "
    "window functions. No server functions (pg_*, dblink, current_setting, set_config, "
    "lo_*), no casts to regclass.\n"
    "5. Always add an ORDER BY that makes the answer readable, and a LIMIT.\n"
    "6. Money columns end in _paise and are integer paise; divide by 100 for rupees.\n\n"
    "If the question cannot be answered from these views — because the data is not there, "
    "because it asks for something personal about a farmer, or because it asks you to do "
    'anything other than read — set "refusal" to one short sentence saying why, and leave '
    '"sql" and "explanation" null. Never guess a column that is not listed.'
)


@dataclass(frozen=True)
class NlqRequest:
    """Everything that goes into the prompt. Pinned by ``NLQ_PROMPT_FIELDS`` (SEC-027)."""

    question: str
    #: The view catalogue (names, grains, columns) — schema only, never data.
    schema: str
    #: The caller's role, in words: "owner", "director", "cluster head".
    role: str
    #: What the role may see, in words: "the whole company" / "one cluster" — never an id.
    scope: str
    #: Today in IST, so relative dates ("last week") resolve.
    today: date

    @staticmethod
    def build(*, question: str, role: str, scope: str, today: date) -> NlqRequest:
        return NlqRequest(
            question=question, schema=schema_text(), role=role, scope=scope, today=today
        )


class NlqAnswer(BaseModel):
    """The structured output the model must return."""

    model_config = ConfigDict(extra="forbid")

    sql: str | None = Field(default=None, max_length=8_000)
    explanation: str | None = Field(default=None, max_length=2_000)
    refusal: str | None = Field(default=None, max_length=500)


@dataclass
class NlqCallRecord:
    """One attempt, written to ``llm_call_log`` by the service (SEC-027)."""

    provider: str
    model: str
    attempt: int
    prompt: dict[str, Any]
    outcome: str
    latency_ms: int
    raw_output: str | None = None
    parsed: dict[str, Any] | None = None
    stop_reason: str | None = None
    stop_details: dict[str, Any] | None = None
    error: str | None = None
    input_tokens: int | None = None
    output_tokens: int | None = None


@dataclass(frozen=True)
class NlqOutcome:
    status: Literal["ok", "refused", "error", "disabled"]
    sql: str | None
    explanation: str | None
    refusal: str | None
    model: str | None
    calls: tuple[NlqCallRecord, ...] = field(default=())

    @staticmethod
    def refused(
        reason: str, model: str | None, calls: list[NlqCallRecord] | None = None
    ) -> NlqOutcome:
        return NlqOutcome("refused", None, None, reason, model, tuple(calls or ()))

    @staticmethod
    def failed(
        reason: str, model: str | None, calls: list[NlqCallRecord] | None = None
    ) -> NlqOutcome:
        return NlqOutcome("error", None, None, reason, model, tuple(calls or ()))


class NlqTemporaryError(RuntimeError):
    """A retryable provider condition (rate limit, 5xx, connection)."""

    def __init__(self, message: str, calls: list[NlqCallRecord]) -> None:
        self.calls = calls
        super().__init__(message)


class NlqClient(Protocol):
    provider: str
    model: str

    async def write_sql(self, request: NlqRequest) -> NlqOutcome: ...


# --------------------------------------------------------------------------- prompt
def question_text(request: NlqRequest) -> str:
    return (
        f"Today is {request.today.isoformat()} (IST).\n"
        f"The person asking is a {request.role} and may see {request.scope}.\n\n"
        f"Authorised views:\n\n{request.schema}\n\n"
        f"Question: {request.question}"
    )


def guard_request(request: NlqRequest) -> None:
    """SEC-027: the prompt's shape is pinned, and its text carries no personal data."""
    fields = {f.name for f in dataclasses.fields(request)}
    if fields != set(NLQ_PROMPT_FIELDS):
        raise PromptPiiError(
            "analytics.ask",
            [f"prompt fields changed: {sorted(fields ^ set(NLQ_PROMPT_FIELDS))}"],
        )
    guard_prompt(
        {"question": request.question, "role": request.role, "scope": request.scope},
        where="analytics.ask",
    )


def build_messages(request: NlqRequest) -> list[dict[str, Any]]:
    guard_request(request)
    return [{"role": "user", "content": [{"type": "text", "text": question_text(request)}]}]


def loggable_prompt(request: NlqRequest, *, max_tokens: int) -> dict[str, Any]:
    """What goes into ``llm_call_log.prompt``: the question and the settings, not the schema
    blob (it is a constant of the deployed version and would bloat every row)."""
    guard_request(request)
    return {
        "system": SYSTEM_PROMPT,
        "question": request.question,
        "role": request.role,
        "scope": request.scope,
        "today": request.today.isoformat(),
        "views": sorted(VIEW_NAMES),
        "max_tokens": max_tokens,
    }


def answer_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["sql", "explanation", "refusal"],
        "properties": {
            "sql": {
                "type": ["string", "null"],
                "description": "One read-only SELECT over the authorised views, or null.",
            },
            "explanation": {
                "type": ["string", "null"],
                "description": "One or two plain sentences describing what the SELECT "
                "computes, in the language of the question.",
            },
            "refusal": {
                "type": ["string", "null"],
                "description": "One short sentence when the question cannot be answered.",
            },
        },
    }


def parse_answer(raw: str) -> NlqAnswer:
    try:
        payload = json.loads(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError("the model did not return JSON") from exc
    try:
        answer = NlqAnswer.model_validate(payload)
    except ValidationError as exc:
        raise ValueError("the model's answer did not match the schema") from exc
    if not answer.sql and not answer.refusal:
        raise ValueError("the model returned neither SQL nor a refusal")
    return answer


def _first_text(content: Any) -> str | None:
    for block in content or []:
        text = getattr(block, "text", None)
        if text:
            return str(text)
    return None


def _dump(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if hasattr(value, "model_dump"):
        return dict(value.model_dump(mode="json"))
    return {"value": str(value)}


# --------------------------------------------------------------------------- Claude
class ClaudeNlqClient:
    """``NlqClient`` over ``anthropic.AsyncAnthropic`` (built once, injected)."""

    provider = PROVIDER_ANTHROPIC

    def __init__(self, client: Any, *, model: str = "claude-opus-5", max_tokens: int = 4_000):
        self._client = client
        self.model = model
        self._max_tokens = max_tokens

    def _record(
        self,
        calls: list[NlqCallRecord],
        step: tuple[int, dict[str, Any], float],
        outcome: str,
        **kw: Any,
    ) -> None:
        attempt, prompt, started = step
        usage = kw.pop("usage", None)
        calls.append(
            NlqCallRecord(
                provider=self.provider,
                model=self.model,
                attempt=attempt,
                prompt=prompt,
                outcome=outcome,
                latency_ms=int((time.monotonic() - started) * 1000),
                input_tokens=getattr(usage, "input_tokens", None),
                output_tokens=getattr(usage, "output_tokens", None),
                **kw,
            )
        )

    async def write_sql(self, request: NlqRequest) -> NlqOutcome:
        messages = build_messages(request)
        schema = answer_schema()
        calls: list[NlqCallRecord] = []
        max_tokens = self._max_tokens
        retries = 1
        attempt = 0
        while True:
            attempt += 1
            step = (attempt, loggable_prompt(request, max_tokens=max_tokens), time.monotonic())
            record = partial(self._record, calls, step)
            try:
                response = await self._client.messages.create(
                    model=self.model,
                    max_tokens=max_tokens,
                    system=SYSTEM_PROMPT,
                    messages=messages,
                    output_config={"format": {"type": "json_schema", "schema": schema}},
                )
            except anthropic.RateLimitError as exc:
                record("rate_limited", error=str(exc)[:500])
                raise NlqTemporaryError("rate limited", calls) from exc
            except anthropic.APIStatusError as exc:
                error = f"{exc.status_code}: {str(exc)[:500]}"
                if exc.status_code >= 500:
                    record("server_error", error=error)
                    raise NlqTemporaryError("provider error", calls) from exc
                record("api_error", error=error)
                return NlqOutcome.failed("the assistant is unavailable", self.model, calls)
            except anthropic.APIConnectionError as exc:
                record("connection_error", error=str(exc)[:500])
                raise NlqTemporaryError("provider unreachable", calls) from exc
            except anthropic.AnthropicError as exc:
                record("api_error", error=str(exc)[:500])
                return NlqOutcome.failed("the assistant is unavailable", self.model, calls)

            usage = getattr(response, "usage", None)
            stop_reason = getattr(response, "stop_reason", None)
            raw = _first_text(response.content)
            if stop_reason == "refusal":
                details = _dump(getattr(response, "stop_details", None))
                record(
                    "refusal",
                    raw_output=raw,
                    stop_reason=stop_reason,
                    stop_details=details,
                    usage=usage,
                )
                log.warning("nlq_refusal", model=self.model, stop_details=details)
                return NlqOutcome.refused("the assistant declined the question", self.model, calls)
            if stop_reason == "max_tokens":
                record("max_tokens", raw_output=raw, stop_reason=stop_reason, usage=usage)
                if retries > 0:
                    retries -= 1
                    max_tokens *= 2
                    continue
                return NlqOutcome.failed("the answer was too long", self.model, calls)
            try:
                answer = parse_answer(raw or "")
            except ValueError as exc:
                record(
                    "invalid",
                    raw_output=raw,
                    stop_reason=stop_reason,
                    error=str(exc)[:500],
                    usage=usage,
                )
                if retries > 0:
                    retries -= 1
                    continue
                return NlqOutcome.failed("the assistant's answer was unusable", self.model, calls)
            record(
                "ok",
                raw_output=raw,
                parsed=answer.model_dump(mode="json"),
                stop_reason=stop_reason,
                usage=usage,
            )
            if answer.refusal or not answer.sql:
                return NlqOutcome.refused(
                    answer.refusal or "the question cannot be answered from these views",
                    self.model,
                    calls,
                )
            return NlqOutcome("ok", answer.sql, answer.explanation, None, self.model, tuple(calls))


# --------------------------------------------------------------------------- stand-ins
class FakeNlqClient:
    """Deterministic stand-in (``NLQ_LLM=fake``: tests, offline dev).

    It understands enough of the SPEC's own acceptance question ("which officers had fewer
    than 3 verified visits last week?") to produce real SQL, answers a handful of other
    shapes, and refuses everything else — the three outcomes the route has to handle.
    ``answers`` lets a test script an exact reply.
    """

    provider = "fake"
    model = "fake-nlq"

    def __init__(self, answers: dict[str, NlqAnswer] | None = None) -> None:
        self.answers = dict(answers or {})
        self.requests: list[NlqRequest] = []

    def _canned(self, question: str, today: date) -> NlqAnswer:
        text = question.casefold()
        if "officer" in text and "visit" in text:
            monday = today.fromordinal(today.toordinal() - today.weekday() - 7)
            return NlqAnswer(
                sql=(
                    # canned SQL of the offline stand-in; the date is computed here
                    "SELECT officer_name, verified_visits, visits "  # nosec B608
                    "FROM v_officer_week "
                    f"WHERE week_start = DATE '{monday.isoformat()}' AND verified_visits < 3 "
                    "ORDER BY verified_visits, officer_name LIMIT 50"
                ),
                explanation=(
                    "Field officers with fewer than three verified visits in the week "
                    f"beginning {monday.isoformat()}."
                ),
            )
        if "store" in text and ("sale" in text or "sold" in text or "revenue" in text):
            return NlqAnswer(
                sql=(
                    "SELECT store_code, SUM(net_paise) AS net_paise FROM v_store_day "
                    "GROUP BY store_code ORDER BY net_paise DESC LIMIT 20"
                ),
                explanation="Net sales per store over every day held.",
            )
        if "referral" in text:
            return NlqAnswer(
                sql=(
                    "SELECT store_code, SUM(attributed) AS attributed FROM v_referral_store "
                    "GROUP BY store_code ORDER BY attributed DESC LIMIT 20"
                ),
                explanation="Referrals attributed per store.",
            )
        if "mandi" in text or "price" in text:
            return NlqAnswer(
                sql=(
                    "SELECT crop_code, market, modal_price_paise, price_date "
                    "FROM v_mandi_price_latest ORDER BY crop_code, market LIMIT 50"
                ),
                explanation="The latest mandi price held for each crop and market.",
            )
        return NlqAnswer(
            refusal="I can only answer from the officer, store, farmer, referral and "
            "mandi-price views."
        )

    async def write_sql(self, request: NlqRequest) -> NlqOutcome:
        guard_request(request)
        self.requests.append(request)
        answer = self.answers.get(request.question) or self._canned(request.question, request.today)
        call = NlqCallRecord(
            provider=self.provider,
            model=self.model,
            attempt=1,
            prompt=loggable_prompt(request, max_tokens=0),
            outcome="ok",
            latency_ms=0,
            raw_output=answer.model_dump_json(),
            parsed=answer.model_dump(mode="json"),
            stop_reason="end_turn",
        )
        if answer.refusal or not answer.sql:
            return NlqOutcome.refused(
                answer.refusal or "the question cannot be answered", self.model, [call]
            )
        return NlqOutcome("ok", answer.sql, answer.explanation, None, self.model, (call,))


class DisabledNlqClient:
    """``NLQ_LLM=off``: no provider configured."""

    provider = "off"
    model = "off"

    async def write_sql(self, request: NlqRequest) -> NlqOutcome:
        return NlqOutcome("disabled", None, None, "the assistant is switched off", None, ())


class LazyClaudeNlqClient:
    """Builds ``anthropic.AsyncAnthropic()`` on the first question, like the DX-004 client,
    so an API without ``ANTHROPIC_API_KEY`` still starts."""

    provider = PROVIDER_ANTHROPIC

    def __init__(self, *, model: str, max_tokens: int) -> None:
        self.model = model
        self._max_tokens = max_tokens
        self._delegate: ClaudeNlqClient | None = None

    async def write_sql(self, request: NlqRequest) -> NlqOutcome:  # pragma: no cover - network
        if self._delegate is None:
            self._delegate = ClaudeNlqClient(
                anthropic.AsyncAnthropic(), model=self.model, max_tokens=self._max_tokens
            )
        return await self._delegate.write_sql(request)


def build_client(settings: Any) -> NlqClient:
    choice = getattr(settings, "nlq_llm", "off")
    if choice == "fake":
        return FakeNlqClient()
    if choice == "claude":
        return LazyClaudeNlqClient(
            model=settings.nlq_llm_model, max_tokens=settings.nlq_llm_max_tokens
        )
    return DisabledNlqClient()


__all__ = [
    "SYSTEM_PROMPT",
    "ClaudeNlqClient",
    "DisabledNlqClient",
    "FakeNlqClient",
    "LazyClaudeNlqClient",
    "NlqAnswer",
    "NlqCallRecord",
    "NlqClient",
    "NlqOutcome",
    "NlqRequest",
    "NlqTemporaryError",
    "answer_schema",
    "build_client",
    "build_messages",
    "guard_request",
    "loggable_prompt",
    "parse_answer",
    "question_text",
]
