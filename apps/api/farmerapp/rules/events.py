"""Event-mode entry points (SPEC 6.1 "Event agents").

* **Pub/Sub** — ``handle_event_message(topic, message)`` is called by the worker dispatch for
  ``visit.created``, ``farmer.registered`` and ``payment.webhook``. The payload carries
  ``tenant_id`` and the id of the record the event is about (``visit_id`` / ``farmer_id`` /
  ``payment_id``); the event rules subscribed to the topic run in one transaction bound to
  the tenant, as the system actor. No rule on the topic -> no database work at all. A
  malformed payload can never succeed: it is logged and acknowledged.
* **In-process** — ``register()`` subscribes to the payments bus (``PaymentCaptured``) with a
  writing subscriber, so event rules on ``payment.captured`` run in the payment's
  transaction. Write paths that own a session (FA-012 registration) call
  ``engine.emit`` directly.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.payments import events as payment_events
from farmerapp.rules.engine import RunReport, emit
from farmerapp.rules.loader import RuleSet, get_rule_set
from farmerapp.rules.schema import Mode
from farmerapp.worker.messages import PubSubMessage

log = get_logger("farmerapp.rules.events")

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]

#: Topic -> payload key of the record id the event is about.
SUBJECT_KEYS: dict[str, str] = {
    "visit.created": "visit_id",
    "farmer.registered": "farmer_id",
    "payment.webhook": "payment_id",
    "payment.captured": "payment_id",
}


async def handle_event_message(
    topic: str,
    message: PubSubMessage,
    *,
    session_provider: SessionProvider = job_session,
    rule_set: RuleSet | None = None,
    now: datetime | None = None,
) -> RunReport | None:
    rule_set = rule_set or get_rule_set()
    if not rule_set.for_mode(Mode.EVENT, trigger=topic):
        return None
    key = SUBJECT_KEYS.get(topic, "id")
    try:
        body = message.json_body()
        tenant_id = uuid.UUID(str(body["tenant_id"]))
        subject_id = uuid.UUID(str(body[key]))
    except (KeyError, ValueError):
        log.error("rules_event_malformed", topic=topic, message_id=message.message_id)
        return None
    with audit.actor_scope(audit.system_actor(tenant_id)):
        async with session_provider(tenant_id) as session:
            return await emit(session, tenant_id, topic, [subject_id], payload=body, now=now)


async def _on_payment_captured(
    session: AsyncSession, event: payment_events.PaymentCaptured
) -> None:
    if not get_rule_set().for_mode(Mode.EVENT, trigger="payment.captured"):
        return
    await emit(
        session,
        event.tenant_id,
        "payment.captured",
        [event.payment_id],
        payload={"order_id": str(event.order_id), "store_id": str(event.store_id)},
        now=event.at,
    )


def register() -> None:
    """Subscribe the event runner to the in-process buses (idempotent)."""
    payment_events.bus.subscribe_async(payment_events.PaymentCaptured, _on_payment_captured)


__all__ = ["SUBJECT_KEYS", "handle_event_message", "register"]
