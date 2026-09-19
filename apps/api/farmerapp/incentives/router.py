"""``/v1/targets``, ``/v1/incentive-rules``, ``/v1/incentives`` — WC-009 (console C90).

* Targets: owners, directors, tenant admins and cluster heads (own cluster's officers and
  stores) set monthly targets; the same plus auditors, accountants and store managers (own
  store) read them; a field officer reads their own.
* Rule sets: versioned JSON rules; owners, directors and tenant admins save and activate;
  auditors, accountants and cluster heads read.
* Payouts: the preview (frozen once the month is closed) for an officer in scope — a field
  officer only their own; ``POST /v1/incentives/preview`` evaluates an unsaved rule document
  (the rule editor); ``POST /v1/incentives/close`` freezes a month (step-up, SEC-028).
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import (
    DEFAULT_VISIBILITY,
    USER_SCOPE,
    Visibility,
    scope_filters,
    visible_store_filters,
)
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.incentives import service
from farmerapp.incentives.models import (
    IncentivePayout,
    IncentiveRuleSet,
    RuleSetStatus,
    SalesTarget,
    TargetSubject,
)
from farmerapp.incentives.schemas import (
    CloseIn,
    CloseOut,
    IncentiveOut,
    PayoutList,
    PreviewIn,
    RuleSetIn,
    RuleSetList,
    RuleSetOut,
    TargetList,
    TargetOut,
    TargetsIn,
)
from farmerapp.tenants.models import Store

targets_router = APIRouter(prefix="/targets", tags=["incentives"])
rules_router = APIRouter(prefix="/incentive-rules", tags=["incentives"])
router = APIRouter(prefix="/incentives", tags=["incentives"])

ADMIN_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)
TARGET_WRITE_ROLES = (*ADMIN_ROLES, Role.CLUSTER_HEAD)
TARGET_READ_ROLES = (
    *TARGET_WRITE_ROLES,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
)
RULE_READ_ROLES = (*ADMIN_ROLES, Role.AUDITOR, Role.ACCOUNTANT, Role.CLUSTER_HEAD)
PAYOUT_READ_ROLES = (*RULE_READ_ROLES, Role.STORE_MANAGER, Role.FIELD_OFFICER)
CLOSE_ROLES = (Role.OWNER, Role.DIRECTOR)

#: Officers whose targets / payouts a role sees (SPEC 2.6 staff scope; accountant: tenant).
OFFICER_VISIBILITY: Mapping[UserRole, Visibility] = {
    **DEFAULT_VISIBILITY,
    UserRole.AGRONOMIST: Visibility.NONE,
    UserRole.FARMER: Visibility.NONE,
}


def month_param(month: date) -> date:
    return service.month_start(month)


async def visible_officer(session: DbSession, actor: User, officer_id: uuid.UUID) -> User:
    officer = (
        await session.execute(
            select(User).where(
                User.id == officer_id,
                User.role == UserRole.FIELD_OFFICER.value,
                User.deleted_at.is_(None),
                *scope_filters(actor, USER_SCOPE, OFFICER_VISIBILITY),
            )
        )
    ).scalar_one_or_none()
    if officer is None:
        raise NotFoundError("Officer not found.")
    return officer


async def visible_target_store(session: DbSession, actor: User, store_id: uuid.UUID) -> Store:
    role = UserRole(actor.role)
    filters = (
        visible_store_filters(actor)
        if role not in (UserRole.FIELD_OFFICER,)
        else [Store.tenant_id == actor.tenant_id, Store.id == actor.store_id]
    )
    store = (
        await session.execute(
            select(Store).where(Store.id == store_id, Store.deleted_at.is_(None), *filters)
        )
    ).scalar_one_or_none()
    if store is None:
        raise NotFoundError("Store not found.")
    return store


async def _check_subject(
    session: DbSession, actor: User, subject_type: TargetSubject, subject_id: uuid.UUID
) -> None:
    if subject_type == TargetSubject.OFFICER:
        await visible_officer(session, actor, subject_id)
    else:
        await visible_target_store(session, actor, subject_id)


# --------------------------------------------------------------------------- targets
@targets_router.get(
    "",
    operation_id="listTargets",
    summary="Monthly targets of the officers and stores in the caller's scope",
    response_model=TargetList,
)
async def list_targets(
    actor: Annotated[User, require_roles(*TARGET_READ_ROLES)],
    session: DbSession,
    month: Annotated[date, Query(description="Any day of the month (YYYY-MM-DD).")],
    subject_type: Annotated[TargetSubject | None, Query()] = None,
) -> TargetList:
    first = month_param(month)
    officers = select(User.id).where(
        User.role == UserRole.FIELD_OFFICER.value,
        *scope_filters(actor, USER_SCOPE, OFFICER_VISIBILITY),
    )
    stores = (
        select(Store.id).where(*visible_store_filters(actor))
        if UserRole(actor.role) != UserRole.FIELD_OFFICER
        else select(Store.id).where(Store.id == actor.store_id)
    )
    stmt = select(SalesTarget).where(
        SalesTarget.tenant_id == actor.tenant_id,
        SalesTarget.month == first,
        SalesTarget.deleted_at.is_(None),
        (
            (SalesTarget.subject_type == TargetSubject.OFFICER.value)
            & SalesTarget.subject_id.in_(officers)
        )
        | (
            (SalesTarget.subject_type == TargetSubject.STORE.value)
            & SalesTarget.subject_id.in_(stores)
        ),
    )
    if subject_type is not None:
        stmt = stmt.where(SalesTarget.subject_type == subject_type.value)
    rows = (
        await session.execute(stmt.order_by(SalesTarget.subject_type, SalesTarget.subject_id))
    ).scalars()
    return TargetList(month=first, items=[TargetOut.from_row(t) for t in rows])


@targets_router.put(
    "",
    operation_id="upsertTargets",
    summary="Set monthly targets per officer / store (a null metric has no target)",
    response_model=TargetList,
    responses=problem_responses((404, "not_found")),
)
async def upsert_targets(
    body: TargetsIn,
    actor: Annotated[User, require_roles(*TARGET_WRITE_ROLES)],
    session: DbSession,
) -> TargetList:
    first = month_param(body.month)
    out: list[TargetOut] = []
    for item in body.items:
        await _check_subject(session, actor, item.subject_type, item.subject_id)
        row = await service.upsert_target(
            session,
            actor,
            month=first,
            subject_type=item.subject_type,
            subject_id=item.subject_id,
            values=item.model_dump(include=set(service.TARGET_FIELDS), exclude_unset=True),
        )
        out.append(TargetOut.from_row(row))
    return TargetList(month=first, items=out)


# --------------------------------------------------------------------------- rule sets
@rules_router.get(
    "",
    operation_id="listIncentiveRuleSets",
    summary="Incentive rule set versions, newest first",
    response_model=RuleSetList,
)
async def list_rule_sets(
    actor: Annotated[User, require_roles(*RULE_READ_ROLES)], session: DbSession
) -> RuleSetList:
    rows = (
        await session.execute(
            select(IncentiveRuleSet)
            .where(
                IncentiveRuleSet.tenant_id == actor.tenant_id,
                IncentiveRuleSet.deleted_at.is_(None),
            )
            .order_by(IncentiveRuleSet.rule_version.desc())
        )
    ).scalars()
    return RuleSetList(items=[RuleSetOut.from_row(r) for r in rows])


@rules_router.post(
    "",
    operation_id="createIncentiveRuleSet",
    summary="Save the rules as a new version (optionally activate it)",
    status_code=201,
    response_model=RuleSetOut,
    responses=problem_responses((422, "invalid_incentive_rules")),
)
async def create_rule_set(
    body: RuleSetIn,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    session: DbSession,
) -> RuleSetOut:
    row = await service.create_rule_set(
        session, actor, name=body.name, definition=body.definition, activate=body.activate
    )
    return RuleSetOut.from_row(row)


@rules_router.get(
    "/{id}",
    operation_id="getIncentiveRuleSet",
    summary="One incentive rule set version",
    response_model=RuleSetOut,
    responses=problem_responses((404, "not_found")),
)
async def get_rule_set(
    id: uuid.UUID, actor: Annotated[User, require_roles(*RULE_READ_ROLES)], session: DbSession
) -> RuleSetOut:
    return RuleSetOut.from_row(await service.get_rule_set(session, actor.tenant_id, id))


@rules_router.post(
    "/{id}/activate",
    operation_id="activateIncentiveRuleSet",
    summary="Make this version the active rules (the previous one is retired)",
    response_model=RuleSetOut,
    responses=problem_responses((404, "not_found")),
)
async def activate_rule_set(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    session: DbSession,
    services: Services,
) -> RuleSetOut:
    row = await service.get_rule_set(session, actor.tenant_id, id)
    if row.status != RuleSetStatus.ACTIVE.value:
        await service.activate_rule_set(session, actor, row, now=services.clock.now())
    return RuleSetOut.from_row(row)


# --------------------------------------------------------------------------- payouts
def _officer_or_self(actor: User, officer_id: uuid.UUID | None) -> uuid.UUID:
    if officer_id is not None:
        return officer_id
    if UserRole(actor.role) == UserRole.FIELD_OFFICER:
        return actor.id
    raise NotFoundError("Officer not found.", extra={"hint": "pass officer_id"})


@router.get(
    "/preview",
    operation_id="previewIncentive",
    summary="Payout preview of an officer for a month (frozen once the month is closed)",
    response_model=IncentiveOut,
    responses=problem_responses((404, "not_found"), (409, "no_active_incentive_rules")),
)
async def preview_incentive(
    actor: Annotated[User, require_roles(*PAYOUT_READ_ROLES)],
    session: DbSession,
    month: Annotated[date, Query(description="Any day of the month (YYYY-MM-DD).")],
    officer_id: Annotated[uuid.UUID | None, Query(description="Default: the caller.")] = None,
    rule_set_id: Annotated[
        uuid.UUID | None, Query(description="Evaluate this version instead of the active one.")
    ] = None,
) -> IncentiveOut:
    officer = await visible_officer(session, actor, _officer_or_self(actor, officer_id))
    rules = (
        await service.get_rule_set(session, actor.tenant_id, rule_set_id)
        if rule_set_id is not None
        else None
    )
    result = await service.preview(session, actor.tenant_id, officer.id, month, rules=rules)
    return IncentiveOut.from_result(result)


@router.post(
    "/preview",
    operation_id="previewIncentiveRules",
    summary="Evaluate an unsaved rule document for an officer and month (rule editor)",
    response_model=IncentiveOut,
    responses=problem_responses((404, "not_found"), (422, "invalid_incentive_rules")),
)
async def preview_rules(
    body: PreviewIn,
    actor: Annotated[User, require_roles(*ADMIN_ROLES)],
    session: DbSession,
) -> IncentiveOut:
    officer = await visible_officer(session, actor, body.officer_id)
    parsed = service.parse_definition(body.definition)
    draft = IncentiveRuleSet(
        tenant_id=actor.tenant_id,
        name="unsaved",
        rule_version=0,
        status=RuleSetStatus.DRAFT.value,
        definition=parsed.model_dump(mode="json", by_alias=True),
    )
    first = service.month_start(body.month)
    result = await service.compute(
        session, actor.tenant_id, officer.id, first, service.next_month(first), draft
    )
    return IncentiveOut.from_result(result)


@router.get(
    "/payouts",
    operation_id="listIncentivePayouts",
    summary="Frozen payouts of a closed month for the officers in scope",
    response_model=PayoutList,
)
async def list_payouts(
    actor: Annotated[User, require_roles(*PAYOUT_READ_ROLES)],
    session: DbSession,
    month: Annotated[date, Query(description="Any day of the month (YYYY-MM-DD).")],
) -> PayoutList:
    first = month_param(month)
    officers = select(User.id).where(*scope_filters(actor, USER_SCOPE, OFFICER_VISIBILITY))
    rows = (
        await session.execute(
            select(IncentivePayout)
            .where(
                IncentivePayout.tenant_id == actor.tenant_id,
                IncentivePayout.month == first,
                IncentivePayout.deleted_at.is_(None),
                IncentivePayout.officer_id.in_(officers),
            )
            .order_by(IncentivePayout.officer_id)
        )
    ).scalars()
    items = [IncentiveOut.from_result(service.frozen_result(p)) for p in rows]
    return PayoutList(month=first, items=items, total_paise=sum(i.amount_paise for i in items))


@router.post(
    "/close",
    operation_id="closeIncentiveMonth",
    summary="Freeze every officer's payout for an ended month (step-up; idempotent)",
    response_model=CloseOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        (401, "step_up_required"),
        (409, "no_active_incentive_rules"),
        (409, "incentive_month_open"),
    ),
)
async def close_month(
    body: CloseIn,
    actor: Annotated[User, require_roles(*CLOSE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> CloseOut:
    report = await service.close_month(
        session,
        tenant_id=actor.tenant_id,
        month=body.month,
        now=services.clock.now(),
        closed_by=actor.id,
    )
    return CloseOut(
        month=report.month,
        closed=len(report.closed),
        already_closed=report.already_closed,
        total_paise=report.total_paise,
        rule_version=report.rule_version,
    )


__all__ = ["router", "rules_router", "targets_router"]
