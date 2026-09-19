"""``/v1/travel/*`` — FA-023 claims and the monthly statement.

============================================ ================================================
route                                        roles
============================================ ================================================
``POST /travel/claims``                      field officer, cluster head (who go on duty)
``GET /travel/claims``                       + owner, director, tenant admin, auditor,
``GET /travel/claims/{id}``                  accountant (finance); scoped to the staff the
``GET /travel/statement``                    caller may see (own / own cluster / tenant)
``POST /travel/claims/{id}/approve|reject``  cluster head (own cluster), owner, director,
                                             tenant admin; never the claim's own officer
============================================ ================================================
"""

from __future__ import annotations

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request

from farmerapp.analytics.filters import today_ist
from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.travel import service
from farmerapp.travel.schemas import (
    ClaimDecisionIn,
    TravelClaimIn,
    TravelClaimOut,
    TravelClaimPage,
    TravelStatementOut,
)
from farmerapp.uploads.blobstore import BlobStore

router = APIRouter(prefix="/travel", tags=["travel"])

DUTY_ROLES = (Role.FIELD_OFFICER, Role.CLUSTER_HEAD)
READ_ROLES = (
    *DUTY_ROLES,
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
)
APPROVE_ROLES = (Role.CLUSTER_HEAD, Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)


def _blobs(request: Request) -> BlobStore:
    blobs: BlobStore = request.app.state.blobs
    return blobs


@router.post(
    "/claims",
    operation_id="submitTravelClaim",
    summary="Submit an expense claim (fuel / bus / other) with its receipt photo",
    status_code=201,
    response_model=TravelClaimOut,
    responses=problem_responses(
        (404, "not_found"),
        (422, "claim_date_invalid"),
        (422, "invalid_blob"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=201)
async def submit_claim(
    request: Request,
    body: TravelClaimIn,
    actor: Annotated[User, require_roles(*DUTY_ROLES)],
    session: DbSession,
    services: Services,
) -> TravelClaimOut:
    now = services.clock.now()
    claim, _ = await service.submit_claim(
        session, actor, body, blobs=_blobs(request), now=now, today=today_ist(now)
    )
    return TravelClaimOut.from_row(claim)


@router.get(
    "/claims",
    operation_id="listTravelClaims",
    summary="Expense claims the caller may see (own / own cluster / tenant), oldest first",
    response_model=TravelClaimPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_claims(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    status: Annotated[
        Literal["submitted", "approved", "rejected"] | None, Query(description="Filter.")
    ] = None,
    officer_id: Annotated[uuid.UUID | None, Query(description="One officer.")] = None,
) -> TravelClaimPage:
    return await service.list_claims(session, actor, page, status=status, officer_id=officer_id)


@router.get(
    "/claims/{id}",
    operation_id="getTravelClaim",
    summary="One expense claim",
    response_model=TravelClaimOut,
    responses=problem_responses((404, "not_found")),
)
async def get_claim(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> TravelClaimOut:
    return TravelClaimOut.from_row(await service.visible_claim(session, actor, id))


async def _decide(
    session: DbSession,
    actor: User,
    id: uuid.UUID,
    body: ClaimDecisionIn,
    services: Services,
    *,
    approve: bool,
) -> TravelClaimOut:
    claim = await service.decide_claim(
        session, actor, id, approve=approve, note=body.note, now=services.clock.now()
    )
    return TravelClaimOut.from_row(claim)


@router.post(
    "/claims/{id}/approve",
    operation_id="approveTravelClaim",
    summary="Approve a submitted claim (cluster head of the officer's cluster)",
    response_model=TravelClaimOut,
    responses=problem_responses((404, "not_found"), (409, "claim_not_pending")),
)
async def approve_claim(
    id: uuid.UUID,
    body: ClaimDecisionIn,
    actor: Annotated[User, require_roles(*APPROVE_ROLES)],
    session: DbSession,
    services: Services,
) -> TravelClaimOut:
    return await _decide(session, actor, id, body, services, approve=True)


@router.post(
    "/claims/{id}/reject",
    operation_id="rejectTravelClaim",
    summary="Reject a submitted claim with a note",
    response_model=TravelClaimOut,
    responses=problem_responses((404, "not_found"), (409, "claim_not_pending")),
)
async def reject_claim(
    id: uuid.UUID,
    body: ClaimDecisionIn,
    actor: Annotated[User, require_roles(*APPROVE_ROLES)],
    session: DbSession,
    services: Services,
) -> TravelClaimOut:
    return await _decide(session, actor, id, body, services, approve=False)


@router.get(
    "/statement",
    operation_id="getTravelStatement",
    summary="Monthly travel statement: daily km and allowance, claims, payable total",
    response_model=TravelStatementOut,
    responses=problem_responses(
        (404, "not_found"), (422, "invalid_month"), (422, "officer_required")
    ),
)
async def get_statement(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    month: Annotated[str, Query(description="YYYY-MM (IST).", pattern=r"^\d{4}-\d{2}$")],
    officer_id: Annotated[
        uuid.UUID | None, Query(description="Officer (default: the caller on duty).")
    ] = None,
) -> TravelStatementOut:
    return await service.statement(session, actor, month=month, officer_id=officer_id)


__all__ = ["router"]
