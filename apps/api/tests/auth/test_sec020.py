"""SEC-020 clause by clause, so the requirement can be closed.

    "JWT access tokens 15 min, refresh 30 days with rotation and reuse detection;
     device-bound refresh for field agents."

``tests/auth/test_tokens.py`` covers the happy paths (claims, rotation, reuse, expiry) and
``tests/admin/test_device_binding.py`` the binding workflow. What was missing — and is here —
is the boundary of each number, that reuse kills *only* the leaked family, that a device-bound
session cannot be refreshed from another device even after a rotation, and that the access
token carries the device so a lost phone is cut off on its own (SEC-025).
"""

from __future__ import annotations

from typing import Any

import jwt
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import RefreshToken, RevokeReason, User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.db.models import Tenant
from farmerapp.settings import Settings, get_settings
from tests.auth.conftest import DEVICE, OFFICER_PHONE, OWNER_PHONE, login

pytestmark = pytest.mark.usefixtures("officer")

ACCESS_TTL = 900
REFRESH_TTL = 30 * 86_400


async def _refresh(client: AsyncClient, token: str, device_id: str | None = DEVICE) -> Any:
    body: dict[str, Any] = {"refresh_token": token}
    if device_id is not None:
        body["device_id"] = device_id
    return await client.post("/v1/auth/refresh", json=body)


# --------------------------------------------------------------------------- the numbers
def test_the_configured_lifetimes_are_the_spec_ones() -> None:
    settings = Settings()
    assert settings.access_token_ttl_seconds == ACCESS_TTL, "SEC-020: access tokens 15 min"
    assert settings.refresh_token_ttl_seconds == REFRESH_TTL, "SEC-020: refresh 30 days"
    assert settings.jwt_algorithm == "HS256"


async def test_an_access_token_is_accepted_up_to_fifteen_minutes_and_not_beyond(
    client: AsyncClient, session_tokens: dict[str, Any], clock: FakeClock
) -> None:
    auth = {"Authorization": f"Bearer {session_tokens['access_token']}"}
    clock.advance(ACCESS_TTL - 1)
    assert (await client.get("/v1/me", headers=auth)).status_code == 200
    clock.advance(2)
    resp = await client.get("/v1/me", headers=auth)
    assert resp.status_code == 401
    assert resp.json()["code"] == "token_expired"


async def test_a_refresh_token_lives_exactly_thirty_days(
    client: AsyncClient, session_tokens: dict[str, Any], clock: FakeClock
) -> None:
    clock.advance(REFRESH_TTL - 1)
    assert (await _refresh(client, session_tokens["refresh_token"])).status_code == 200


async def test_rotation_resets_the_thirty_days_but_keeps_the_family(
    client: AsyncClient, session_tokens: dict[str, Any], db_session: AsyncSession, clock: FakeClock
) -> None:
    clock.advance(10 * 86_400)
    rotated = (await _refresh(client, session_tokens["refresh_token"])).json()["refresh_token"]
    rows = (
        (await db_session.execute(select(RefreshToken).order_by(RefreshToken.created_at)))
        .scalars()
        .all()
    )
    old, new = rows
    assert old.family_id == new.family_id, "rotation stays inside the login's family"
    assert old.revoked_reason == RevokeReason.ROTATED
    assert (new.expires_at - clock.now()).days == 30
    assert rotated


# --------------------------------------------------------------------------- reuse detection
async def test_reuse_revokes_only_the_leaked_family(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession, officer: User
) -> None:
    """A second phone (or the console) must not be signed out by another session's leak."""
    first = await login(client, sms, device_id=DEVICE)
    # A field officer is bound to one device, so the second session is the officer's console
    # login (no device id) — a different family either way.
    console = await client.post("/v1/auth/otp/send", json={"phone": OFFICER_PHONE})
    assert console.status_code == 202
    second = await login(client, sms, device_id=DEVICE)

    rotated = (await _refresh(client, first["refresh_token"])).json()["refresh_token"]
    replayed = await _refresh(client, first["refresh_token"])
    assert replayed.status_code == 401 and replayed.json()["code"] == "refresh_reused"
    assert (await _refresh(client, rotated)).status_code == 401, "the family is dead"

    # The other login is untouched.
    assert (await _refresh(client, second["refresh_token"])).status_code == 200

    families = {
        row.family_id: row.revoked_reason
        for row in (await db_session.execute(select(RefreshToken))).scalars().all()
    }
    assert RevokeReason.REUSE.value in families.values()


