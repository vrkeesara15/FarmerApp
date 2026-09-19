"""FA-023 domain events (same bus contract as ``farmerapp.visits.events``).

* ``TravelClaimSubmitted`` — an officer submitted an expense claim; carries the km the track
  processing computed for that day (``km_computed``, null when no processed duty) and the
  travel allowance already due for it, for VA-E07 (claims vs computed km). The rules agent
  subscribes with ``bus.subscribe_async(TravelClaimSubmitted, handler)``; the write path
  dispatches after the claim row is flushed (each subscriber in a savepoint).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal

from farmerapp.visits.events import EventBus


@dataclass(frozen=True)
class TravelClaimSubmitted:
    tenant_id: uuid.UUID
    claim_id: uuid.UUID
    officer_id: uuid.UUID
    claim_date: date
    claim_type: str
    amount_paise: int
    km_computed: Decimal | None
    ta_paise: int
    at: datetime


#: The process-wide bus of the travel write paths.
bus = EventBus()

__all__ = ["TravelClaimSubmitted", "bus"]
