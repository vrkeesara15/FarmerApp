"""Fixtures for the WC-011 / WC-012 / WC-103 administration API and SEC-020 / 025 / 028.

Builds on the auth fixtures (``FakeClock`` at T0, fake SMS outbox, tenant "fcc" with an
officer and an owner) and adds the other admin roles, token helpers and a step-up helper.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import Device, User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.stepup import STEP_UP_HEADER, issue_step_up_token
from farmerapp.db.models import AuditLog, Tenant
from tests.auth import conftest as _auth
from tests.auth.conftest import last_code

# The auth fixtures, re-exported (FakeClock, fake SMS outbox, tenant "fcc", officer, owner).
auth_services = _auth.auth_services
clock = _auth.clock
officer = _auth.officer
owner = _auth.owner
scheduler = _auth.scheduler
sms = _auth.sms
tenant = _auth.tenant
whatsapp = _auth.whatsapp

PHONE_OFFICER_DEVICE = "officer-phone-1"
PHONE_OFFICER_DEVICE_2 = "officer-phone-2"

Headers = dict[str, str]
Mint = Callable[..., Headers]


async def _user(session: AsyncSession, tenant: Tenant, role: UserRole, phone: str) -> User:
    user = User(tenant_id=tenant.id, phone=phone, name=f"{role.value} user", role=role)
    session.add(user)
    await session.flush()
    return user


@pytest.fixture
async def director(db_session: AsyncSession, tenant: Tenant) -> User:
    return await _user(db_session, tenant, UserRole.DIRECTOR, "+919000000002")


@pytest.fixture
async def tenant_admin(db_session: AsyncSession, tenant: Tenant) -> User:
    return await _user(db_session, tenant, UserRole.TENANT_ADMIN, "+919000000009")


@pytest.fixture
async def auditor(db_session: AsyncSession, tenant: Tenant) -> User:
    return await _user(db_session, tenant, UserRole.AUDITOR, "+919000000005")


@pytest.fixture
async def store_manager(db_session: AsyncSession, tenant: Tenant) -> User:
    return await _user(db_session, tenant, UserRole.STORE_MANAGER, "+919000000006")


@pytest.fixture
def bearer(auth_services: AuthServices) -> Mint:
    """``Authorization`` header for ``user`` (``device_id`` binds the token like the app's)."""

    def _mint(user: User, device_id: str | None = None) -> Headers:
        token = auth_services.tokens.issue_access_token(
            user, auth_services.clock.now(), device_id=device_id
        )
        return {"Authorization": f"Bearer {token}"}

    return _mint


@pytest.fixture
def step_up(auth_services: AuthServices) -> Callable[[User], Headers]:
    def _mint(user: User) -> Headers:
        token = issue_step_up_token(auth_services.settings, user, auth_services.clock.now())
        return {STEP_UP_HEADER: token}

    return _mint


@pytest.fixture
def admin_headers(bearer: Mint, step_up: Callable[[User], Headers]) -> Mint:
    """Bearer + step-up for an admin action."""

    def _mint(user: User) -> Headers:
        return bearer(user) | step_up(user)

    return _mint


async def app_login(
    client: AsyncClient,
    sms: FakeProvider,
    phone: str,
    device_id: str | None,
    *,
    expect: int = 200,
    **extra: Any,
) -> dict[str, Any]:
    """The mobile login flow (send + verify) from ``device_id``; returns the JSON body."""
    send = {"phone": phone} | ({"device_id": device_id} if device_id else {})
    resp = await client.post("/v1/auth/otp/send", json=send)
    assert resp.status_code == 202, resp.text
    verify = {"phone": phone, "code": last_code(sms, phone), **extra}
    if device_id:
        verify["device_id"] = device_id
    resp = await client.post("/v1/auth/otp/verify", json=verify)
    assert resp.status_code == expect, resp.text
    body: dict[str, Any] = resp.json()
    return body


def auth(tokens: dict[str, Any]) -> Headers:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


async def refresh(client: AsyncClient, tokens: dict[str, Any], device_id: str | None) -> Any:
    body: dict[str, Any] = {"refresh_token": tokens["refresh_token"]}
    if device_id:
        body["device_id"] = device_id
    return await client.post("/v1/auth/refresh", json=body)


async def devices_of(session: AsyncSession, user: User) -> dict[str, Device]:
    rows = await session.execute(select(Device).where(Device.user_id == user.id))
    return {d.device_id: d for d in rows.scalars()}


async def audit_rows(session: AsyncSession, *, action: str) -> Sequence[AuditLog]:
    stmt = select(AuditLog).where(AuditLog.action == action).order_by(AuditLog.created_at)
    return (await session.execute(stmt)).scalars().all()


def problem(resp: Any, status: int, code: str) -> dict[str, Any]:
    assert resp.status_code == status, resp.text
    body: dict[str, Any] = resp.json()
    assert body["code"] == code, body
    return body
