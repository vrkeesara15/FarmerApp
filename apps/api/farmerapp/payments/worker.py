"""``payment.webhook`` worker handler (SEC-023, FM-010).

The API stored the verified ``webhook_event`` and published ``{tenant_id,
webhook_event_id, event_id}``. Here, in one transaction bound to that tenant: load the row,
apply it (``farmerapp.payments.webhooks.apply_webhook_event``) and commit. Idempotent: a
redelivered message finds the row already processed and does nothing. A message that
arrives before the API transaction committed finds no row and raises, so Pub/Sub retries
(nack) — within the SLO (99.9 % within 2 min, SPEC 12.1) and long before the dead letter.
A message without the two ids can never succeed: it is logged and acknowledged.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.payments.models import WebhookEvent
from farmerapp.payments.service import PaymentServices, build_payment_services
from farmerapp.payments.webhooks import Applied, apply_webhook_event
from farmerapp.settings import get_settings
from farmerapp.worker.messages import PubSubMessage

log = get_logger("farmerapp.payments.worker")

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]


class WebhookEventNotFoundError(LookupError):
    """Not visible yet (the API transaction has not committed): nack and retry."""


async def handle_payment_webhook(
    message: PubSubMessage,
    *,
    session_provider: SessionProvider = job_session,
    services: PaymentServices | None = None,
    now: datetime | None = None,
) -> Applied | None:
    try:
        body = message.json_body()
        tenant_id = uuid.UUID(str(body["tenant_id"]))
        row_id = uuid.UUID(str(body["webhook_event_id"]))
    except (KeyError, ValueError):
        log.error("payment_webhook_message_malformed", message_id=message.message_id)
        return None
    services = services or build_payment_services(get_settings())
    with audit.actor_scope(audit.system_actor(tenant_id)):
        async with session_provider(tenant_id) as session:
            row = await session.get(WebhookEvent, row_id)
            if row is None:
                raise WebhookEventNotFoundError(str(row_id))
            return await apply_webhook_event(
                session,
                row,
                provider=services.provider,
                ledger=services.ledger,
                now=now or datetime.now(UTC),
            )


__all__ = ["SessionProvider", "WebhookEventNotFoundError", "handle_payment_webhook"]
