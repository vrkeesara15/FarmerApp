"""``GET /v1/policies/location`` and ``POST /v1/policies/location/accept`` (FA-011, VV-010).

Any authenticated user may read the policy and accept it (the app shows screen A05 on first
run for every staff role); duty itself is limited to field officers and cluster heads.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import require_roles
from farmerapp.location.schemas import PolicyAcceptanceOut
from farmerapp.policies import service
from farmerapp.policies.schemas import LocationPolicyOut, PolicyAcceptIn

router = APIRouter(prefix="/policies", tags=["policies"])

ALL_ROLES = tuple(UserRole)


@router.get(
    "/location",
    operation_id="getLocationPolicy",
    summary="The employee location policy the caller's tenant requires (text in 5 languages)",
    response_model=LocationPolicyOut,
)
async def get_location_policy(
    actor: Annotated[User, require_roles(*ALL_ROLES)], session: DbSession
) -> LocationPolicyOut:
    policy = await service.current_policy(session, actor.tenant_id)
    return LocationPolicyOut(version=policy.version, text_hash=policy.text_hash, text=policy.text)


@router.post(
    "/location/accept",
    operation_id="acceptLocationPolicy",
    summary="Record the caller's acceptance of the current location policy version",
    status_code=201,
    response_model=PolicyAcceptanceOut,
    responses=problem_responses((422, "policy_version_stale"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=201)
async def accept_location_policy(
    request: Request,
    body: PolicyAcceptIn,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> PolicyAcceptanceOut:
    return await service.accept_policy(session, actor, body, now=services.clock.now())


__all__ = ["ALL_ROLES", "router"]
