"""Typed tenant settings (WC-012): ``tenant.settings`` (SPEC 8.2 ``settings jsonb``) plus
``tenant.branding``, with defaults and validation ranges.

Every setting the API reads lives here; a missing key means the default. Readers go through
one accessor, ``get_tenant_settings(session, tenant_id)`` (or ``settings_from_tenant(tenant)``
when the row is already loaded); ``PATCH /v1/settings`` validates with the same model.

=================================== ============ ==============================================
key                                 default      used by
=================================== ============ ==============================================
consent_version                     2026-09-v1   FM-002 consent text version (TODO-LEGAL)
geofence_radius_m                   150          FA-014 / VV-003 buffer around a farm polygon
meeting_point_radius_m              null         VV-003 default meeting-point radius for villages
                                                 without their own (null -> geofence_radius_m)
min_visit_duration_s                300          FA-017 visits under it are flagged, never rejected
auto_duty_end_local_time            "20:00"      VV-007 duty ends at this local (IST) time
idle_end_minutes                    60           VV-007 duty ends after this long idle at home
location_policy_version             2026-09-v1   FA-011 / VV-010 policy the app must accept
sampling.moving_s                   120          VV-001 location sample interval while moving
sampling.stationary_s               600          VV-001 interval while stationary
sampling.upload_s                   900          VV-001 batch upload interval
ta_rate_per_km_paise                300          FA-023 travel allowance per km (Rs 3; assumption)
store_manager_max_credit_limit_paise 5000000     ST-007 most a store manager may set (Rs 50,000)
credit_due_days                     90           FA-022 due date of a credit sale without harvest
day_close_variance_threshold_paise  50000        ST-006 |variance| above it flags auditors
webhook_replay_window_s             300          SEC-023 reject webhooks older than this
legal_name                          tenant name  ST-001 seller on the GST invoice
gstin_by_state                      placeholder  ST-001 seller GSTIN per state (TODO-HUMAN)
invoice_prefix                      slug upper   ST-001 first segment of the invoice number
working_days                        [1..6]       OPS-007 ISO weekdays stores trade (Mon-Sat)
holidays                            []           OPS-007 dates (YYYY-MM-DD) no store trades
day_close_deadline_local_time       "22:00"      OPS-007 a working day not closed by then alerts
languages_enabled                   all five     NF-008 languages the apps offer
default_language                    "en"         language of a new user
features.on_device_crop_guess       false        DX-001 apps pre-select the on-device crop guess
branding.*                          see Branding C102 app names, colour, logo, support phone
=================================== ============ ==============================================

The visit confirmation token TTL is deployment-wide (``Settings.visit_confirm_token_ttl_s``),
not a tenant setting.

Loading is lenient: a stored value that no longer validates falls back to its default (logged
as ``tenant_settings_invalid`` with the key names) so one bad key never breaks check-in or
invoicing; writes are strict (422).
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from datetime import date, time
from typing import TYPE_CHECKING, Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, ValidationError
from sqlalchemy import inspect

from farmerapp.farmers.models import DEFAULT_CONSENT_VERSION
from farmerapp.logging import get_logger
from farmerapp.payments.config import (
    DEFAULT_REPLAY_WINDOW_S,
    DEFAULT_VARIANCE_THRESHOLD_PAISE,
    placeholder_gstin,
)

if TYPE_CHECKING:
    from sqlalchemy.ext.asyncio import AsyncSession

    from farmerapp.db.models.tenant import Tenant

log = get_logger("farmerapp.tenants.settings")

#: TODO-LEGAL: placeholder until the written employee location policy is approved and signed
#: in HR onboarding (VV-010, SPEC 14.6 human gate). The in-app acceptance references it.
DEFAULT_LOCATION_POLICY_VERSION = "2026-09-v1"
#: ₹50,000: the most a store manager may set as a farmer's limit without a cluster head.
DEFAULT_STORE_MANAGER_MAX_CREDIT_LIMIT_PAISE = 5_000_000
#: Due date of a credit sale when the farmer has no upcoming harvest on record.
DEFAULT_CREDIT_DUE_DAYS = 90
#: FA-023 assumption until the owner sets it: Rs 3 per km (two-wheeler rate).
DEFAULT_TA_RATE_PER_KM_PAISE = 300
#: NF-008 launch languages (SPEC 0.3): Telugu, Kannada, Hindi, Marathi, English.
Language = Literal["en", "te", "kn", "hi", "mr"]
SUPPORTED_LANGUAGES: tuple[Language, ...] = ("en", "te", "kn", "hi", "mr")
DEFAULT_PRIMARY_COLOUR = "#1F6B3A"  # design/tokens.json color.primary.default

_HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"
Gstin = Annotated[str, StringConstraints(pattern=r"^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")]

SETTINGS_KEYS: Mapping[str, str] = {
    "consent_version": "FM-002 consent text version shown to farmers",
    "geofence_radius_m": "FA-014 / VV-003 geofence buffer in metres around a farm polygon",
    "meeting_point_radius_m": "VV-003 default meeting-point radius (null: geofence radius)",
    "min_visit_duration_s": "FA-017 minimum visit duration in seconds (flag, not reject)",
    "auto_duty_end_local_time": "VV-007 local time (HH:MM, IST) at which duty auto-ends",
    "idle_end_minutes": "VV-007 minutes idle at the home location before duty auto-ends",
    "location_policy_version": "FA-011 / VV-010 employee location policy version to accept",
    "sampling": "VV-001 sampling intervals: moving_s, stationary_s, upload_s",
    "ta_rate_per_km_paise": "FA-023 travel allowance rate per km, in paise",
    "store_manager_max_credit_limit_paise": "ST-007 store manager's maximum credit limit",
    "credit_due_days": "FA-022 due days of a credit sale without a known harvest",
    "day_close_variance_threshold_paise": "ST-006 cash variance that alerts auditors",
    "webhook_replay_window_s": "SEC-023 payment webhook replay window in seconds",
    "legal_name": "ST-001 seller legal name on invoices",
    "gstin_by_state": "ST-001 seller GSTIN per state",
    "invoice_prefix": "ST-001 invoice number prefix",
    "working_days": "OPS-007 ISO weekdays the stores trade (1 = Monday .. 7 = Sunday)",
    "holidays": "OPS-007 dates (YYYY-MM-DD) on which no store trades",
    "day_close_deadline_local_time": "OPS-007 local time (HH:MM, IST) by which a day is closed",
    "languages_enabled": "NF-008 languages offered in the apps",
    "default_language": "Language of new users",
    "features": "App feature flags: on_device_crop_guess (DX-001 crop hint, default off)",
    "branding": "C102 app names, primary colour, logo and support phone (tenant.branding)",
}


class SamplingSettings(BaseModel):
    model_config = ConfigDict(extra="ignore")

    moving_s: int = Field(default=120, ge=30, le=3600)
    stationary_s: int = Field(default=600, ge=60, le=7200)
    upload_s: int = Field(default=900, ge=60, le=86_400)


class FeatureSettings(BaseModel):
    """Remote-config flags the apps read from ``GET /v1/settings/public`` (``features``)."""

    model_config = ConfigDict(extra="ignore")

    on_device_crop_guess: bool = Field(
        default=False,
        description="DX-001: send and pre-select the on-device crop guess. Off until the "
        "field-accuracy gate passes (ml/ondevice/INTEGRATION.md section 7).",
    )


class Branding(BaseModel):
    """``tenant.branding`` (C102): overrides of the app names (null: the i18n default,
    "Mitra" / "Kisan"), the primary colour, the logo (a blob URI from ``/v1/uploads``) and
    the support phone shown in both apps."""

    model_config = ConfigDict(extra="ignore")

    app_name_agent: str | None = Field(default=None, min_length=1, max_length=40)
    app_name_farmer: str | None = Field(default=None, min_length=1, max_length=40)
    primary_colour: str = Field(default=DEFAULT_PRIMARY_COLOUR, pattern=r"^#[0-9A-Fa-f]{6}$")
    logo_blob_uri: str | None = Field(default=None, min_length=1, max_length=512)
    support_phone: str | None = Field(default=None, pattern=r"^\+?[0-9]{8,15}$")


class TenantSettings(BaseModel):
    model_config = ConfigDict(extra="ignore")

    consent_version: str = Field(default=DEFAULT_CONSENT_VERSION, min_length=1, max_length=32)
    geofence_radius_m: int = Field(default=150, ge=10, le=2000)
    meeting_point_radius_m: int | None = Field(default=None, ge=10, le=2000)
    min_visit_duration_s: int = Field(default=300, ge=0, le=86_400)
    auto_duty_end_local_time: str = Field(default="20:00", pattern=_HHMM)
    idle_end_minutes: int = Field(default=60, ge=5, le=720)
    location_policy_version: str = Field(
        default=DEFAULT_LOCATION_POLICY_VERSION, min_length=1, max_length=32
    )
    sampling: SamplingSettings = Field(default_factory=SamplingSettings)
    ta_rate_per_km_paise: int = Field(default=DEFAULT_TA_RATE_PER_KM_PAISE, ge=0, le=10_000)
    store_manager_max_credit_limit_paise: int = Field(
        default=DEFAULT_STORE_MANAGER_MAX_CREDIT_LIMIT_PAISE, ge=0, le=100_000_000_00
    )
    credit_due_days: int = Field(default=DEFAULT_CREDIT_DUE_DAYS, ge=1, le=730)
    day_close_variance_threshold_paise: int = Field(
        default=DEFAULT_VARIANCE_THRESHOLD_PAISE, ge=0, le=100_000_00
    )
    webhook_replay_window_s: int = Field(default=DEFAULT_REPLAY_WINDOW_S, ge=30, le=86_400)
    legal_name: str | None = Field(default=None, min_length=1, max_length=200)
    gstin_by_state: dict[str, Gstin] = Field(default_factory=dict)
    invoice_prefix: str | None = Field(default=None, max_length=8, pattern=r"^[A-Z0-9]+$")
    working_days: list[Annotated[int, Field(ge=1, le=7)]] = Field(
        default_factory=lambda: [1, 2, 3, 4, 5, 6], min_length=1, max_length=7
    )
    holidays: list[date] = Field(default_factory=list, max_length=366)
    day_close_deadline_local_time: str = Field(default="22:00", pattern=_HHMM)
    languages_enabled: list[Language] = Field(
        default_factory=lambda: list(SUPPORTED_LANGUAGES), min_length=1
    )
    default_language: Language = "en"
    features: FeatureSettings = Field(default_factory=FeatureSettings)
    branding: Branding = Field(default_factory=Branding)

    def auto_duty_end_time(self) -> time:
        hour, minute = self.auto_duty_end_local_time.split(":")
        return time(int(hour), int(minute))

    def day_close_deadline(self) -> time:
        hour, minute = self.day_close_deadline_local_time.split(":")
        return time(int(hour), int(minute))

    def is_working_day(self, day: date) -> bool:
        """OPS-007 tenant calendar: a working weekday that is not a holiday."""
        return day.isoweekday() in self.working_days and day not in self.holidays

    @property
    def meeting_point_default_radius_m(self) -> int:
        return self.meeting_point_radius_m or self.geofence_radius_m

    def gstin_for(self, state: str) -> str:
        return self.gstin_by_state.get(state) or placeholder_gstin(state)


#: What the field and farmer apps may read (``GET /v1/settings/public``): no finance or
#: credit keys. The mobile settings cache (geofence radius, minimum duration) fills from it.
PUBLIC_KEYS: tuple[str, ...] = (
    "geofence_radius_m",
    "meeting_point_radius_m",
    "min_visit_duration_s",
    "auto_duty_end_local_time",
    "idle_end_minutes",
    "location_policy_version",
    "sampling",
    "languages_enabled",
    "default_language",
    "features",
    "branding",
)


def parse_settings(
    raw: Mapping[str, Any] | None, branding: Mapping[str, Any] | None = None
) -> TenantSettings:
    """Lenient read: keys that fail validation fall back to their defaults (logged)."""
    data: dict[str, Any] = dict(raw or {})
    data["branding"] = dict(branding or {})
    try:
        return TenantSettings.model_validate(data)
    except ValidationError as exc:
        bad = {str(err["loc"][0]) for err in exc.errors() if err.get("loc")}
        log.warning("tenant_settings_invalid", keys=sorted(bad))
        return TenantSettings.model_validate({k: v for k, v in data.items() if k not in bad})


def tenant_settings(raw: Mapping[str, Any] | None) -> TenantSettings:
    """Strict: the typed settings of a raw ``tenant.settings`` mapping (raises on bad values)."""
    return TenantSettings.model_validate(dict(raw or {}))


def settings_from_tenant(tenant: Tenant | None) -> TenantSettings:
    """The typed settings of a loaded tenant row (defaults when ``None``)."""
    if tenant is None:
        return TenantSettings()
    return parse_settings(tenant.settings, tenant.branding)


_CACHE = "tenant_settings"


async def get_tenant_settings(session: AsyncSession, tenant_id: uuid.UUID) -> TenantSettings:
    """The one accessor for tenant settings (a missing row means the defaults).

    Cached per session (NF-005: a sync batch re-read the tenant row for every op, the session's
    identity map holding it only weakly). The cache keeps the row and its ``version``: a change
    made in this session (a settings PATCH, tests) bumps the version on flush, or leaves the row
    modified before it, and either one reloads."""
    from farmerapp.db.models.tenant import Tenant

    cache: dict[uuid.UUID, tuple[Any, int, TenantSettings]] = session.info.setdefault(_CACHE, {})
    hit = cache.get(tenant_id)
    if hit is not None:
        row, version, settings = hit
        state = inspect(row)
        fresh = (
            state.persistent
            and not state.modified
            and not ({"version", "settings", "branding"} & state.expired_attributes)
        )
        if fresh and row.version == version:
            return settings
    tenant = await session.get(Tenant, tenant_id)
    settings = settings_from_tenant(tenant)
    if tenant is not None:
        cache[tenant_id] = (tenant, tenant.version, settings)
    return settings


__all__ = [
    "DEFAULT_CREDIT_DUE_DAYS",
    "DEFAULT_LOCATION_POLICY_VERSION",
    "DEFAULT_STORE_MANAGER_MAX_CREDIT_LIMIT_PAISE",
    "DEFAULT_TA_RATE_PER_KM_PAISE",
    "PUBLIC_KEYS",
    "SETTINGS_KEYS",
    "SUPPORTED_LANGUAGES",
    "Branding",
    "FeatureSettings",
    "SamplingSettings",
    "TenantSettings",
    "get_tenant_settings",
    "parse_settings",
    "settings_from_tenant",
    "tenant_settings",
]
