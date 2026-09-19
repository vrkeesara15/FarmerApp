"""FA-024 x WC-009: the ``IncentivePort`` over the incentive rules engine.

``GET /v1/me/performance`` (FA-024) shows the incentive an officer earned over the period it
reports on, and reads it only through ``farmerapp.performance.ports.IncentivePort``. This is
the WC-009 adapter: it delegates to ``farmerapp.incentives.service.incentive_for``, which
returns the frozen payout for a closed calendar month and a live preview with the active rule
set otherwise. The port's ``first`` / ``last`` are inclusive IST days; ``incentive_for`` takes
``period_end`` exclusive, hence the extra day.

``None`` (not ``0``) stays the answer when no rule set is active, so the app keeps showing
"--" rather than a payout the tenant never configured.
"""

from __future__ import annotations

import uuid
from datetime import date, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.incentives.service import incentive_for


class ServiceIncentives:
    """Implements ``farmerapp.performance.ports.IncentivePort``."""

    async def earned_paise(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        officer_id: uuid.UUID,
        first: date,
        last: date,
    ) -> int | None:
        result = await incentive_for(
            session,
            tenant_id=tenant_id,
            officer_id=officer_id,
            period_start=first,
            period_end=last + timedelta(days=1),
        )
        return None if result is None else result.amount_paise


#: The instance the API registers on ``app.state.incentives``.
SERVICE_INCENTIVES = ServiceIncentives()

__all__ = ["SERVICE_INCENTIVES", "ServiceIncentives"]
