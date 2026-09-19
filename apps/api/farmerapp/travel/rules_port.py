"""FA-023 x VA-E07: the ``TravelClaimPort`` over the ``travel_claim`` table.

The rules package reads TA claims through ``farmerapp.rules.ports.TravelClaimPort``; this is
the travel package's adapter, registered at startup (``register()``: the API app and the
worker's event path). A claim carries money, not km: the km it implies is its amount at the
tenant's ``ta_rate_per_km_paise`` (``amount_paise / rate``, two decimals), which VA-E07
compares with the processed duty km (VV-006) of the claim's IST day. A tenant without a rate
(0) implies no km: its claims are not returned, so the rule never judges them.

The subscription of VA-E07 to ``TravelClaimSubmitted`` lives with the other event seams in
``farmerapp.rules.events.register``.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.rules import ports
from farmerapp.tenants.settings import get_tenant_settings
from farmerapp.travel.models import TravelClaim

CENT = Decimal("0.01")


def implied_km(amount_paise: int, rate_per_km_paise: int) -> Decimal | None:
    """The km a claim's amount pays for at the tenant's TA rate (None without a rate)."""
    if rate_per_km_paise <= 0:
        return None
    return (Decimal(amount_paise) / Decimal(rate_per_km_paise)).quantize(
        CENT, rounding=ROUND_HALF_UP
    )


class DbTravelClaims:
    """Submitted claims of the tenant, read in the rule's (RLS-bound) session."""

    async def claims(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        *,
        claim_ids: Sequence[uuid.UUID] | None = None,
        submitted_since: datetime | None = None,
    ) -> list[ports.TravelClaim]:
        stmt = select(TravelClaim).where(
            TravelClaim.tenant_id == tenant_id, TravelClaim.deleted_at.is_(None)
        )
        if claim_ids is not None:
            if not claim_ids:
                return []
            stmt = stmt.where(TravelClaim.id.in_(claim_ids))
        if submitted_since is not None:
            stmt = stmt.where(TravelClaim.created_at >= submitted_since)
        rows = (await session.execute(stmt.order_by(TravelClaim.created_at))).scalars().all()
        if not rows:
            return []
        rate = (await get_tenant_settings(session, tenant_id)).ta_rate_per_km_paise
        out: list[ports.TravelClaim] = []
        for row in rows:
            km = implied_km(row.amount_paise, rate)
            if km is None:
                continue
            out.append(
                ports.TravelClaim(
                    tenant_id=row.tenant_id,
                    id=row.id,
                    officer_id=row.officer_id,
                    day=row.claim_date,
                    claimed_km=km,
                    submitted_at=row.created_at,
                )
            )
        return out


def register() -> None:
    """Register the adapter process-wide (idempotent; tests swap it with ``override_ports``)."""
    if not isinstance(ports.get_ports().travel_claims, DbTravelClaims):
        ports.set_ports(travel_claims=DbTravelClaims())


__all__ = ["DbTravelClaims", "implied_km", "register"]
