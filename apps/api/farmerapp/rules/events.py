"""Event-mode entry points (SPEC 6.1 "Event agents").

* **Pub/Sub** — ``handle_event_message(topic, message)`` is called by the worker dispatch for
  ``visit.created``, ``location.batch``, ``farmer.registered`` and ``payment.webhook``. The
  payload carries ``tenant_id`` and the id of the record the event is about (``visit_id`` /
  ``duty_session_id`` / ``farmer_id`` / ``payment_id``, see ``SUBJECT_KEYS``); the event
  rules subscribed to the topic run in one transaction bound to the tenant, as the system
  actor. No rule on the topic -> no database work at all. A malformed payload can never
  succeed: it is logged and acknowledged.
* **In-process** — ``register()`` subscribes writing (``subscribe_async``) handlers to the
  in-process buses, so event rules run in the write path's own transaction, each bus
  subscriber in a savepoint (a failing rule never rolls back the business write):

  ==============================  =====================  ==========================
  event (bus)                      topic                  subject ids
  ==============================  =====================  ==========================
  ``VisitCheckedIn`` (visits)      ``visit.created``      the visit
  ``VisitPhotoAdded`` (visits)     ``visit.photo``        the visit
  ``VisitConfirmed`` (visits)      ``visit.confirmed``    the visit
  ``VisitCheckedOut`` (visits)     ``visit.checked_out``  the visit
  ``DutyStarted`` (location)       ``duty.started``       the duty session
  ``LocationBatchIngested``        ``location.batch``     the duty session
  ``PaymentCaptured`` (payments)   ``payment.captured``   the payment
  ``CashVarianceDetected``         ``day_close.variance`` the day close
  (payments, ST-006 day close)
  ``TravelClaimSubmitted``         ``ta.claim.submitted`` the claim
  (travel, FA-023)
  ==============================  =====================  ==========================

  FA-023 TA claims (M7): the claim submit path (``POST /v1/travel/claims`` and the
  ``travel_claim`` sync create) dispatches ``TravelClaimSubmitted`` after the claim row is
  flushed; the subscriber runs ``on_travel_claim_submitted`` (VA-E07 reads the claim through
  the ``TravelClaimPort`` the travel package registers, ``farmerapp.travel.rules_port``).
  The Pub/Sub worker accepts the same topic with ``claim_id``.

  Write paths that own a session without a bus (FA-012 registration, farm photos) call
  ``engine.emit`` directly (``farmer.registered``, ``farm.photo``).

The in-process run and a later Pub/Sub delivery of the same event are both safe: the dedupe
key never raises an unresolved flag twice.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.location import events as location_events
from farmerapp.logging import get_logger
from farmerapp.payments import events as payment_events
from farmerapp.rules.engine import RunReport, emit
from farmerapp.rules.loader import RuleSet, get_rule_set
from farmerapp.rules.schema import Mode
from farmerapp.travel import events as travel_events
from farmerapp.visits import events as visit_events
from farmerapp.worker.messages import PubSubMessage

log = get_logger("farmerapp.rules.events")

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]

#: Topic -> payload key of the record id the event is about.
SUBJECT_KEYS: dict[str, str] = {
    "visit.created": "visit_id",
    "visit.photo": "visit_id",
    "visit.confirmed": "visit_id",
    "visit.checked_out": "visit_id",
    "duty.started": "duty_session_id",
    "location.batch": "duty_session_id",
    "farmer.registered": "farmer_id",
    "farm.photo": "farm_id",
    "payment.webhook": "payment_id",
    "payment.captured": "payment_id",
    "day_close.variance": "day_close_id",  # M7 VA-E10
    "ta.claim.submitted": "claim_id",  # M7 VA-E07 (FA-023 travel claims)
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
            report = await emit(session, tenant_id, topic, [subject_id], payload=body, now=now)
    if report.flag_ids:
        # VA-004: summarise the flags this event raised, after they are committed.
        from farmerapp.flags.review_agent import summarise_flags

        await summarise_flags(
            tenant_id, report.flag_ids, session_provider=session_provider, rule_set=rule_set
        )
    return report


async def _run_subscribed(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    topic: str,
    subject_id: uuid.UUID,
    *,
    payload: dict[str, str],
    at: datetime,
) -> None:
    if not get_rule_set().for_mode(Mode.EVENT, trigger=topic):
        return
    await emit(session, tenant_id, topic, [subject_id], payload=payload, now=at)


async def _on_payment_captured(
    session: AsyncSession, event: payment_events.PaymentCaptured
) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "payment.captured",
        event.payment_id,
        payload={"order_id": str(event.order_id), "store_id": str(event.store_id)},
        at=event.at,
    )


async def _on_cash_variance(
    session: AsyncSession, event: payment_events.CashVarianceDetected
) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "day_close.variance",
        event.day_close_id,
        payload={"store_id": str(event.store_id), "closed_by": str(event.closed_by)},
        at=event.at,
    )


async def on_travel_claim_submitted(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    claim_id: uuid.UUID,
    *,
    officer_id: uuid.UUID,
    at: datetime,
) -> None:
    """FA-023 seam: run the ``ta.claim.submitted`` rules (VA-E07) for a claim the travel write
    path just flushed, in its transaction (call inside a savepoint: a failing rule is logged
    by the engine and never rolls back the claim)."""
    await _run_subscribed(
        session,
        tenant_id,
        "ta.claim.submitted",
        claim_id,
        payload={"officer_id": str(officer_id)},
        at=at,
    )


async def _on_travel_claim_submitted(
    session: AsyncSession, event: travel_events.TravelClaimSubmitted
) -> None:
    await on_travel_claim_submitted(
        session, event.tenant_id, event.claim_id, officer_id=event.officer_id, at=event.at
    )


async def _on_visit_checked_in(session: AsyncSession, event: visit_events.VisitCheckedIn) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "visit.created",
        event.visit_id,
        payload={"officer_id": str(event.officer_id)},
        at=event.at,
    )


async def _on_visit_photo(session: AsyncSession, event: visit_events.VisitPhotoAdded) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "visit.photo",
        event.visit_id,
        payload={"photo_id": str(event.photo_id)},
        at=event.at,
    )


async def _on_visit_confirmed(session: AsyncSession, event: visit_events.VisitConfirmed) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "visit.confirmed",
        event.visit_id,
        payload={"confirmation_id": str(event.confirmation_id), "channel": event.channel},
        at=event.at,
    )


async def _on_visit_checked_out(session: AsyncSession, event: visit_events.VisitCheckedOut) -> None:
    await _run_subscribed(
        session, event.tenant_id, "visit.checked_out", event.visit_id, payload={}, at=event.at
    )


async def _on_duty_started(session: AsyncSession, event: location_events.DutyStarted) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "duty.started",
        event.duty_session_id,
        payload={"officer_id": str(event.officer_id)},
        at=event.at,
    )


async def _on_location_batch(
    session: AsyncSession, event: location_events.LocationBatchIngested
) -> None:
    await _run_subscribed(
        session,
        event.tenant_id,
        "location.batch",
        event.duty_session_id,
        payload={"officer_id": str(event.officer_id), "accepted": str(event.accepted)},
        at=event.at,
    )


def register() -> None:
    """Subscribe the event runner to the in-process buses (idempotent)."""
    payment_events.bus.subscribe_async(payment_events.PaymentCaptured, _on_payment_captured)
    payment_events.bus.subscribe_async(payment_events.CashVarianceDetected, _on_cash_variance)
    visit_events.bus.subscribe_async(visit_events.VisitCheckedIn, _on_visit_checked_in)
    visit_events.bus.subscribe_async(visit_events.VisitPhotoAdded, _on_visit_photo)
    visit_events.bus.subscribe_async(visit_events.VisitConfirmed, _on_visit_confirmed)
    visit_events.bus.subscribe_async(visit_events.VisitCheckedOut, _on_visit_checked_out)
    location_events.bus.subscribe_async(location_events.DutyStarted, _on_duty_started)
    location_events.bus.subscribe_async(location_events.LocationBatchIngested, _on_location_batch)
    travel_events.bus.subscribe_async(
        travel_events.TravelClaimSubmitted, _on_travel_claim_submitted
    )


__all__ = ["SUBJECT_KEYS", "handle_event_message", "on_travel_claim_submitted", "register"]
