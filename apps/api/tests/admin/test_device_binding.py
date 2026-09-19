"""SEC-020 / WC-011: device rows on login and refresh; a field officer is bound to one device."""

from __future__ import annotations

from collections.abc import Callable

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import DeviceStatus, User
from farmerapp.auth.providers import FakeProvider
from tests.admin.conftest import (
    PHONE_OFFICER_DEVICE,
    PHONE_OFFICER_DEVICE_2,
    Headers,
    Mint,
    app_login,
    audit_rows,
    auth,
    devices_of,
    problem,
    refresh,
)


async def test_first_login_binds_the_officer_device_with_its_details(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    db_session: AsyncSession,
    clock: FakeClock,
) -> None:
    await app_login(
        client,
        sms,
        officer.phone,
        PHONE_OFFICER_DEVICE,
        platform="android",
        model="Redmi 9A",
        app_version="0.4.0",
    )
    device = (await devices_of(db_session, officer))[PHONE_OFFICER_DEVICE]
    assert device.status == DeviceStatus.ACTIVE
    assert device.bound_at == clock.now() == device.first_seen == device.last_seen
    assert (device.platform, device.model, device.app_version) == ("android", "Redmi 9A", "0.4.0")


async def test_refresh_updates_last_seen_and_app_version(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    db_session: AsyncSession,
    clock: FakeClock,
) -> None:
    tokens = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    clock.advance(3600)
    resp = await client.post(
        "/v1/auth/refresh",
        json={
            "refresh_token": tokens["refresh_token"],
            "device_id": PHONE_OFFICER_DEVICE,
            "app_version": "0.5.0",
        },
    )
    assert resp.status_code == 200, resp.text
    device = (await devices_of(db_session, officer))[PHONE_OFFICER_DEVICE]
    assert device.last_seen == clock.now() and device.app_version == "0.5.0"


async def test_second_device_is_refused_and_recorded_pending(
    client: AsyncClient, sms: FakeProvider, officer: User, db_session: AsyncSession
) -> None:
    await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    await client.post(
        "/v1/auth/otp/send", json={"phone": officer.phone, "device_id": PHONE_OFFICER_DEVICE_2}
    )
    resp = await client.post(
        "/v1/auth/otp/verify",
        json={
            "phone": officer.phone,
            "code": _code(sms, officer.phone),
            "device_id": PHONE_OFFICER_DEVICE_2,
            "model": "Galaxy M12",
        },
    )
    problem(resp, 409, "device_not_bound")
    devices = await devices_of(db_session, officer)
    assert devices[PHONE_OFFICER_DEVICE].status == DeviceStatus.ACTIVE
    assert devices[PHONE_OFFICER_DEVICE_2].status == DeviceStatus.PENDING
    assert devices[PHONE_OFFICER_DEVICE_2].model == "Galaxy M12"
    assert devices[PHONE_OFFICER_DEVICE_2].bound_at is None
    assert await audit_rows(db_session, action="auth.login") != []  # only the first login
    assert len(await audit_rows(db_session, action="auth.login")) == 1


def _code(sms: FakeProvider, phone: str) -> str:
    from tests.auth.conftest import last_code

    return last_code(sms, phone)


async def test_officer_must_sign_in_with_a_device_id(
    client: AsyncClient, sms: FakeProvider, officer: User
) -> None:
    await client.post("/v1/auth/otp/send", json={"phone": officer.phone})
    resp = await client.post(
        "/v1/auth/otp/verify", json={"phone": officer.phone, "code": _code(sms, officer.phone)}
    )
    problem(resp, 422, "device_id_required")


async def test_other_roles_may_use_several_devices(
    client: AsyncClient, sms: FakeProvider, owner: User, db_session: AsyncSession, clock: FakeClock
) -> None:
    first = await app_login(client, sms, owner.phone, "owner-phone")
    clock.advance(60)
    second = await app_login(client, sms, owner.phone, "owner-tablet")
    devices = await devices_of(db_session, owner)
    assert {d.status for d in devices.values()} == {DeviceStatus.ACTIVE}
    assert set(devices) == {"owner-phone", "owner-tablet"}
    for tokens in (first, second):
        assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 200
    # console login without a device id is fine for non-officers
    await app_login(client, sms, owner.phone, None)


async def test_admin_binds_the_new_device_and_unbinds_the_old_one(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    owner: User,
    db_session: AsyncSession,
    clock: FakeClock,
    admin_headers: Mint,
) -> None:
    old = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE_2, expect=409)

    resp = await client.get(f"/v1/users/{officer.id}/devices", headers=admin_headers(owner))
    assert resp.status_code == 200, resp.text
    listed = {d["device_id"]: d["status"] for d in resp.json()["items"]}
    assert listed == {PHONE_OFFICER_DEVICE: "active", PHONE_OFFICER_DEVICE_2: "pending"}

    resp = await client.post(
        f"/v1/users/{officer.id}/devices/{PHONE_OFFICER_DEVICE_2}/bind",
        headers=admin_headers(owner),
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "active" and resp.json()["bound_at"] is not None

    devices = await devices_of(db_session, officer)
    assert devices[PHONE_OFFICER_DEVICE].status == DeviceStatus.REVOKED
    assert devices[PHONE_OFFICER_DEVICE_2].status == DeviceStatus.ACTIVE
    # the old device is signed out at once: access and refresh
    problem(await client.get("/v1/me", headers=auth(old)), 401, "session_revoked")
    problem(await refresh(client, old, PHONE_OFFICER_DEVICE), 401, "session_revoked")
    # ... and cannot sign in again until bound
    await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE, expect=409)
    # the new one can
    clock.advance(1)
    new = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE_2)
    assert (await client.get("/v1/me", headers=auth(new))).status_code == 200

    (row,) = await audit_rows(db_session, action="device.bind")
    assert row.after is not None and row.after["unbound"] == [PHONE_OFFICER_DEVICE]
    assert row.actor_id == owner.id


async def test_bind_creates_an_unseen_device(
    client: AsyncClient, officer: User, owner: User, admin_headers: Mint, db_session: AsyncSession
) -> None:
    resp = await client.post(
        f"/v1/users/{officer.id}/devices/replacement-phone/bind", headers=admin_headers(owner)
    )
    assert resp.status_code == 200, resp.text
    assert (await devices_of(db_session, officer))["replacement-phone"].status == "active"


async def test_bind_and_list_are_admin_only(
    client: AsyncClient,
    officer: User,
    store_manager: User,
    bearer: Mint,
    step_up: Callable[[User], Headers],
) -> None:
    headers = bearer(store_manager) | step_up(store_manager)
    resp = await client.post(f"/v1/users/{officer.id}/devices/x/bind", headers=headers)
    problem(resp, 403, "forbidden")
    resp = await client.get(f"/v1/users/{officer.id}/devices", headers=headers)
    problem(resp, 403, "forbidden")
