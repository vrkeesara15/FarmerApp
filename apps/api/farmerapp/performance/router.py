"""``GET /v1/me/performance`` — FA-024 the field officer's own KPIs over a period.

Computed by the console's own code path: the caller's analytics scope (``resolve_scope``,
level ``own``) and ``farmerapp.analytics.field_team.officer_profile`` — the same function
behind ``GET /v1/analytics/officers/{id}`` — so the numbers match the console for the same
officer and period by construction (``tests/performance/test_my_performance.py`` asserts it).
Definitions are SPEC 5.2 (``farmerapp.analytics.kpi``): verified visit = score >= 70,
confirmation rate = confirmed / all visits, sales = net of the fulfilled orders they placed,
collections = money they collected (paid / reconciled / cash in hand). Incentive earned comes
from the ``IncentivePort`` (``null`` until WC-009).
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from farmerapp.analytics import field_team
from farmerapp.analytics.filters import FiltersOut, analytics_filters, resolve_scope
from farmerapp.analytics.ports import FlagCountsPort, get_flag_counts
from farmerapp.api.errors import problem_responses
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.performance.ports import IncentivePort, get_incentives

router = APIRouter(prefix="/me", tags=["performance"])


class PerformanceOut(BaseModel):
    filters: FiltersOut
    officer_id: uuid.UUID
    from_: date = Field(alias="from", serialization_alias="from")
    to: date
    duty_days: int
    visits: int = Field(description="All visits checked in during the period.")
    verified_visits: int = Field(description="Visits with score >= 70 (VV-004 / SPEC 5.2).")
    verified_visits_per_day: float | None
    unique_farmers_reached: int
    farmers_added: int = Field(description="Farmers the officer registered in the period.")
    confirmation_rate: float | None = Field(description="Confirmed / all visits (0-1).")
    time_on_farm_s: int
    conversion_rate: float | None
    sales_net_paise: int = Field(description="Net sales of the orders they placed.")
    sales_orders: int
    collections_paise: int = Field(description="Money they collected.")
    km_per_day: float | None
    rank: int = Field(description="Always 1: the officer's own row (no ranking against others).")
    incentive_earned_paise: int | None = Field(
        description="Incentive earned in the period (WC-009); null until the rules exist."
    )

    model_config = {"populate_by_name": True}


@router.get(
    "/performance",
    operation_id="getMyPerformance",
    summary="The caller's KPIs for a period, computed exactly like the console",
    response_model=PerformanceOut,
    responses=problem_responses((422, "invalid_date_range")),
)
async def get_my_performance(
    actor: Annotated[User, require_roles(Role.FIELD_OFFICER)],
    session: DbSession,
    flags: Annotated[FlagCountsPort, Depends(get_flag_counts)],
    incentives: Annotated[IncentivePort, Depends(get_incentives)],
    from_: Annotated[
        date | None,
        Query(alias="from", description="First IST day (inclusive). Default: `to` - 29 days."),
    ] = None,
    to: Annotated[
        date | None, Query(description="Last IST day (inclusive). Default: today (IST).")
    ] = None,
) -> PerformanceOut:
    own = analytics_filters(from_=from_, to=to)
    scope = await resolve_scope(session, actor, own)
    profile = await field_team.officer_profile(session, scope, actor.id, flags)
    card = profile.scorecard
    return PerformanceOut(
        filters=scope.echo(),
        officer_id=actor.id,
        from_=own.from_,
        to=own.to,
        duty_days=card.duty_days,
        visits=card.visits,
        verified_visits=card.verified_visits,
        verified_visits_per_day=card.verified_visits_per_day,
        unique_farmers_reached=card.unique_farmers_reached,
        farmers_added=card.new_registrations,
        confirmation_rate=card.confirmation_rate,
        time_on_farm_s=card.time_on_farm_s,
        conversion_rate=card.conversion_rate,
        sales_net_paise=profile.sales_net_paise,
        sales_orders=profile.sales_orders,
        collections_paise=card.collections_paise,
        km_per_day=card.km_per_day,
        rank=card.rank,
        incentive_earned_paise=await incentives.earned_paise(
            session, actor.tenant_id, actor.id, own.from_, own.to
        ),
    )


__all__ = ["PerformanceOut", "router"]
