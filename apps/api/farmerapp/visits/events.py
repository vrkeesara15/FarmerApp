"""In-process domain events of the visit flow (FA-014, FA-016, FA-028).

A minimal synchronous bus: handlers are plain callables registered per event type and run
in the publishing coroutine's thread, right after the write path flushed the rows. The
events are the seams for later milestones:

* ``IntegrityEvent`` — FA-028: the device reported a mock location, a rooted device or a
  clock drift over five minutes at check-in. Recorded, never blocking; the M4 validation
  agent (VA-E01) subscribes and raises the flag. The structured log ``integrity_signal`` is
  emitted next to it so the signal is visible before M4 lands.
* ``OverrideRequested`` — FA-014: an officer checked in outside the geofence with a note;
  the cluster head of the officer's cluster must approve. FA-007 notifications (the
  ``notification`` table of the duty / location migration) deliver it; until then the
  event is the only outlet and the cluster head finds the request on ``GET /v1/visits/{id}``.
* ``ConfirmationRequested`` — FA-016 ``app_push``: the farmer's app should show the
  confirm prompt (FM-011); the event carries the signed token the farmer app must post to
  ``POST /v1/visits/{id}/farmer-confirm``. Delivery is FA-007.

Handlers must not raise: an exception in a subscriber is logged and swallowed so a
notification failure never rolls back a check-in.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from farmerapp.logging import get_logger

log = get_logger("farmerapp.visits.events")


@dataclass(frozen=True)
class IntegrityEvent:
    """FA-028 / VA-E01 signal: which integrity checks failed at check-in."""

    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    visit_id: uuid.UUID
    issues: tuple[str, ...]
    is_mock: bool
    is_rooted: bool
    clock_drift_s: int
    at: datetime


@dataclass(frozen=True)
class OverrideRequested:
    """FA-014: a geofence override waits for the cluster head's decision."""

    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    override_request_id: uuid.UUID
    officer_id: uuid.UUID
    cluster_id: uuid.UUID | None
    approver_role: str
    note: str
    distance_m: float | None
    at: datetime


@dataclass(frozen=True)
class ConfirmationRequested:
    """FA-016 ``app_push``: prompt the farmer's app; ``token`` is what it posts back."""

    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    confirmation_id: uuid.UUID
    farmer_id: uuid.UUID
    farmer_user_id: uuid.UUID
    officer_id: uuid.UUID
    channel: str
    token: str
    expires_at: datetime


Event = IntegrityEvent | OverrideRequested | ConfirmationRequested
Handler = Callable[[Any], None]


@dataclass
class EventBus:
    """Handlers per event type; ``publish`` calls each in registration order."""

    _handlers: dict[type[Any], list[Handler]] = field(default_factory=lambda: defaultdict(list))

    def subscribe(self, event_type: type[Event], handler: Handler) -> Handler:
        if handler not in self._handlers[event_type]:
            self._handlers[event_type].append(handler)
        return handler

    def unsubscribe(self, event_type: type[Event], handler: Handler) -> None:
        handlers = self._handlers.get(event_type, [])
        if handler in handlers:
            handlers.remove(handler)

    def handlers(self, event_type: type[Event]) -> tuple[Handler, ...]:
        return tuple(self._handlers.get(event_type, ()))

    def publish(self, event: Event) -> int:
        """Deliver ``event``; returns how many handlers ran. Handler errors are logged."""
        delivered = 0
        for handler in self.handlers(type(event)):
            try:
                handler(event)
            except Exception:
                log.exception("visit_event_handler_failed", event_type=type(event).__name__)
            else:
                delivered += 1
        return delivered


#: The process-wide bus the write path publishes to (M4 / FA-007 subscribe here).
bus = EventBus()


__all__ = [
    "ConfirmationRequested",
    "Event",
    "EventBus",
    "Handler",
    "IntegrityEvent",
    "OverrideRequested",
    "bus",
]
