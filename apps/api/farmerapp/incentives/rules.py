"""WC-009 declarative incentive rules: the stored JSON document and its pure evaluation.

A rule set (``incentive_rule_set.definition``) looks like::

    {
      "eligibility": {"min_verified_visits": 20, "count_visit_statuses": ["verified"]},
      "components": [
        {"id": "visits", "metric": "verified_visits", "kind": "slab_per_unit",
         "slabs": [{"from": 0, "to": 40, "rate_paise": 0},
                   {"from": 40, "to": 80, "rate_paise": 2000},
                   {"from": 80, "rate_paise": 3000}]},
        {"id": "sales", "metric": "sales_paise", "kind": "percent", "rate_bp": 100,
         "cap_paise": 500000},
        {"id": "own_brand", "metric": "own_brand_share", "kind": "threshold",
         "threshold": 0.4, "amount_paise": 100000},
        {"id": "farmers", "metric": "new_farmers", "kind": "per_unit", "rate_paise": 5000}
      ],
      "multipliers": [{"metric": "attainment.sales_paise", "gte": 1.0, "factor": 1.1}],
      "cap_paise": 1500000,
      "clawback": {"cancelled_orders": true}
    }

Component kinds (amounts are integer paise, rounded half-up once per component):

* ``per_unit`` — ``rate_paise`` x the metric (counts).
* ``slab_per_unit`` — tiered: each unit is paid at the rate of the slab it falls in
  (``from`` inclusive, ``to`` exclusive; the last slab may be open).
* ``slab_flat`` — the slab containing the metric pays its ``amount_paise`` once.
* ``percent`` — ``rate_bp`` basis points of a paise metric.
* ``threshold`` — ``amount_paise`` when the metric is at least ``threshold``.

Each component may have a ``cap_paise``. ``multipliers`` multiply the summed components when
their metric is at least ``gte`` (all matching factors apply; ``attainment.<metric>`` is the
actual / monthly target ratio, absent without a target). ``cap_paise`` caps the total after
multipliers. **Clawback** (``cancelled_orders``, default on): orders the officer placed in an
earlier month and that were cancelled in this one are deducted at every ``percent``
component's rate on ``sales_paise``. The payable amount never goes below zero.

**Eligibility** (VV-005): visits count only when their status is in
``count_visit_statuses`` — ``["verified"]`` by default; ``min_verified_visits`` gates the
whole payout (an ineligible officer gets 0 with the reason).
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

BASIS_POINTS = 10_000

ATTAINMENT_METRICS = (
    "verified_visits",
    "new_farmers",
    "sales_paise",
    "collections_paise",
    "own_brand_share",
)
Metric = Annotated[
    str,
    StringConstraints(
        pattern=r"^(verified_visits|visits|new_farmers|sales_paise|collections_paise|"
        r"own_brand_share|own_brand_sales_paise|attainment\.(verified_visits|new_farmers|"
        r"sales_paise|collections_paise|own_brand_share))$"
    ),
]
VisitStatusName = Literal["verified", "partial", "unverified"]


class Slab(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    from_: float = Field(alias="from", ge=0)
    to: float | None = None
    rate_paise: int | None = Field(default=None, ge=0)
    amount_paise: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def _range(self) -> Slab:
        if self.to is not None and self.to <= self.from_:
            raise ValueError("a slab's `to` must be above its `from`")
        return self


class Component(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: Annotated[str, StringConstraints(pattern=r"^[a-z0-9_]{1,32}$")]
    metric: Metric
    kind: Literal["per_unit", "slab_per_unit", "slab_flat", "percent", "threshold"]
    rate_paise: int | None = Field(default=None, ge=0)
    rate_bp: int | None = Field(default=None, ge=0, le=BASIS_POINTS)
    slabs: list[Slab] = Field(default_factory=list, max_length=20)
    threshold: float | None = Field(default=None, ge=0)
    amount_paise: int | None = Field(default=None, ge=0)
    cap_paise: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def _shape(self) -> Component:
        need = {
            "per_unit": ("rate_paise",),
            "percent": ("rate_bp",),
            "threshold": ("threshold", "amount_paise"),
        }.get(self.kind, ())
        missing = [name for name in need if getattr(self, name) is None]
        if missing:
            raise ValueError(f"component {self.id}: {self.kind} needs {', '.join(missing)}")
        if self.kind.startswith("slab"):
            if not self.slabs:
                raise ValueError(f"component {self.id}: {self.kind} needs slabs")
            ordered = sorted(self.slabs, key=lambda s: s.from_)
            for a, b in itertools.pairwise(ordered):
                if a.to is None or a.to > b.from_:
                    raise ValueError(f"component {self.id}: slabs overlap")
            attr = "rate_paise" if self.kind == "slab_per_unit" else "amount_paise"
            if any(getattr(s, attr) is None for s in self.slabs):
                raise ValueError(f"component {self.id}: every slab needs {attr}")
            self.slabs = ordered
        if self.kind == "percent" and not self.metric.endswith("_paise"):
            raise ValueError(f"component {self.id}: percent applies to a paise metric")
        return self


class Multiplier(BaseModel):
    model_config = ConfigDict(extra="forbid")

    metric: Metric
    gte: float = Field(ge=0)
    factor: float = Field(gt=0, le=5)


class Eligibility(BaseModel):
    model_config = ConfigDict(extra="forbid")

    min_verified_visits: int = Field(default=0, ge=0)
    count_visit_statuses: list[VisitStatusName] = Field(
        default_factory=lambda: list[VisitStatusName](["verified"]),
        min_length=1,
        description="VV-005: visits that count (verified only by default).",
    )


class Clawback(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cancelled_orders: bool = True


class RuleDefinition(BaseModel):
    model_config = ConfigDict(extra="forbid")

    eligibility: Eligibility = Field(default_factory=Eligibility)
    components: list[Component] = Field(min_length=1, max_length=20)
    multipliers: list[Multiplier] = Field(default_factory=list, max_length=10)
    cap_paise: int | None = Field(default=None, ge=0)
    clawback: Clawback = Field(default_factory=Clawback)

    @model_validator(mode="after")
    def _unique_ids(self) -> RuleDefinition:
        ids = [c.id for c in self.components]
        if len(ids) != len(set(ids)):
            raise ValueError("component ids must be unique")
        return self


# --------------------------------------------------------------------------- evaluation
@dataclass(frozen=True)
class Metrics:
    """One officer's month (``own_brand_share`` is a ratio 0..1, None without sales)."""

    verified_visits: int = 0
    visits: int = 0
    new_farmers: int = 0
    sales_paise: int = 0
    own_brand_sales_paise: int = 0
    own_brand_share: float | None = None
    collections_paise: int = 0
    cancelled_prior_sales_paise: int = 0

    def as_json(self) -> dict[str, float | int | None]:
        return {
            "verified_visits": self.verified_visits,
            "visits": self.visits,
            "new_farmers": self.new_farmers,
            "sales_paise": self.sales_paise,
            "own_brand_sales_paise": self.own_brand_sales_paise,
            "own_brand_share": self.own_brand_share,
            "collections_paise": self.collections_paise,
            "cancelled_prior_sales_paise": self.cancelled_prior_sales_paise,
        }


