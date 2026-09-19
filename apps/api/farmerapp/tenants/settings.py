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
ta_daily_km_cap                     150          FA-023 most km paid for one day (assumption)
beat_daily_target                   10           FA-018 stops on the generated beat plan
beat_follow_up_days                 14           FA-018 a farmer is due a follow-up after this
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
service_area.districts              []           VA-F04 districts the tenant serves (code, name,
                                                 state, bbox or polygon); empty = not checked
discount_policy_max_bps             1000         VA-E09 most discount on a sale (bp of subtotal)
incentive_cutoff_day                25           VA-E09 day of month the incentive is computed
campaigns.attribution_days          14           WC-008 / AN-008 conversion window (days)
campaigns.dlt_templates             {}           WC-008 template key -> DLT template id (SMS)
campaigns.whatsapp_templates        {}           WC-008 template key -> WhatsApp template name
campaigns.sends_per_run             500          WC-008 throttle: recipients sent per job run
campaigns.holdout_pct               0            AN-008 default control group share (%)
stock_alerts.default_reorder_level  10           ST-004 reorder level of a SKU without its own
stock_alerts.expiry_days            [60, 30]     ST-004 expiry alert thresholds (days)
reports.weekly_owner_emails         []           AN-015 owner / director report addresses
reports.accounting_emails           []           ST-008 accountant addresses
accounting.*                        see model    ST-008 Tally / Zoho ledger names
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
#: FA-023 assumption until the owner sets it: at most 150 km of travel allowance a day.
DEFAULT_TA_DAILY_KM_CAP = 150
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
    "ta_daily_km_cap": "FA-023 most km paid as travel allowance for one day",
    "beat_daily_target": "FA-018 how many stops the daily beat plan suggests",
    "beat_follow_up_days": "FA-018 days after the last visit a farmer is due a follow-up",
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
    "service_area": "VA-F04 service districts: [{code, name, state, bbox | polygon}]",
    "discount_policy_max_bps": "VA-E09 largest discount on a sale, basis points of subtotal",
    "incentive_cutoff_day": "VA-E09 day of month the officer incentive is computed (1-28)",
    "campaigns": "WC-008 attribution window, DLT / WhatsApp template ids, throttle, holdout",
    "stock_alerts": "ST-004 default reorder level and expiry alert thresholds",
    "reports": "AN-015 weekly owner report and ST-008 accounting export email addresses",
    "accounting": "ST-008 Tally / Zoho ledger names",
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


class ServiceDistrict(BaseModel):
    """VA-F04: one district the tenant serves. ``bbox`` is ``[min_lon, min_lat, max_lon,
    max_lat]``; ``polygon`` an outer ring ``[[lon, lat], ...]`` (wins over ``bbox``). The demo
    tenants carry generous bounding boxes around their stores; real district boundaries
    (Survey of India / LGD) are a human gate (docs/prs/M7-rules.md)."""

    model_config = ConfigDict(extra="ignore")

    code: str = Field(min_length=1, max_length=32)
    name: str = Field(min_length=1, max_length=80)
    state: str | None = Field(default=None, max_length=80)
    bbox: list[float] | None = Field(default=None, min_length=4, max_length=4)
    polygon: list[list[float]] | None = Field(default=None, min_length=4, max_length=5000)

    def contains(self, lon: float, lat: float) -> bool:
        if self.polygon:
            return _point_in_ring(lon, lat, self.polygon)
        if self.bbox:
            min_lon, min_lat, max_lon, max_lat = self.bbox
            return min_lon <= lon <= max_lon and min_lat <= lat <= max_lat
        return False


def _point_in_ring(lon: float, lat: float, ring: list[list[float]]) -> bool:
    """Ray casting (even-odd) on a lon / lat ring: fine at district scale."""
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        if (y1 > lat) != (y2 > lat):
            cross = x1 + (lat - y1) * (x2 - x1) / (y2 - y1)
            if lon < cross:
                inside = not inside
    return inside


