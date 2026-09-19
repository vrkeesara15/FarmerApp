"""``/v1/settings`` — typed tenant settings (WC-012, C102).

* ``GET /v1/settings`` — every setting with its effective value (owner, director,
  tenant_admin).
* ``GET /v1/settings/public`` — the subset the apps need (any signed-in role): geofence and
  meeting-point radius, minimum visit time, auto duty end, idle end, sampling, location
  policy version, languages, feature flags (``features.on_device_crop_guess``) and branding.
  **The mobile settings cache (geofence radius, minimum visit duration, sampling, features) is
  filled from this endpoint** on login and on every sync; the values are authoritative
  server-side (check-in and check-out re-evaluate them).
* ``PATCH /v1/settings`` — owner and tenant_admin, step-up required (SEC-028). A partial
  body: nested ``sampling`` / ``features`` / ``branding`` merge key by key, ``null`` resets
  a nullable key to its default. The merged result is validated with ``TenantSettings`` (422
  ``invalid_settings`` with the pydantic errors). Audited twice: the FA-006 listener's
  ``tenant.update`` row (raw JSON diff) and an explicit ``tenant_settings.update`` with the
  before / after of the changed keys only.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from farmerapp.api.errors import AppError, problem_responses
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.db import audit
from farmerapp.db.models.tenant import Tenant
from farmerapp.logging import get_logger
from farmerapp.tenants.settings import (
    PUBLIC_KEYS,
    Branding,
    FeatureSettings,
    Language,
    SamplingSettings,
    ServiceArea,
    TenantSettings,
    parse_settings,
    settings_from_tenant,
)

log = get_logger("farmerapp.tenants.settings")

router = APIRouter(prefix="/settings", tags=["settings"])

READ_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)
# SPEC 2.6 permissions matrix: Owner / director write Settings (step-up still required).
WRITE_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)


class InvalidSettingsError(AppError):
    status = 422
    code = "invalid_settings"


class PublicSettings(BaseModel):
    """What the field and farmer apps read (no finance, credit or invoicing keys)."""

    geofence_radius_m: int
    meeting_point_radius_m: int | None
    min_visit_duration_s: int
    auto_duty_end_local_time: str
    idle_end_minutes: int
    location_policy_version: str
    sampling: SamplingSettings
    languages_enabled: list[Language]
    default_language: Language
    features: FeatureSettings
    branding: Branding

    @classmethod
    def of(cls, settings: TenantSettings) -> PublicSettings:
        return cls.model_validate(settings.model_dump(include=set(PUBLIC_KEYS)))


class SamplingPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    moving_s: int | None = None
    stationary_s: int | None = None
    upload_s: int | None = None


class FeaturesPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    on_device_crop_guess: bool | None = None


class BrandingPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    app_name_agent: str | None = None
    app_name_farmer: str | None = None
    primary_colour: str | None = None
    logo_blob_uri: str | None = None
    support_phone: str | None = None


class SettingsPatch(BaseModel):
    """Partial update; ranges are those of ``TenantSettings`` (see ``GET /v1/settings``)."""

    model_config = ConfigDict(extra="forbid")

    consent_version: str | None = None
    geofence_radius_m: int | None = Field(default=None, description="10-2000 m.")
    meeting_point_radius_m: int | None = Field(default=None, description="10-2000 m or null.")
    min_visit_duration_s: int | None = Field(default=None, description="0-86400 s.")
    auto_duty_end_local_time: str | None = Field(default=None, description="HH:MM (IST).")
    idle_end_minutes: int | None = Field(default=None, description="5-720 min.")
    location_policy_version: str | None = None
    sampling: SamplingPatch | None = None
    ta_rate_per_km_paise: int | None = Field(default=None, description="0-10000 paise.")
    store_manager_max_credit_limit_paise: int | None = None
    credit_due_days: int | None = Field(default=None, description="1-730 days.")
    day_close_variance_threshold_paise: int | None = None
    webhook_replay_window_s: int | None = Field(default=None, description="30-86400 s.")
    legal_name: str | None = None
    gstin_by_state: dict[str, str] | None = None
    invoice_prefix: str | None = None
    working_days: list[int] | None = Field(
        default=None, description="OPS-007 ISO weekdays 1 (Mon) - 7 (Sun)."
    )
    holidays: list[date] | None = Field(default=None, description="OPS-007 YYYY-MM-DD dates.")
    day_close_deadline_local_time: str | None = Field(
        default=None, description="OPS-007 HH:MM (IST)."
    )
    languages_enabled: list[Language] | None = None
    default_language: Language | None = None
    features: FeaturesPatch | None = None
    branding: BrandingPatch | None = None
    service_area: ServiceArea | None = Field(
        default=None, description="VA-F04 service districts (replaces the whole list)."
    )
    discount_policy_max_bps: int | None = Field(default=None, description="VA-E09 0-10000 bp.")
    incentive_cutoff_day: int | None = Field(default=None, description="VA-E09 day 1-28.")


def _merge(current: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    out = dict(current)
    for key, value in patch.items():
        if value is None:
            out.pop(key, None)  # back to the default
        else:
            out[key] = value
    return out


@router.get(
    "",
    operation_id="getSettings",
    summary="Every tenant setting with its effective value (C102)",
    response_model=TenantSettings,
)
async def get_settings(
    actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> TenantSettings:
    return settings_from_tenant(await session.get(Tenant, actor.tenant_id))


@router.get(
    "/public",
    operation_id="getPublicSettings",
    summary="The settings the apps cache: geofence, visit time, duty, sampling, branding",
    response_model=PublicSettings,
)
async def get_public_settings(
    actor: Annotated[User, require_roles(*Role)], session: DbSession
) -> PublicSettings:
    return PublicSettings.of(settings_from_tenant(await session.get(Tenant, actor.tenant_id)))


@router.patch(
    "",
    operation_id="updateSettings",
    summary="Change tenant settings (step-up required; audited with before / after)",
    response_model=TenantSettings,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses((401, "step_up_required"), (422, "invalid_settings")),
)
async def update_settings(
    body: SettingsPatch,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
) -> TenantSettings:
    tenant = await session.get_one(Tenant, actor.tenant_id)
    before = settings_from_tenant(tenant)
    patch = body.model_dump(exclude_unset=True, mode="json")
    branding_patch = patch.pop("branding", None)
    sampling_patch = patch.pop("sampling", None)
    features_patch = patch.pop("features", None)

    raw = _merge(dict(tenant.settings or {}), patch)
    if sampling_patch is not None:
        raw["sampling"] = _merge(dict(raw.get("sampling") or {}), sampling_patch)
    if features_patch is not None:
        raw["features"] = _merge(dict(raw.get("features") or {}), features_patch)
    branding = dict(tenant.branding or {})
    if branding_patch is not None:
        branding = _merge(branding, branding_patch)
    try:
        TenantSettings.model_validate({**raw, "branding": branding})
    except ValidationError as exc:
        errors = [
            {"loc": [str(p) for p in err["loc"]], "msg": err["msg"], "type": err["type"]}
            for err in exc.errors()
        ]
        raise InvalidSettingsError(
            "Some settings are out of range.", extra={"errors": errors}
        ) from exc

    tenant.settings = raw
    tenant.branding = branding
    after = parse_settings(raw, branding)
    old, new = before.model_dump(mode="json"), after.model_dump(mode="json")
    changed = sorted(k for k in new if old.get(k) != new.get(k))
    if changed:
        audit.record(
            session,
            action="tenant_settings.update",
            entity="tenant",
            entity_id=tenant.id,
            before={k: old[k] for k in changed},
            after={k: new[k] for k in changed},
        )
    await session.flush()
    log.info("tenant_settings_updated", actor_id=str(actor.id), keys=changed)
    return after
