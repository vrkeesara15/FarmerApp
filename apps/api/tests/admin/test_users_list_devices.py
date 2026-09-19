"""WC-011 / C101: ``GET /v1/users`` rows carry the device status and the latest device, so the
console's users table needs one request (no devices request per row)."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import User
from farmerapp.auth.providers import FakeProvider
from tests.admin.conftest import PHONE_OFFICER_DEVICE, PHONE_OFFICER_DEVICE_2, Mint, app_login


def _row(body: dict[str, Any], user: User) -> dict[str, Any]:
    return next(i for i in body["items"] if i["id"] == str(user.id))


async def test_list_shows_device_status_and_latest_device(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    owner: User,
    bearer: Mint,
    clock: FakeClock,
) -> None:
    resp = await client.get("/v1/users", headers=bearer(owner))
    assert resp.status_code == 200, resp.text
    row = _row(resp.json(), officer)
    assert row["device_status"] == "none" and row["latest_device"] is None

    await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE, platform="android")
    resp = await client.get("/v1/users", headers=bearer(owner))
    row = _row(resp.json(), officer)
    assert row["device_status"] == "active"
    assert row["latest_device"]["device_id"] == PHONE_OFFICER_DEVICE
    assert row["latest_device"]["status"] == "active"
    assert row["latest_device"]["platform"] == "android"

    # A second phone waits for binding: the row says pending and shows the newer device.
    clock.advance(600)
    await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE_2, expect=409)
    resp = await client.get("/v1/users", headers=bearer(owner))
    row = _row(resp.json(), officer)
    assert row["device_status"] == "pending"
    assert row["latest_device"]["device_id"] == PHONE_OFFICER_DEVICE_2
    assert row["latest_device"]["status"] == "pending"
    # The owner signed in without a device header: no device rows.
    assert _row(resp.json(), owner)["device_status"] == "none"
