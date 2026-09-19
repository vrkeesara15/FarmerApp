"""``IncentivePort``: incentive earned by an officer over a period (WC-009 seam).

The targets and incentive rules engine (WC-009) lands later in M7. FA-024 reads the earned
incentive only through this port: ``NullIncentives`` answers ``None`` ("not configured") so
the app shows "--" rather than a fake zero. WC-009 registers its adapter on
``app.state.incentives``.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Protocol

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession


class IncentivePort(Protocol):
    async def earned_paise(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        officer_id: uuid.UUID,
        first: date,
        last: date,
    ) -> int | None: ...


class NullIncentives:
    """Until WC-009: no incentive rules, nothing earned (``None``, not 0)."""

    async def earned_paise(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        officer_id: uuid.UUID,
        first: date,
        last: date,
    ) -> int | None:
        return None


NULL_INCENTIVES = NullIncentives()


def get_incentives(request: Request) -> IncentivePort:
    port: IncentivePort = getattr(request.app.state, "incentives", NULL_INCENTIVES)
    return port


__all__ = ["NULL_INCENTIVES", "IncentivePort", "NullIncentives", "get_incentives"]
