"""Rule implementations registered by id (VA-001): ``@rule("VA-F02")``.

A rule is one small async function that reads the database through ``ctx.session`` (already
bound to ``ctx.tenant_id`` under RLS) and returns ``Finding``s. It never writes: the engine
turns findings into flags (dedupe, routing, SLA, notifications). Thresholds come from
``ctx.params`` — the YAML defaults merged with the tenant's overrides — so tuning a rule is
a config change, never a code change.

``ctx.subject_ids`` narrows the check to the records a write path or event touched
(inline / event modes); ``None`` means "the whole tenant" (batch).
"""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.rules.schema import Mode, RuleConfig, Subject


@dataclass(frozen=True)
class Evidence:
    """The evidence bundle stored on a flag (VA-002, VA-004 reads only this)."""

    records: list[dict[str, str]] = field(default_factory=list)  # [{type, id}]
    points: list[dict[str, Any]] = field(default_factory=list)  # GeoJSON Point geometries
    polygons: list[dict[str, Any]] = field(default_factory=list)  # GeoJSON Polygon geometries
    photos: list[str] = field(default_factory=list)  # blob URIs
    metrics: dict[str, Any] = field(default_factory=dict)

    def as_json(self) -> dict[str, Any]:
        return {
            "records": self.records,
            "map": {"points": self.points, "polygons": self.polygons},
            "photos": self.photos,
            "metrics": self.metrics,
        }


def record(kind: str, id: uuid.UUID | str) -> dict[str, str]:
    return {"type": kind, "id": str(id)}


@dataclass(frozen=True)
class Finding:
    """One suspicious thing. ``key`` makes the dedupe key unique within the rule and subject
    (e.g. the farm id, or the sorted pair of duplicate farmers)."""

    subject_type: Subject
    subject_id: uuid.UUID
    key: str
    title: str
    evidence: Evidence = field(default_factory=Evidence)


@dataclass(frozen=True)
class RuleContext:
    session: AsyncSession
    tenant_id: uuid.UUID
    rule: RuleConfig
    params: dict[str, Any]
    mode: Mode
    now: datetime
    subject_ids: tuple[uuid.UUID, ...] | None = None
    payload: dict[str, Any] = field(default_factory=dict)

    def param(self, name: str) -> Any:
        if name not in self.params:
            raise KeyError(f"{self.rule.id}: missing param {name!r} in rules/{self.rule.id}.yaml")
        return self.params[name]


RuleFn = Callable[[RuleContext], Awaitable[list[Finding]]]

_REGISTRY: dict[str, RuleFn] = {}


def rule(rule_id: str) -> Callable[[RuleFn], RuleFn]:
    """Register the implementation of ``rules/<rule_id>.yaml``."""

    def _register(fn: RuleFn) -> RuleFn:
        existing = _REGISTRY.get(rule_id)
        if existing is not None and existing is not fn:
            raise RuntimeError(f"rule {rule_id} is registered twice")
        _REGISTRY[rule_id] = fn
        return fn

    return _register


def implementations() -> dict[str, RuleFn]:
    """Every registered rule (importing ``farmerapp.rules.checks`` registers them all)."""
    import farmerapp.rules.checks  # noqa: F401  (side effect: @rule registrations)

    return dict(_REGISTRY)


__all__ = [
    "Evidence",
    "Finding",
    "RuleContext",
    "RuleFn",
    "implementations",
    "record",
    "rule",
]
