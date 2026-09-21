"""``/v1/admin/*`` — WC-014 platform tenant administration.

Every route here is guarded by ``PlatformAdmin`` (``platform_admin`` *and* the platform
tenant) and every write also needs a step-up token (SEC-028): creating, re-planning,
suspending or archiving a tenant is the highest-privilege action in the system.

    GET    /v1/admin/plans                          the plan catalogue
    POST   /v1/admin/tenants                        create + provision (one call)
    GET    /v1/admin/tenants                        the registry
    GET    /v1/admin/tenants/{id}                   one tenant
    PATCH  /v1/admin/tenants/{id}                   plan, limits, contact, notes
    POST   /v1/admin/tenants/{id}/invite            OTP to the primary contact (follow-up)
    POST   /v1/admin/tenants/{id}/suspend|resume|archive
    GET    /v1/admin/tenants/{id}/usage             counters against the plan limits
    POST   /v1/admin/tenants/{id}/statements        generate the monthly statement
    GET    /v1/admin/tenants/{id}/statements        statements, newest first
    GET    /v1/admin/tenants/{id}/statements/{period}/csv

These are the only cross-tenant routes in the API. They reach a tenant's rows the same way a
job does — by binding that tenant with ``tenant_scope`` — never by bypassing RLS, of which
there is no mechanism.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Path, Response, status
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.db import audit
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.logging import get_logger
from farmerapp.platform_admin import billing
from farmerapp.platform_admin.deps import PLATFORM_OPENAPI, PlatformAdmin
from farmerapp.platform_admin.errors import UnknownPlanProblemError
from farmerapp.platform_admin.lifecycle import set_status
from farmerapp.platform_admin.models import (
    PLATFORM_TENANT_ID,
    BillingStatement,
    PlatformTenant,
    TenantStatus,
)
from farmerapp.platform_admin.plans import PLANS, merge_limits, plan_by_name
from farmerapp.platform_admin.provisioning import TenantSpec, provision_tenant
from farmerapp.platform_admin.schemas import (
    InviteOut,
    PlanList,
    PlanOut,
    StatementList,
    StatementOut,
    StatementRequest,
    StatusChange,
    TenantCreate,
    TenantCreated,
    TenantList,
    TenantOut,
    TenantUpdate,
    UsageMetricOut,
    UsageOut,
)
from farmerapp.platform_admin.state import invalidate
from farmerapp.platform_admin.usage import snapshot

log = get_logger("farmerapp.platform_admin")

router = APIRouter(prefix="/admin", tags=["platform admin"])

TenantIdPath = Annotated[uuid.UUID, Path(description="The tenant's id.")]
PeriodPath = Annotated[str, Path(pattern=r"^\d{4}-(0[1-9]|1[0-2])$", description="`YYYY-MM`.")]

_STEP_UP = (401, "step_up_required")
_OPENAPI = {**PLATFORM_OPENAPI, **STEP_UP_OPENAPI}


async def _registry_row(session: DbSession, tenant_id: uuid.UUID) -> PlatformTenant:
    row = (
        await session.execute(
            select(PlatformTenant).where(
                PlatformTenant.tenant_id == PLATFORM_TENANT_ID,
                PlatformTenant.subject_tenant_id == tenant_id,
                PlatformTenant.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("No such tenant.")
    return row


# --------------------------------------------------------------------------- plans
@router.get(
    "/plans",
    operation_id="listPlans",
    summary="The plan catalogue with its limits and overage prices",
    openapi_extra=PLATFORM_OPENAPI,
)
async def list_plans(_actor: PlatformAdmin) -> PlanList:
    return PlanList(items=[PlanOut.of(plan) for plan in PLANS.values()])


# --------------------------------------------------------------------------- tenants
@router.post(
    "/tenants",
    operation_id="createTenant",
    status_code=status.HTTP_201_CREATED,
    summary="Create and provision a tenant (WC-014)",
    responses=problem_responses(_STEP_UP, (409, "tenant_slug_taken"), (422, "unknown_plan")),
    openapi_extra=_OPENAPI,
)
async def create_tenant(
    body: TenantCreate, actor: PlatformAdmin, _step_up: StepUp, session: DbSession
) -> TenantCreated:
    spec = TenantSpec(
        name=body.name,
        slug=body.slug,
        plan=body.plan,
        region=body.region,
        primary_contact_name=body.primary_contact_name,
        primary_contact_phone=body.primary_contact_phone,
        languages=tuple(str(lang) for lang in body.languages),
        default_language=str(body.default_language),
        branding=body.branding.model_dump(mode="json"),
        plan_limits=body.plan_limits.model_dump(exclude_unset=True) if body.plan_limits else {},
        disabled_rules=tuple(body.disabled_rules),
        notes=body.notes,
    )
    result = await provision_tenant(session, spec)
    row = await _registry_row(session, result.tenant_id)
    audit.record(
        session,
        action="tenant.provision",
        entity="tenant",
        entity_id=result.tenant_id,
        tenant_id=PLATFORM_TENANT_ID,
        after={"slug": spec.slug, "plan": spec.plan, "created": dict(result.created)},
    )
    # Flush while the session is still bound to the platform tenant: the audit row belongs to
    # it, and a later flush under another binding would be refused by RLS.
    await session.flush()
    return TenantCreated.of(row, result)


@router.get(
    "/tenants",
    operation_id="listTenants",
    summary="Every tenant on the platform",
    openapi_extra=PLATFORM_OPENAPI,
)
async def list_tenants(
    _actor: PlatformAdmin, session: DbSession, tenant_status: TenantStatus | None = None
) -> TenantList:
    stmt = select(PlatformTenant).where(
        PlatformTenant.tenant_id == PLATFORM_TENANT_ID, PlatformTenant.deleted_at.is_(None)
    )
    if tenant_status is not None:
        stmt = stmt.where(PlatformTenant.status == tenant_status)
    rows = (await session.execute(stmt.order_by(PlatformTenant.slug))).scalars().all()
    return TenantList(items=[TenantOut.of(row) for row in rows])


@router.get(
    "/tenants/{id}",
    operation_id="getTenant",
    summary="One tenant's registry record",
    openapi_extra=PLATFORM_OPENAPI,
)
async def get_tenant(id: TenantIdPath, _actor: PlatformAdmin, session: DbSession) -> TenantOut:
    return TenantOut.of(await _registry_row(session, id))


@router.patch(
    "/tenants/{id}",
    operation_id="updateTenant",
    summary="Change a tenant's plan, limits, contact or notes",
    responses=problem_responses(_STEP_UP, (422, "unknown_plan")),
    openapi_extra=_OPENAPI,
)
async def update_tenant(
    id: TenantIdPath,
    body: TenantUpdate,
    _actor: PlatformAdmin,
    _step_up: StepUp,
    session: DbSession,
) -> TenantOut:
    row = await _registry_row(session, id)
    if body.plan is not None:
        try:
            plan_by_name(body.plan)
        except KeyError as exc:  # pragma: no cover - the schema validates first
            raise UnknownPlanProblemError(str(exc)) from exc
        row.plan = body.plan
    if body.name is not None:
        row.name = body.name
    if body.primary_contact_name is not None:
        row.primary_contact_name = body.primary_contact_name
    if body.notes is not None:
        row.notes = body.notes
    if body.plan_limits is not None:
        row.plan_limits = body.plan_limits.model_dump(exclude_unset=True)
    # Flush the registry (and its FA-006 audit row) while still bound to the platform tenant;
    # the block below rebinds, and a deferred flush there would be refused by RLS.
    await session.flush()
    # The tenant row carries what the runtime reads; both are written in this transaction.
    async with tenant_scope(session, id):
        tenant = await session.get(Tenant, id)
        if tenant is None:  # pragma: no cover
            raise NotFoundError("No such tenant.")
        tenant.plan = row.plan
        tenant.plan_limits = dict(row.plan_limits or {})
        if body.name is not None:
            tenant.name = body.name
        await session.flush()
    await session.flush()
    invalidate(id)
    return TenantOut.of(row)


@router.post(
    "/tenants/{id}/invite",
    operation_id="inviteTenantAdmin",
    summary="Send the primary contact their login code (the follow-up invite)",
    responses=problem_responses(_STEP_UP, (404, "not_found")),
    openapi_extra=_OPENAPI,
)
async def invite_tenant_admin(
    id: TenantIdPath,
    _actor: PlatformAdmin,
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> InviteOut:
    from farmerapp.auth.models import User

    row = await _registry_row(session, id)
    if row.primary_contact_user_id is None:
        raise NotFoundError("This tenant has no primary contact.")
    async with tenant_scope(session, id):
        admin = await session.get(User, row.primary_contact_user_id)
        if admin is None:
            raise NotFoundError("This tenant has no primary contact.")
        phone = admin.phone
    result = await services.otp.send(session, phone=phone)
    # ``otp.send`` binds the invited tenant on the session; put the platform tenant back so
    # the rest of the request (audit row, response) stays in the caller's scope.
    from farmerapp.db.session import set_tenant

    await set_tenant(session, PLATFORM_TENANT_ID)
    audit.record(
        session,
        action="tenant.invite",
        entity="tenant",
        entity_id=id,
        tenant_id=PLATFORM_TENANT_ID,
        after={"slug": row.slug, "user_id": str(row.primary_contact_user_id)},
    )
    await session.flush()
    challenge = result.challenge
    return InviteOut(
        tenant_id=id,
        user_id=row.primary_contact_user_id,
        channel=str(challenge.channel),
        resends_left=result.resends_left,
    )


def _status_route(name: str, target: TenantStatus, summary: str) -> None:
    @router.post(
        f"/tenants/{{id}}/{name}",
        operation_id=f"{name}Tenant",
        summary=summary,
        responses=problem_responses(_STEP_UP, (409, "invalid_tenant_state")),
        openapi_extra=_OPENAPI,
        name=f"{name}_tenant",
    )
    async def _change(
        id: TenantIdPath,
        actor: PlatformAdmin,
        _step_up: StepUp,
        session: DbSession,
        body: StatusChange | None = None,
    ) -> TenantOut:
        row = await set_status(
            session, id, target, actor_id=actor.id, reason=(body.reason if body else None)
        )
        return TenantOut.of(row)


_status_route("suspend", TenantStatus.SUSPENDED, "Suspend a tenant (reversible)")
_status_route("resume", TenantStatus.ACTIVE, "Resume a suspended tenant")
_status_route("archive", TenantStatus.ARCHIVED, "Archive a tenant (terminal)")


# --------------------------------------------------------------------------- usage
@router.get(
    "/tenants/{id}/usage",
    operation_id="getTenantUsage",
    summary="Usage counters against the plan limits",
    openapi_extra=PLATFORM_OPENAPI,
)
async def get_tenant_usage(id: TenantIdPath, _actor: PlatformAdmin, session: DbSession) -> UsageOut:
    row = await _registry_row(session, id)
    plan = plan_by_name(row.plan)
    limits = merge_limits(plan.limits, row.plan_limits)
    now = datetime.now(UTC)
    async with tenant_scope(session, id):
        lines = await snapshot(session, id, limits, when=now)
    return UsageOut(
        tenant_id=id,
        plan=plan.name,
        as_of=now,
        metrics=[UsageMetricOut.of(line) for line in lines],
    )


# --------------------------------------------------------------------------- billing
def _statement_out(statement: BillingStatement) -> StatementOut:
    return StatementOut.model_validate(
        {
            "tenant_id": statement.tenant_id,
            "period": statement.period,
            "plan": statement.plan,
            "generated_at": statement.generated_at,
            "lines": statement.lines,
            "base_price_paise": statement.base_price_paise,
            "overage_paise": statement.overage_paise,
            "total_paise": statement.total_paise,
            "external_invoice_ref": statement.external_invoice_ref,
        }
    )


@router.post(
    "/tenants/{id}/statements",
    operation_id="generateStatement",
    status_code=status.HTTP_201_CREATED,
    summary="Generate (or regenerate) a tenant's monthly usage statement",
    responses=problem_responses(_STEP_UP),
    openapi_extra=_OPENAPI,
)
async def generate_statement(
    id: TenantIdPath,
    _actor: PlatformAdmin,
    _step_up: StepUp,
    session: DbSession,
    body: StatementRequest | None = None,
) -> StatementOut:
    await _registry_row(session, id)
    async with tenant_scope(session, id):
        statement = await billing.generate_statement(
            session, id, period=(body.period if body else None)
        )
        out = _statement_out(statement)
    return out


@router.get(
    "/tenants/{id}/statements",
    operation_id="listStatements",
    summary="A tenant's usage statements, newest first",
    openapi_extra=PLATFORM_OPENAPI,
)
async def list_statements(
    id: TenantIdPath, _actor: PlatformAdmin, session: DbSession
) -> StatementList:
    await _registry_row(session, id)
    async with tenant_scope(session, id):
        rows = (
            (
                await session.execute(
                    select(BillingStatement)
                    .where(
                        BillingStatement.tenant_id == id,
                        BillingStatement.deleted_at.is_(None),
                    )
                    .order_by(BillingStatement.period.desc())
                )
            )
            .scalars()
            .all()
        )
        items = [_statement_out(row) for row in rows]
    return StatementList(items=items)


@router.get(
    "/tenants/{id}/statements/{period}/csv",
    operation_id="getStatementCsv",
    summary="One statement as CSV",
    response_class=Response,
    responses={
        200: {"content": {"text/csv": {"schema": {"type": "string"}}}},
        **problem_responses((404, "not_found")),
    },
    openapi_extra=PLATFORM_OPENAPI,
)
async def get_statement_csv(
    id: TenantIdPath,
    period: PeriodPath,
    _actor: PlatformAdmin,
    session: DbSession,
) -> Response:
    row = await _registry_row(session, id)
    async with tenant_scope(session, id):
        statement = (
            await session.execute(
                select(BillingStatement).where(
                    BillingStatement.tenant_id == id,
                    BillingStatement.period == period,
                    BillingStatement.deleted_at.is_(None),
                )
            )
        ).scalar_one_or_none()
        if statement is None:
            raise NotFoundError("No statement for that period.")
        body = billing.statement_csv(statement, tenant_slug=row.slug)
    return Response(
        content=body,
        media_type="text/csv",
        headers={
            "Content-Disposition": f'attachment; filename="{row.slug}-{period}.csv"',
        },
    )


__all__ = ["router"]
