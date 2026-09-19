"""GET /v1/me requires a valid access token; the session is bound to the user's tenant."""

from __future__ import annotations

from typing import Any

import jwt
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.db.models import Tenant
from farmerapp.settings import get_settings
from tests.auth.conftest import login


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.usefixtures("officer")
async def test_me_returns_profile(
    client: AsyncClient, session_tokens: dict[str, Any], officer: User
) -> None:
    resp = await client.get("/v1/me", headers=_bearer(session_tokens["access_token"]))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["id"] == str(officer.id)
    assert body["role"] == "field_officer"
    assert body["tenant_id"] == str(officer.tenant_id)
    assert "code_hash" not in body and "token" not in str(body)


async def test_me_without_token(client: AsyncClient) -> None:
    resp = await client.get("/v1/me")
    assert resp.status_code == 401
    body = resp.json()
    assert body["code"] == "unauthenticated"
    assert resp.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("header", ["Bearer garbage", "Basic abc", "Bearer "])
async def test_me_with_invalid_token(client: AsyncClient, header: str) -> None:
    resp = await client.get("/v1/me", headers={"Authorization": header})
    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthenticated"


@pytest.mark.usefixtures("officer")
async def test_me_with_expired_token(
    client: AsyncClient, session_tokens: dict[str, Any], clock: FakeClock
) -> None:
    clock.advance(901)
    resp = await client.get("/v1/me", headers=_bearer(session_tokens["access_token"]))
    assert resp.status_code == 401
    assert resp.json()["code"] == "token_expired"


@pytest.mark.usefixtures("officer")
async def test_me_rejects_refresh_typed_or_forged_jwt(client: AsyncClient, officer: User) -> None:
    settings = get_settings()
    forged = jwt.encode(
        {"sub": str(officer.id), "typ": "access"},
        "wrong-key-long-enough-for-hs256-checks",
        algorithm="HS256",
    )
    resp = await client.get("/v1/me", headers=_bearer(forged))
    assert resp.status_code == 401
    wrong_type = jwt.encode(
        {
            "sub": str(officer.id),
            "tid": str(officer.tenant_id),
            "typ": "refresh",
            "exp": 4102444800,
        },
        settings.jwt_signing_key,
        algorithm=settings.jwt_algorithm,
    )
    resp = await client.get("/v1/me", headers=_bearer(wrong_type))
    assert resp.status_code == 401


@pytest.mark.usefixtures("officer")
async def test_me_for_disabled_user(
    client: AsyncClient, session_tokens: dict[str, Any], officer: User, db_session: AsyncSession
) -> None:
    officer.status = "disabled"
    await db_session.flush()
    resp = await client.get("/v1/me", headers=_bearer(session_tokens["access_token"]))
    # A disabled account is no longer a valid session: 401 so clients drop tokens and re-login
    # (login itself answers 403 `user_disabled`). The token is bound to the app's device, so
    # SEC-025 tells that app to wipe its local data (console tokens get `user_disabled`).
    assert resp.status_code == 401
    assert resp.json()["code"] == "device_wipe_required"
    assert resp.headers["www-authenticate"] == "Bearer"


@pytest.mark.usefixtures("officer")
async def test_me_binds_tenant_on_session(
    client: AsyncClient, session_tokens: dict[str, Any], officer: User, db_session: AsyncSession
) -> None:
    from sqlalchemy import text

    await client.get("/v1/me", headers=_bearer(session_tokens["access_token"]))
    bound = await db_session.scalar(text("SELECT current_setting('app.tenant_id', true)"))
    assert bound == str(officer.tenant_id)


@pytest.mark.parametrize("role", [r.value for r in UserRole])
async def test_every_role_can_log_in_and_read_me(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession, tenant: Tenant, role: str
) -> None:
    """SEC-006 matrix for FA-001: /me is allowed for every role; the role is echoed back."""
    phone = f"+919000001{list(UserRole).index(UserRole(role)):03d}"
    db_session.add(User(tenant_id=tenant.id, phone=phone, name=role, role=UserRole(role)))
    await db_session.flush()
    tokens = await login(client, sms, phone=phone)
    resp = await client.get("/v1/me", headers=_bearer(tokens["access_token"]))
    assert resp.status_code == 200
    assert resp.json()["role"] == role
    assert len(UserRole) == 10
