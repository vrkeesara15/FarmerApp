"""WC-011 acceptance: a revoked user loses access within 5 minutes (here: at once, or within
the device-status cache TTL, which is at most 60 s). SEC-020 forced logout."""

from __future__ import annotations

from datetime import timedelta

import pytest
from httpx import AsyncClient
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.devices import DeviceStatusCache
from farmerapp.auth.models import DeviceStatus, User
from farmerapp.auth.providers import FakeProvider
from farmerapp.settings import Settings
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

ACCEPTANCE = timedelta(minutes=5)


def test_worst_case_revocation_is_within_the_acceptance_window(
    auth_services: AuthServices,
) -> None:
    assert auth_services.device_cache.ttl <= timedelta(seconds=60) < ACCEPTANCE
    assert Settings().security_cache_ttl_seconds == 30
    with pytest.raises(ValidationError):
        Settings(security_cache_ttl_seconds=61)
    with pytest.raises(ValueError):
        DeviceStatusCache(FakeClock(auth_services.clock.now()), 61)


async def test_force_logout_rejects_unexpired_tokens_and_refresh_at_once(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    owner: User,
    admin_headers: Mint,
    db_session: AsyncSession,
    clock: FakeClock,
) -> None:
    tokens = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 200

    clock.advance(10)
    resp = await client.post(f"/v1/users/{officer.id}/force-logout", headers=admin_headers(owner))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["revoked_sessions"] == 1 and body["user_id"] == str(officer.id)

    # The access token has 14+ minutes left, yet it stops working immediately.
    resp = await client.get("/v1/me", headers=auth(tokens))
    problem(resp, 401, "session_revoked")
    assert resp.headers["www-authenticate"] == "Bearer"
    problem(await refresh(client, tokens, PHONE_OFFICER_DEVICE), 401, "session_revoked")

    (row,) = await audit_rows(db_session, action="user.force_logout")
    assert row.actor_id == owner.id and row.entity_id == officer.id
    assert row.after is not None and row.after["revoked_sessions"] == 1

    # The officer signs in again (same bound device) and works normally.
    clock.advance(1)
    again = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    assert (await client.get("/v1/me", headers=auth(again))).status_code == 200


async def test_disable_revokes_and_tells_the_device_to_wipe(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    owner: User,
    admin_headers: Mint,
    bearer: Mint,
) -> None:
    tokens = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    console = bearer(officer)  # a token without a device (console)
    resp = await client.patch(
        f"/v1/users/{officer.id}", json={"status": "disabled"}, headers=admin_headers(owner)
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "disabled"

    problem(await client.get("/v1/me", headers=auth(tokens)), 401, "device_wipe_required")
    problem(await client.get("/v1/me", headers=console), 401, "user_disabled")
    problem(await refresh(client, tokens, PHONE_OFFICER_DEVICE), 401, "device_wipe_required")
    # and login answers 403 user_disabled
    resp = await client.post("/v1/auth/otp/send", json={"phone": officer.phone})
    problem(resp, 403, "user_disabled")


async def test_deactivate_endpoint(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    director: User,
    admin_headers: Mint,
    db_session: AsyncSession,
) -> None:
    tokens = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    resp = await client.post(f"/v1/users/{officer.id}/deactivate", headers=admin_headers(director))
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "disabled"
    problem(await client.get("/v1/me", headers=auth(tokens)), 401, "device_wipe_required")
    # idempotent
    resp = await client.post(f"/v1/users/{officer.id}/deactivate", headers=admin_headers(director))
    assert resp.status_code == 200
    rows = [
        r
        for r in await audit_rows(db_session, action="user.update")
        if r.entity_id == officer.id and r.after is not None and "status" in r.after
    ]
    assert len(rows) == 1 and rows[0].after is not None
    assert rows[0].after["status"] == "disabled" and rows[0].actor_id == director.id


async def test_lost_device_seen_by_another_instance_within_the_cache_ttl(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    db_session: AsyncSession,
    clock: FakeClock,
    auth_services: AuthServices,
) -> None:
    """The instance that handles report-lost drops its cache entry; any other instance keeps
    answering from its cache until the TTL runs out — and not a second longer."""
    tokens = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 200  # cached

    # Another instance marks the device lost (this instance's cache is not told).
    device = (await devices_of(db_session, officer))[PHONE_OFFICER_DEVICE]
    device.status = DeviceStatus.LOST
    await db_session.flush()

    ttl = auth_services.device_cache.ttl
    clock.advance(ttl - timedelta(seconds=1))
    assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 200
    clock.advance(timedelta(seconds=1))
    problem(await client.get("/v1/me", headers=auth(tokens)), 401, "device_wipe_required")


async def test_revoked_device_seen_after_the_cache_ttl(
    client: AsyncClient,
    sms: FakeProvider,
    officer: User,
    db_session: AsyncSession,
    clock: FakeClock,
    auth_services: AuthServices,
) -> None:
    tokens = await app_login(client, sms, officer.phone, PHONE_OFFICER_DEVICE)
    assert (await client.get("/v1/me", headers=auth(tokens))).status_code == 200
    device = (await devices_of(db_session, officer))[PHONE_OFFICER_DEVICE]
    device.status = DeviceStatus.REVOKED
    await db_session.flush()
    clock.advance(auth_services.device_cache.ttl)
    problem(await client.get("/v1/me", headers=auth(tokens)), 401, "session_revoked")


async def test_zero_ttl_cache_reads_every_time(
    db_session: AsyncSession, officer: User, clock: FakeClock
) -> None:
    cache = DeviceStatusCache(clock, 0)
    assert await cache.status(db_session, officer.tenant_id, officer.id, "nope") is None
    cache.clear()


async def test_non_owner_cannot_force_logout_an_owner(
    client: AsyncClient, owner: User, director: User, admin_headers: Mint
) -> None:
    resp = await client.post(f"/v1/users/{owner.id}/force-logout", headers=admin_headers(director))
    problem(resp, 403, "role_not_grantable")
