"""WC-009 request / response models (console C90, agent app FA-024 through the port)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from farmerapp.incentives.models import IncentiveRuleSet, SalesTarget, TargetSubject
from farmerapp.incentives.service import IncentiveResult


class TargetItemIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subject_type: TargetSubject
    subject_id: uuid.UUID
    visits_verified: int | None = Field(default=None, ge=0, le=100_000)
    new_farmers: int | None = Field(default=None, ge=0, le=100_000)
    sales_paise: int | None = Field(default=None, ge=0)
    collections_paise: int | None = Field(default=None, ge=0)
    own_brand_share_bp: int | None = Field(default=None, ge=0, le=10_000)


class TargetsIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    month: date = Field(description="Any day of the month; stored as its first day.")
    items: list[TargetItemIn] = Field(min_length=1, max_length=500)


class TargetOut(BaseModel):
    id: uuid.UUID
    month: date
    subject_type: str
    subject_id: uuid.UUID
    visits_verified: int | None
    new_farmers: int | None
    sales_paise: int | None
    collections_paise: int | None
    own_brand_share_bp: int | None
    set_by: uuid.UUID | None
    updated_at: datetime

    @classmethod
    def from_row(cls, t: SalesTarget) -> TargetOut:
        return cls(
            id=t.id,
            month=t.month,
            subject_type=t.subject_type,
            subject_id=t.subject_id,
            visits_verified=t.visits_verified,
            new_farmers=t.new_farmers,
            sales_paise=t.sales_paise,
            collections_paise=t.collections_paise,
            own_brand_share_bp=t.own_brand_share_bp,
            set_by=t.set_by,
            updated_at=t.updated_at,
        )


class TargetList(BaseModel):
    month: date
    items: list[TargetOut]


class RuleSetIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, StringConstraints(min_length=1, max_length=120)]
    definition: dict[str, Any] = Field(
        description="The rule document (see farmerapp/incentives/rules.py and "
        "docs/prs/M7-growth-api.md)."
    )
    activate: bool = False


class RuleSetOut(BaseModel):
    id: uuid.UUID
    name: str
    version: int = Field(description="Rule set version number (1, 2, ...).")
    status: str
    definition: dict[str, Any]
    created_by: uuid.UUID | None
    created_at: datetime
    activated_at: datetime | None

    @classmethod
    def from_row(cls, r: IncentiveRuleSet) -> RuleSetOut:
        return cls(
            id=r.id,
            name=r.name,
            version=r.rule_version,
            status=r.status,
            definition=dict(r.definition or {}),
            created_by=r.created_by,
            created_at=r.created_at,
            activated_at=r.activated_at,
        )


class RuleSetList(BaseModel):
    items: list[RuleSetOut]


class PreviewIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    officer_id: uuid.UUID
    month: date
    definition: dict[str, Any]


class IncentiveLineOut(BaseModel):
    component: str
    metric: str
    value: float | None
    amount_paise: int
    capped: bool = False
    note: str | None = None


class IncentiveOut(BaseModel):
    officer_id: uuid.UUID
    period_start: date
    period_end: date = Field(description="Exclusive.")
    status: str = Field(description="`preview` (live) or `closed` (frozen).")
    rule_set_id: uuid.UUID | None
    rule_version: int | None
    eligible: bool
    metrics: dict[str, Any]
    targets: dict[str, Any]
    lines: list[IncentiveLineOut]
    gross_paise: int
    clawback_paise: int
    amount_paise: int
    reasons: list[str]

    @classmethod
    def from_result(cls, r: IncentiveResult) -> IncentiveOut:
        return cls(
            officer_id=r.officer_id,
            period_start=r.period_start,
            period_end=r.period_end,
            status=r.status,
            rule_set_id=r.rule_set_id,
            rule_version=r.rule_version or None,
            eligible=r.eligible,
            metrics=r.metrics,
            targets=r.targets,
            lines=[IncentiveLineOut.model_validate(line) for line in r.lines],
            gross_paise=r.gross_paise,
            clawback_paise=r.clawback_paise,
            amount_paise=r.amount_paise,
            reasons=r.reasons,
        )


class PayoutList(BaseModel):
    month: date
    items: list[IncentiveOut]
    total_paise: int


class CloseIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    month: date


class CloseOut(BaseModel):
    month: date
    closed: int
    already_closed: int
    total_paise: int
    rule_version: int | None


__all__ = [
    "CloseIn",
    "CloseOut",
    "IncentiveLineOut",
    "IncentiveOut",
    "PayoutList",
    "PreviewIn",
    "RuleSetIn",
    "RuleSetList",
    "RuleSetOut",
    "TargetItemIn",
    "TargetList",
    "TargetOut",
    "TargetsIn",
]
