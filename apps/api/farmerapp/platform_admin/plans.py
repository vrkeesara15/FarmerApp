"""WC-014 plans and their limits.

A **plan** is a named bundle of limits a tenant is sold: how many officers, farmers and
stores it may hold, and how many photos, campaigns and LLM calls it may use per month, plus
optional retention overrides (NF-012). The catalogue lives here, in code, because a plan is a
commercial contract, not tenant data: it is reviewed, versioned and deployed like a rule set.
Per-tenant deviations ("this pilot gets 400 officers") are stored as a sparse override map on
the tenant row (``tenant.plan_limits``) and merged over the catalogue plan by ``plan_for``.

``None`` as a limit means *unlimited* (``unlimited`` plan, and any override set to ``null``).

The plan sizes are tied to the NF-007 scale target (SPEC 7: 50 tenants, 5,000 officers,
2 million farmers, 20 million photos): the average tenant at target is 100 officers and
40,000 farmers, which is the ``growth`` plan; ``enterprise`` is the headroom above it.

Retention overrides (``retention_overrides``: retention class -> days) may only ever *lengthen*
a window. A RETAIN class (financial records, 8 years) is a statutory floor and a PURGE class
(location points, 180 days) is a DPDP promise to the farmer: shortening either by selling a
cheaper plan is not a commercial decision we allow, so ``effective_retention_days`` clamps.
"""

from __future__ import annotations

from collections.abc import Mapping
from enum import StrEnum
from typing import TYPE_CHECKING, Any

from pydantic import BaseModel, ConfigDict, Field

if TYPE_CHECKING:  # ``farmerapp.retention`` imports this module (plan retention overrides).
    from farmerapp.retention.policy import RetentionClass


class Metric(StrEnum):
    """What a plan limits and what ``usage_counter`` counts."""

    OFFICERS = "officers"
    FARMERS = "farmers"
    STORES = "stores"
    PHOTOS = "photos"
    CAMPAIGNS = "campaigns"
    LLM_CALLS = "llm_calls"


#: Metrics counted per calendar month (period ``YYYY-MM``); the rest are standing head counts
#: (period ``total``) that go up on create and down on delete.
MONTHLY: frozenset[Metric] = frozenset({Metric.PHOTOS, Metric.CAMPAIGNS, Metric.LLM_CALLS})

#: Period value used for the standing head counts.
TOTAL_PERIOD = "total"

#: Metric -> the ``PlanLimits`` field that caps it.
LIMIT_FIELD: Mapping[Metric, str] = {
    Metric.OFFICERS: "officers",
    Metric.FARMERS: "farmers",
    Metric.STORES: "stores",
    Metric.PHOTOS: "photos_per_month",
    Metric.CAMPAIGNS: "campaigns_per_month",
    Metric.LLM_CALLS: "llm_calls_per_month",
}


class PlanLimits(BaseModel):
    """Caps of one plan. ``None`` = unlimited."""

    model_config = ConfigDict(extra="forbid")

    officers: int | None = Field(default=None, ge=0)
    farmers: int | None = Field(default=None, ge=0)
    stores: int | None = Field(default=None, ge=0)
    photos_per_month: int | None = Field(default=None, ge=0)
    campaigns_per_month: int | None = Field(default=None, ge=0)
    llm_calls_per_month: int | None = Field(default=None, ge=0)
    #: NF-012 retention class -> days. Only lengthening is honoured (see the module docstring).
    retention_overrides: dict[str, int] = Field(default_factory=dict)

    def limit_for(self, metric: Metric) -> int | None:
        value: int | None = getattr(self, LIMIT_FIELD[Metric(metric)])
        return value


class Plan(BaseModel):
    """A sellable plan: its limits and what an extra unit costs (money is integer paise)."""

    model_config = ConfigDict(extra="forbid")

    name: str
    title: str
    limits: PlanLimits
    #: Monthly platform fee in paise.
    base_price_paise: int = Field(default=0, ge=0)
    #: Metric -> price per unit over the limit, in paise. A metric missing here bills nothing.
    overage_paise: dict[str, int] = Field(default_factory=dict)


