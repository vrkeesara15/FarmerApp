"""``tenant.settings`` keys used by M2 (FA-014, FA-017, VV-001, VV-007, VV-010) with defaults."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from farmerapp.farmers.models import DEFAULT_CONSENT_VERSION
from farmerapp.tenants.settings import (
    DEFAULT_LOCATION_POLICY_VERSION,
    SETTINGS_KEYS,
    SamplingSettings,
    TenantSettings,
    tenant_settings,
)


def test_defaults_match_the_spec() -> None:
    s = TenantSettings()
    assert s.geofence_radius_m == 150  # FA-014
    assert s.min_visit_duration_s == 300  # FA-017 (5 min)
    assert s.auto_duty_end_local_time == "20:00"  # VV-007
    assert s.idle_end_minutes == 60  # VV-007
    assert s.location_policy_version == DEFAULT_LOCATION_POLICY_VERSION == "2026-09-v1"  # VV-010
    assert s.sampling == SamplingSettings(moving_s=120, stationary_s=600, upload_s=900)  # VV-001
    assert s.consent_version == DEFAULT_CONSENT_VERSION


def test_tenant_settings_reads_overrides_and_ignores_unknown_keys() -> None:
    s = tenant_settings(
        {
            "geofence_radius_m": 200,
            "min_visit_duration_s": 120,
            "auto_duty_end_local_time": "19:30",
            "sampling": {"moving_s": 60},
            "something_else": {"x": 1},
        }
    )
    assert s.geofence_radius_m == 200 and s.min_visit_duration_s == 120
    assert s.auto_duty_end_local_time == "19:30"
    assert s.sampling.moving_s == 60 and s.sampling.stationary_s == 600
    assert tenant_settings(None) == TenantSettings()
    assert tenant_settings({}) == TenantSettings()


@pytest.mark.parametrize(
    "raw",
    [
        {"geofence_radius_m": 0},
        {"geofence_radius_m": 10_000},
        {"min_visit_duration_s": -1},
        {"auto_duty_end_local_time": "8pm"},
        {"auto_duty_end_local_time": "24:00"},
        {"idle_end_minutes": 0},
        {"sampling": {"moving_s": 5}},
        {"location_policy_version": ""},
    ],
)
def test_invalid_values_are_rejected(raw: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        tenant_settings(raw)


def test_every_key_is_documented() -> None:
    assert set(SETTINGS_KEYS) == set(TenantSettings.model_fields)
    assert all(doc for doc in SETTINGS_KEYS.values())


def test_auto_end_as_time() -> None:
    assert TenantSettings().auto_duty_end_time().strftime("%H:%M") == "20:00"
    assert TenantSettings(auto_duty_end_local_time="07:05").auto_duty_end_time().hour == 7
