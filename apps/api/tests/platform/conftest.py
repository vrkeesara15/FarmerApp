"""Fixtures for the WC-014 platform administration tests."""

from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User
from farmerapp.auth.stepup import STEP_UP_HEADER, issue_step_up_token
from farmerapp.db.session import set_tenant
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID
from farmerapp.platform_admin.provisioning import ensure_platform_admin
from farmerapp.platform_admin.state import invalidate

PLATFORM_ADMIN_PHONE = "+919999900001"

#: A complete, valid create body. Tests override what they care about.
TENANT_BODY: dict[str, Any] = {
    "name": "Nava Agri Services",
    "slug": "nava",
    "plan": "pilot",
    "region": "asia-south1",
    "primary_contact_name": "Latha Rao",
    "primary_contact_phone": "+919000188001",
    "default_language": "te",
}


@pytest.fixture(autouse=True)
def _clear_tenant_state_cache() -> Iterator[None]:
    """The tenant-state cache is per process and outlives a rolled-back test transaction."""
    invalidate()
    yield
    invalidate()


@pytest.fixture
async def platform_admin(db_session: AsyncSession) -> User:
    """The one ``platform_admin``, in the platform tenant."""
    user = await ensure_platform_admin(db_session, phone=PLATFORM_ADMIN_PHONE)
    await set_tenant(db_session, PLATFORM_TENANT_ID)
    return user


Bearer = Callable[[User], dict[str, str]]


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    """An access token for a user (the OTP round trip has its own tests)."""
    services: AuthServices = app.state.auth

    def _mint(user: User) -> dict[str, str]:
        token = services.tokens.issue_access_token(user, services.clock.now())
        return {"Authorization": f"Bearer {token}"}

    return _mint


@pytest.fixture
def step_up(app: FastAPI) -> Bearer:
    """SEC-028 ``X-Step-Up-Token`` for a user."""
    services: AuthServices = app.state.auth

    def _mint(user: User) -> dict[str, str]:
        return {STEP_UP_HEADER: issue_step_up_token(services.settings, user, services.clock.now())}

    return _mint


@pytest.fixture
def as_platform(platform_admin: User, bearer: Bearer, step_up: Bearer) -> dict[str, str]:
    """Bearer + step-up headers for the platform admin (every write needs both)."""
    return {**bearer(platform_admin), **step_up(platform_admin)}


@pytest.fixture
async def created_tenant(client: AsyncClient, as_platform: dict[str, str]) -> dict[str, Any]:
    """One provisioned tenant, as the API creates it."""
    resp = await client.post("/v1/admin/tenants", json=TENANT_BODY, headers=as_platform)
    assert resp.status_code == 201, resp.text
    body: dict[str, Any] = resp.json()
    return body


__all__ = ["PLATFORM_ADMIN_PHONE", "TENANT_BODY", "Bearer"]
