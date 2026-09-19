"""``/v1/analytics/*`` — read-only dashboards for the console (AN-001 .. AN-003, AN-011,
WC-001 .. WC-004). See ``docs/prs/M4-analytics-api.md`` for the payloads.

Roles per route (SPEC 2.6; anything else is 403 ``forbidden``):

====================================== =======================================================
route                                  roles
====================================== =======================================================
``GET /analytics/owner-home``          owner, director, tenant admin, auditor ("All stores
                                       KPIs": read), cluster head (own cluster), store manager
                                       (own store)
``GET /analytics/field-team``,         the above plus the field officer (own row only);
``GET /analytics/officers/{id}``       store managers never get location-derived figures
``GET /analytics/officers/{id}/``      owner, director, tenant admin, auditor, cluster head
``day-replay``                         (own cluster), the officer themself ("Officer location
                                       track"; never store managers or other officers)
``GET /analytics/farmers``,            owner, director, tenant admin, auditor, cluster head,
``GET /analytics/farmers/{id}/360``    store manager, field officer (own farmers)
``GET /analytics/stores``,             owner, director, tenant admin, auditor, accountant
``GET /analytics/stores/{id}``         (finance), cluster head, store manager (own store)
====================================== =======================================================
"""

from __future__ import annotations

import uuid
from dataclasses import replace
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from farmerapp.analytics import farmers as farmer_views
from farmerapp.analytics import field_team as team_views
from farmerapp.analytics import stores as store_views
from farmerapp.analytics.filters import Filters, resolve_scope
from farmerapp.analytics.owner_home import owner_home
from farmerapp.analytics.ports import FlagCountsPort, get_flag_counts
from farmerapp.analytics.replay import day_replay
from farmerapp.analytics.schemas import (
    DayReplayOut,
    Farmer360Out,
    FarmerDirectoryOut,
    FieldTeamOut,
    OfficerProfileOut,
    OwnerHomeOut,
    StoreDetailOut,
    StoreListOut,
)
from farmerapp.api.errors import problem_responses
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.location.router import TRACK_ROLES, visible_officer

router = APIRouter(prefix="/analytics", tags=["analytics"])

OWNER_HOME_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
)
FIELD_TEAM_ROLES = (*OWNER_HOME_ROLES, Role.FIELD_OFFICER)
FARMER_ROLES = FIELD_TEAM_ROLES
STORE_ROLES = (*OWNER_HOME_ROLES, Role.ACCOUNTANT)

FlagPort = Annotated[FlagCountsPort, Depends(get_flag_counts)]
FILTER_PROBLEMS = (
    (404, "not_found"),
    (422, "invalid_date_range"),
    (422, "invalid_filter_combination"),
    (422, "validation_error"),
)


@router.get(
    "/owner-home",
    operation_id="getOwnerHome",
    summary="Owner home: KPI row with targets, last year and trends, store map, officers, flags",
    response_model=OwnerHomeOut,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def get_owner_home(
    actor: Annotated[User, require_roles(*OWNER_HOME_ROLES)],
    session: DbSession,
    filters: Filters,
    flags: FlagPort,
) -> OwnerHomeOut:
    scope = await resolve_scope(session, actor, filters)
    return await owner_home(session, scope, flags)


@router.get(
    "/field-team",
    operation_id="getFieldTeam",
    summary="Field team scorecard: one ranked row per officer with a weekly sparkline",
    response_model=FieldTeamOut,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def get_field_team(
    actor: Annotated[User, require_roles(*FIELD_TEAM_ROLES)],
    session: DbSession,
    filters: Filters,
    flags: FlagPort,
) -> FieldTeamOut:
    scope = await resolve_scope(session, actor, filters)
    return await team_views.field_team(session, scope, flags)


@router.get(
    "/officers/{id}",
    operation_id="getOfficerProfile",
    summary="Officer profile: scorecard, duty days and recent visits over the range",
    response_model=OfficerProfileOut,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def get_officer_profile(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*FIELD_TEAM_ROLES)],
    session: DbSession,
    filters: Filters,
    flags: FlagPort,
) -> OfficerProfileOut:
    scope = await resolve_scope(session, actor, replace(filters, officer_id=None))
    return await team_views.officer_profile(session, scope, id, flags)


@router.get(
    "/officers/{id}/day-replay",
    operation_id="getOfficerDayReplay",
    summary="Officer day replay: track, stops, gaps, visits with proof, timeline, km",
    response_model=DayReplayOut,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def get_day_replay(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*TRACK_ROLES)],
    session: DbSession,
    filters: Filters,
    day: Annotated[date, Query(alias="date", description="The IST day to replay (YYYY-MM-DD).")],
) -> DayReplayOut:
    officer = await visible_officer(session, actor, id)
    scope = await resolve_scope(session, actor, replace(filters, officer_id=None))
    return await day_replay(session, officer, day, scope.echo())


