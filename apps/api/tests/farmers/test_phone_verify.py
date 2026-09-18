"""FA-012 / VA-F01: OTP verification of the farmer's phone (before registration through a
short-lived token, or afterwards on the farmer record). Reuses the FA-001 OTP machinery
with the ``farmer_register`` purpose: same limits and lockout."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.scheduler import InProcessScheduler
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.settings import get_settings
from tests.auth.conftest import T0, last_code
from tests.authz.conftest import Bearer
from tests.farmers.write_fixtures import WriteCtx

PHONE = "+919000199101"


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock(T0)


@pytest.fixture
def sms() -> FakeProvider:
    return FakeProvider()


@pytest.fixture(autouse=True)
def auth_services(app: FastAPI, clock: FakeClock, sms: FakeProvider) -> AuthServices:
    services = AuthServices(
        settings=get_settings(),
        clock=clock,
        sms=sms,
        whatsapp=sms,
        scheduler=InProcessScheduler(clock),
    )
    app.state.auth = services
    return services


async def _token(client: AsyncClient, ctx: WriteCtx, sms: FakeProvider, phone: str = PHONE) -> str:
    resp = await client.post(
        "/v1/farmers/phone/verify/send", json={"phone": phone}, headers=ctx.headers
    )
    assert resp.status_code == 202, resp.text
    body: dict[str, Any] = resp.json()
    assert body["phone_masked"].endswith(phone[-4:]) and body["channel"] == "sms"
    resp = await client.post(
        "/v1/farmers/phone/verify/confirm",
        json={"phone": phone, "code": last_code(sms, phone)},
        headers=ctx.headers,
    )
    assert resp.status_code == 200, resp.text
    token: str = resp.json()["phone_verification_token"]
    assert resp.json()["expires_in"] == 1800
    return token


async def test_token_flow_registers_a_verified_farmer(
    client: AsyncClient, ctx: WriteCtx, sms: FakeProvider
) -> None:
    token = await _token(client, ctx, sms)
    resp = await client.post(
        "/v1/farmers",
        json=ctx.farmer(phone=PHONE, phone_verification_token=token),
        headers=ctx.headers,
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["phone_verified"] is True


async def test_token_is_bound_to_the_phone_and_tenant(
    client: AsyncClient, ctx: WriteCtx, sms: FakeProvider
) -> None:
    token = await _token(client, ctx, sms)
    resp = await client.post(
        "/v1/farmers",
        json=ctx.farmer(phone="+919000199102", phone_verification_token=token),
        headers=ctx.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "phone_verification_invalid"
    resp = await client.post(
        "/v1/farmers",
        json=ctx.farmer(phone=PHONE, phone_verification_token="not-a-token"),
        headers=ctx.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "phone_verification_invalid"


async def test_token_expires_after_30_minutes(
    client: AsyncClient, ctx: WriteCtx, sms: FakeProvider, clock: FakeClock, bearer: Bearer
) -> None:
    token = await _token(client, ctx, sms)
    clock.advance(1801)
    resp = await client.post(
        "/v1/farmers",
        json=ctx.farmer(phone=PHONE, phone_verification_token=token),
        headers=bearer(ctx.officer),  # a fresh access token: only the phone token is stale
    )
    assert resp.status_code == 422 and resp.json()["code"] == "phone_verification_invalid"


async def test_wrong_code_counts_and_locks_like_login(
    client: AsyncClient, ctx: WriteCtx, sms: FakeProvider
) -> None:
    await client.post("/v1/farmers/phone/verify/send", json={"phone": PHONE}, headers=ctx.headers)
    for attempts_left in (4, 3, 2, 1):
        resp = await client.post(
            "/v1/farmers/phone/verify/confirm",
            json={"phone": PHONE, "code": "000000"},
            headers=ctx.headers,
        )
        assert resp.status_code == 401 and resp.json()["code"] == "otp_invalid"
        assert resp.json()["attempts_left"] == attempts_left
    resp = await client.post(
        "/v1/farmers/phone/verify/confirm",
        json={"phone": PHONE, "code": "000000"},
        headers=ctx.headers,
    )
    assert resp.status_code == 423 and resp.json()["code"] == "otp_locked"
    resp = await client.post(
        "/v1/farmers/phone/verify/send", json={"phone": PHONE}, headers=ctx.headers
    )
    assert resp.status_code == 423


async def test_verify_later_on_the_farmer_record(
    client: AsyncClient, ctx: WriteCtx, sms: FakeProvider, db_session: AsyncSession
) -> None:
    resp = await client.post("/v1/farmers", json=ctx.farmer(phone=PHONE), headers=ctx.headers)
    assert resp.status_code == 201 and resp.json()["phone_verified"] is False
    fid = resp.json()["id"]
    resp = await client.post(f"/v1/farmers/{fid}/phone/verify/send", headers=ctx.headers)
    assert resp.status_code == 202, resp.text
    resp = await client.post(
        f"/v1/farmers/{fid}/phone/verify/confirm",
        json={"code": last_code(sms, PHONE)},
        headers=ctx.headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["phone_verified"] is True and resp.json()["version"] == 2
    async with tenant_scope(db_session, ctx.tenant_id):
        row = await db_session.get_one(Farmer, uuid.UUID(fid))
        assert row.phone_verified is True
    # Scope: another officer cannot drive verification for this farmer.
    resp = await client.post(f"/v1/farmers/{fid}/phone/verify/send", headers=ctx.other_headers)
    assert resp.status_code == 404


async def test_no_code_leaks_into_responses(
    client: AsyncClient, ctx: WriteCtx, sms: FakeProvider
) -> None:
    resp = await client.post(
        "/v1/farmers/phone/verify/send", json={"phone": PHONE}, headers=ctx.headers
    )
    assert resp.status_code == 202
    assert last_code(sms, PHONE) not in resp.text
