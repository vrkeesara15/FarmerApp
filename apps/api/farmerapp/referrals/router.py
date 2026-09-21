"""FM-013 referral routes.

Farmer app (F70 "Me" -> Refer a friend):

* ``GET  /v1/me/referral`` — the farmer's own code, share link, reward and their referrals.
* ``POST /v1/me/referral/invites`` — record an invite about to be shared (``pending``).
* ``POST /v1/me/referral/claim`` — the invited farmer applies the code from the invite link
  (the farmer app never asks anyone to type it: NF-010).

Console (Referrals per store):

* ``GET   /v1/referrals`` / ``GET /v1/referrals/summary`` — owner, director, tenant admin,
  auditor, cluster head, store manager (own store only).
* ``POST  /v1/referrals/{id}/reward`` — store manager (own store), tenant admin, owner.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, status
from sqlalchemy import select

from farmerapp.advisory.calendar import own_farmer
from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.referrals import service
from farmerapp.referrals.models import Referral, ReferralSource, ReferralStatus
from farmerapp.referrals.schemas import (
    SHARE_LINK_TEMPLATE,
    MyReferralOut,
    ReferralClaimIn,
    ReferralInviteIn,
    ReferralListOut,
    ReferralOut,
    ReferralRewardIn,
    ReferralSummaryOut,
    StoreReferralsOut,
)
from farmerapp.tenants.settings import get_tenant_settings

me_router = APIRouter(prefix="/me/referral", tags=["referrals"])
router = APIRouter(prefix="/referrals", tags=["referrals"])

READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
)
REWARD_ROLES = (Role.OWNER, Role.TENANT_ADMIN, Role.STORE_MANAGER)

_CLAIM_PROBLEMS = (
    (404, "not_found"),
    (409, "referral_already_attributed"),
    (422, "referral_code_unknown"),
    (422, "referral_disabled"),
    (422, "referral_self"),
    (422, "referral_window_closed"),
)


# --------------------------------------------------------------------------- farmer app
@me_router.get(
    "",
    operation_id="getMyReferral",
    summary="FM-013: the farmer's invite code, share link, reward and referrals",
    response_model=MyReferralOut,
    responses=problem_responses((404, "not_found")),
)
async def my_referral(
    actor: Annotated[User, require_roles(Role.FARMER)], session: DbSession
) -> MyReferralOut:
    farmer = await own_farmer(session, actor)
    code = await service.ensure_code(session, farmer)
    settings = (await get_tenant_settings(session, actor.tenant_id)).referral
    rows = await service.my_referrals(session, farmer)
    return MyReferralOut(
        farmer_id=farmer.id,
        code=code,
        share_link=SHARE_LINK_TEMPLATE.format(code=code),
        enabled=settings.enabled,
        referrer_reward_paise=settings.referrer_reward_paise,
        store_reward_paise=settings.store_reward_paise,
        reward_note=settings.reward_note,
        invited=sum(1 for r in rows if r.status == ReferralStatus.PENDING),
        attributed=sum(1 for r in rows if r.status == ReferralStatus.ATTRIBUTED),
        rewarded=sum(1 for r in rows if r.status == ReferralStatus.REWARDED),
        referrals=[ReferralOut.model_validate(r) for r in rows],
    )


@me_router.post(
    "/invites",
    operation_id="createReferralInvite",
    summary="FM-013: record an invite the farmer is about to share",
    status_code=status.HTTP_201_CREATED,
    response_model=ReferralOut,
    responses=problem_responses(
        (404, "not_found"), (422, "referral_disabled"), (422, "referral_self")
    ),
)
async def create_invite(
    body: ReferralInviteIn,
    actor: Annotated[User, require_roles(Role.FARMER)],
    session: DbSession,
    services: Services,
) -> ReferralOut:
    farmer = await own_farmer(session, actor)
    row = await service.create_invite(
        session, referrer=farmer, phone=body.phone, now=services.clock.now()
    )
    return ReferralOut.model_validate(row)


@me_router.post(
    "/claim",
    operation_id="claimReferral",
    summary="FM-013: the invited farmer applies the code from the invite link",
    status_code=status.HTTP_201_CREATED,
    response_model=ReferralOut,
    responses=problem_responses(*_CLAIM_PROBLEMS),
)
async def claim_referral(
    body: ReferralClaimIn,
    actor: Annotated[User, require_roles(Role.FARMER)],
    session: DbSession,
    services: Services,
) -> ReferralOut:
    farmer = await own_farmer(session, actor)
    row = await service.attribute(
        session,
        invited=farmer,
        code=body.code,
        source=ReferralSource.FARMER_APP,
        now=services.clock.now(),
    )
    return ReferralOut.model_validate(row)


# --------------------------------------------------------------------------- console
@router.get(
    "",
    operation_id="listReferrals",
    summary="FM-013: referrals, newest first (a store manager sees their own store)",
    response_model=ReferralListOut,
)
async def list_referrals(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    store_id: uuid.UUID | None = None,
    referral_status: Annotated[ReferralStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ReferralListOut:
    rows, total = await service.list_referrals(
        session,
        actor,
        store_id=store_id,
        status=referral_status.value if referral_status else None,
        limit=limit,
        offset=offset,
    )
    return ReferralListOut(items=[ReferralOut.model_validate(r) for r in rows], total=total)


@router.get(
    "/summary",
    operation_id="getReferralSummary",
    summary="FM-013: referrals per store for the console",
    response_model=ReferralSummaryOut,
)
async def referral_summary(
    actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> ReferralSummaryOut:
    stores = await service.summary_by_store(session, actor)
    return ReferralSummaryOut(
        stores=[
            StoreReferralsOut(
                store_id=s.store_id,
                store_code=s.store_code,
                store_name=s.store_name,
                pending=s.pending,
                attributed=s.attributed,
                rewarded=s.rewarded,
                total=s.total,
                referrer_reward_paise=s.referrer_reward_paise,
                store_reward_paise=s.store_reward_paise,
            )
            for s in stores
        ],
        pending=sum(s.pending for s in stores),
        attributed=sum(s.attributed for s in stores),
        rewarded=sum(s.rewarded for s in stores),
    )


@router.post(
    "/{id}/reward",
    operation_id="rewardReferral",
    summary="FM-013: mark an attributed referral as rewarded",
    response_model=ReferralOut,
    responses=problem_responses((404, "not_found"), (409, "referral_not_attributed")),
)
async def reward_referral(
    id: uuid.UUID,
    body: ReferralRewardIn,
    actor: Annotated[User, require_roles(*REWARD_ROLES)],
    session: DbSession,
    services: Services,
) -> ReferralOut:
    row = await session.scalar(
        select(Referral).where(
            Referral.id == id,
            Referral.tenant_id == actor.tenant_id,
            Referral.deleted_at.is_(None),
        )
    )
    if row is None or (
        UserRole(actor.role) == UserRole.STORE_MANAGER and row.store_id != actor.store_id
    ):
        raise NotFoundError("Referral not found.")
    updated = await service.reward(
        session, actor=actor, referral=row, note=body.note, now=services.clock.now()
    )
    return ReferralOut.model_validate(updated)


__all__ = ["me_router", "router"]
