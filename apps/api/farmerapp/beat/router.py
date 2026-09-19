"""``/v1/me/beat`` — FA-018 the field officer's own beat plan (read, reorder / add / remove).

Field officers only (the plan is of the farmers they registered); every other role is 403.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query

from farmerapp.api.errors import problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.beat import service
from farmerapp.beat.schemas import BeatPlanOut, BeatPlanUpdate

router = APIRouter(prefix="/me", tags=["beat"])

DayParam = Annotated[date, Query(alias="date", description="The IST day (YYYY-MM-DD).")]


@router.get(
    "/beat",
    operation_id="getMyBeatPlan",
    summary="The caller's beat plan for a day (generated at 06:00 IST, or on first read)",
    response_model=BeatPlanOut,
    responses=problem_responses((404, "beat_plan_not_found")),
)
async def get_my_beat(
    actor: Annotated[User, require_roles(Role.FIELD_OFFICER)],
    session: DbSession,
    services: Services,
    day: DayParam,
) -> BeatPlanOut:
    return await service.my_plan(session, actor, day, now=services.clock.now())


@router.put(
    "/beat",
    operation_id="updateMyBeatPlan",
    summary="Reorder, add and remove stops (the whole ordered list)",
    response_model=BeatPlanOut,
    responses=problem_responses((409, "version_conflict"), (422, "beat_item_unknown")),
)
async def put_my_beat(
    body: BeatPlanUpdate,
    actor: Annotated[User, require_roles(Role.FIELD_OFFICER)],
    session: DbSession,
    services: Services,
    day: DayParam,
) -> BeatPlanOut:
    return await service.update_plan(session, actor, day, body, now=services.clock.now())


__all__ = ["router"]
