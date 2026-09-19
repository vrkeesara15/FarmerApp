"""Dispatch table: topic -> async handler. Handlers are skeletons until their milestone."""

from __future__ import annotations

from collections.abc import Awaitable, Callable

from farmerapp.logging import get_logger
from farmerapp.worker.messages import PubSubMessage
from farmerapp.worker.topics import Topic

Handler = Callable[[PubSubMessage], Awaitable[None]]

log = get_logger("farmerapp.worker")


async def _todo(topic: Topic) -> None:
    log.info("handler_noop", topic=str(topic))


async def _rules(topic: Topic, message: PubSubMessage) -> None:
    """M4: the event validation rules subscribed to ``topic`` (SPEC 6.1)."""
    from farmerapp.rules.events import handle_event_message

    await handle_event_message(str(topic), message)


async def on_visit_created(message: PubSubMessage) -> None:
    """M4: event validation agents for a new visit (VA-E01, VA-E08, VA-F08)."""
    await _rules(Topic.VISIT_CREATED, message)


async def on_farmer_registered(message: PubSubMessage) -> None:
    """M4: registration burst (VA-F06) and other ``farmer.registered`` rules."""
    await _rules(Topic.FARMER_REGISTERED, message)


async def on_diagnosis_requested(message: PubSubMessage) -> None:
    """M6: diagnosis pipeline (SPEC 3): encode -> kNN -> decision -> LLM -> treatments."""
    from farmerapp.diagnosis.worker import handle_diagnosis_message

    await handle_diagnosis_message(message)


async def on_payment_webhook(message: PubSubMessage) -> None:
    """M3 (SEC-023, FA-021): apply a stored, verified provider webhook (idempotent by event
    id). Imported lazily so the worker app does not load the payments stack at import."""
    from farmerapp.orders import payment_events
    from farmerapp.payments.worker import handle_payment_webhook

    payment_events.register()  # a paid order moves on in the same transaction (ST-005)
    await handle_payment_webhook(message)
    await _rules(Topic.PAYMENT_WEBHOOK, message)  # M4: event rules on payments (none yet)


async def on_order_created(message: PubSubMessage) -> None:
    """M3: stock, khata and notification fan-out."""
    await _todo(Topic.ORDER_CREATED)


async def on_location_batch(message: PubSubMessage) -> None:
    """M4: device integrity (VA-E01) and impossible travel (VA-E02) on a duty session's new
    points (payload ``tenant_id`` + ``duty_session_id``). Track processing (VV-*) runs at
    duty end in the API."""
    await _rules(Topic.LOCATION_BATCH, message)


async def on_notify_send(message: PubSubMessage) -> None:
    """FA-007: push the pending ``notification`` rows of a tenant (or one row) to the users'
    active devices (``farmerapp.notifications.delivery``); retries back off per row."""
    from farmerapp.notifications.delivery import handle_notify_message
    from farmerapp.notifications.service import worker_push_sender
    from farmerapp.settings import get_settings

    await handle_notify_message(
        message, sender=worker_push_sender(), max_attempts=get_settings().notify_max_attempts
    )


HANDLERS: dict[Topic, Handler] = {
    Topic.VISIT_CREATED: on_visit_created,
    Topic.FARMER_REGISTERED: on_farmer_registered,
    Topic.DIAGNOSIS_REQUESTED: on_diagnosis_requested,
    Topic.PAYMENT_WEBHOOK: on_payment_webhook,
    Topic.ORDER_CREATED: on_order_created,
    Topic.LOCATION_BATCH: on_location_batch,
    Topic.NOTIFY_SEND: on_notify_send,
}


async def dispatch(topic: Topic, message: PubSubMessage) -> None:
    handler = HANDLERS[topic]
    log.info("dispatch", topic=str(topic), message_id=message.message_id)
    await handler(message)
