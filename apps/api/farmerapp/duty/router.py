"""``/v1/duty/*`` — the REST twins of the ``duty_session`` sync ops (FA-010, VV-001, VV-007).

Field officers and cluster heads (who also go on duty) only; every other role is 403. A
session is always the caller's own: ``GET /v1/duty-sessions`` (``location/router.py``) is
the scoped listing for managers.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.duty import service
from farmerapp.duty.schemas import DutyEndIn, DutyPolicyOut, DutyStartIn, DutyStatusOut
from farmerapp.location.schemas import DutySessionOut
from farmerapp.policies.service import settings_for

router = APIRouter(prefix="/duty", tags=["duty"])

DUTY_ROLES = (Role.FIELD_OFFICER, Role.CLUSTER_HEAD)


@router.post(
    "/start",
    operation_id="startDuty",
    summary="Start a duty session (needs the current location policy accepted)",
    status_code=201,
    response_model=DutySessionOut,
    responses=problem_responses(
        (409, "duty_already_active"),
        (422, "policy_not_accepted"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=201)
async def start_duty(
    request: Request,
    body: DutyStartIn,
    actor: Annotated[User, require_roles(*DUTY_ROLES)],
    session: DbSession,
    services: Services,
) -> DutySessionOut:
    return await service.start_duty(session, actor, body, now=services.clock.now())


@router.post(
    "/end",
    operation_id="endDuty",
    summary="End the caller's open duty session; km and stops are computed from the points",
    response_model=DutySessionOut,
    responses=problem_responses((409, "no_active_duty"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=200)
async def end_duty(
    request: Request,
    body: DutyEndIn,
    actor: Annotated[User, require_roles(*DUTY_ROLES)],
    session: DbSession,
    services: Services,
) -> DutySessionOut:
    return await service.end_duty(session, actor, body, now=services.clock.now())


@router.get(
    "/current",
    operation_id="getCurrentDuty",
    summary="The caller's open duty session (null when off duty) and their policy state",
    response_model=DutyStatusOut,
)
async def current_duty(
    actor: Annotated[User, require_roles(*DUTY_ROLES)], session: DbSession
) -> DutyStatusOut:
    return await service.status(session, actor)


@router.get(
    "/policy",
    operation_id="getDutyPolicy",
    summary="VV-001 sampling policy for the caller's tenant",
    response_model=DutyPolicyOut,
)
async def duty_policy(
    actor: Annotated[User, require_roles(*DUTY_ROLES)], session: DbSession
) -> DutyPolicyOut:
    return service.sampling_policy(await settings_for(session, actor.tenant_id))


__all__ = ["DUTY_ROLES", "router"]
