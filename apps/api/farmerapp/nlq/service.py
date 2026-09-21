"""AN-016: ask a question, get rows, the SQL and a plain-language answer.

``ask()`` is the whole pipeline:

1. **Scope** the caller (:func:`caller_scope`): owner / director see the tenant, a cluster
   head only their cluster. The scope goes into two GUCs the authorised views read, so it
   binds the *data*, not the generated SQL.
2. **Write SQL** with the model (:mod:`farmerapp.nlq.llm`). The prompt carries the view
   schema and the scope in words — no row, no id, no PII (SEC-027).
3. **Validate** (:mod:`farmerapp.nlq.sql_guard`): one SELECT, authorised views only, no
   writes, no catalogue, no unknown function, hard row limit.
4. **Run** it in a savepoint as ``farmerapp_readonly`` with
   ``transaction_read_only = on`` and a ``statement_timeout``, then roll the savepoint back —
   so even a bug in every layer above cannot leave a change behind.
5. **Log** the question, the generated SQL, the validation outcome and the row count into
   the append-only ``llm_call_log`` (SEC-027), and emit an ``nlq_asked`` event.

Every failure — the model refusing, invalid SQL, a rejected relation, a timeout, no provider
configured — comes back as ``answered=false`` with a friendly "I could not answer that" and
a reason. Nothing raises a 5xx at the caller for a question that simply could not be
answered.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import text
from sqlalchemy.exc import DBAPIError, SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.diagnosis.models import LlmCallLog
from farmerapp.logging import get_logger
from farmerapp.nlq import llm as nlq_llm
from farmerapp.nlq.llm import NlqClient, NlqRequest, NlqTemporaryError
from farmerapp.nlq.sql_guard import SqlRejectedError, validate
from farmerapp.nlq.views import CLUSTER_SETTING, READONLY_ROLE, STORE_SETTING
from farmerapp.payments.config import IST
from farmerapp.pii.llm_guard import PromptPiiError

log = get_logger("farmerapp.nlq.service")

#: SEC-027 / SPEC 3.4: LLM prompts and outputs are kept one year.
LLM_LOG_RETENTION = timedelta(days=366)

#: Shown whenever the question could not be answered (the app / console translates the key).
COULD_NOT_ANSWER_KEY = "analytics.ask.could_not_answer"

#: Roles that may ask (SPEC 5.3: "for owners"; directors and cluster heads share the
#: dashboards, a cluster head scoped to their own cluster).
ASK_ROLES: tuple[UserRole, ...] = (UserRole.OWNER, UserRole.DIRECTOR, UserRole.CLUSTER_HEAD)

_SCOPE_WORDS = {
    UserRole.OWNER: "the whole company",
    UserRole.DIRECTOR: "the whole company",
    UserRole.CLUSTER_HEAD: "one cluster only",
}
_ROLE_WORDS = {
    UserRole.OWNER: "owner",
    UserRole.DIRECTOR: "director",
    UserRole.CLUSTER_HEAD: "cluster head",
}


@dataclass(frozen=True)
class Scope:
    """What the caller may see; ``cluster_id`` / ``store_id`` bind the views."""

    role: UserRole
    cluster_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None

    @property
    def words(self) -> str:
        return _SCOPE_WORDS.get(self.role, "their own records")

    @property
    def role_words(self) -> str:
        return _ROLE_WORDS.get(self.role, str(self.role))


@dataclass
class AskResult:
    answered: bool
    question: str
    #: The validated SQL, pretty-printed — what the console shows under "SQL used".
    sql: str | None = None
    #: Plain-language answer: the model's own explanation plus the real row count.
    answer: str | None = None
    #: Why it could not be answered (refusal, validation reason, timeout).
    reason: str | None = None
    #: i18n key of the "I could not answer that" headline; null when answered.
    message_key: str | None = None
    columns: list[str] = field(default_factory=list)
    rows: list[dict[str, Any]] = field(default_factory=list)
    row_count: int = 0
    truncated: bool = False
    views: list[str] = field(default_factory=list)
    model: str | None = None
    elapsed_ms: int = 0
    scope: str = ""


def caller_scope(actor: User) -> Scope:
    role = UserRole(actor.role)
    if role is UserRole.CLUSTER_HEAD:
        return Scope(role, cluster_id=actor.cluster_id)
    return Scope(role)


def _jsonable(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, uuid.UUID):
        return str(value)
    return value


async def run_readonly(
    session: AsyncSession,
    sql: str,
    *,
    scope: Scope,
    statement_timeout_ms: int,
) -> tuple[list[str], list[dict[str, Any]]]:
    """Run ``sql`` as ``farmerapp_readonly`` inside a savepoint that is always rolled back.

    The savepoint is what makes the read *provably* free of side effects: whatever the
    statement did, the nested transaction is discarded before the caller's session continues.
    ``SET LOCAL`` unwinds with it, so the role, the timeout and the scope GUCs never leak
    into the rest of the request.
    """
    with session.no_autoflush:  # never flush application writes as the read-only role
        async with session.begin_nested() as nested:
            try:
                await session.execute(text(f"SET LOCAL ROLE {READONLY_ROLE}"))
                await session.execute(text("SET LOCAL transaction_read_only = on"))
                await session.execute(
                    text("SELECT set_config('statement_timeout', :ms, true)"),
                    {"ms": str(int(statement_timeout_ms))},
                )
                await session.execute(
                    text(f"SELECT set_config('{CLUSTER_SETTING}', :v, true)"),
                    {"v": str(scope.cluster_id) if scope.cluster_id else ""},
                )
                await session.execute(
                    text(f"SELECT set_config('{STORE_SETTING}', :v, true)"),
                    {"v": str(scope.store_id) if scope.store_id else ""},
                )
                result = await session.execute(text(sql))
                columns = list(result.keys())
                rows = [
                    {key: _jsonable(value) for key, value in zip(columns, row, strict=True)}
                    for row in result.fetchall()
                ]
            finally:
                await nested.rollback()
    return columns, rows


def _log_calls(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    calls: tuple[nlq_llm.NlqCallRecord, ...],
    now: datetime,
    outcome: dict[str, Any] | None = None,
) -> None:
    """SEC-027 / AN-016: every attempt, its prompt, its output — and, on the last row, the
    validation outcome and the row count — into the append-only ``llm_call_log``."""
    for index, call in enumerate(calls):
        parsed = dict(call.parsed or {})
        if outcome is not None and index == len(calls) - 1:
            parsed["nlq"] = outcome
        session.add(
            LlmCallLog(
                tenant_id=tenant_id,
                provider=call.provider,
                model=call.model,
                attempt=call.attempt,
                prompt=call.prompt,
                raw_output=call.raw_output,
                parsed=parsed or None,
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
            purpose="analytics_ask",
            provider=call.provider,
            model=call.model,
            attempt=call.attempt,
            outcome=call.outcome,
            latency_ms=call.latency_ms,
            input_tokens=call.input_tokens,
            output_tokens=call.output_tokens,
        )


def _summary(explanation: str | None, rows: int, truncated: bool, limit: int) -> str:
    head = (explanation or "").strip()
    if truncated:
        tail = f"{rows} rows (the first {limit}; there may be more)."
    elif rows == 0:
        tail = "No rows matched."
    elif rows == 1:
        tail = "1 row."
    else:
        tail = f"{rows} rows."
    return f"{head} {tail}".strip()


async def ask(
    session: AsyncSession,
    actor: User,
    question: str,
    *,
    client: NlqClient,
    row_limit: int = 200,
    statement_timeout_ms: int = 5_000,
    now: datetime | None = None,
) -> AskResult:
    """AN-016: answer ``question`` for ``actor``, or say plainly why it could not be."""
    now = now or datetime.now(UTC)
    started = time.monotonic()
    scope = caller_scope(actor)
    result = AskResult(answered=False, question=question, scope=scope.words)
    request = NlqRequest.build(
        question=question,
        role=scope.role_words,
        scope=scope.words,
        today=now.astimezone(IST).date(),
    )

    try:
        outcome = await client.write_sql(request)
    except PromptPiiError as exc:
        # SEC-027: the question itself carried a phone, an e-mail or a position. Nothing was
        # sent; the owner is asked to leave personal details out rather than shown an error.
        log.warning("nlq_prompt_refused", tenant_id=str(actor.tenant_id), reasons=exc.reasons)
        return _fail(
            result,
            "please ask without personal details such as a phone number, an e-mail address "
            "or a location",
            started,
        )
    except NlqTemporaryError as exc:
        _log_calls(
            session,
            tenant_id=actor.tenant_id,
            calls=tuple(exc.calls),
            now=now,
            outcome={"question": question, "validation": "not_reached", "rows": 0},
        )
        return _fail(result, "the assistant is busy; please try again", started)

    result.model = outcome.model
    if outcome.status != "ok" or not outcome.sql:
        _log_calls(
            session,
            tenant_id=actor.tenant_id,
            calls=outcome.calls,
            now=now,
            outcome={
                "question": question,
                "validation": outcome.status,
                "rows": 0,
                "scope": scope.words,
            },
        )
        return _fail(result, outcome.refusal or "the question could not be answered", started)

    try:
        valid = validate(outcome.sql, row_limit=row_limit)
    except SqlRejectedError as exc:
        _log_calls(
            session,
            tenant_id=actor.tenant_id,
            calls=outcome.calls,
            now=now,
            outcome={
                "question": question,
                "sql": outcome.sql,
                "validation": "rejected",
                "validation_reason": exc.reason,
                "rows": 0,
                "scope": scope.words,
            },
        )
        log.warning(
            "nlq_sql_rejected",
            tenant_id=str(actor.tenant_id),
            reason=exc.reason,
            model=outcome.model,
        )
        return _fail(result, exc.reason, started)

    result.sql = valid.sql
    result.views = list(valid.relations)
    try:
        columns, rows = await run_readonly(
            session, valid.executable, scope=scope, statement_timeout_ms=statement_timeout_ms
        )
    except (DBAPIError, SQLAlchemyError) as exc:
        reason = _db_reason(exc)
        _log_calls(
            session,
            tenant_id=actor.tenant_id,
            calls=outcome.calls,
            now=now,
            outcome={
                "question": question,
                "sql": valid.sql,
                "validation": "accepted",
                "execution": "failed",
                "error": reason,
                "rows": 0,
                "scope": scope.words,
            },
        )
        log.warning("nlq_query_failed", tenant_id=str(actor.tenant_id), error=reason)
        return _fail(result, reason, started)

    result.answered = True
    result.columns = columns
    result.rows = rows
    result.row_count = len(rows)
    result.truncated = len(rows) >= row_limit
    result.answer = _summary(outcome.explanation, len(rows), result.truncated, row_limit)
    result.elapsed_ms = int((time.monotonic() - started) * 1000)
    _log_calls(
        session,
        tenant_id=actor.tenant_id,
        calls=outcome.calls,
        now=now,
        outcome={
            "question": question,
            "sql": valid.sql,
            "validation": "accepted",
            "execution": "ok",
            "views": list(valid.relations),
            "rows": result.row_count,
            "scope": scope.words,
        },
    )
    log.info(
        "nlq_asked",
        tenant_id=str(actor.tenant_id),
        user_id=str(actor.id),
        role=str(actor.role),
        answered=True,
        views=list(valid.relations),
        rows=result.row_count,
        model=outcome.model,
        elapsed_ms=result.elapsed_ms,
    )
    return result


def _db_reason(exc: Exception) -> str:
    text_ = str(getattr(exc, "orig", exc))
    lowered = text_.lower()
    if "statement timeout" in lowered or "canceling statement" in lowered:
        return "the query took too long; please ask for a smaller period"
    if "permission denied" in lowered:
        return "the query touched something the read-only role may not read"
    if "read-only" in lowered:
        return "only reading is allowed"
    if "does not exist" in lowered or "undefined" in lowered:
        return "the query referred to a column that does not exist"
    return "the query could not be run"


def _fail(result: AskResult, reason: str, started: float) -> AskResult:
    result.answered = False
    result.reason = reason
    result.message_key = COULD_NOT_ANSWER_KEY
    result.answer = None
    result.elapsed_ms = int((time.monotonic() - started) * 1000)
    return result


__all__ = [
    "ASK_ROLES",
    "COULD_NOT_ANSWER_KEY",
    "LLM_LOG_RETENTION",
    "AskResult",
    "Scope",
    "ask",
    "caller_scope",
    "run_readonly",
]
