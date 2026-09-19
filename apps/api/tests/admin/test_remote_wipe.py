"""SEC-025: remote wipe signal when a device is reported lost (or the account disabled)."""

from __future__ import annotations

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import DeviceStatus, User
from farmerapp.auth.providers import FakeProvider
from tests.admin.conftest import (
    PHONE_OFFICER_DEVICE,
    Mint,
    app_login,
    audit_rows,
    auth,
    devices_of,
    problem,
    refresh,
)


async def test_report_lost_wipes_that_device_only(
    client: AsyncClient,
    sms: FakeProvider,
    owner: User,
    tenant_admin: User,
    admin_headers: Mint,
    db_session: AsyncSession,
    clock: FakeClock,
) -> None:
    phone = await app_login(client, sms, owner.phone, "owner-phone")
    clock.advance(1)
    tablet = await app_login(client, sms, owner.phone, "owner-tablet")

    resp = await client.post(
        f"/v1/users/{owner.id}/devices/owner-phone/report-lost", headers=admin_headers(owner)
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "lost" and resp.json()["revoked_at"] is not None

    # the lost phone: every call and refresh says "wipe"; so does a new login from it
    problem(await client.get("/v1/me", headers=auth(phone)), 401, "device_wipe_required")
    problem(await refresh(client, phone, "owner-phone"), 401, "device_wipe_required")
    await app_login(client, sms, owner.phone, "owner-phone", expect=401)
    # the tablet keeps working
    assert (await client.get("/v1/me", headers=auth(tablet))).status_code == 200
    resp = await client.get("/v1/devices/me/status", headers=auth(tablet))
    assert resp.status_code == 200
    assert resp.json() == {
        "device_id": "owner-tablet",
        "status": "active",
        "wipe_required": False,
        "user_status": "active",
    }

    (row,) = await audit_rows(db_session, action="device.report_lost")
    assert row.after is not None and row.after["revoked_sessions"] == 1
    assert (await devices_of(db_session, owner))["owner-phone"].status == DeviceStatus.LOST


async def test_status_endpoint_reads_the_device_header(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    owner: User,
    admin_headers: Mint,
    bearer: Mint,
) -> None:
    """An app holding a token without a device claim still learns it must wipe."""
    await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    resp = await client.post(
        f"/v1/users/{officer.id}/devices/{PHONE_OFFICER_DEVICE}/report-lost",
        headers=admin_headers(owner),
    )
    assert resp.status_code == 200, resp.text
    resp = await client.get(
        "/v1/devices/me/status", headers=bearer(officer) | {"X-Device-Id": PHONE_OFFICER_DEVICE}
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["wipe_required"] is True and resp.json()["status"] == "lost"
    resp = await client.get("/v1/devices/me/status", headers=bearer(officer))
    assert resp.json() == {
        "device_id": None,
        "status": "unknown",
        "wipe_required": False,
        "user_status": "active",
    }


async def test_report_lost_unknown_device_is_404(
    client: AsyncClient, officer: User, owner: User, admin_headers: Mint
) -> None:
    resp = await client.post(
        f"/v1/users/{officer.id}/devices/nope/report-lost", headers=admin_headers(owner)
    )
    problem(resp, 404, "not_found")
