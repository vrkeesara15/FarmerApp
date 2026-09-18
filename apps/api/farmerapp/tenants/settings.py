"""Typed view of ``tenant.settings`` (SPEC 8.2 ``settings jsonb``) with the defaults.

Keys the API reads, all optional in the JSON (a missing key means the default below):

======================== ============ ==================================================
key                      default      used by
======================== ============ ==================================================
consent_version          2026-09-v1   FM-002 consent text version (TODO-LEGAL placeholder)
geofence_radius_m        150          FA-014 / VV-003 buffer around a farm polygon or a
                                      village meeting point (``village.meeting_point_radius_m``
                                      overrides it per village)
min_visit_duration_s     300          FA-017 visits under it are flagged, never rejected
auto_duty_end_local_time "20:00"      VV-007 duty ends at this local (IST) time
idle_end_minutes         60           VV-007 duty ends after this long idle at home
location_policy_version  2026-09-v1   FA-011 / VV-010 policy the app must have accepted before
                                      duty can start (TODO-LEGAL: HR signs the same version)
sampling.moving_s        120          VV-001 location sample interval while moving
sampling.stationary_s    600          VV-001 interval while stationary
sampling.upload_s        900          VV-001 batch upload interval (or Wi-Fi / charging)
======================== ============ ==================================================

Only owners write settings (SPEC 2.6); the write endpoint is a WC item. Validation here is
the contract for that endpoint too (``TenantSettings.model_validate``).
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import time
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.farmers.models import DEFAULT_CONSENT_VERSION

#: TODO-LEGAL: placeholder until the written employee location policy is approved and signed
#: in HR onboarding (VV-010, SPEC 14.6 human gate). The in-app acceptance references it.
DEFAULT_LOCATION_POLICY_VERSION = "2026-09-v1"

SETTINGS_KEYS: Mapping[str, str] = {
    "consent_version": "FM-002 consent text version shown to farmers",
    "geofence_radius_m": "FA-014 / VV-003 geofence buffer in metres (farm polygon, meeting point)",
    "min_visit_duration_s": "FA-017 minimum visit duration in seconds (flag, not reject)",
    "auto_duty_end_local_time": "VV-007 local time (HH:MM, IST) at which duty auto-ends",
    "idle_end_minutes": "VV-007 minutes idle at the home location before duty auto-ends",
    "location_policy_version": "FA-011 / VV-010 employee location policy version to accept",
    "sampling": "VV-001 sampling intervals: moving_s, stationary_s, upload_s",
}


class SamplingSettings(BaseModel):
    model_config = ConfigDict(extra="ignore")

    moving_s: int = Field(default=120, ge=30, le=3600)
    stationary_s: int = Field(default=600, ge=60, le=7200)
    upload_s: int = Field(default=900, ge=60, le=86_400)


class TenantSettings(BaseModel):
    model_config = ConfigDict(extra="ignore")

    consent_version: str = Field(default=DEFAULT_CONSENT_VERSION, min_length=1, max_length=32)
    geofence_radius_m: int = Field(default=150, ge=10, le=2000)
    min_visit_duration_s: int = Field(default=300, ge=0, le=86_400)
    auto_duty_end_local_time: str = Field(default="20:00", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    idle_end_minutes: int = Field(default=60, ge=5, le=720)
    location_policy_version: str = Field(
        default=DEFAULT_LOCATION_POLICY_VERSION, min_length=1, max_length=32
    )
    sampling: SamplingSettings = Field(default_factory=SamplingSettings)

    def auto_duty_end_time(self) -> time:
        hour, minute = self.auto_duty_end_local_time.split(":")
        return time(int(hour), int(minute))


def tenant_settings(raw: Mapping[str, Any] | None) -> TenantSettings:
    """The typed settings of a tenant row (``tenant_settings(tenant.settings)``)."""
    return TenantSettings.model_validate(dict(raw or {}))


__all__ = [
    "DEFAULT_LOCATION_POLICY_VERSION",
    "SETTINGS_KEYS",
    "SamplingSettings",
    "TenantSettings",
    "tenant_settings",
]
