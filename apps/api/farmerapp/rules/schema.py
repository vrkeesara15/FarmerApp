"""The rule file contract (VA-001): one ``rules/<rule_id>.yaml`` per validation rule.

A rule file is configuration only — the check itself is Python registered under the same id
(``farmerapp.rules.registry.rule``). Everything a reviewer may want to tune lives here:
thresholds (``params``), whether the rule runs (``enabled``), its severity, routing hint and
SLA, and per-tenant overrides keyed by the tenant slug. ``version`` is stored on every flag
(VA-002) and must be bumped with any change, so precision (VA-006) is tracked per version.

The model is strict (``extra="forbid"``): a typo in a key fails the loader, and therefore
the test suite (``tests/rules/test_loader.py``), instead of silently falling back to a
default.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

RULE_ID_PATTERN = r"^VA-[FE][0-9]{2}$"


class Subject(StrEnum):
    FARMER = "farmer"
    EMPLOYEE = "employee"
    VISIT = "visit"
    STORE = "store"
    TENANT = "tenant"  # OPS monitors about the whole tenant (OPS-008 finance ticket)


class Mode(StrEnum):
    INLINE = "inline"  # API write path, same transaction (SPEC 6.1)
    EVENT = "event"  # in-process bus / Pub/Sub worker
    BATCH = "batch"  # nightly job (02:00 IST)


class Severity(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class OwnerRole(StrEnum):
    """VA-003 routing hint: who owns a flag of this rule by default."""

    CLUSTER_HEAD = "cluster_head"
    STORE_MANAGER = "store_manager"
    AUDITOR = "auditor"


class TenantOverride(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    params: dict[str, Any] = Field(default_factory=dict)
    enabled: bool | None = None


class RuleConfig(BaseModel):
    """One validated ``rules/<id>.yaml``."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=RULE_ID_PATTERN)
    version: int = Field(ge=1)
    title: str = Field(min_length=3, max_length=200)
    description: str | None = None
    subject: Subject
    mode: tuple[Mode, ...] = Field(min_length=1)
    triggers: tuple[str, ...] = Field(
        default=(), description="Event topics that run the rule in event mode."
    )
    severity: Severity
    owner_role: OwnerRole
    sla_hours: int = Field(gt=0, le=24 * 30)
    params: dict[str, Any] = Field(default_factory=dict)
    enabled: bool = True
    tenant_overrides: dict[str, TenantOverride] = Field(default_factory=dict)

    @field_validator("mode", mode="before")
    @classmethod
    def _one_or_many(cls, value: Any) -> Any:
        return [value] if isinstance(value, str) else value

    @model_validator(mode="after")
    def _consistent(self) -> RuleConfig:
        if len(set(self.mode)) != len(self.mode):
            raise ValueError("mode lists a runner twice")
        if Mode.EVENT in self.mode and not self.triggers:
            raise ValueError("an event rule needs at least one trigger topic")
        if self.triggers and Mode.EVENT not in self.mode:
            raise ValueError("triggers are only meaningful for event rules")
        for slug, override in self.tenant_overrides.items():
            unknown = set(override.params) - set(self.params)
            if unknown:
                raise ValueError(
                    f"tenant_overrides.{slug}.params sets unknown keys {sorted(unknown)}"
                )
            for key, value in override.params.items():
                default = self.params[key]
                if isinstance(default, bool) != isinstance(value, bool) or (
                    not isinstance(default, bool)
                    and isinstance(default, int | float)
                    and not isinstance(value, int | float)
                ):
                    raise ValueError(
                        f"tenant_overrides.{slug}.params.{key} must have the type of the default"
                    )
        return self

    def params_for(self, tenant_slug: str | None) -> dict[str, Any]:
        """The defaults with the tenant's overrides applied."""
        override = self.tenant_overrides.get(tenant_slug or "")
        return {**self.params, **(override.params if override else {})}

    def enabled_for(self, tenant_slug: str | None) -> bool:
        override = self.tenant_overrides.get(tenant_slug or "")
        if override is not None and override.enabled is not None:
            return override.enabled
        return self.enabled


__all__ = [
    "RULE_ID_PATTERN",
    "Mode",
    "OwnerRole",
    "RuleConfig",
    "Severity",
    "Subject",
    "TenantOverride",
]
