"""``diagnosis.requested`` worker handler (SPEC 9.2; M6).

Payload ``{"tenant_id", "diagnosis_id"}``. One delivery:

1. bump ``attempts`` in its own committed transaction (so the count survives a failed run);
2. run the pipeline in a second transaction as the system actor;
3. a retryable failure (LLM rate limit / 5xx / connection, encoder down) writes the LLM call
   log in a third transaction and re-raises: the push answers 5xx and Pub/Sub redelivers
   with backoff (dead-letter after the subscription's max attempts). From the
   ``DIAGNOSIS_MAX_ATTEMPTS``-th delivery on, a failing LLM call is "unknown" instead
   (provisional + agronomist queue), so a farmer is never left waiting on a broken provider.

A diagnosis not visible yet (published by a request whose transaction has not committed)
is retried for ``NOT_FOUND_RETRY`` after publishing, then acknowledged. A malformed payload
can never succeed: logged and acknowledged. Already processed -> no-op (redelivery safe).
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.llm import LlmTemporaryError
from farmerapp.diagnosis.models import Diagnosis, DiagnosisStatus
from farmerapp.diagnosis.pipeline import process, write_llm_logs
from farmerapp.diagnosis.services import DiagnosisServices, worker_services
from farmerapp.logging import get_logger
from farmerapp.worker.messages import PubSubMessage

log = get_logger("farmerapp.diagnosis.worker")

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]
NOT_FOUND_RETRY = timedelta(minutes=10)


class DiagnosisNotReadyError(RuntimeError):
    """The row is not visible yet: nack so Pub/Sub redelivers."""


def _publish_time(message: PubSubMessage) -> datetime | None:
    try:
        return datetime.fromisoformat(message.publish_time.replace("Z", "+00:00"))
    except ValueError:
        return None


async def handle_diagnosis_message(
    message: PubSubMessage,
    *,
    services: DiagnosisServices | None = None,
    session_provider: SessionProvider = job_session,
    now: datetime | None = None,
) -> str:
    """Returns what happened (``processed`` / ``skipped`` / ``ignored``) for tests and logs."""
    now = now or datetime.now(UTC)
    try:
        body = message.json_body()
        tenant_id = uuid.UUID(str(body["tenant_id"]))
        diagnosis_id = uuid.UUID(str(body["diagnosis_id"]))
    except (ValueError, KeyError, TypeError):
        log.warning("diagnosis_message_invalid", message_id=message.message_id)
        return "ignored"
    services = services or worker_services()
    with audit.actor_scope(audit.system_actor(tenant_id)):
        async with session_provider(tenant_id) as session:
            diagnosis = await session.scalar(
                select(Diagnosis).where(Diagnosis.id == diagnosis_id).with_for_update()
            )
            if diagnosis is None:
                published = _publish_time(message)
                if published is not None and now - published < NOT_FOUND_RETRY:
                    raise DiagnosisNotReadyError(str(diagnosis_id))
                log.warning("diagnosis_message_unknown", diagnosis_id=str(diagnosis_id))
                return "ignored"
            if diagnosis.status != DiagnosisStatus.QUEUED.value:
                return "skipped"
            diagnosis.attempts += 1
            attempts = diagnosis.attempts
        final = attempts >= services.settings.diagnosis_max_attempts
        try:
            async with session_provider(tenant_id) as session:
                diagnosis = await session.scalar(
                    select(Diagnosis).where(Diagnosis.id == diagnosis_id).with_for_update()
                )
                if diagnosis is None or diagnosis.status != DiagnosisStatus.QUEUED.value:
                    return "skipped"
                await process(session, services, diagnosis, now=now, final_attempt=final)
        except LlmTemporaryError as exc:
            async with session_provider(tenant_id) as session:
                await write_llm_logs(session, tenant_id, diagnosis_id, exc.calls, now=now)
            log.warning(
                "diagnosis_retry", diagnosis_id=str(diagnosis_id), attempts=attempts, cause="llm"
            )
            raise
    return "processed"


__all__ = ["NOT_FOUND_RETRY", "DiagnosisNotReadyError", "handle_diagnosis_message"]
