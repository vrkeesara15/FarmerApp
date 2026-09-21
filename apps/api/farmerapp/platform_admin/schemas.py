"""Request and response models for ``/v1/admin/*`` (WC-014)."""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from farmerapp.platform_admin.models import PlatformTenant, TenantStatus
from farmerapp.platform_admin.plans import PLAN_NAMES, Metric, Plan, PlanLimits
from farmerapp.platform_admin.provisioning import DEFAULT_REGION, REGIONS, ProvisionResult
from farmerapp.platform_admin.usage import UsageLine
from farmerapp.tenants.settings import Branding, Language

SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{1,48}[a-z0-9]$")
Slug = Annotated[str, StringConstraints(min_length=3, max_length=50)]
Phone = Annotated[str, StringConstraints(pattern=r"^\+91[6-9]\d{9}$")]


class PlanOut(BaseModel):
    name: str
    title: str
    limits: PlanLimits
    base_price_paise: int
    overage_paise: dict[str, int]

    @classmethod
    def of(cls, plan: Plan) -> PlanOut:
        return cls.model_validate(plan.model_dump())


class PlanList(BaseModel):
    items: list[PlanOut]


class TenantCreate(BaseModel):
    """WC-014: everything needed to make a tenant usable, in one body."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=2, max_length=200)
    slug: Slug
    plan: str = Field(default="pilot", max_length=32)
    region: str = Field(default=DEFAULT_REGION, max_length=40)
    primary_contact_name: str = Field(min_length=2, max_length=200)
    primary_contact_phone: Phone
    languages: list[Language] = Field(default_factory=list)
    default_language: Language = "en"
    branding: Branding = Field(default_factory=Branding)
    #: Sparse overrides on the plan's limits, e.g. ``{"farmers": 80000}``.
    plan_limits: PlanLimits | None = None
    #: VA-006 rule ids this tenant does not run.
    disabled_rules: list[str] = Field(default_factory=list, max_length=64)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("slug")
    @classmethod
    def _slug_shape(cls, value: str) -> str:
        if not SLUG_RE.match(value):
            raise ValueError("slug must be lowercase letters, digits and hyphens")
        return value

    @field_validator("plan")
    @classmethod
    def _known_plan(cls, value: str) -> str:
        if value not in PLAN_NAMES:
            raise ValueError(f"unknown plan (have: {', '.join(PLAN_NAMES)})")
        return value

    @field_validator("region")
    @classmethod
    def _known_region(cls, value: str) -> str:
        if value not in REGIONS:
            raise ValueError(f"unknown region (have: {', '.join(REGIONS)})")
        return value


class TenantUpdate(BaseModel):
    """Plan, limits, contact name and notes. Slug and region never change (they are in
    invoice numbers and in the residency promise)."""

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=2, max_length=200)
    plan: str | None = Field(default=None, max_length=32)
    plan_limits: PlanLimits | None = None
    primary_contact_name: str | None = Field(default=None, min_length=2, max_length=200)
    notes: str | None = Field(default=None, max_length=1000)

    @field_validator("plan")
    @classmethod
    def _known_plan(cls, value: str | None) -> str | None:
        if value is not None and value not in PLAN_NAMES:
            raise ValueError(f"unknown plan (have: {', '.join(PLAN_NAMES)})")
        return value


class TenantOut(BaseModel):
    id: uuid.UUID
    slug: str
    name: str
    plan: str
    status: TenantStatus
    region: str
    primary_contact_user_id: uuid.UUID | None
    primary_contact_name: str | None
    plan_limits: dict[str, Any]
    provisioned: dict[str, Any]
    provisioned_at: datetime | None
    suspended_at: datetime | None
    archived_at: datetime | None
    notes: str | None

    @classmethod
    def of(cls, row: PlatformTenant) -> TenantOut:
        return cls(
            id=row.subject_tenant_id,
            slug=row.slug,
            name=row.name,
            plan=row.plan,
            status=TenantStatus(row.status),
            region=row.region,
            primary_contact_user_id=row.primary_contact_user_id,
            primary_contact_name=row.primary_contact_name,
            plan_limits=dict(row.plan_limits or {}),
            provisioned=dict(row.provisioned or {}),
            provisioned_at=row.provisioned_at,
            suspended_at=row.suspended_at,
            archived_at=row.archived_at,
            notes=row.notes,
        )


class TenantList(BaseModel):
    items: list[TenantOut]


class TenantCreated(BaseModel):
    """What one ``POST /v1/admin/tenants`` produced, so the operator can act immediately."""

    tenant: TenantOut
    admin_user_id: uuid.UUID
    store_id: uuid.UUID
    cluster_id: uuid.UUID
    created: dict[str, int]
    elapsed_ms: int

    @classmethod
    def of(cls, row: PlatformTenant, result: ProvisionResult) -> TenantCreated:
        return cls(
            tenant=TenantOut.of(row),
            admin_user_id=result.admin_user_id,
            store_id=result.store_id,
            cluster_id=result.cluster_id,
            created=dict(result.created),
            elapsed_ms=result.elapsed_ms,
        )


class InviteOut(BaseModel):
    """The follow-up invite: an OTP on its way to the primary contact's phone."""

    tenant_id: uuid.UUID
    user_id: uuid.UUID
    #: The channel the code went out on (SMS, or WhatsApp as the FA-001 fallback).
    channel: str
    resends_left: int


class UsageMetricOut(BaseModel):
    metric: Metric
    period: str
    used: int
    limit: int | None
    remaining: int | None
    over: int

    @classmethod
    def of(cls, line: UsageLine) -> UsageMetricOut:
        return cls(
            metric=Metric(line.metric),
            period=line.period,
            used=line.used,
            limit=line.limit,
            remaining=line.remaining,
            over=line.over,
        )


class UsageOut(BaseModel):
    tenant_id: uuid.UUID
    plan: str
    as_of: datetime
    metrics: list[UsageMetricOut]


class StatementLineOut(BaseModel):
    metric: str
    period: str
    used: int
    included: int | None
    overage: int
    unit_price_paise: int
    amount_paise: int


class StatementOut(BaseModel):
    tenant_id: uuid.UUID
    period: str
    plan: str
    generated_at: datetime
    lines: list[StatementLineOut]
    base_price_paise: int
    overage_paise: int
    total_paise: int
    external_invoice_ref: str | None


class StatementList(BaseModel):
    items: list[StatementOut]


class StatementRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    #: ``YYYY-MM``; default: the current month.
    period: str | None = Field(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")


class StatusChange(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str | None = Field(default=None, max_length=500)


__all__ = [
    "InviteOut",
    "PlanList",
    "PlanOut",
    "StatementLineOut",
    "StatementList",
    "StatementOut",
    "StatementRequest",
    "StatusChange",
    "TenantCreate",
    "TenantCreated",
    "TenantList",
    "TenantOut",
    "TenantUpdate",
    "UsageMetricOut",
    "UsageOut",
]