#: The catalogue. Adding a plan is a code change reviewed like a rule set.
PLANS: Mapping[str, Plan] = {
    plan.name: plan
    for plan in (
        Plan(
            name="pilot",
            title="Pilot",
            limits=PlanLimits(
                officers=25,
                farmers=5_000,
                stores=10,
                photos_per_month=50_000,
                campaigns_per_month=20,
                llm_calls_per_month=5_000,
            ),
            base_price_paise=2_500_000,  # Rs 25,000 / month
            overage_paise={
                Metric.FARMERS: 200,  # Rs 2 per farmer over
                Metric.OFFICERS: 50_000,  # Rs 500 per officer over
                Metric.PHOTOS: 5,
                Metric.LLM_CALLS: 100,
            },
        ),
        Plan(
            name="growth",
            title="Growth",
            # NF-007: the average tenant at the scale target (100 officers, 40,000 farmers).
            limits=PlanLimits(
                officers=200,
                farmers=50_000,
                stores=60,
                photos_per_month=500_000,
                campaigns_per_month=100,
                llm_calls_per_month=50_000,
            ),
            base_price_paise=10_000_000,  # Rs 1,00,000 / month
            overage_paise={
                Metric.FARMERS: 150,
                Metric.OFFICERS: 40_000,
                Metric.PHOTOS: 4,
                Metric.LLM_CALLS: 80,
            },
        ),
        Plan(
            name="enterprise",
            title="Enterprise",
            limits=PlanLimits(
                officers=2_000,
                farmers=500_000,
                stores=500,
                photos_per_month=5_000_000,
                campaigns_per_month=1_000,
                llm_calls_per_month=500_000,
                retention_overrides={"location_points": 365},
            ),
            base_price_paise=50_000_000,
            overage_paise={
                Metric.FARMERS: 100,
                Metric.OFFICERS: 30_000,
                Metric.PHOTOS: 3,
                Metric.LLM_CALLS: 60,
            },
        ),
        Plan(
            name="unlimited",
            title="Unlimited (internal)",
            # The platform tenant and the demo tenants: every limit off, nothing billed.
            limits=PlanLimits(),
        ),
    )
}

#: The plan a tenant gets when none is named.
DEFAULT_PLAN = "pilot"
PLAN_NAMES: tuple[str, ...] = tuple(PLANS)


class UnknownPlanError(KeyError):
    """Raised for a plan name that is not in the catalogue."""


def plan_by_name(name: str) -> Plan:
    try:
        return PLANS[name]
    except KeyError as exc:  # pragma: no cover - defensive; routes validate first
        raise UnknownPlanError(f"unknown plan {name!r} (have: {', '.join(PLAN_NAMES)})") from exc


def merge_limits(base: PlanLimits, overrides: Mapping[str, Any] | None) -> PlanLimits:
    """Catalogue limits with the tenant's sparse overrides applied.

    An override key that is not a limit is ignored (forward compatible with an older API
    reading a newer row); ``retention_overrides`` merges key by key.
    """
    if not overrides:
        return base
    data = base.model_dump()
    retention = dict(data["retention_overrides"])
    for key, value in overrides.items():
        if key == "retention_overrides" and isinstance(value, Mapping):
            retention.update({str(k): int(v) for k, v in value.items()})
        elif key in data:
            data[key] = value
    data["retention_overrides"] = retention
    return PlanLimits.model_validate(data)


def effective_retention_days(entry: RetentionClass, limits: PlanLimits) -> int:
    """Days for ``entry`` under ``limits``: the plan may lengthen a window, never shorten it."""
    override = limits.retention_overrides.get(entry.name)
    if override is None:
        return entry.days
    return max(entry.days, int(override))


__all__ = [
    "DEFAULT_PLAN",
    "LIMIT_FIELD",
    "MONTHLY",
    "PLANS",
    "PLAN_NAMES",
    "TOTAL_PERIOD",
    "Metric",
    "Plan",
    "PlanLimits",
    "UnknownPlanError",
    "effective_retention_days",
    "merge_limits",
    "plan_by_name",
]