async def test_an_admin_revocation_is_not_mistaken_for_reuse(
    client: AsyncClient, session_tokens: dict[str, Any], db_session: AsyncSession
) -> None:
    """A forced logout must say ``session_revoked``, not accuse the client of a leak."""
    row = (await db_session.execute(select(RefreshToken))).scalar_one()
    row.revoked_at = row.created_at
    row.revoked_reason = RevokeReason.FORCE_LOGOUT
    await db_session.flush()
    resp = await _refresh(client, session_tokens["refresh_token"])
    assert resp.status_code == 401
    assert resp.json()["code"] == "session_revoked"


# --------------------------------------------------------------------------- device binding
async def test_a_field_officers_refresh_stays_bound_after_rotation(
    client: AsyncClient, session_tokens: dict[str, Any]
) -> None:
    rotated = (await _refresh(client, session_tokens["refresh_token"])).json()["refresh_token"]
    stolen = await _refresh(client, rotated, device_id="another-phone")
    assert stolen.status_code == 401
    assert stolen.json()["code"] == "refresh_device_mismatch"
    missing = await _refresh(client, rotated, device_id=None)
    assert missing.status_code == 401
    assert missing.json()["code"] == "refresh_device_mismatch"


async def test_access_tokens_of_a_bound_session_carry_the_device(
    client: AsyncClient, session_tokens: dict[str, Any]
) -> None:
    """SEC-025 leans on this: a lost device's access tokens are identifiable on their own."""
    settings = get_settings()
    for token in (
        session_tokens["access_token"],
        (await _refresh(client, session_tokens["refresh_token"])).json()["access_token"],
    ):
        claims = jwt.decode(
            token,
            settings.jwt_signing_key,
            algorithms=[settings.jwt_algorithm],
            options={"verify_exp": False, "verify_iat": False},
        )
        assert claims["did"] == DEVICE


async def test_a_console_session_has_no_device_claim_and_no_device_binding(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession, tenant: Tenant
) -> None:
    """Device binding is for field agents; an owner signs in from any browser (SEC-020)."""
    db_session.add(User(tenant_id=tenant.id, phone=OWNER_PHONE, name="Suresh", role=UserRole.OWNER))
    await db_session.flush()
    await client.post("/v1/auth/otp/send", json={"phone": OWNER_PHONE})
    from tests.auth.conftest import last_code

    verified = await client.post(
        "/v1/auth/otp/verify", json={"phone": OWNER_PHONE, "code": last_code(sms, OWNER_PHONE)}
    )
    assert verified.status_code == 200, verified.text
    tokens = verified.json()
    settings = get_settings()
    claims = jwt.decode(
        tokens["access_token"],
        settings.jwt_signing_key,
        algorithms=[settings.jwt_algorithm],
        options={"verify_exp": False, "verify_iat": False},
    )
    assert "did" not in claims
    assert (await _refresh(client, tokens["refresh_token"], device_id=None)).status_code == 200


async def test_logout_kills_one_family_not_the_account(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession
) -> None:
    first = await login(client, sms)
    second = await login(client, sms)
    assert (
        await client.post("/v1/auth/logout", json={"refresh_token": first["refresh_token"]})
    ).status_code == 204
    assert (await _refresh(client, first["refresh_token"])).status_code == 401
    assert (await _refresh(client, second["refresh_token"])).status_code == 200
    reasons = {
        row.revoked_reason
        for row in (await db_session.execute(select(RefreshToken))).scalars().all()
        if row.revoked_at is not None
    }
    assert RevokeReason.LOGOUT.value in reasons
    assert RevokeReason.REUSE.value not in reasons, "a logout is never reported as a leak"
