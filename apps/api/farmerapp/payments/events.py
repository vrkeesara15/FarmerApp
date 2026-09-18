"""In-process domain events emitted by payments and the day close.

Same contract as ``farmerapp.visits.events``: a synchronous bus, handlers run right after
the write path flushed, a failing handler is logged and swallowed (a subscriber can never
roll back a payment). Subscribers register at import / startup time.

* ``PaymentCaptured`` — an order payment is in hand: a provider webhook marked a UPI QR /
  link payment ``paid`` (SEC-023), or the store took cash / card / credit. The orders
  branch (FA-020 / ST-005) subscribes to move the order to ``placed`` / ``reserved``;
  payments never imports orders code. Dues payments (no order) do not emit it: their
  khata credit is posted through the ``LedgerPort`` in the same transaction (FM-010).
* ``CashVarianceDetected`` — ST-006: a day close whose |variance| is above the tenant
  threshold. The auditors are notified in the same transaction; M4 validation (VA-E10:
  "cash variance at day close above threshold; repeated small variances") subscribes.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any

from farmerapp.logging import get_logger

log = get_logger("farmerapp.payments.events")


@dataclass(frozen=True)
class PaymentCaptured:
    tenant_id: uuid.UUID
    payment_id: uuid.UUID
    order_id: uuid.UUID
    store_id: uuid.UUID
    farmer_id: uuid.UUID | None
    mode: str
    amount_paise: int
    provider_event_id: str | None
    at: datetime


@dataclass(frozen=True)
class CashVarianceDetected:
    tenant_id: uuid.UUID
    day_close_id: uuid.UUID
    store_id: uuid.UUID
    business_date: date
    cash_expected_paise: int
    cash_counted_paise: int
    variance_paise: int
    threshold_paise: int
    closed_by: uuid.UUID
    at: datetime


Event = PaymentCaptured | CashVarianceDetected
Handler = Callable[[Any], None]


@dataclass
class EventBus:
    _handlers: dict[type[Any], list[Handler]] = field(default_factory=lambda: defaultdict(list))

    def subscribe(self, event_type: type[Any], handler: Handler) -> Handler:
        if handler not in self._handlers[event_type]:
            self._handlers[event_type].append(handler)
        return handler

    def unsubscribe(self, event_type: type[Any], handler: Handler) -> None:
        handlers = self._handlers.get(event_type, [])
        if handler in handlers:
            handlers.remove(handler)

    def publish(self, event: Event) -> int:
        delivered = 0
        for handler in tuple(self._handlers.get(type(event), ())):
            try:
                handler(event)
            except Exception:
                log.exception("payment_event_handler_failed", event_type=type(event).__name__)
            else:
                delivered += 1
        return delivered


#: The process-wide bus (the orders branch and M4 validation subscribe here).
bus = EventBus()

__all__ = ["CashVarianceDetected", "Event", "EventBus", "Handler", "PaymentCaptured", "bus"]
