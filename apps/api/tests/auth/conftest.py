"""Auth test fixtures: injected clock, in-process fake providers and a seeded tenant/user.

The app fixture from ``tests/conftest.py`` builds the real app; here we replace
``app.state.auth`` with services wired to a ``FakeClock`` and ``FakeProvider`` so tests drive
time (expiry, windows, fallback) without sleeping and read OTP codes from the fake outbox.
"""

from __future__ import annotations

import re
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.scheduler import InProcessScheduler
from farmerapp.db.models import Tenant
from farmerapp.settings import get_settings

T0 = datetime(2026, 9, 17, 9, 0, tzinfo=UTC)
OFFICER_PHONE = "+919000000004"
OWNER_PHONE = "+919000000001"
DEVICE = "device-abc"


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock(T0)


@pytest.fixture
def sms() -> FakeProvider:
    return FakeProvider()


@pytest.fixture
def whatsapp() -> FakeProvider:
    return FakeProvider()


@pytest.fixture
def scheduler(clock: FakeClock) -> InProcessScheduler:
    return InProcessScheduler(clock)


@pytest.fixture(autouse=True)
def auth_services(
    app: FastAPI,
    clock: FakeClock,
    sms: FakeProvider,
    whatsapp: FakeProvider,
    scheduler: InProcessScheduler,
) -> AuthServices:
    services = AuthServices(
        settings=get_settings(), clock=clock, sms=sms, whatsapp=whatsapp, scheduler=scheduler
    )
    app.state.auth = services
    return services


@pytest.fixture
async def tenant(db_session: AsyncSession) -> Tenant:
    t = Tenant(name="Future Crop Care", slug="fcc")
    db_session.add(t)
    await db_session.flush()
    return t


@pytest.fixture
async def officer(db_session: AsyncSession, tenant: Tenant) -> User:
    user = User(
        tenant_id=tenant.id,
        phone=OFFICER_PHONE,
        name="Ramesh",
        role=UserRole.FIELD_OFFICER,
        language="te",
    )
    db_session.add(user)
    await db_session.flush()
    return user


@pytest.fixture
async def owner(db_session: AsyncSession, tenant: Tenant) -> User:
    user = User(tenant_id=tenant.id, phone=OWNER_PHONE, name="Suresh", role=UserRole.OWNER)
    db_session.add(user)
    await db_session.flush()
    return user


CODE_RE = re.compile(r"\b(\d{6})\b")


def last_code(provider: FakeProvider, phone: str) -> str:
    """Extract the OTP from the most recent fake message to ``phone``."""
    messages = [m for m in provider.sent if m.to == phone]
    assert messages, f"no message sent to {phone}"
    match = CODE_RE.search(messages[-1].body)
    assert match, f"no 6-digit code in {messages[-1].body!r}"
    return match.group(1)


async def send_otp(
    client: AsyncClient, phone: str = OFFICER_PHONE, **extra: object
) -> dict[str, Any]:
    resp = await client.post("/v1/auth/otp/send", json={"phone": phone, **extra})
    assert resp.status_code == 202, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def login(
    client: AsyncClient, sms: FakeProvider, phone: str = OFFICER_PHONE, device_id: str = DEVICE
) -> dict[str, Any]:
    await send_otp(client, phone, device_id=device_id)
    resp = await client.post(
        "/v1/auth/otp/verify",
        json={"phone": phone, "code": last_code(sms, phone), "device_id": device_id},
    )
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    return body


@pytest.fixture
async def session_tokens(
    client: AsyncClient, sms: FakeProvider, officer: User
) -> AsyncIterator[dict[str, Any]]:
    yield await login(client, sms)
