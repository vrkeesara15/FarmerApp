"""WC-012: typed tenant settings — read, public subset, validated and audited writes, and the
one accessor every reader goes through."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.models import Tenant
from farmerapp.khata.ledger import tenant_credit_settings
from farmerapp.policies.service import settings_for
from farmerapp.tenants.settings import (
    PUBLIC_KEYS,
    SETTINGS_KEYS,
    TenantSettings,
    get_tenant_settings,
    parse_settings,
    settings_from_tenant,
)
from farmerapp.visits.service import settings_of
from tests.admin.conftest import Mint, audit_rows, problem

FINANCE_KEYS = {
    "ta_rate_per_km_paise",
    "store_manager_max_credit_limit_paise",
    "credit_due_days",
    "day_close_variance_threshold_paise",
    "webhook_replay_window_s",
    "legal_name",
    "gstin_by_state",
    "invoice_prefix",
    "consent_version",
}


async def test_get_returns_every_setting_with_defaults(
    client: AsyncClient, director: User, bearer: Mint
) -> None:
    resp = await client.get("/v1/settings", headers=bearer(director))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body) == set(SETTINGS_KEYS) == set(TenantSettings.model_fields)
    assert body["geofence_radius_m"] == 150 and body["min_visit_duration_s"] == 300
    assert body["ta_rate_per_km_paise"] == 300
    assert body["store_manager_max_credit_limit_paise"] == 5_000_000
    assert body["languages_enabled"] == ["en", "te", "kn", "hi", "mr"]
    assert body["branding"]["primary_colour"] == "#1F6B3A"
    assert body["meeting_point_radius_m"] is None


async def test_public_subset_for_every_role(
    client: AsyncClient, officer: User, bearer: Mint
) -> None:
    resp = await client.get("/v1/settings/public", headers=bearer(officer))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body) == set(PUBLIC_KEYS)
    assert not FINANCE_KEYS & set(body)
    assert body["geofence_radius_m"] == 150 and body["min_visit_duration_s"] == 300
    assert body["sampling"] == {"moving_s": 120, "stationary_s": 600, "upload_s": 900}
    problem(await client.get("/v1/settings", headers=bearer(officer)), 403, "forbidden")


async def test_patch_merges_validates_and_audits_before_after(
    client: AsyncClient,
    owner: User,
    officer: User,
    tenant: Tenant,
    admin_headers: Mint,
    bearer: Mint,
    db_session: AsyncSession,
) -> None:
    tenant.settings = {**tenant.settings, "legacy_key": "kept", "sampling": {"upload_s": 1200}}
    await db_session.flush()
    resp = await client.patch(
        "/v1/settings",
        json={
            "geofence_radius_m": 200,
            "min_visit_duration_s": 240,
            "ta_rate_per_km_paise": 350,
            "sampling": {"moving_s": 90},
            "languages_enabled": ["te", "en"],
            "branding": {"app_name_agent": "FCC Mitra", "primary_colour": "#0A5C36"},
        },
        headers=admin_headers(owner),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["geofence_radius_m"] == 200 and body["ta_rate_per_km_paise"] == 350
    assert body["sampling"] == {"moving_s": 90, "stationary_s": 600, "upload_s": 1200}
    assert body["branding"]["app_name_agent"] == "FCC Mitra"

    await db_session.refresh(tenant)
    assert tenant.settings["legacy_key"] == "kept"  # unknown keys survive a write
    assert tenant.settings["sampling"] == {"upload_s": 1200, "moving_s": 90}
    assert tenant.branding == {"app_name_agent": "FCC Mitra", "primary_colour": "#0A5C36"}

    (row,) = await audit_rows(db_session, action="tenant_settings.update")
    assert row.actor_id == owner.id and row.entity == "tenant" and row.entity_id == tenant.id
    assert row.before is not None and row.after is not None
    assert (
        set(row.before)
        == set(row.after)
        == {
            "branding",
            "geofence_radius_m",
            "languages_enabled",
            "min_visit_duration_s",
            "sampling",
            "ta_rate_per_km_paise",
        }
    )
    assert row.before["geofence_radius_m"] == 150 and row.after["geofence_radius_m"] == 200
    assert row.before["ta_rate_per_km_paise"] == 300 and row.after["ta_rate_per_km_paise"] == 350
    assert await audit_rows(db_session, action="tenant.update")  # the listener's raw diff too

    # the apps see the change at once
    public = (await client.get("/v1/settings/public", headers=bearer(officer))).json()
    assert public["geofence_radius_m"] == 200 and public["min_visit_duration_s"] == 240
    assert public["languages_enabled"] == ["te", "en"]


async def test_on_device_crop_guess_flag_default_off_public_and_audited(
    client: AsyncClient,
    owner: User,
    officer: User,
    tenant: Tenant,
    admin_headers: Mint,
    bearer: Mint,
    db_session: AsyncSession,
) -> None:
    """DX-001: ``features.on_device_crop_guess`` is off by default, readable by the apps
    (farmer and officer) and every change is audited with before / after."""
    farmer_user = User(
        tenant_id=tenant.id, phone="+919000000071", name="farmer user", role=UserRole.FARMER
    )
    db_session.add(farmer_user)
    await db_session.flush()
    for user in (farmer_user, officer):
        public = (await client.get("/v1/settings/public", headers=bearer(user))).json()
        assert public["features"] == {"on_device_crop_guess": False}

    resp = await client.patch(
        "/v1/settings",
        json={"features": {"on_device_crop_guess": True}},
        headers=admin_headers(owner),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["features"] == {"on_device_crop_guess": True}
    (row,) = await audit_rows(db_session, action="tenant_settings.update")
    assert row.before == {"features": {"on_device_crop_guess": False}}
    assert row.after == {"features": {"on_device_crop_guess": True}}
    for user in (farmer_user, officer):
        public = (await client.get("/v1/settings/public", headers=bearer(user))).json()
        assert public["features"]["on_device_crop_guess"] is True

    # the same value again is no change (no event); null resets to the default (audited)
    same = await client.patch(
        "/v1/settings",
        json={"features": {"on_device_crop_guess": True}},
        headers=admin_headers(owner),
    )
    assert same.status_code == 200
    assert len(await audit_rows(db_session, action="tenant_settings.update")) == 1
    reset = await client.patch(
        "/v1/settings",
        json={"features": {"on_device_crop_guess": None}},
        headers=admin_headers(owner),
    )
    assert reset.json()["features"] == {"on_device_crop_guess": False}
    assert len(await audit_rows(db_session, action="tenant_settings.update")) == 2
    unknown = await client.patch(
        "/v1/settings", json={"features": {"crop_hint": True}}, headers=admin_headers(owner)
    )
    assert unknown.status_code == 422, unknown.text


async def test_null_resets_to_default_and_noop_writes_no_event(
    client: AsyncClient, tenant_admin: User, admin_headers: Mint, db_session: AsyncSession
) -> None:
    headers = admin_headers(tenant_admin)
    resp = await client.patch("/v1/settings", json={"meeting_point_radius_m": 80}, headers=headers)
    assert resp.status_code == 200 and resp.json()["meeting_point_radius_m"] == 80
    resp = await client.patch(
        "/v1/settings",
        json={"meeting_point_radius_m": None, "branding": {"support_phone": None}},
        headers=headers,
    )
    assert resp.status_code == 200 and resp.json()["meeting_point_radius_m"] is None
    assert len(await audit_rows(db_session, action="tenant_settings.update")) == 2
    resp = await client.patch("/v1/settings", json={"geofence_radius_m": 150}, headers=headers)
    assert resp.status_code == 200
    assert len(await audit_rows(db_session, action="tenant_settings.update")) == 2


@pytest.mark.parametrize(
    "body",
    [
        {"geofence_radius_m": 5},
        {"geofence_radius_m": 5000},
        {"min_visit_duration_s": -1},
        {"auto_duty_end_local_time": "8pm"},
        {"idle_end_minutes": 0},
        {"sampling": {"moving_s": 5}},
        {"ta_rate_per_km_paise": -1},
        {"credit_due_days": 0},
        {"webhook_replay_window_s": 10},
        {"invoice_prefix": "fcc-1"},
        {"gstin_by_state": {"Telangana": "NOT-A-GSTIN"}},
        {"branding": {"primary_colour": "green"}},
        {"branding": {"support_phone": "call us"}},
        {"languages_enabled": []},
    ],
)
async def test_out_of_range_values_are_rejected(
    client: AsyncClient, owner: User, admin_headers: Mint, body: dict[str, Any]
) -> None:
    resp = await client.patch("/v1/settings", json=body, headers=admin_headers(owner))
    problem_body = problem(resp, 422, "invalid_settings")
    assert problem_body["errors"]


async def test_unknown_keys_and_languages_fail_request_validation(
    client: AsyncClient, owner: User, admin_headers: Mint
) -> None:
    for body in ({"surprise": 1}, {"languages_enabled": ["fr"]}, {"branding": {"font": "x"}}):
        resp = await client.patch("/v1/settings", json=body, headers=admin_headers(owner))
        assert resp.status_code == 422, resp.text


async def test_director_writes_settings_with_step_up(
    client: AsyncClient, director: User, bearer: Mint, admin_headers: Mint
) -> None:
    """SPEC 2.6: Owner / director write Settings; SEC-028 step-up still applies."""
    body = {"geofence_radius_m": 200}
    resp = await client.patch("/v1/settings", json=body, headers=bearer(director))
    problem(resp, 401, "step_up_required")
    resp = await client.patch("/v1/settings", json=body, headers=admin_headers(director))
    assert resp.status_code == 200, resp.text
    assert resp.json()["geofence_radius_m"] == 200


async def test_other_roles_cannot_write_settings(
    client: AsyncClient, store_manager: User, admin_headers: Mint
) -> None:
    resp = await client.patch(
        "/v1/settings", json={"geofence_radius_m": 200}, headers=admin_headers(store_manager)
    )
    problem(resp, 403, "forbidden")


async def test_readers_share_the_one_accessor(db_session: AsyncSession, tenant: Tenant) -> None:
    """Visits, duty / policies and khata read the same typed settings (behaviour unchanged)."""
    defaults = TenantSettings()
    assert await get_tenant_settings(db_session, tenant.id) == defaults
    assert await settings_of(db_session, tenant.id) == defaults
    assert await settings_for(db_session, tenant.id) == defaults
    credit = await tenant_credit_settings(db_session, tenant.id)
    assert credit.store_manager_max_credit_limit_paise == 5_000_000
    assert credit.credit_due_days == 90

    tenant.settings = {"geofence_radius_m": 600, "store_manager_max_credit_limit_paise": 1}
    await db_session.flush()
    assert (await settings_of(db_session, tenant.id)).geofence_radius_m == 600
    assert (await settings_for(db_session, tenant.id)).geofence_radius_m == 600
    assert (
        await tenant_credit_settings(db_session, tenant.id)
    ).store_manager_max_credit_limit_paise == 1


def test_lenient_load_falls_back_per_key() -> None:
    settings = parse_settings(
        {"geofence_radius_m": -3, "min_visit_duration_s": 120, "invoice_prefix": "bad prefix"},
        {"primary_colour": "not-a-colour", "app_name_farmer": "FCC Kisan"},
    )
    assert settings.geofence_radius_m == 150  # invalid -> default
    assert settings.min_visit_duration_s == 120  # valid keys kept
    assert settings.invoice_prefix is None
    assert settings.branding.primary_colour == "#1F6B3A"  # whole branding falls back
    assert settings_from_tenant(None) == TenantSettings()


def test_derived_values() -> None:
    settings = TenantSettings(geofence_radius_m=180)
    assert settings.meeting_point_default_radius_m == 180
    assert TenantSettings(meeting_point_radius_m=90).meeting_point_default_radius_m == 90
    assert settings.gstin_for("Telangana").startswith("36")
    assert (
        TenantSettings(gstin_by_state={"Telangana": "36ABCDE1234F1Z5"}).gstin_for("Telangana")
        == "36ABCDE1234F1Z5"
    )
