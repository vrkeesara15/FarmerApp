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
* ``VisitCheckedIn`` / ``VisitPhotoAdded`` / ``VisitConfirmed`` / ``VisitCheckedOut`` — the
  steps of the visit flow (M4): the validation agents' event rules (SPEC 6.1) subscribe
  (``farmerapp.rules.events``: VA-E01, VA-E08, VA-F08).

Handlers must not raise: an exception in a subscriber is logged and swallowed so a
notification failure never rolls back a check-in.

Two kinds of subscribers:

* ``subscribe`` — plain synchronous callables, no database access (``publish``).
* ``subscribe_async`` — writing subscribers that need the database (the rules engine reads
  the visit and raises flags). The write path calls ``await bus.dispatch(session, event)``:
  each async subscriber runs **in the write path's transaction inside its own savepoint**,
  so a failing one is logged and only its own writes roll back, then the plain subscribers
  run. The synchronous ``publish`` can never await, which is why database work cannot hang
  off it.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime
from typing import TYPE_CHECKING, Any

from farmerapp.logging import get_logger

if TYPE_CHECKING:
    from sqlalchemy.ext.asyncio import AsyncSession

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


@dataclass(frozen=True)
class VisitCheckedIn:
    """FA-014: a visit was created (not on a replay of the same check-in)."""

    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    officer_id: uuid.UUID
    at: datetime


@dataclass(frozen=True)
class VisitPhotoAdded:
    """FA-015: an in-app photo was attached (not on a replay)."""

    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    photo_id: uuid.UUID
    photo_flags: tuple[str, ...]
    at: datetime


@dataclass(frozen=True)
class VisitConfirmed:
    """FA-016: one confirmation channel succeeded."""

    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    confirmation_id: uuid.UUID
    channel: str
    at: datetime


@dataclass(frozen=True)
class VisitCheckedOut:
    """FA-017: the visit was closed and scored (not on a replay)."""

    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    at: datetime


Event = (
    IntegrityEvent
    | OverrideRequested
    | ConfirmationRequested
    | VisitCheckedIn
    | VisitPhotoAdded
    | VisitConfirmed
    | VisitCheckedOut
)
Handler = Callable[[Any], None]
#: A subscriber that needs the database: runs in the publisher's transaction (savepoint).
AsyncHandler = Callable[["AsyncSession", Any], Awaitable[None]]


@dataclass
class EventBus:
    """Handlers per event type; ``publish`` calls each in registration order."""

    _handlers: dict[type[Any], list[Handler]] = field(default_factory=lambda: defaultdict(list))
    _async: dict[type[Any], list[AsyncHandler]] = field(default_factory=lambda: defaultdict(list))

    def subscribe(self, event_type: type[Any], handler: Handler) -> Handler:
        if handler not in self._handlers[event_type]:
            self._handlers[event_type].append(handler)
        return handler

    def unsubscribe(self, event_type: type[Any], handler: Handler) -> None:
        handlers = self._handlers.get(event_type, [])
        if handler in handlers:
            handlers.remove(handler)

    def handlers(self, event_type: type[Any]) -> tuple[Handler, ...]:
        return tuple(self._handlers.get(event_type, ()))

    def subscribe_async(self, event_type: type[Any], handler: AsyncHandler) -> AsyncHandler:
        if handler not in self._async[event_type]:
            self._async[event_type].append(handler)
        return handler

    def unsubscribe_async(self, event_type: type[Any], handler: AsyncHandler) -> None:
        handlers = self._async.get(event_type, [])
        if handler in handlers:
            handlers.remove(handler)

    async def dispatch(self, session: AsyncSession, event: Any) -> int:
        """Run the async subscribers (each in a savepoint of ``session``), then the plain
        ones. A failure is logged and swallowed; only that subscriber's writes roll back."""
        delivered = 0
        for handler in tuple(self._async.get(type(event), ())):
            try:
                async with session.begin_nested():
                    await handler(session, event)
            except Exception:
                log.exception("visit_event_handler_failed", event_type=type(event).__name__)
            else:
                delivered += 1
        return delivered + self.publish(event)

    def publish(self, event: Any) -> int:
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
    "AsyncHandler",
    "ConfirmationRequested",
    "Event",
    "EventBus",
    "Handler",
    "IntegrityEvent",
    "OverrideRequested",
    "VisitCheckedIn",
    "VisitCheckedOut",
    "VisitConfirmed",
    "VisitPhotoAdded",
    "bus",
]