@dataclass(frozen=True)
class Line:
    component: str
    metric: str
    value: float | None
    amount_paise: int
    capped: bool = False
    note: str | None = None

    def as_json(self) -> dict[str, object]:
        return {
            "component": self.component,
            "metric": self.metric,
            "value": self.value,
            "amount_paise": self.amount_paise,
            "capped": self.capped,
            "note": self.note,
        }


@dataclass(frozen=True)
class Evaluation:
    eligible: bool
    lines: list[Line]
    subtotal_paise: int
    multiplier: float
    gross_paise: int
    clawback_paise: int
    amount_paise: int
    capped: bool
    reasons: list[str] = field(default_factory=list)


def paise(value: Decimal | float | int) -> int:
    return int(Decimal(str(value)).quantize(Decimal(1), rounding=ROUND_HALF_UP))


def metric_value(
    name: str, metrics: Metrics, targets: dict[str, float | int | None]
) -> float | None:
    if name.startswith("attainment."):
        base = name.split(".", 1)[1]
        target = targets.get(base)
        actual = metric_value(base, metrics, targets)
        if not target or actual is None:
            return None
        return round(float(actual) / float(target), 6)
    value = getattr(metrics, name)
    return None if value is None else float(value)


def _component(c: Component, value: float | None) -> tuple[int, str | None]:
    if value is None:
        return 0, "no value"
    v = Decimal(str(value))
    if c.kind == "per_unit":
        return paise(v * (c.rate_paise or 0)), None
    if c.kind == "percent":
        return paise(v * (c.rate_bp or 0) / BASIS_POINTS), None
    if c.kind == "threshold":
        met = value >= (c.threshold or 0)
        return (c.amount_paise or 0) if met else 0, None if met else "below threshold"
    if c.kind == "slab_flat":
        for s in c.slabs:
            if value >= s.from_ and (s.to is None or value < s.to):
                return s.amount_paise or 0, None
        return 0, "no slab"
    total = Decimal(0)  # slab_per_unit: each unit at its slab's rate
    for s in c.slabs:
        upper = Decimal(str(s.to)) if s.to is not None else v
        units = min(v, upper) - Decimal(str(s.from_))
        if units > 0:
            total += units * (s.rate_paise or 0)
    return paise(total), None


