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


async def on_visit_created(message: PubSubMessage) -> None:
    """M2/M4: event validation agents for a new visit (VA-E*)."""
    await _todo(Topic.VISIT_CREATED)


async def on_farmer_registered(message: PubSubMessage) -> None:
    """M1/M4: registration burst / duplicate checks (VA-F06)."""
    await _todo(Topic.FARMER_REGISTERED)


async def on_diagnosis_requested(message: PubSubMessage) -> None:
    """M6: diagnosis pipeline (SPEC 3)."""
    await _todo(Topic.DIAGNOSIS_REQUESTED)


async def on_payment_webhook(message: PubSubMessage) -> None:
    """M3 (SEC-023, FA-021): apply a stored, verified provider webhook (idempotent by event
    id). Imported lazily so the worker app does not load the payments stack at import."""
    from farmerapp.payments.worker import handle_payment_webhook

    await handle_payment_webhook(message)


async def on_order_created(message: PubSubMessage) -> None:
    """M3: stock, khata and notification fan-out."""
    await _todo(Topic.ORDER_CREATED)


async def on_location_batch(message: PubSubMessage) -> None:
    """M2: track processing (VV-*)."""
    await _todo(Topic.LOCATION_BATCH)


async def on_notify_send(message: PubSubMessage) -> None:
    """M2+: SMS / WhatsApp / push delivery."""
    await _todo(Topic.NOTIFY_SEND)


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