class ServiceArea(BaseModel):
    """VA-F04: the districts a tenant serves (empty: the check is off)."""

    model_config = ConfigDict(extra="ignore")

    districts: list[ServiceDistrict] = Field(default_factory=list, max_length=200)

    def district_of(self, lon: float, lat: float) -> ServiceDistrict | None:
        return next((d for d in self.districts if d.contains(lon, lat)), None)


_EMAIL = r"^[^@\s]+@[^@\s]+\.[^@\s]+$"
Email = Annotated[str, StringConstraints(pattern=_EMAIL, max_length=254)]


class CampaignSettings(BaseModel):
    """WC-008 / AN-008. Template ids are registrations (DLT, WhatsApp Business): human work."""

    model_config = ConfigDict(extra="ignore")

    attribution_days: int = Field(default=14, ge=1, le=90)
    dlt_templates: dict[str, Annotated[str, StringConstraints(max_length=64)]] = Field(
        default_factory=dict, description="template key -> DLT template id (TRAI, SMS)"
    )
    whatsapp_templates: dict[str, Annotated[str, StringConstraints(max_length=64)]] = Field(
        default_factory=dict, description="template key -> WhatsApp Business template name"
    )
    sends_per_run: int = Field(default=500, ge=1, le=10_000)
    holdout_pct: int = Field(default=0, ge=0, le=50)


class StockAlertSettings(BaseModel):
    """ST-004 nightly alerts."""

    model_config = ConfigDict(extra="ignore")

    default_reorder_level: int = Field(default=10, ge=0, le=1_000_000)
    expiry_days: list[Annotated[int, Field(ge=1, le=365)]] = Field(
        default_factory=lambda: [60, 30], min_length=1, max_length=5
    )


class ReportSettings(BaseModel):
    """Where recurring reports go (users carry no email address)."""

    model_config = ConfigDict(extra="ignore")

    weekly_owner_emails: list[Email] = Field(default_factory=list, max_length=20)
    accounting_emails: list[Email] = Field(default_factory=list, max_length=20)


class AccountingSettings(BaseModel):
    """ST-008 ledger names in the tenant's books (Tally / Zoho). TODO-HUMAN: the accountant
    confirms them against the company's chart of accounts."""

    model_config = ConfigDict(extra="ignore")

    sales_ledger_prefix: str = Field(default="Sales", min_length=1, max_length=60)
    output_tax_prefix: str = Field(default="Output", min_length=1, max_length=60)
    round_off_ledger: str = Field(default="Round Off", min_length=1, max_length=60)
    cash_ledger: str = Field(default="Cash", min_length=1, max_length=60)
    upi_ledger: str = Field(default="UPI Collections", min_length=1, max_length=60)
    card_ledger: str = Field(default="Card Collections", min_length=1, max_length=60)
    walk_in_party: str = Field(default="Cash Customer", min_length=1, max_length=60)


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
    ta_daily_km_cap: int = Field(default=DEFAULT_TA_DAILY_KM_CAP, ge=1, le=1000)
    beat_daily_target: int = Field(default=10, ge=1, le=50)
    beat_follow_up_days: int = Field(default=14, ge=1, le=180)
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
    service_area: ServiceArea = Field(default_factory=ServiceArea)
    discount_policy_max_bps: int = Field(default=1000, ge=0, le=10_000)
    incentive_cutoff_day: int = Field(default=25, ge=1, le=28)
    campaigns: CampaignSettings = Field(default_factory=CampaignSettings)
    stock_alerts: StockAlertSettings = Field(default_factory=StockAlertSettings)
    reports: ReportSettings = Field(default_factory=ReportSettings)
    accounting: AccountingSettings = Field(default_factory=AccountingSettings)
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
    "DEFAULT_TA_DAILY_KM_CAP",
    "DEFAULT_TA_RATE_PER_KM_PAISE",
    "PUBLIC_KEYS",
    "SETTINGS_KEYS",
    "SUPPORTED_LANGUAGES",
    "AccountingSettings",
    "Branding",
    "CampaignSettings",
    "FeatureSettings",
    "ReportSettings",
    "SamplingSettings",
    "ServiceArea",
    "ServiceDistrict",
    "StockAlertSettings",
    "TenantSettings",
    "get_tenant_settings",
    "parse_settings",
    "settings_from_tenant",
    "tenant_settings",
]