def evaluate(
    definition: RuleDefinition,
    metrics: Metrics,
    targets: dict[str, float | int | None] | None = None,
) -> Evaluation:
    targets = targets or {}
    reasons: list[str] = []
    eligible = metrics.verified_visits >= definition.eligibility.min_verified_visits
    if not eligible:
        reasons.append(
            f"verified visits {metrics.verified_visits} below the minimum "
            f"{definition.eligibility.min_verified_visits}"
        )
    lines: list[Line] = []
    for c in definition.components:
        value = metric_value(c.metric, metrics, targets)
        amount, note = _component(c, value)
        capped = c.cap_paise is not None and amount > c.cap_paise
        if capped and c.cap_paise is not None:
            amount = c.cap_paise
        lines.append(Line(c.id, c.metric, value, amount, capped, note))
    subtotal = sum(line.amount_paise for line in lines)
    factor = Decimal(1)
    for m in definition.multipliers:
        value = metric_value(m.metric, metrics, targets)
        if value is not None and value >= m.gte:
            factor *= Decimal(str(m.factor))
    gross = paise(Decimal(subtotal) * factor)
    capped_total = definition.cap_paise is not None and gross > definition.cap_paise
    if capped_total and definition.cap_paise is not None:
        gross = definition.cap_paise
    clawback = 0
    if definition.clawback.cancelled_orders and metrics.cancelled_prior_sales_paise:
        for c in definition.components:
            if c.kind == "percent" and c.metric == "sales_paise":
                clawback += paise(
                    Decimal(metrics.cancelled_prior_sales_paise) * (c.rate_bp or 0) / BASIS_POINTS
                )
    if not eligible:
        return Evaluation(
            eligible=False,
            lines=lines,
            subtotal_paise=subtotal,
            multiplier=float(factor),
            gross_paise=0,
            clawback_paise=clawback,
            amount_paise=0,
            capped=capped_total,
            reasons=reasons,
        )
    return Evaluation(
        eligible=True,
        lines=lines,
        subtotal_paise=subtotal,
        multiplier=float(factor),
        gross_paise=gross,
        clawback_paise=clawback,
        amount_paise=max(gross - clawback, 0),
        capped=capped_total,
        reasons=reasons,
    )


__all__ = [
    "ATTAINMENT_METRICS",
    "Clawback",
    "Component",
    "Eligibility",
    "Evaluation",
    "Line",
    "Metrics",
    "Multiplier",
    "RuleDefinition",
    "Slab",
    "evaluate",
    "metric_value",
    "paise",
]
