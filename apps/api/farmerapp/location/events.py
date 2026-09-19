"""In-process domain events of duty and location ingest (FA-010, VV-001, FA-028).

Same contract as ``farmerapp.visits.events`` (the bus class is shared): the write path
flushes its rows, then ``await bus.dispatch(session, event)`` runs the database subscribers in
its transaction, each in a savepoint (a failing subscriber never rolls back the duty start or
the batch).

* ``DutyStarted`` — FA-010: a duty session began; carries the FA-028 integrity flags the
  device reported at the start. VA-E01 subscribes (topic ``duty.started``).
* ``LocationBatchIngested`` — a batch of on-duty points was stored (REST twin or the sync
  op; only when at least one point was accepted). VA-E01 / VA-E02 subscribe (topic
  ``location.batch``, the same name as the Pub/Sub topic the worker handles).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

from farmerapp.visits.events import EventBus


@dataclass(frozen=True)
class DutyStarted:
    tenant_id: uuid.UUID
    duty_session_id: uuid.UUID
    officer_id: uuid.UUID
    at: datetime


@dataclass(frozen=True)
class LocationBatchIngested:
    tenant_id: uuid.UUID
    duty_session_id: uuid.UUID
    officer_id: uuid.UUID
    accepted: int
    clock_drift_s: int
    at: datetime


#: The process-wide bus of the duty / location write paths.
bus = EventBus()

__all__ = ["DutyStarted", "LocationBatchIngested", "bus"]