@router.get(
    "/farmers",
    operation_id="listAnalyticsFarmers",
    summary="Farmers directory: search, filters, sort, cursor; last visit / purchase, credit",
    response_model=FarmerDirectoryOut,
    responses=problem_responses(*FILTER_PROBLEMS, (400, "invalid_cursor"), (422, "invalid_sort")),
)
async def list_farmers(
    actor: Annotated[User, require_roles(*FARMER_ROLES)],
    session: DbSession,
    filters: Filters,
    q: Annotated[
        str | None,
        Query(max_length=100, description="Name or village contains; 4 digits: phone last 4."),
    ] = None,
    district: Annotated[str | None, Query(max_length=80)] = None,
    stage: Annotated[str | None, Query(max_length=16, description="Crop stage.")] = None,
    credit_risk: Annotated[farmer_views.Risk | None, Query()] = None,
    last_visit: Annotated[farmer_views.LastVisit | None, Query()] = None,
    sort: Annotated[
        str, Query(description="name, last_visit, last_purchase, ltv, balance, overdue; -desc.")
    ] = "name",
    cursor: Annotated[str | None, Query(description="Opaque cursor from `next_cursor`.")] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> FarmerDirectoryOut:
    scope = await resolve_scope(session, actor, filters)
    return await farmer_views.directory(
        session,
        scope,
        q=q,
        district=district,
        stage=stage,
        risk=credit_risk,
        last_visit=last_visit,
        sort=sort,
        cursor=cursor,
        limit=limit,
    )


@router.get(
    "/farmers/{id}/360",
    operation_id="getFarmer360",
    summary="Farmer 360: profile, farms, crops, visits, orders, khata, consent, app usage, LTV",
    response_model=Farmer360Out,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def get_farmer_360(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*FARMER_ROLES)],
    session: DbSession,
    filters: Filters,
) -> Farmer360Out:
    # A profile is addressed by id: only the role scope applies, not the list narrowing.
    base = replace(filters, cluster_id=None, store_id=None, officer_id=None, crop_id=None)
    scope = await resolve_scope(session, actor, base)
    return await farmer_views.farmer_360(session, scope, id)


@router.get(
    "/stores",
    operation_id="listAnalyticsStores",
    summary="Stores: sales, margin, stock value, credit book and last day-close variance",
    response_model=StoreListOut,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def list_stores(
    actor: Annotated[User, require_roles(*STORE_ROLES)],
    session: DbSession,
    filters: Filters,
) -> StoreListOut:
    scope = await resolve_scope(session, actor, filters)
    return await store_views.store_list(session, scope)


@router.get(
    "/stores/{id}",
    operation_id="getAnalyticsStore",
    summary="Store detail: category and brand sales, stock, credit ageing, day closes, P&L",
    response_model=StoreDetailOut,
    responses=problem_responses(*FILTER_PROBLEMS),
)
async def get_store(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*STORE_ROLES)],
    session: DbSession,
    filters: Filters,
) -> StoreDetailOut:
    scope = await resolve_scope(session, actor, replace(filters, store_id=None))
    return await store_views.store_detail(session, scope, id)


__all__ = [
    "FARMER_ROLES",
    "FIELD_TEAM_ROLES",
    "OWNER_HOME_ROLES",
    "STORE_ROLES",
    "router",
]
